using UnityEngine;

namespace HMD
{
    /// <summary>
    /// The LSXmotorsport workshop in the city: corrugated metal walls with a black lower band (like
    /// Hamad's photo), the real LSX logo on a lit sign, a forecourt, and a roller door. The door rolls
    /// up only when the car is very close (about 7.5 m) and the car is never pulled in: you drive
    /// through the door yourself, and crossing the threshold takes you inside.
    /// </summary>
    public class GarageBuilding : MonoBehaviour
    {
        public const float OpenDistance = 7.5f;
        public System.Action OnEnter;

        Transform door;
        BoxCollider doorCol;
        float open;           // 0 closed .. 1 open
        Vector3 doorPos;      // centre of the door opening on the ground
        Transform player;
        float cooldown;
        const float DoorW = 6f, DoorH = 4.6f, W = 34f, D = 26f, H = 9f;

        public Vector3 DoorPos => doorPos;
        public Vector3 Forecourt => doorPos + Vector3.back * 9f;

        public void Build(Vector3 doorCenter, Transform playerT)
        {
            player = playerT;
            doorPos = doorCenter;
            transform.position = doorCenter;
            // building occupies +Z from the door
            var corr = Res.TexMat("Tex/corrugated_iron", new Vector2(1f / 2.5f, 1f / 2.5f), 0.55f, 0.6f, new Color(0.92f, 0.9f, 0.82f));
            var band = Res.Mat(new Color(0.03f, 0.03f, 0.035f), 0.4f, 0.2f);
            var roof = Res.TexMat("Tex/concrete_panels", Vector2.one / 4f, 0.25f, 0f, new Color(0.4f, 0.4f, 0.42f));
            var apron = Res.TexMat("Tex/concrete_pavement", Vector2.one / 4f, 0.45f, 0f, new Color(0.62f, 0.62f, 0.62f));
            var yellow = Res.Mat(new Color(0.95f, 0.75f, 0.05f), 0.5f);

            var b = new MeshBuilder(4);
            Vector3 c = new Vector3(0, 0, D * 0.5f);
            // walls with the door hole in the front face
            float fz = 0f;
            b.Sub(0);
            // front wall left / right of the door, and above it
            float side = (W - DoorW) * 0.5f;
            b.Box(new Vector3(-(DoorW * 0.5f + side * 0.5f), H * 0.5f, fz + 0.15f), new Vector3(side, H, 0.3f), 2.5f, true, false);
            b.Box(new Vector3(DoorW * 0.5f + side * 0.5f, H * 0.5f, fz + 0.15f), new Vector3(side, H, 0.3f), 2.5f, true, false);
            b.Box(new Vector3(0, (H + DoorH) * 0.5f, fz + 0.15f), new Vector3(DoorW, H - DoorH, 0.3f), 2.5f, true, false);
            b.Box(new Vector3(-W * 0.5f, H * 0.5f, c.z), new Vector3(0.3f, H, D), 2.5f, true, false);
            b.Box(new Vector3(W * 0.5f, H * 0.5f, c.z), new Vector3(0.3f, H, D), 2.5f, true, false);
            b.Box(new Vector3(0, H * 0.5f, D), new Vector3(W, H, 0.3f), 2.5f, true, false);
            // black lower band
            b.Sub(1);
            b.Box(new Vector3(-(DoorW * 0.5f + side * 0.5f), 0.6f, fz - 0.02f), new Vector3(side, 1.2f, 0.1f), 2f, true, false);
            b.Box(new Vector3(DoorW * 0.5f + side * 0.5f, 0.6f, fz - 0.02f), new Vector3(side, 1.2f, 0.1f), 2f, true, false);
            // door frame
            b.Box(new Vector3(-DoorW * 0.5f - 0.15f, DoorH * 0.5f, fz - 0.05f), new Vector3(0.3f, DoorH, 0.3f), 1f);
            b.Box(new Vector3(DoorW * 0.5f + 0.15f, DoorH * 0.5f, fz - 0.05f), new Vector3(0.3f, DoorH, 0.3f), 1f);
            b.Box(new Vector3(0, DoorH + 0.35f, fz - 0.1f), new Vector3(DoorW + 0.6f, 0.7f, 0.5f), 1f);   // roller box
            // roof
            b.Sub(2).Box(new Vector3(0, H + 0.2f, c.z), new Vector3(W + 0.6f, 0.4f, D + 0.6f), 4f, true, false);
            // forecourt apron + yellow guide lines into the door
            b.Sub(3).Box(new Vector3(0, 0.02f, -6f), new Vector3(W, 0.04f, 12f), 4f, true, false);
            var go = MeshBuilder.Spawn("LSX_Building", b.Build("lsx"), new[] { corr, band, roof, apron }, transform, true, true);

            var lines = new MeshBuilder(1);
            for (int s = -1; s <= 1; s += 2)
                lines.Box(new Vector3(s * (DoorW * 0.5f - 0.4f), 0.05f, -5.5f), new Vector3(0.18f, 0.02f, 11f), 1f, true, false);
            MeshBuilder.Spawn("GuideLines", lines.Build("guides"), new[] { yellow }, transform, false, false);

            // driveway ramp over the kerb, so the car rolls up onto the forecourt smoothly
            float kerb = 0.19f, rampLen = 2.2f, edge = -City.Walk;
            var ramp = MeshBuilder.Cube("Ramp", transform, new Vector3(0, kerb * 0.5f - 0.05f, edge - rampLen * 0.5f + 0.3f), new Vector3(DoorW + 3f, 0.1f, rampLen), apron, true);
            ramp.transform.localRotation = Quaternion.Euler(-Mathf.Atan2(kerb, rampLen) * Mathf.Rad2Deg, 0, 0);

            // interior darkness behind the door so the opening looks deep
            MeshBuilder.Cube("Inside", transform, new Vector3(0, DoorH * 0.5f, 3.2f), new Vector3(DoorW, DoorH, 0.1f), Res.Mat(new Color(0.02f, 0.02f, 0.02f), 0.1f));
            var warm = new GameObject("InsideLight").AddComponent<Light>();
            warm.transform.SetParent(transform, false);
            warm.transform.localPosition = new Vector3(0, 3.6f, 1.5f);
            warm.type = LightType.Point; warm.range = 9; warm.intensity = 2.5f; warm.color = new Color(1f, 0.92f, 0.8f);

            // roller door: ribbed panel that slides up into the roller box
            var dm = Res.TexMat("Tex/corrugated_iron", new Vector2(1f / 1.2f, 1f / 3f), 0.6f, 0.8f, new Color(0.7f, 0.72f, 0.75f));
            door = MeshBuilder.Cube("RollerDoor", transform, new Vector3(0, DoorH * 0.5f, 0.45f), new Vector3(DoorW + 0.3f, DoorH, 0.12f), dm, true).transform;
            doorCol = door.GetComponent<BoxCollider>();

            // LSX logo sign over the door, with its own light
            var logo = Res.Tex("Art/lsx-logo");
            var sign = GameObject.CreatePrimitive(PrimitiveType.Quad);
            Object.Destroy(sign.GetComponent<Collider>());
            sign.name = "LSX_Logo";
            sign.transform.SetParent(transform, false);
            sign.transform.localPosition = new Vector3(0, H - 1.9f, -0.25f);
            sign.transform.localScale = new Vector3(9.2f, 9.2f * 292f / 900f, 1);
            var sm = Res.Mat(Color.white, 0.7f, 0.2f);
            if (logo)
            {
                Res.SetMainTex(sm, logo, Vector2.one);
                sm.SetFloat("_AlphaClip", 1f); sm.SetFloat("_Cutoff", 0.3f); sm.EnableKeyword("_ALPHATEST_ON");
                Res.SetEmission(sm, Color.white * 0.9f, logo);
            }
            sign.GetComponent<Renderer>().sharedMaterial = sm;
            // dark sign board behind the logo
            MeshBuilder.Cube("SignBoard", transform, new Vector3(0, H - 1.9f, -0.18f), new Vector3(10.4f, 3.6f, 0.1f), Res.Mat(new Color(0.02f, 0.02f, 0.022f), 0.8f, 0.5f));
            for (int s = -1; s <= 1; s += 2)
            {
                var sl = new GameObject("SignSpot").AddComponent<Light>();
                sl.transform.SetParent(transform, false);
                sl.transform.localPosition = new Vector3(s * 3.5f, H + 0.4f, -2.2f);
                sl.transform.localRotation = Quaternion.Euler(60, 0, 0);
                sl.type = LightType.Spot; sl.range = 10; sl.spotAngle = 70; sl.intensity = 6f; sl.color = new Color(1f, 0.95f, 0.88f);
            }
            // red neon strip under the roof edge (brand red from the logo X)
            MeshBuilder.Cube("RedStrip", transform, new Vector3(0, H - 0.25f, -0.2f), new Vector3(W, 0.12f, 0.08f), Res.Glow(new Color(1f, 0.05f, 0.05f), 5f));
        }

        void Update()
        {
            if (player == null) return;
            cooldown -= Time.deltaTime;
            Vector3 rel = player.position - doorPos;
            float dist = new Vector2(rel.x, rel.z).magnitude;
            bool near = dist < OpenDistance;
            open = Mathf.MoveTowards(open, near ? 1f : 0f, Time.deltaTime / 1.4f);
            door.localPosition = new Vector3(0, DoorH * 0.5f + open * DoorH * 0.96f, 0.45f);
            door.localScale = new Vector3(DoorW + 0.3f, DoorH * (1 - open * 0.92f), 0.12f);
            doorCol.enabled = open < 0.85f;
            // the car itself drives through: crossing the threshold enters the garage
            if (open > 0.85f && rel.z > 1.2f && Mathf.Abs(rel.x) < DoorW * 0.5f && cooldown <= 0)
            {
                cooldown = 3f;
                OnEnter?.Invoke();
            }
        }

        public void SetPlayer(Transform t) => player = t;

        public void ForceClosed() { open = 0; cooldown = 2.5f; }
    }
}
