using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// City traffic around the player. Cars drive in their lane, always facing the way they move,
    /// slow down behind other cars and the player, and pick a turn at intersections. Cars far
    /// away are moved to a fresh spot near the player so the streets always feel busy.
    /// </summary>
    public class Traffic : MonoBehaviour
    {
        class TCar
        {
            public GameObject go;
            public int axis;          // 0: drives along Z, 1: drives along X
            public int road;          // road line index
            public int lane;          // 0,1 = negative side (drive -dir), 2,3 = positive side
            public float pos;         // position along the road
            public float speed, cruise;
            public int lastNode = int.MinValue;
            // drive on the right (Dubai): on a Z road the +X side goes +Z; on an X road the -Z side goes +X
            public float dir => (lane < 2 ? -1f : 1f) * (axis == 0 ? 1f : -1f);
        }

        public int count = 16;
        public float radius = 230f;
        readonly List<TCar> cars = new List<TCar>();
        Transform player;
        System.Random rng = new System.Random(3);
        static readonly string[] Models = { "sedan", "suv", "euro", "tuner", "muscle", "classic", "rotary", "pickup", "sport" };

        public void Setup(Transform playerT)
        {
            player = playerT;
            count = GfxSetup.IsMobile ? 18 : 32;   // busier streets
            for (int i = 0; i < count; i++)
            {
                var id = Models[i % Models.Length];
                var go = CarFactory.BuildTraffic(id, transform, Color.gray);
                var t = new TCar { go = go };
                Respawn(t, true);
                cars.Add(t);
            }
            Parked();
        }

        /// <summary>
        /// Cars parked along the kerb in the strip outside the outer lane (lanes end 9.6 m from the road
        /// centre, the kerb is at 12 m), away from crossings and the LSX forecourt. Lights off, culled when far.
        /// </summary>
        void Parked()
        {
            var root = new GameObject("Parked").transform;
            root.SetParent(transform, false);
            var prng = new System.Random(11);
            float off = City.Road * 0.5f - 1.25f;
            Vector3 door = City.I != null ? City.I.GarageDoor : new Vector3(1e6f, 0, 1e6f);
            int n = 0, max = GfxSetup.IsMobile ? 60 : 140;
            for (int k = 0; k <= City.N && n < max; k++)
                for (int seg = 0; seg < City.N && n < max; seg++)
                    for (int axis = 0; axis < 2; axis++)
                        for (int side = -1; side <= 1; side += 2)
                        {
                            if (prng.NextDouble() > 0.42) continue;
                            float line = City.RoadLine(k) + side * off;
                            float s0 = seg * City.Pitch + 14f, s1 = seg * City.Pitch + City.Block - 14f;
                            int cnt = 1 + prng.Next(2);
                            float along = s0 + (float)prng.NextDouble() * (s1 - s0 - 8f);
                            for (int c = 0; c < cnt && along < s1; c++, along += 6.5f + (float)prng.NextDouble() * 6f)
                            {
                                Vector3 p = axis == 0 ? new Vector3(line, 0, along) : new Vector3(along, 0, line);
                                if ((p - door).sqrMagnitude < 20f * 20f) continue;
                                // facing the way that side's traffic drives (right-hand traffic)
                                Vector3 fwd = axis == 0 ? new Vector3(0, 0, side) : new Vector3(-side, 0, 0);
                                var go = CarFactory.BuildTraffic(Models[prng.Next(Models.Length)], root, Color.gray, false);
                                go.transform.SetPositionAndRotation(p, Quaternion.LookRotation(fwd));
                                go.isStatic = true;
                                var lg = go.AddComponent<LODGroup>();
                                lg.SetLODs(new[] { new LOD(0.025f, go.GetComponentsInChildren<Renderer>()) });
                                lg.RecalculateBounds();
                                n++;
                            }
                        }
        }

        public void SetPlayer(Transform t) => player = t;

        void Respawn(TCar t, bool anywhere)
        {
            Vector3 p = player ? player.position : Vector3.zero;
            for (int tries = 0; tries < 20; tries++)
            {
                t.axis = rng.Next(2);
                t.lane = rng.Next(4);
                // road line near the player
                float across = t.axis == 0 ? p.x : p.z;
                int k = Mathf.Clamp(Mathf.RoundToInt((across + City.Road * 0.5f) / City.Pitch) + rng.Next(-2, 3), 0, City.N);
                t.road = k;
                float along = (t.axis == 0 ? p.z : p.x) + (float)(rng.NextDouble() * 2 - 1) * radius;
                along = Mathf.Clamp(along, 0, City.Extent - City.Road);
                t.pos = along;
                Vector3 w = World(t);
                float d = Vector3.Distance(w, p);
                if (anywhere ? d > 25 : (d > 90 && d < radius)) break;
            }
            t.cruise = 11f + (float)rng.NextDouble() * 8f;
            t.speed = t.cruise;
            t.lastNode = int.MinValue;
            Place(t);
        }

        Vector3 World(TCar t)
        {
            float line = City.RoadLine(t.road) + City.LaneOffset(t.lane);
            return t.axis == 0 ? new Vector3(line, 0, t.pos) : new Vector3(t.pos, 0, line);
        }

        void Place(TCar t)
        {
            var p = World(t);
            Vector3 fwd = t.axis == 0 ? new Vector3(0, 0, t.dir) : new Vector3(t.dir, 0, 0);
            t.go.transform.SetPositionAndRotation(p, Quaternion.LookRotation(fwd, Vector3.up));
        }

        void Update()
        {
            if (player == null) return;
            float dt = Time.deltaTime;
            foreach (var t in cars)
            {
                Vector3 p = t.go.transform.position;
                if (Vector3.Distance(p, player.position) > radius + 40f) { Respawn(t, false); continue; }

                // keep a gap to anything ahead in the lane (other traffic or the player)
                float target = t.cruise;
                Vector3 fwd = t.go.transform.forward;
                float ahead = 999f;
                foreach (var o in cars)
                {
                    if (o == t) continue;
                    Vector3 d = o.go.transform.position - p;
                    float f = Vector3.Dot(d, fwd);
                    if (f > 0 && f < ahead && Mathf.Abs(Vector3.Dot(d, t.go.transform.right)) < 2.2f) ahead = f;
                }
                Vector3 dp = player.position - p;
                float pf = Vector3.Dot(dp, fwd);
                if (pf > 0 && Mathf.Abs(Vector3.Dot(dp, t.go.transform.right)) < 2.6f) ahead = Mathf.Min(ahead, pf);
                if (ahead < 30f) target = Mathf.Min(target, Mathf.Max(0, (ahead - 8f) * 0.8f));
                t.speed = Mathf.MoveTowards(t.speed, target, (target < t.speed ? 14f : 4f) * dt);
                float prevPos = t.pos;
                t.pos += t.speed * t.dir * dt;

                // intersections: when we cross a road line, maybe turn onto it
                int node = Mathf.RoundToInt((t.pos + City.Road * 0.5f) / City.Pitch);
                float nodePos = City.RoadLine(node);
                if (node != t.lastNode && (prevPos - nodePos) * (t.pos - nodePos) <= 0 && node >= 0 && node <= City.N)
                {
                    t.lastNode = node;
                    int r = rng.Next(10);
                    if (r < 3)
                    {
                        // turn: new axis, the old road becomes our position, the crossing road becomes our road
                        float oldLine = City.RoadLine(t.road) + City.LaneOffset(t.lane);
                        int newRoad = node;
                        int newLane = rng.Next(4);
                        t.axis = 1 - t.axis;
                        t.road = newRoad;
                        t.lane = newLane;
                        t.pos = oldLine;
                        t.lastNode = Mathf.RoundToInt((t.pos + City.Road * 0.5f) / City.Pitch);
                    }
                }
                if (t.pos < -City.Road || t.pos > City.Extent) { Respawn(t, false); continue; }

                // smooth heading change after a turn
                Vector3 want = World(t);
                Vector3 wantFwd = t.axis == 0 ? new Vector3(0, 0, t.dir) : new Vector3(t.dir, 0, 0);
                var rot = Quaternion.RotateTowards(t.go.transform.rotation, Quaternion.LookRotation(wantFwd), 120f * dt);
                Vector3 np = Vector3.MoveTowards(p, want, Mathf.Max(t.speed * 1.5f, 6f) * dt + 0.02f);
                t.go.transform.SetPositionAndRotation(new Vector3(np.x, 0, np.z), rot);
            }
        }
    }
}
