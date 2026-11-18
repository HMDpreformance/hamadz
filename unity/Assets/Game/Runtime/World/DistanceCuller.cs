using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Phones: "if things are far away, why draw them from very far" (Hamad). Small things stop being drawn at a short
    /// distance, mid-rise buildings at a middle one, and only towers and landmarks stay to the far clip, so the skyline is
    /// kept while the thousands of villas, palms and street pieces far away cost nothing. The night haze hides the edge.
    /// Each object is checked against the camera a slice per frame (all of them about every half second), and switched
    /// with SetActive only when it crosses its distance. PC: not used (full distances).
    /// </summary>
    public class DistanceCuller : MonoBehaviour
    {
        public static DistanceCuller I;
        // phone distances in metres (tuned by eye against the haze)
        public const float Palm = 300f, LowBuilding = 380f, MidBuilding = 750f, Street = 420f;

        struct Item { public GameObject go; public Vector3 p; public float d2; }
        readonly List<Item> items = new List<Item>();
        int cursor;
        Transform cam;
        Vector3 lastCam = new Vector3(1e6f, 0, 0);

        public static bool Wanted => GfxSetup.IsMobile && !(Application.isEditor && PlayerPrefs.GetInt("hmd_nocull", 0) == 1);   // Editor A/B switch

        public static void Ensure(Transform parent)
        {
            if (I != null || !Wanted) return;
            I = new GameObject("DistanceCuller").AddComponent<DistanceCuller>();
            I.transform.SetParent(parent, false);
        }

        /// <summary>Register an object to hide beyond 'dist' metres (horizontal distance from the camera).</summary>
        public static void Add(GameObject go, Vector3 p, float dist)
        {
            if (I == null || go == null || dist <= 0f) return;
            I.items.Add(new Item { go = go, p = p, d2 = dist * dist });
        }

        /// <summary>Distance for a building of this height: low ones go first, towers stay (0 = never culled).</summary>
        public static float ForBuilding(float height) => height >= 80f ? 0f : height >= 25f ? MidBuilding : LowBuilding;

        void Update()
        {
            if (cam == null) { var c = Camera.main; if (c == null) return; cam = c.transform; }
            int n = items.Count; if (n == 0) return;
            Vector3 cp = cam.position;
            int slice = Mathf.Max(64, n / 30);   // all items about twice a second at 60 fps
            // a jump (teleport to the garage, respawn, start): check everything this frame, so nothing near pops in late
            if ((cp - lastCam).sqrMagnitude > 60f * 60f) slice = n;
            lastCam = cp;
            for (int k = 0; k < slice && n > 0; k++)
            {
                if (cursor >= n) cursor = 0;
                var it = items[cursor++];
                if (it.go == null) continue;
                float dx = it.p.x - cp.x, dz = it.p.z - cp.z;
                bool on = dx * dx + dz * dz <= it.d2;
                if (it.go.activeSelf != on) it.go.SetActive(on);
            }
        }

        public int Count => items.Count;
        public int ActiveCount { get { int a = 0; foreach (var it in items) if (it.go != null && it.go.activeSelf) a++; return a; } }
    }
}
