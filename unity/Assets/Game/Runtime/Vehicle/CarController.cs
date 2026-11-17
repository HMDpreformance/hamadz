using UnityEngine;

namespace HMD
{
    public static class RbExt
    {
#if UNITY_6000_0_OR_NEWER
        public static Vector3 Vel(this Rigidbody rb) => rb.linearVelocity;
        public static void SetVel(this Rigidbody rb, Vector3 v) => rb.linearVelocity = v;
        public static void SetDamping(this Rigidbody rb, float lin, float ang) { rb.linearDamping = lin; rb.angularDamping = ang; }
#else
        public static Vector3 Vel(this Rigidbody rb) => rb.velocity;
        public static void SetVel(this Rigidbody rb, Vector3 v) => rb.velocity = v;
        public static void SetDamping(this Rigidbody rb, float lin, float ang) { rb.drag = lin; rb.angularDrag = ang; }
#endif
    }

    /// <summary>
    /// Real vehicle physics on Unity WheelColliders: a torque curve made from the car's hp and
    /// torque, a gearbox with automatic shifting, a differential (RWD/AWD), anti-roll bars,
    /// aero drag tuned so the car tops out at its real top speed, downforce, ABS, light traction
    /// control, speed-sensitive steering and a handbrake that lets the rear step out for drifts.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class CarController : MonoBehaviour
    {
        public CarSpec spec;
        public WheelCollider[] wheels = new WheelCollider[4];   // FL, FR, RL, RR
        public Transform[] wheelVisuals = new Transform[4];

        // inputs (set by the player input or by a script like the dyno)
        [Range(-1, 1)] public float steer;
        [Range(0, 1)] public float throttle;
        [Range(0, 1)] public float brake;
        public bool handbrake, nitro, reverseHeld;
        public bool inputLocked;       // garage, intro: no driving
        public bool dynoMode;          // car strapped down: wheels spin, body stays still

        // outputs
        public float SpeedKmh { get; private set; }
        public float ForwardSpeed { get; private set; }
        public float Rpm { get; private set; }
        public int Gear { get; private set; } = 1;     // -1 reverse, 0 neutral, 1..n
        public float EngineLoad { get; private set; }
        public float RearSlip { get; private set; }
        public float NitroAmount { get; set; } = 1f;
        public bool Shifting => shiftTimer > 0;
        public bool Grounded { get; private set; }
        public Rigidbody Body => rb;

        Rigidbody rb;
        float peakTorque, peakRpm, dragK, shiftTimer, steerSmoothed, wheelRpm;
        WheelFrictionCurve rearSideBase, frontSideBase;
        float dynoWheelAngle;

        const float AirDensity = 1.2f;

        public void Setup(CarSpec s)
        {
            spec = s;
            rb = GetComponent<Rigidbody>();
            rb.mass = s.weightKg;
            rb.SetDamping(0.01f, 0.35f);
            rb.interpolation = RigidbodyInterpolation.Interpolate;
            rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            rb.centerOfMass = new Vector3(0, 0.38f, 0.05f);
            rb.maxAngularVelocity = 12f;

            // torque peak lands mid-range; curve falls off so peak power is near redline*0.85
            peakTorque = s.torqueNm;
            peakRpm = s.rpmRedline * 0.55f;
            // drag so that (power at wheels) = drag power at top speed
            float vTop = s.topKmh / 3.6f;
            float watts = s.hp * 745.7f * 0.85f;
            dragK = watts / (vTop * vTop * vTop);  // F = k v^2

            float springPerWheel = s.weightKg * 9.81f / 4f / 0.09f; // ~9 cm static sag
            foreach (var w in wheels)
            {
                if (w == null) continue;
                w.mass = 22f;
                w.radius = s.wheelRadius;
                w.suspensionDistance = 0.16f;
                w.forceAppPointDistance = 0.1f;
                var sp = w.suspensionSpring;
                sp.spring = springPerWheel * (0.9f + s.handling / 400f);
                sp.damper = Mathf.Sqrt(sp.spring * s.weightKg / 4f) * 0.55f;
                sp.targetPosition = 0.45f;
                w.suspensionSpring = sp;

                var fwd = w.forwardFriction;
                fwd.extremumSlip = 0.35f; fwd.extremumValue = 1.0f;
                fwd.asymptoteSlip = 0.9f; fwd.asymptoteValue = 0.75f;
                fwd.stiffness = 1.6f;
                w.forwardFriction = fwd;

                var side = w.sidewaysFriction;
                side.extremumSlip = 0.22f; side.extremumValue = 1.0f;
                side.asymptoteSlip = 0.6f; side.asymptoteValue = 0.8f;
                side.stiffness = 1.45f + s.handling / 160f;
                w.sidewaysFriction = side;
            }
            frontSideBase = wheels[0].sidewaysFriction;
            rearSideBase = wheels[2].sidewaysFriction;
            Gear = 1;
            Rpm = s.rpmIdle;
        }

        /// <summary>Engine torque (Nm) at an rpm: rises to the peak then falls towards redline.</summary>
        public float TorqueAt(float rpm)
        {
            float x = rpm / peakRpm;
            float t = x < 1 ? Mathf.Lerp(0.55f, 1f, Mathf.Sin(Mathf.Clamp01(x) * Mathf.PI * 0.5f))
                            : Mathf.Lerp(1f, 0.72f, Mathf.Clamp01((rpm - peakRpm) / (spec.rpmRedline - peakRpm)));
            return peakTorque * t;
        }

        public float PowerHpAt(float rpm) => TorqueAt(rpm) * rpm / 7127f;

        float Ratio(int g) => g < 0 ? -3.2f * spec.finalDrive : g == 0 ? 0 : spec.gears[g - 1] * spec.finalDrive;

        void FixedUpdate()
        {
            if (spec == null) return;
            float dt = Time.fixedDeltaTime;
            Vector3 v = rb.Vel();
            ForwardSpeed = Vector3.Dot(v, transform.forward);
            SpeedKmh = dynoMode ? Mathf.Abs(wheelRpm) * 2 * Mathf.PI * spec.wheelRadius / 60f * 3.6f : v.magnitude * 3.6f;

            float thr = inputLocked ? 0 : throttle;
            float brk = inputLocked ? 1 : brake;

            if (dynoMode) { DynoStep(dt, thr); return; }

            // --- steering: less lock at speed, smoothed, with a little counter-steer help
            float speedFactor = Mathf.InverseLerp(10f, 200f, SpeedKmh);
            float maxLock = Mathf.Lerp(34f, 7.5f, speedFactor);
            float target = steer * maxLock;
            // counter-steer assist: when the rear slides, steer into it a bit
            float slipAngle = Vector3.SignedAngle(transform.forward, v.sqrMagnitude > 4 ? v.normalized : transform.forward, Vector3.up);
            if (SpeedKmh > 20 && Mathf.Abs(slipAngle) < 80) target += Mathf.Clamp(slipAngle * 0.35f, -12f, 12f) * (1 - Mathf.Abs(steer) * 0.5f);
            steerSmoothed = Mathf.MoveTowards(steerSmoothed, target, 160f * dt);
            wheels[0].steerAngle = steerSmoothed;
            wheels[1].steerAngle = steerSmoothed;

            // --- reverse: brake to a stop, then back up
            bool wantsReverse = (brk > 0.5f && ForwardSpeed < 1.0f && thr < 0.1f) || reverseHeld;
            if (wantsReverse && Gear >= 0 && ForwardSpeed < 0.5f) Gear = -1;
            if (Gear == -1 && thr > 0.1f && !reverseHeld) Gear = 1;

            // --- engine rpm from the driven wheels
            float avgWheelRpm = 0; int n = 0;
            for (int i = 0; i < 4; i++) if (IsDriven(i)) { avgWheelRpm += wheels[i].rpm; n++; }
            avgWheelRpm /= Mathf.Max(1, n);
            wheelRpm = avgWheelRpm;
            float ratio = Ratio(Gear);
            float rpmFromWheels = Mathf.Abs(avgWheelRpm * ratio);
            // clutch slip at launch
            float clutch = Mathf.Clamp01(ForwardSpeed / 4f + 0.25f);
            float freeRev = spec.rpmIdle + (spec.rpmRedline - spec.rpmIdle) * (Gear == -1 ? thr * 0.5f : thr * 0.75f);
            float targetRpm = Mathf.Lerp(Mathf.Max(freeRev, spec.rpmIdle), Mathf.Max(rpmFromWheels, spec.rpmIdle), clutch);
            if (shiftTimer > 0) targetRpm = Mathf.Lerp(Rpm, targetRpm, 0.2f);
            Rpm = Mathf.Clamp(Mathf.Lerp(Rpm, targetRpm, 12f * dt), spec.rpmIdle, spec.rpmRedline * 1.02f);

            // --- automatic gearbox
            if (shiftTimer > 0) shiftTimer -= dt;
            else if (Gear >= 1)
            {
                if (Rpm > spec.rpmRedline * 0.93f && Gear < spec.gears.Length && Grounded) { Gear++; shiftTimer = 0.18f; }
                else if (Gear > 1 && Rpm < spec.rpmRedline * 0.42f) { Gear--; shiftTimer = 0.15f; }
            }

            // --- drive torque
            float engineT = TorqueAt(Rpm) * thr;
            if (Rpm >= spec.rpmRedline) engineT = 0;               // limiter
            if (shiftTimer > 0) engineT *= 0.1f;
            float nitroBoost = 1f;
            if (nitro && NitroAmount > 0 && thr > 0.5f && Gear > 0)
            {
                nitroBoost = 1.45f;
                NitroAmount = Mathf.Max(0, NitroAmount - dt / 6f);
            }
            else NitroAmount = Mathf.Min(1, NitroAmount + dt / 40f);
            float wheelT = engineT * ratio * 0.88f * nitroBoost;
            EngineLoad = thr;

            // traction control: back off torque when driven wheels spin much faster than the ground
            float spin = 0;
            for (int i = 2; i < 4; i++)
                if (wheels[i].GetGroundHit(out var h)) spin = Mathf.Max(spin, Mathf.Abs(h.forwardSlip));
            if (spin > 0.6f && !handbrake) wheelT *= Mathf.Lerp(1f, 0.55f, (spin - 0.6f) / 0.6f);

            int driven = spec.drive == Drive.AWD ? 4 : 2;
            for (int i = 0; i < 4; i++)
            {
                float share = 0;
                if (spec.drive == Drive.AWD) share = i < 2 ? 0.4f / 2f : 0.6f / 2f;
                else if (IsDriven(i)) share = 1f / driven;
                wheels[i].motorTorque = (brk > 0.1f && Gear != -1) ? 0 : wheelT * share;
            }

            // --- brakes (with ABS) and handbrake
            float brakeTorque = spec.weightKg * 2.6f;  // Nm per wheel at full pedal
            for (int i = 0; i < 4; i++)
            {
                float b = Gear == -1 ? (thr > 0.1f ? brakeTorque * thr : 0) : brakeTorque * brk;
                if (i < 2) b *= 1.25f; else b *= 0.75f;
                if (wheels[i].GetGroundHit(out var h) && Mathf.Abs(h.forwardSlip) > 0.55f) b *= 0.4f; // ABS
                if (handbrake && i >= 2) b = brakeTorque * 3f;
                if (Gear == -1 && brk > 0.1f) wheels[i].motorTorque = -TorqueAt(Rpm) * brk * Mathf.Abs(Ratio(-1)) * 0.5f / 4f;
                wheels[i].brakeTorque = b;
            }
            if (Gear == -1 && brk > 0.1f)
                for (int i = 0; i < 4; i++) wheels[i].brakeTorque = 0;

            // --- handbrake drift: rear loses side grip
            var rs = rearSideBase;
            if (handbrake && SpeedKmh > 15) rs.stiffness = rearSideBase.stiffness * 0.42f;
            wheels[2].sidewaysFriction = rs;
            wheels[3].sidewaysFriction = rs;

            // --- anti-roll bars
            AntiRoll(wheels[0], wheels[1], spec.weightKg * 6f);
            AntiRoll(wheels[2], wheels[3], spec.weightKg * 4.5f);

            // --- aero
            Grounded = false;
            foreach (var w in wheels) if (w.isGrounded) Grounded = true;
            float vv = v.magnitude;
            rb.AddForce(-v.normalized * dragK * vv * vv, ForceMode.Force);
            if (Grounded) rb.AddForce(-transform.up * vv * vv * 1.1f, ForceMode.Force);   // downforce
            // rolling resistance
            rb.AddForce(-v * spec.weightKg * 0.015f, ForceMode.Force);

            // rear slip for smoke + tyre squeal
            RearSlip = 0;
            for (int i = 2; i < 4; i++)
                if (wheels[i].GetGroundHit(out var h))
                    RearSlip = Mathf.Max(RearSlip, Mathf.Abs(h.sidewaysSlip) * 1.3f + Mathf.Max(0, Mathf.Abs(h.forwardSlip) - 0.4f));
        }

        bool IsDriven(int i) => spec.drive == Drive.AWD || (spec.drive == Drive.RWD ? i >= 2 : i < 2);

        void AntiRoll(WheelCollider l, WheelCollider r, float k)
        {
            float tl = 1, tr = 1;
            bool gl = l.GetGroundHit(out var hl), gr = r.GetGroundHit(out var hr);
            if (gl) tl = (-l.transform.InverseTransformPoint(hl.point).y - l.radius) / l.suspensionDistance;
            if (gr) tr = (-r.transform.InverseTransformPoint(hr.point).y - r.radius) / r.suspensionDistance;
            float f = (tl - tr) * k;
            if (gl) rb.AddForceAtPosition(l.transform.up * -f, l.transform.position);
            if (gr) rb.AddForceAtPosition(r.transform.up * f, r.transform.position);
        }

        /// <summary>On the dyno the body is held still and the driven wheels spin up against the rollers' inertia.</summary>
        void DynoStep(float dt, float thr)
        {
            rb.isKinematic = true;
            float ratio = Ratio(Mathf.Max(1, Gear));
            // roller inertia chosen so a full pull from idle to redline takes about 6.5 s (like a real 4th-gear run)
            float wRed = spec.rpmRedline / Mathf.Max(0.5f, ratio) * 2 * Mathf.PI / 60f;
            float rollerInertia = Mathf.Max(2f, peakTorque * 0.8f * ratio * 0.88f * 6.5f / Mathf.Max(1f, wRed));
            float wheelT = (Rpm >= spec.rpmRedline ? 0 : TorqueAt(Rpm) * thr) * ratio * 0.88f;
            // roller + tyre losses grow with speed but stay well under engine torque, so every car reaches redline
            float wheelRpmRed = spec.rpmRedline / Mathf.Max(0.5f, ratio);
            float loss = peakTorque * ratio * 0.88f * 0.14f * Mathf.Clamp01(wheelRpm / wheelRpmRed) + 10f;
            float accel = (wheelT - loss) / rollerInertia;                 // rad/s^2
            float w = wheelRpm * 2 * Mathf.PI / 60f + accel * dt;
            if (thr < 0.05f) w *= 1 - dt * 0.6f;
            wheelRpm = Mathf.Max(0, w * 60f / (2 * Mathf.PI));
            Rpm = Mathf.Clamp(wheelRpm * ratio, spec.rpmIdle, spec.rpmRedline * 1.01f);
            EngineLoad = thr;
            dynoWheelAngle += wheelRpm * 6f * dt;
        }

        public void ResetDyno()
        {
            Gear = Mathf.Min(4, spec.gears.Length);  // dyno pulls run in a 1:1-ish gear like real dyno runs
            Rpm = spec.rpmIdle; dynoWheelAngle = 0;
            wheelRpm = spec.rpmIdle / Mathf.Max(0.5f, Ratio(Gear));   // rollers already turning at idle: the pull starts at once
        }

        void Update()
        {
            // wheel visuals
            for (int i = 0; i < 4; i++)
            {
                if (wheels[i] == null || wheelVisuals[i] == null) continue;
                wheels[i].GetWorldPose(out var p, out var q);
                // parked (kinematic) the colliders do not simulate and report a hanging wheel: show the wheels
                // where the model has them instead, so a parked car sits on its tyres
                if (rb.isKinematic) p = wheels[i].transform.position;
                if (dynoMode)
                    q = transform.rotation * Quaternion.Euler(IsDriven(i) ? dynoWheelAngle : 0, 0, 0);
                wheelVisuals[i].SetPositionAndRotation(p, q);
            }
        }

        /// <summary>Height of the car origin above the ground when parked with the wheels where the model has them.</summary>
        public float RestHeight
        {
            get
            {
                float m = float.MaxValue;
                for (int i = 0; i < 4; i++)
                    if (wheels[i] != null) m = Mathf.Min(m, transform.InverseTransformPoint(wheels[i].transform.position).y - wheels[i].radius);
                return m == float.MaxValue ? 0f : -m;
            }
        }

        /// <summary>Moves a parked (kinematic) car: transform and body together, so interpolation cannot pull it back.</summary>
        public void Place(Vector3 pos, Quaternion rot)
        {
            transform.SetPositionAndRotation(pos, rot);
            rb.position = pos; rb.rotation = rot;
            Physics.SyncTransforms();
        }

        /// <summary>Puts the car back on its wheels at a spot (used after a crash or a teleport).</summary>
        public void Teleport(Vector3 pos, Quaternion rot)
        {
            rb.isKinematic = true;
            transform.SetPositionAndRotation(pos, rot);
            rb.position = pos; rb.rotation = rot;   // move the body too, or interpolation snaps the car straight back
            Physics.SyncTransforms();
            rb.isKinematic = false;
            rb.SetVel(Vector3.zero);
            rb.angularVelocity = Vector3.zero;
            Gear = 1; Rpm = spec.rpmIdle; steerSmoothed = 0;
            for (int i = 0; i < 4; i++) { wheels[i].motorTorque = 0; wheels[i].brakeTorque = 0; }
        }
    }
}
