using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Builds a detailed wheel: rounded tyre with a tread band, a deep-dish multi-spoke rim with a lip,
    /// a centre cap, a drilled-look brake disc and a red caliper. The outer face points to +X
    /// (left-side wheels are mirrored). Sub-meshes: 0 tyre, 1 rim, 2 brake disc, 3 caliper.
    /// </summary>
    public static class WheelMesh
    {
        static readonly Dictionary<string, Mesh> cache = new Dictionary<string, Mesh>();
        static Mesh unitCube;

        public enum Style { Mesh10, Split5, Deep6, Classic }

        public static Mesh Get(float radius, float width, Style style)
        {
            string key = radius.ToString("F3") + width.ToString("F3") + style;
            if (cache.TryGetValue(key, out var m)) return m;
            m = Build(radius, width, style);
            cache[key] = m;
            return m;
        }

        static Mesh UnitCube()
        {
            if (unitCube != null) return unitCube;
            var b = new MeshBuilder();
            b.Box(Vector3.zero, Vector3.one, 1f, false, false);
            unitCube = b.Build("unitcube");
            return unitCube;
        }

        static Mesh Build(float R, float W, Style style)
        {
            var b = new MeshBuilder(5);   // 0 tyre, 1 rim, 2 brake disc, 3 caliper, 4 dark (grooves, barrel back)
            float hw = W * 0.5f;
            // rim radius: low-profile sports tyre (big rim), taller truck sidewall (smaller rim)
            float rr = R * (style == Style.Split5 ? 0.74f : style == Style.Deep6 ? 0.6f : 0.68f);
            const int seg = 40;

            // tyre: walk around the cross-section with the outside on the left
            b.Sub(0).Lathe(new[]
            {
                new Vector2(-hw * 0.92f, rr * 0.98f),
                new Vector2(-hw, rr * 1.06f),
                new Vector2(-hw * 1.03f, R * 0.84f),
                new Vector2(-hw * 0.98f, R * 0.93f),
                new Vector2(-hw * 0.88f, R * 0.985f),
                new Vector2(-hw * 0.72f, R),
                new Vector2(hw * 0.72f, R),
                new Vector2(hw * 0.88f, R * 0.985f),
                new Vector2(hw * 0.98f, R * 0.93f),
                new Vector2(hw * 1.03f, R * 0.84f),
                new Vector2(hw, rr * 1.06f),
                new Vector2(hw * 0.92f, rr * 0.98f),
            }, seg, Vector3.zero);

            float face = hw * 0.78f;
            // rim lip + barrel (barrel seen through the spokes)
            b.Sub(1).Lathe(new[]
            {
                new Vector2(face - 0.01f, rr * 0.86f),
                new Vector2(face + 0.012f, rr * 0.9f),
                new Vector2(face + 0.012f, rr * 1.0f),
                new Vector2(face - 0.005f, rr * 1.02f),
            }, seg, Vector3.zero);
            b.Sub(1).Lathe(new[]
            {
                new Vector2(face - 0.01f, rr * 0.97f),
                new Vector2(-hw * 0.85f, rr * 0.97f),
            }, seg, Vector3.zero);
            // dark inner barrel back wall
            b.Sub(4).Disc(new Vector3(-hw * 0.6f, 0, 0), rr * 0.97f, seg, 1f);

            // spokes
            float dish = style == Style.Deep6 ? 0.06f : style == Style.Classic ? 0.01f : 0.035f;
            int count = style == Style.Mesh10 ? 10 : style == Style.Split5 ? 10 : style == Style.Deep6 ? 6 : 14;
            float spokeW = style == Style.Mesh10 ? rr * 0.1f : style == Style.Split5 ? rr * 0.11f : style == Style.Deep6 ? rr * 0.24f : rr * 0.06f;
            for (int i = 0; i < count; i++)
            {
                float a = i * 360f / count;
                if (style == Style.Split5) a = (i / 2) * 72f + (i % 2 == 0 ? -6f : 6f);
                var rot = Quaternion.Euler(a, 0, 0);
                float len = rr * 0.72f;
                Vector3 mid = rot * new Vector3(face - dish * 0.5f, rr * 0.2f + len * 0.5f, 0);
                // tilt the spoke so the hub sits further out than the rim (concave dish)
                var tilt = Quaternion.Euler(0, 0, -Mathf.Atan2(dish, len) * Mathf.Rad2Deg);
                var xf = Matrix4x4.TRS(mid, rot * tilt, new Vector3(0.045f, len, spokeW));
                b.Sub(1).Add(UnitCube(), xf, 1);
            }
            // hub + centre cap + lug nuts
            b.Sub(1).Lathe(new[]
            {
                new Vector2(face - 0.04f, rr * 0.26f),
                new Vector2(face + 0.005f, rr * 0.26f),
                new Vector2(face + 0.012f, rr * 0.2f),
            }, 24, Vector3.zero);
            b.Sub(1).Disc(new Vector3(face + 0.013f, 0, 0), rr * 0.2f, 24, 1f);   // centre cap in the rim finish (it used the caliper red)
            for (int i = 0; i < 5; i++)
            {
                var rot = Quaternion.Euler(i * 72f + 36f, 0, 0);
                b.Sub(1).Add(UnitCube(), Matrix4x4.TRS(rot * new Vector3(face + 0.005f, rr * 0.15f, 0), rot, new Vector3(0.02f, 0.022f, 0.022f)), 1);
            }

            // tread: shallow dark grooves in the tread face (three rings + fine cross cuts drawn just inside the
            // surface), so the silhouette stays a clean round tyre; a thin rim-protector lip on each sidewall
            foreach (float gx in new[] { -0.42f, 0f, 0.42f })
                b.Sub(4).Lathe(new[] { new Vector2(hw * gx - 0.006f, R * 0.9995f), new Vector2(hw * gx + 0.006f, R * 0.9995f) }, seg * 2, Vector3.zero);
            for (int k = -1; k <= 1; k += 2)
                b.Sub(0).Lathe(k > 0
                    ? new[] { new Vector2(hw * 0.96f, rr * 1.12f), new Vector2(hw * 1.04f, rr * 1.16f), new Vector2(hw * 0.97f, rr * 1.2f) }
                    : new[] { new Vector2(-hw * 0.97f, rr * 1.2f), new Vector2(-hw * 1.04f, rr * 1.16f), new Vector2(-hw * 0.96f, rr * 1.12f) }, seg, Vector3.zero);

            // brake disc (behind the spokes) and caliper
            b.Sub(2).Disc(new Vector3(face - 0.07f, 0, 0), rr * 0.75f, seg, 1f);
            b.Sub(2).Lathe(new[] { new Vector2(face - 0.07f, rr * 0.75f), new Vector2(face - 0.1f, rr * 0.75f) }, seg, Vector3.zero);
            var cal = Matrix4x4.TRS(new Vector3(face - 0.06f, rr * 0.58f, -rr * 0.32f), Quaternion.Euler(-35f, 0, 0), new Vector3(0.045f, rr * 0.16f, rr * 0.3f));   // small caliper, about 1/6 of the disc
            b.Sub(3).Add(UnitCube(), cal, 3);

            return b.Build("wheel_" + style);
        }

        static Material tyreMat, discMat, darkMat;
        public static Material[] Materials(Color rimColor, Color caliper)
        {
            if (tyreMat == null)
            {
                tyreMat = Res.Mat(new Color(0.05f, 0.05f, 0.052f), 0.22f, 0f);
                discMat = Res.Mat(new Color(0.42f, 0.43f, 0.45f), 0.6f, 0.7f);   // steel disc
            }
            // polished alloy: bright but not a pure mirror (a mirror shows the dark night and reads black)
            var rim = Res.Mat(rimColor, 0.72f, 0.55f);
            Res.SetEmission(rim, rimColor * 0.04f);
            var cal = Res.Mat(caliper, 0.7f, 0.1f);
            if (darkMat == null) darkMat = Res.Mat(new Color(0.008f, 0.008f, 0.01f), 0.1f, 0f);
            return new[] { tyreMat, rim, discMat, cal, darkMat };
        }
    }
}
