using UnityEngine;

namespace HMD
{
    /// <summary>
    /// One camera for the whole game. Chase: behind the car, a little lag and lean, wider field of view
    /// with speed. Intro: the car is shown from the BACK (rear three-quarter) first, slowly sweeping
    /// in to the chase view, as Hamad asked. Orbit: slow turntable around the car in the garage.
    /// Fixed: a set shot (dyno, TV zoom, screenshots).
    /// </summary>
    public class CameraRig : MonoBehaviour
    {
        public enum Mode { Chase, Intro, Orbit, Fixed }
        public Mode mode = Mode.Chase;
        public Transform target;
        public Camera Cam { get; private set; }

        float introT, orbitAngle = 200f, shake;
        Vector3 vel, fixedPos, fixedLook, fixedFromPos, fixedFromLook;
        float fixedBlend = 1f;
        public System.Action OnIntroDone;
        public float orbitDistance = 6.5f, orbitHeight = 1.6f;

        public void Setup()
        {
            Cam = GetComponent<Camera>();
            Cam.nearClipPlane = 0.15f;
            Cam.farClipPlane = 2500f;
            Cam.fieldOfView = 58f;
        }

        public void StartIntro() { mode = Mode.Intro; introT = 0; }
        public void SetFixed(Vector3 pos, Vector3 look, bool blend = true)
        {
            fixedFromPos = transform.position;
            fixedFromLook = transform.position + transform.forward * 5f;
            fixedPos = pos; fixedLook = look;
            fixedBlend = blend ? 0f : 1f;
            mode = Mode.Fixed;
        }
        public void Shake(float a) => shake = Mathf.Max(shake, a);

        CarController Car => target ? target.GetComponent<CarController>() : null;

        void LateUpdate()
        {
            if (target == null && mode != Mode.Fixed) return;
            float dt = Time.deltaTime;
            switch (mode)
            {
                case Mode.Chase: Chase(dt, false); break;
                case Mode.Intro: Intro(dt); break;
                case Mode.Orbit: Orbit(dt); break;
                case Mode.Fixed:
                    fixedBlend = Mathf.MoveTowards(fixedBlend, 1f, dt / 1.2f);
                    float e = Mathf.SmoothStep(0, 1, fixedBlend);
                    Vector3 p = Vector3.Lerp(fixedFromPos, fixedPos, e);
                    Vector3 l = Vector3.Lerp(fixedFromLook, fixedLook, e);
                    transform.position = p;
                    transform.rotation = Quaternion.LookRotation(l - p, Vector3.up);
                    break;
            }
            if (shake > 0)
            {
                transform.position += Random.insideUnitSphere * shake * 0.05f;
                shake = Mathf.MoveTowards(shake, 0, dt * 3f);
            }
        }

        void Chase(float dt, bool snap)
        {
            var car = Car;
            float speed = car ? car.SpeedKmh : 0;
            Vector3 fwd = target.forward; fwd.y = 0; fwd.Normalize();
            // look a bit along the velocity so drifts read well
            if (car && car.Body && car.Body.Vel().sqrMagnitude > 25)
            {
                Vector3 v = car.Body.Vel(); v.y = 0;
                fwd = Vector3.Slerp(fwd, v.normalized, 0.35f).normalized;
            }
            float dist = Mathf.Lerp(5.0f, 6.2f, speed / 220f);   // lower and closer: a high wide camera makes the car look like a toy
            dist *= Mathf.Max(1f, CarLen() / 4.9f);
            float height = Mathf.Lerp(1.5f, 1.35f, speed / 220f) * Mathf.Lerp(1f, Mathf.Max(1f, CarLen() / 4.9f), 0.6f);
            Vector3 want = target.position - fwd * dist + Vector3.up * height;
            transform.position = snap ? want : Vector3.SmoothDamp(transform.position, want, ref vel, 0.09f);
            Vector3 look = target.position + Vector3.up * 0.85f + fwd * 3f;
            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(look - transform.position, Vector3.up), snap ? 1 : 12f * dt);
            float nitroFov = car && car.nitro && car.NitroAmount > 0 ? 8f : 0;
            Cam.fieldOfView = Mathf.Lerp(Cam.fieldOfView, 55f + Mathf.Clamp(speed / 260f, 0, 1) * 12f + nitroFov, 4f * dt);
        }

        /// <summary>Starts low behind the car at the rear quarter (tail lights, exhaust), circles slowly, then settles behind it.</summary>
        float CarLen() { var c = target ? target.GetComponent<CarController>() : null; return c != null && c.spec != null ? c.spec.length : 4.4f; }

        void Intro(float dt)
        {
            introT += dt;
            const float dur = 5.5f;
            float t = Mathf.Clamp01(introT / dur);
            float e = Mathf.SmoothStep(0, 1, t);
            // angle measured from straight behind the car: start at 35 deg off the rear, end at 0
            float ang = Mathf.Lerp(38f, 0f, e);
            // scaled to the car: a long, tall pickup needs the camera further back than a coupe
            float size = Mathf.Max(1f, CarLen() / 4.4f);
            float dist = Mathf.Lerp(4.2f, 6.4f, e) * size;
            float h = Mathf.Lerp(0.55f, 2.0f, e) * Mathf.Lerp(1f, size, 0.7f);
            Vector3 back = -target.forward;
            Vector3 dir = Quaternion.Euler(0, ang, 0) * back;
            transform.position = target.position + dir * dist + Vector3.up * h;
            Vector3 look = target.position + Vector3.up * Mathf.Lerp(0.7f, 1.05f, e) + target.forward * Mathf.Lerp(0f, 2.5f, e);
            transform.rotation = Quaternion.LookRotation(look - transform.position, Vector3.up);
            Cam.fieldOfView = Mathf.Lerp(42f, 58f, e);
            if (t >= 1f)
            {
                mode = Mode.Chase;
                OnIntroDone?.Invoke();
            }
        }

        void Orbit(float dt)
        {
            orbitAngle += dt * 9f;
            if (Input.GetMouseButton(0) || Input.touchCount == 1)
            {
                float dx = Input.touchCount == 1 ? Input.GetTouch(0).deltaPosition.x : Input.GetAxis("Mouse X") * 20f;
                orbitAngle += dx * 0.25f;
            }
            Vector3 dir = Quaternion.Euler(0, orbitAngle, 0) * Vector3.forward;
            transform.position = target.position + dir * orbitDistance + Vector3.up * orbitHeight;
            transform.rotation = Quaternion.LookRotation(target.position + Vector3.up * 0.6f - transform.position, Vector3.up);
            Cam.fieldOfView = Mathf.Lerp(Cam.fieldOfView, 50f, 3f * dt);
        }

        public void SnapChase() { mode = Mode.Chase; Chase(0.016f, true); }
    }
}
