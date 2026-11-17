using System.Collections;
using System.IO;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// -newcity -hmdshots: an autopilot test drive on the new city (highways, flyovers, ramps) that logs every bump,
    /// drop, stop and run-off by json coordinates, then a set of nc_ screenshots. Pictures go to the Shots folder.
    /// </summary>
    public class NcShots : MonoBehaviour
    {
        string dir;
        Game g; CarController car; NewCity nc;
        int bumps, drops, stops, offs;
        float K => nc != null ? nc.Scale / 0.75f : 1f;   // shot distances were tuned at plan scale 0.75

        IEnumerator Start()
        {
            // Test runs are unattended: keep going when the window loses focus (Player setting runInBackground is off).
            Application.runInBackground = true;
            dir = Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".", "Shots");
            Directory.CreateDirectory(dir);
            g = Game.I; car = g.car; nc = NewCity.I;
            var pi = car.GetComponent<PlayerInput>(); if (pi) pi.enabled = false;
            yield return new WaitForSeconds(1.5f);
            yield return Shot("nc_00_spawn");
            while (g.state == Game.State.Intro) yield return null;

            // -ncdrive <part>: which roads to drive this run (the city is big: split into runs)
            //   all | highway | main | ramp | street | none.  -ncaudit: static road audit (raycasts along every road).
            string cl = System.Environment.CommandLine;
            string part = "default";
            var argv = System.Environment.GetCommandLineArgs();
            for (int a = 0; a + 1 < argv.Length; a++) if (argv[a] == "-ncdrive") part = argv[a + 1];
            if (cl.Contains("-ncaudit")) Audit();
            if (cl.Contains("-uncap")) { Application.targetFrameRate = -1; QualitySettings.vSyncCount = 0; }
            fpsSum = 0; fpsN = 0; fpsMin = 999;
            // a road can end next to the LSX door: entering the garage would park the car in the shop with locked
            // controls and every later drive would start from there. No garage while the autopilot drives.
            var enter = g.garage.OnEnter; g.garage.OnEnter = null;
            if (part == "tests") yield return OwnerTests();
            else if (part == "profiles") Profiles();
            else if (part == "junctions") yield return JunctionTests();
            else if (part == "bridge") yield return BridgeTests();
            else if (part == "look") yield return LookShots();
            else if (part == "video") yield return VideoDrive();
            else if (part == "default")
            {
                foreach (var rd in nc.roads) if (rd.cls == "highway") yield return Drive(rd, 230f, rd.name == "E11");
                int ramps = 0;
                foreach (var rd in nc.roads) if (rd.cls == "ramp" && ramps++ < 6) yield return Drive(rd, 70f, false);
            }
            else if (part != "none")
            {
                var perName = new System.Collections.Generic.Dictionary<string, int>();
                foreach (var rd in nc.roads)
                {
                    if (part != "all" && rd.cls != part) continue;
                    if (rd.cls == "street")
                    {
                        // a sample: at most 2 streets per name and only longer ones
                        perName.TryGetValue(rd.name, out int cnt); if (cnt >= 2 || rd.pts.Count < 6) continue; perName[rd.name] = cnt + 1;
                    }
                    float v = rd.cls == "highway" ? 200f : rd.cls == "main" ? 120f : rd.cls == "ramp" ? 70f : 70f;
                    yield return Drive(rd, v, rd.name == "E11" && part == "highway");
                }
            }
            g.garage.OnEnter = enter;
            if (fpsN > 0) Debug.Log($"[HMD] nc fps while driving: avg {fpsSum / fpsN:F0}, min {fpsMin:F0} over {fpsN} frames ({(cl.Contains("-uncap") ? "uncapped" : "capped at 60")})");
            Debug.Log($"[HMD] nc drive summary: bumps={bumps} drops={drops} stops={stops} runoffs={offs}");

            if (cl.Contains("-ncnostills")) { Debug.Log("[HMD] nc run done (no stills)"); Application.Quit(); yield break; }
            // stills
            g.rig.mode = CameraRig.Mode.Fixed;
            car.Body.isKinematic = true;
            // on top of the highest flyover deck, and under it
            Vector3 top = Vector3.zero; NewCity.Road topRd = null; int topI = 0;
            foreach (var rd in nc.roads) for (int i = 0; i + 1 < rd.pts.Count; i++) if (rd.pts[i].y > top.y) { top = rd.pts[i]; topRd = rd; topI = i; }
            if (topRd != null)
            {
                Vector3 d = Dir(topRd, topI);
                Park(top, d);
                Cam(top - d * 14f + Vector3.up * 4f + Vector3.Cross(Vector3.up, d) * 5f, top + d * 30f);
                yield return Shot("nc_02_flyover_top");
                Vector3 under = NewCity.Surface(top + Vector3.down * 3f + Vector3.Cross(Vector3.up, d) * 22f * K);
                Cam(under + Vector3.up * 1.6f, top + Vector3.down * 1f);
                yield return Shot("nc_03_under_flyover");
            }
            if (nc.junctions.Count > 0)
            {
                var j = nc.junctions[nc.junctions.Count / 3];
                Cam(j + new Vector3(-28, 9, -28), j);
                yield return Shot("nc_04_junction");
            }
            Vector3 palm = Vector3.zero, hills = Vector3.zero;
            foreach (var (name, pos) in nc.districts) { if (name.Contains("Palm")) palm = pos; if (name.Contains("Hills")) hills = pos; }
            if (palm != Vector3.zero)
            {
                Vector3 p = NewCity.Surface(palm + Vector3.up * 30f);
                Cam(p + new Vector3(-90, 70, -140) * K, p);
                yield return Shot("nc_05_palm");
            }
            if (hills != Vector3.zero)
            {
                Vector3 p = NewCity.Surface(hills + Vector3.up * 30f);
                Cam(p + new Vector3(-50, 12, -60) * K, p + Vector3.up * 2f);
                yield return Shot("nc_06_dubai_hills");
            }
            if (nc.blocks.Count > 0)
            {
                var b = nc.blocks[0];
                Vector3 f = Quaternion.Euler(0, b.yaw, 0) * Vector3.forward;
                Cam(b.pos - f * 18f + Vector3.up * 3f + Vector3.Cross(Vector3.up, f) * 3f, b.pos + Vector3.up);
                yield return Shot("nc_07_road_block");
            }
            // round 10: the dressed city
            {
                Vector3 S(float x, float z) => NewCity.Surface(new Vector3(x, 40f, z));
                Vector3 LM(string k, Vector3 def) { foreach (var lm in NewCityDressing.Landmarks) if (lm.kind == k) return lm.p; return def; }
                Vector3 gar = nc.Garage;
                Cam(gar + new Vector3(-16, 5, -26), gar + new Vector3(0, 4, 6)); yield return Shot("nc_10_lsx");
                Cam(gar + new Vector3(-170, 140, -170) * K, gar + new Vector3(30, 0, 120) * K); yield return Shot("nc_18_lsx_aerial");
                Vector3 needle = LM("needle_tower", new Vector3(1267.5f, 3.7f, 1207.5f));
                // on a road west of Downtown looking east at the needle tower
                Vector3 best = Vector3.zero; float bd = float.MaxValue;
                foreach (var rd in nc.roads) if (rd.cls == "highway" || rd.cls == "main") foreach (var p in rd.pts) { float d = Mathf.Abs(Vector3.Distance(p, needle) - 650f * K) + Mathf.Abs(p.z - needle.z) * 0.5f; if (d < bd) { bd = d; best = p; } }
                Vector3 dn = (needle - best); dn.y = 0; dn.Normalize();
                best += Vector3.Cross(Vector3.up, dn) * 6.5f;   // right-hand lane, clear of the median lamps
                Park(best, dn);
                Debug.Log($"[HMD] shot nc_11 from {V(best)}, heading to the needle at {V(needle)}");
                Cam(NewCity.Surface(best) - dn * 7f + Vector3.up * 2.2f, needle + Vector3.up * 120f); yield return Shot("nc_11_needle_ahead");
                Vector3 tw = LM("twisted_tower", new Vector3(390f, 2f, 1080f));
                Cam(S(tw.x - 120, tw.z - 140) + Vector3.up * 25f, tw + Vector3.up * 80f); yield return Shot("nc_12_marina");
                Vector3 wheel = LM("big_wheel", new Vector3(187.5f, 0f, 1290f));
                Cam(S(wheel.x + 90 * K, wheel.z - 120 * K) + Vector3.up * 6f, wheel + Vector3.up * 50f); yield return Shot("nc_13_jbr_beach");
                Vector3 arch = new Vector3(465f, 1.35f, 1696.5f);
                foreach (var lm in NewCityDressing.Landmarks) if (lm.kind == "arch_hotel") arch = lm.p;
                Vector3 palmC = arch + new Vector3(0, -arch.y, -280f * K);   // fronds centre: south of the arch hotel on the crescent
                Vector3 mid = (palmC + arch) * 0.5f; mid.y = 0;
                // from above the trunk, looking along the fronds to the arch hotel on the crescent
                Vector3 toArch = arch - palmC; toArch.y = 0; toArch = toArch.sqrMagnitude > 1 ? toArch.normalized : Vector3.forward;
                Cam(palmC - toArch * 260f + Vector3.up * 210f, mid + Vector3.up * 10f); yield return Shot("nc_14_palm");
                Vector3 frondC = (palmC + arch) * 0.5f; frondC.y = 0;
                g.rig.Cam.transform.position = frondC + Vector3.up * 700f * K; g.rig.SetFixed(frondC + Vector3.up * 700f * K, frondC + Vector3.forward * 0.5f, false);   // straight down
                yield return Shot("nc_14b_palm_top");
                Cam(NewCity.Surface(mid) + Vector3.up * 1.8f - toArch * 20f, arch + Vector3.up * 40f); yield return Shot("nc_14c_palm_road");
                Debug.Log($"[HMD] palm: centre {palmC} arch {arch}");
                Cam(S(gar.x - 60, gar.z - 40) + Vector3.up * 2f, gar + new Vector3(60, 5, 30)); yield return Shot("nc_15_al_quoz");
                Vector3 hl = new Vector3(1125f, 0, 232.5f) * K; foreach (var (dn3, dp3) in nc.districts) if (dn3.Contains("Hills")) hl = new Vector3(dp3.x, 0, dp3.z);
                Cam(S(hl.x - 70, hl.z - 70) + Vector3.up * 18f, S(hl.x, hl.z)); yield return Shot("nc_16_hills_villas");
                Cam(nc.MeshBounds.center + new Vector3(-700, 520, -900) * K, needle + Vector3.up * 60f); yield return Shot("nc_17_aerial_city");
            }
            // the full map of the new city, and the minimap while driving
            g.hud.Map.Open();
            yield return Shot("nc_09_map");
            g.hud.Map.Close();
            var c = nc.MeshBounds.center;
            Cam(c + new Vector3(-500, 650, -700), c);
            yield return Shot("nc_08_aerial");
            Debug.Log("[HMD] nc shots done");
            Application.Quit();
        }

        float fpsSum, fpsMin = 999; int fpsN;

        /// <summary>Static road audit: along every road, raycast down at the centre and near both edges every ~5 m and
        /// report spots where the first thing hit is not asphalt (ground or a kerb poking through, a gap) or where the
        /// surface is far from the plan height; also lamps standing on asphalt. Results are grouped per stretch.</summary>
        void Audit()
        {
            Physics.SyncTransforms();
            int stretches = 0, checkedPts = 0;
            foreach (var rd in nc.roads)
            {
                string open = null; Vector3 openAt = Vector3.zero, last = Vector3.zero; int n = 0;
                void Close() { if (open != null) { Debug.Log($"[HMD] audit {rd.name} ({rd.cls}): {open} from ({openAt.x:F0},{openAt.z:F0}) to ({last.x:F0},{last.z:F0}), {n} samples"); stretches++; } open = null; n = 0; }
                for (int i = 1; i < rd.pts.Count; i++)
                {
                    Vector3 a = rd.pts[i - 1], c = rd.pts[i];
                    Vector3 d = c - a; d.y = 0; float len = d.magnitude; if (len < 0.1f) continue; d /= len;
                    Vector3 side = Vector3.Cross(Vector3.up, d);
                    for (float t = 0; t < len; t += 5f)
                    {
                        Vector3 p = Vector3.Lerp(a, c, t / len);
                        string bad = null;
                        foreach (float o in new[] { 0f, rd.width * 0.5f - 1f, -(rd.width * 0.5f - 1f) })
                        {
                            Vector3 q = p + side * o;
                            if (!Physics.Raycast(q + Vector3.up * 2.5f, Vector3.down, out var hit, 6f)) { bad = "hole (nothing under the road)"; break; }
                            string hn = hit.collider.name.ToLowerInvariant();
                            if (!hn.Contains("asphalt"))
                            {
                                if (hn.Contains("terrain")) bad = "ground through the road";
                                else if (hn.Contains("sidewalk") || hn.Contains("concrete")) bad = o == 0 ? "kerb/concrete across the road" : null;
                                else if (hn.Contains("barrier")) bad = o == 0 ? "barrier on the road" : null;
                                else if (hn.StartsWith("dress")) bad = "building on the road";
                                else bad = "other object on the road (" + hit.collider.name + ")";
                                if (bad != null) break;
                            }
                            else if (Mathf.Abs(hit.point.y - p.y) > 0.8f) { bad = $"surface {hit.point.y - p.y:+0.0;-0.0} m off the plan height"; break; }
                        }
                        checkedPts++;
                        if (bad != open) { Close(); if (bad != null) { open = bad; openAt = p; } }
                        if (bad != null) { last = p; n++; }
                    }
                }
                Close();
            }
            Debug.Log($"[HMD] audit done: {checkedPts} spots checked, {stretches} defect stretches");
        }

        static Vector3 Dir(NewCity.Road rd, int i)
        {
            var d = rd.pts[Mathf.Min(i + 1, rd.pts.Count - 1)] - rd.pts[Mathf.Max(0, i - (i + 1 >= rd.pts.Count ? 1 : 0))];
            d.y = 0; return d.sqrMagnitude > 0.01f ? d.normalized : Vector3.forward;
        }

        void Park(Vector3 p, Vector3 d) => car.Place(NewCity.Surface(p) + Vector3.up * car.RestHeight, Quaternion.LookRotation(d));

        void Cam(Vector3 pos, Vector3 look) => g.rig.SetFixed(pos, look, false);

        /// <summary>Autopilot along a road centre line (in the right half of the road) at a target speed; logs trouble.</summary>
        IEnumerator Drive(NewCity.Road rd, float kmh, bool shoot)
        {
            if (rd.pts.Count < 4) yield break;
            car.Body.isKinematic = false; car.inputLocked = false; car.dynoMode = false;
            if (g.state != Game.State.Drive) Debug.Log($"[HMD] nc WARNING: game state {g.state} before {rd.name}");
            g.rig.SnapChase();
            g.rig.mode = CameraRig.Mode.Chase;
            float lane = rd.width * 0.25f;
            Vector3 d0 = Dir(rd, 1);
            Vector3 start = rd.pts[1] + Vector3.Cross(Vector3.up, d0) * lane;   // pts[0] can sit on the map edge
            car.Teleport(NewCity.Surface(start) + Vector3.up * 0.6f, Quaternion.LookRotation(d0));
            car.Body.linearVelocity = d0 * 20f;
            yield return new WaitForFixedUpdate(); yield return new WaitForFixedUpdate();
            if (Vector3.Distance(car.transform.position, start) > 8f) { car.Teleport(NewCity.Surface(start) + Vector3.up * 0.6f, Quaternion.LookRotation(d0)); car.Body.linearVelocity = d0 * 20f; yield return new WaitForFixedUpdate(); }
            float roadLen = 0; for (int q = 1; q < rd.pts.Count; q++) roadLen += Vector3.Distance(rd.pts[q - 1], rd.pts[q]);
            float tMax = Mathf.Max(40f, roadLen / (Mathf.Min(kmh, 120f) / 3.6f) * 1.6f + 10f);
            int idx = 1; float t = 0, logT = 0, slow = 0, lastVy = 0; bool shot = false;
            float maxKmh = 0;
            while (idx < rd.pts.Count - 2 && t < tMax)
            {
                t += Time.deltaTime;
                Vector3 p = car.transform.position;
                // advance along the line
                while (idx < rd.pts.Count - 2 && Vector3.Dot(rd.pts[idx + 1] - p, rd.pts[idx + 1] - rd.pts[idx]) < 0) idx++;
                float ahead = Mathf.Max(14f, car.SpeedKmh / 3.6f * 0.7f);
                int k = idx; while (k < rd.pts.Count - 1 && Vector3.Distance(rd.pts[k], p) < ahead) k++;
                Vector3 dk = Dir(rd, k);
                Vector3 target = rd.pts[k] + Vector3.Cross(Vector3.up, dk) * lane;
                Vector3 to = target - p; to.y = 0;
                float ang = Vector3.SignedAngle(Vector3.ProjectOnPlane(car.transform.forward, Vector3.up), to, Vector3.up);
                car.steer = Mathf.Clamp(ang / 18f, -1f, 1f);
                float v = car.SpeedKmh;
                { float f0 = 1f / Mathf.Max(0.0001f, Time.unscaledDeltaTime); fpsSum += f0; fpsN++; if (t > 2f) fpsMin = Mathf.Min(fpsMin, f0); }
                car.throttle = v < kmh ? 1f : 0.2f;
                car.brake = v > kmh + 25f || Mathf.Abs(ang) > 35f && v > 90f ? 0.6f : 0f;
                maxKmh = Mathf.Max(maxKmh, v);

                // checks against the centre line
                Vector3 seg = rd.pts[idx + 1] - rd.pts[idx];
                float f = Mathf.Clamp01(Vector3.Dot(p - rd.pts[idx], seg) / Mathf.Max(0.01f, seg.sqrMagnitude));
                Vector3 onLine = Vector3.Lerp(rd.pts[idx], rd.pts[idx + 1], f);
                float side = Vector3.ProjectOnPlane(p - onLine, Vector3.up).magnitude;
                float vy = car.Body.linearVelocity.y;
                if (Mathf.Abs(vy - lastVy) > 4.5f) { bumps++; Debug.Log($"[HMD] nc BUMP on {rd.name} at ({p.x:F0},{p.y:F1},{p.z:F0}) dVy={vy - lastVy:F1} kmh={v:F0}"); }
                lastVy = vy;
                if (p.y < onLine.y - 2.5f) { drops++; Debug.Log($"[HMD] nc DROP on {rd.name} at ({p.x:F0},{p.y:F1},{p.z:F0}) line y={onLine.y:F1}"); break; }
                if (side > rd.width * 0.5f + 3f && (side > rd.width * 0.5f + 12f || !Under(p).ToLowerInvariant().Contains("asphalt"))) { offs++; Debug.Log($"[HMD] nc RUN-OFF on {rd.name} at ({p.x:F0},{p.z:F0}) {side:F1} m from the centre, under the car: {Under(p)}"); break; }
                if (Vector3.Dot(car.transform.up, Vector3.up) < 0.4f) { Debug.Log($"[HMD] nc FLIP on {rd.name} at ({p.x:F0},{p.y:F1},{p.z:F0})"); drops++; break; }
                slow = (t > 4f && v < 15f) ? slow + Time.deltaTime : 0;
                if (slow > 1.2f)
                {
                    stops++;
                    string what = "nothing";
                    foreach (var hc in Physics.OverlapSphere(p + Vector3.up * 0.8f, 3.5f)) if (!hc.transform.IsChildOf(car.transform)) what = hc.name + "/" + (hc.transform.parent ? hc.transform.parent.name : "-") + (hc is MeshCollider ? "" : " " + hc.bounds.size);
                    Debug.Log($"[HMD] nc STOP (wall?) on {rd.name} at ({p.x:F0},{p.y:F1},{p.z:F0}) touching {what}");
                    break;
                }
                if ((logT -= Time.deltaTime) <= 0) { logT = 1f; Debug.Log($"[HMD] nc {rd.name} ({p.x:F0},{p.y:F1},{p.z:F0}) {v:F0} km/h idx {idx}/{rd.pts.Count}"); }
                if (shoot && !shot && v > 180f) { shot = true; yield return Shot("nc_01_highway_chase"); }
                yield return null;
            }
            Debug.Log($"[HMD] nc drove {rd.name} ({rd.cls}) {idx}/{rd.pts.Count} points in {t:F0} s, max {maxKmh:F0} km/h");
            car.throttle = 0; car.brake = 1; car.steer = 0;
            yield return new WaitForSeconds(0.3f);
            car.brake = 0;
        }

        // ================================================================ the owner's checks (-ncdrive tests)

        static string V(Vector3 p) => $"({p.x:F0},{p.y:F1},{p.z:F0})";
        string Under(Vector3 p)
        {
            string best = "nothing"; float bd = 99;
            foreach (var h in Physics.RaycastAll(p + Vector3.up * 1.5f, Vector3.down, 8f)) if (!h.transform.IsChildOf(car.transform) && h.distance < bd) { bd = h.distance; best = h.collider.name; }
            return best;
        }

        /// <summary>Places a car in the right lane of a road at point i, facing along it (or against it).</summary>
        void PutOn(CarController c, NewCity.Road rd, int i, bool back = false)
        {
            i = Mathf.Clamp(i, 0, rd.pts.Count - 2);
            var d = rd.pts[i + 1] - rd.pts[i]; d.y = 0; d.Normalize(); if (back) d = -d;
            var p = rd.pts[i] + Vector3.Cross(Vector3.up, d) * rd.width * 0.25f;
            c.Body.isKinematic = false; c.inputLocked = false; c.handbrake = false; c.reverseHeld = false;
            c.Teleport(NewCity.Surface(p) + Vector3.up * 0.6f, Quaternion.LookRotation(d));
        }

        // one stability sample window
        float mRoll, mPitch, mYawRate, mSlip, mAir, mTravel; int mBumps; float mLastVy;
        float mLastV, mHit; string mHitWhat = "";
        void ResetM() { mRoll = mPitch = mYawRate = mSlip = mAir = 0; mTravel = 1; mBumps = 0; mLastVy = 0; mLastV = -1; mHit = 0; mHitWhat = ""; }
        void Measure(CarController c)
        {
            var up = c.transform.up; var fw = c.transform.forward;
            mRoll = Mathf.Max(mRoll, Mathf.Abs(Mathf.Asin(Mathf.Clamp(Vector3.Dot(c.transform.right, Vector3.up), -1, 1)) * Mathf.Rad2Deg));
            mPitch = Mathf.Max(mPitch, Mathf.Abs(Mathf.Asin(Mathf.Clamp(Vector3.Dot(fw, Vector3.up), -1, 1)) * Mathf.Rad2Deg));
            mYawRate = Mathf.Max(mYawRate, Mathf.Abs(c.Body.angularVelocity.y) * Mathf.Rad2Deg);
            var v = c.Body.linearVelocity; v.y = 0;
            if (v.magnitude > 8f) mSlip = Mathf.Max(mSlip, Vector3.Angle(Vector3.ProjectOnPlane(fw, Vector3.up), v));
            bool any = false;
            foreach (var w in c.wheels)
            {
                if (!w.GetGroundHit(out var gh)) continue; any = true;
                float travel = (-w.transform.InverseTransformPoint(gh.point).y - w.radius) / Mathf.Max(0.01f, w.suspensionDistance);
                mTravel = Mathf.Min(mTravel, travel);   // 0 = fully compressed (bottomed out)
            }
            if (!any) mAir += Time.fixedDeltaTime;
            float vy = c.Body.linearVelocity.y; if (Mathf.Abs(vy - mLastVy) > 4.5f) mBumps++; mLastVy = vy;
            // a hit: speed drops faster than full braking can (over 2.5 g in one physics step)
            float sp = c.Body.linearVelocity.magnitude;
            if (mLastV >= 0 && (mLastV - sp) / Time.fixedDeltaTime > 25f && mLastV - sp > mHit)
            {
                mHit = mLastV - sp; mHitWhat = "?";
                var bb = c.GetComponentInChildren<BoxCollider>().bounds;   // the body box: the thing that touches walls
                float bd = 99; foreach (var hc in Physics.OverlapSphere(bb.center, 6f)) { if (hc.transform.IsChildOf(c.transform)) continue; float d = bb.SqrDistance(hc.ClosestPoint(bb.center)); if (d < bd) { bd = d; mHitWhat = hc.name; } }
                mHitWhat += $" at {V(c.transform.position)}";
            }
            mLastV = sp;
        }
        string M() => $"roll {mRoll:F1} deg, pitch {mPitch:F1} deg, yaw rate {mYawRate:F0} deg/s, slip angle {mSlip:F0} deg, airborne {mAir:F2} s, least suspension travel left {mTravel * 100:F0}%, bumps {mBumps}{(mHit > 0 ? $", HIT {mHitWhat} losing {mHit * 3.6f:F0} km/h" : "")}";

        /// <summary>Drives a car along a road (autopilot on the right lane) from point i0 for a time; extra steering
        /// and braking come from the callback (t -> (steerAdd, brake, throttleOverride or -1)).</summary>
        IEnumerator Follow(CarController c, NewCity.Road rd, int i0, float kmh, float secs, System.Func<float, Vector3> ctl, bool back = false)
        {
            ResetM();
            var pts = new System.Collections.Generic.List<Vector3>(rd.pts); if (back) { pts.Reverse(); i0 = pts.Count - 2 - i0; }
            int idx = Mathf.Max(0, i0); float t = 0; float lane = rd.width * 0.25f;
            while (t < secs && idx < pts.Count - 2)
            {
                t += Time.fixedDeltaTime;
                Vector3 p = c.transform.position;
                while (idx < pts.Count - 2 && Vector3.Dot(pts[idx + 1] - p, pts[idx + 1] - pts[idx]) < 0) idx++;
                float ahead = Mathf.Max(14f, c.SpeedKmh / 3.6f * 0.7f);
                int k = idx; while (k < pts.Count - 1 && Vector3.Distance(pts[k], p) < ahead) k++;
                var dk = pts[Mathf.Min(k + 1, pts.Count - 1)] - pts[Mathf.Max(0, Mathf.Min(k, pts.Count - 2))]; dk.y = 0; dk.Normalize();
                Vector3 to = pts[k] + Vector3.Cross(Vector3.up, dk) * lane - p; to.y = 0;
                float ang = Vector3.SignedAngle(Vector3.ProjectOnPlane(c.transform.forward, Vector3.up), to, Vector3.up);
                var u = ctl != null ? ctl(t) : new Vector3(0, 0, -1);
                if (u.x >= 9f) yield break;   // the caller says: far enough
                c.steer = Mathf.Clamp(ang / 18f + u.x, -1f, 1f);
                c.throttle = u.z >= 0 ? u.z : (c.SpeedKmh < kmh ? 1f : 0.15f);
                c.brake = u.y;
                if (t > 1.2f) Measure(c);   // not while it settles after the teleport (0.6 m drop)
                if (Mathf.Repeat(t, 2f) < Time.fixedDeltaTime) Debug.Log($"[HMD] follow {rd.name} t {t:F0} {V(p)} {c.SpeedKmh:F0} km/h grounded {c.Grounded} under {Under(p)} gear {c.Gear}");
                yield return new WaitForFixedUpdate();
            }
        }

        static float Grade(NewCity.Road rd, int i)
        {
            var a = rd.pts[i]; var b = rd.pts[Mathf.Min(i + 1, rd.pts.Count - 1)];
            float h = new Vector2(b.x - a.x, b.z - a.z).magnitude; return h > 0.5f ? (b.y - a.y) / h : 0;
        }

        IEnumerator OwnerTests()
        {
            var e11 = nc.Find("E11"); var beach = nc.Find("Beach Road"); var blvd = nc.Find("Downtown Blvd");
            // a long flat straight bit of the E11 for the handling tests
            int flat = 1; float bestF = float.MaxValue;
            for (int i = 2; i + 12 < e11.pts.Count; i++)
            {
                float turn = Vector3.Angle(e11.pts[i + 1] - e11.pts[i], e11.pts[i + 12] - e11.pts[i + 11]);
                float slope = Mathf.Abs(e11.pts[i + 12].y - e11.pts[i].y);
                if (turn + slope * 3 < bestF) { bestF = turn + slope * 3; flat = i; }
            }
            Debug.Log($"[HMD] test: flat E11 stretch from point {flat} {V(e11.pts[flat])}");

            // ---- 1. locked controls
            PutOn(car, e11, flat); yield return new WaitForSeconds(1f);
            car.inputLocked = true; car.throttle = 1; car.reverseHeld = true; var p0 = car.transform.position;
            yield return new WaitForSeconds(3f);
            Debug.Log($"[HMD] test LOCK at standstill (throttle and reverse held): moved {Vector3.Distance(p0, car.transform.position):F2} m in 3 s, gear {car.Gear}, speed {car.SpeedKmh:F1}");
            car.inputLocked = false; car.reverseHeld = false;
            PutOn(car, e11, flat);
            yield return Follow(car, e11, flat, 100f, 12f, t => new Vector3(0, 0, -1));
            float v0 = car.SpeedKmh; car.inputLocked = true; p0 = car.transform.position; float tStop = -1;
            for (float t = 0; t < 8f; t += Time.fixedDeltaTime) { if (tStop < 0 && car.SpeedKmh < 1f) tStop = t; yield return new WaitForFixedUpdate(); }
            var p1 = car.transform.position; yield return new WaitForSeconds(2f);
            Debug.Log($"[HMD] test LOCK at {v0:F0} km/h: stopped after {(tStop < 0 ? "NOT STOPPED" : tStop.ToString("F1") + " s")}, {Vector3.Distance(p0, p1):F0} m; then moved {Vector3.Distance(p1, car.transform.position):F2} m in 2 s, gear {car.Gear}");
            car.inputLocked = false;

            // ---- 2. reverse with RWD (player sport) and AWD (pickup), handbrake while reversing
            yield return ReverseTest(car, e11, flat);
            var pk = CarFactory.Build("pickup", car.transform.position + Vector3.right * 30f, Quaternion.identity, false);
            yield return null;
            car.Body.isKinematic = true; car.transform.position += Vector3.up * 50f; car.Body.position = car.transform.position;   // the sport car out of the way
            yield return ReverseTest(pk, e11, flat);
            Destroy(pk.gameObject);
            yield return null;

            // ---- 3. stability: quick left-right at 80/140/200 on the flat E11 stretch
            foreach (float kmh in new[] { 80f, 140f, 200f })
            {
                PutOn(car, e11, flat - 1 > 1 ? flat - 1 : flat);
                g.rig.SnapChase();
                yield return Follow(car, e11, flat, kmh, 40f, t => car.SpeedKmh >= kmh - 3 ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1));   // 9 = signal: up to speed
                ResetM();
                float h0 = car.transform.eulerAngles.y; float maxDh = 0;
                // 3 s of hard left-right (0.5 s each way, 60 % lock) holding speed
                for (float t = 0; t < 3f; t += Time.fixedDeltaTime)
                {
                    float amp = kmh < 100 ? 0.6f : kmh < 170 ? 0.35f : 0.22f;   // a quick lane-change size input, smaller at speed like a driver
                    car.steer = (Mathf.Repeat(t, 1f) < 0.5f ? amp : -amp); car.throttle = car.SpeedKmh < kmh ? 1 : 0.2f; car.brake = 0;
                    Measure(car); maxDh = Mathf.Max(maxDh, Mathf.Abs(Mathf.DeltaAngle(h0, car.transform.eulerAngles.y)));
                    yield return new WaitForFixedUpdate();
                }
                car.steer = 0;
                for (float t = 0; t < 2f; t += Time.fixedDeltaTime) { Measure(car); maxDh = Mathf.Max(maxDh, Mathf.Abs(Mathf.DeltaAngle(h0, car.transform.eulerAngles.y))); yield return new WaitForFixedUpdate(); }
                bool spun = maxDh > 75f || mSlip > 35f; bool rolled = Vector3.Dot(car.transform.up, Vector3.up) < 0.5f;
                Debug.Log($"[HMD] test SLALOM {kmh:F0} km/h: heading swing {maxDh:F0} deg, {M()}, now {car.SpeedKmh:F0} km/h -> {(rolled ? "ROLLED" : spun ? "SPUN" : "stable")}");
            }

            // ---- 4. hard braking downhill: the steepest down stretch of a ramp or bridge (main/highway too)
            NewCity.Road dr = null; int di = 0; float dg = 0;
            foreach (var rd in nc.roads) if (rd.cls != "street") for (int i = 3; i + 3 < rd.pts.Count; i++) { float gr = -Grade(rd, i); if (gr > dg) { dg = gr; dr = rd; di = i; } }
            if (dr != null)
            {
                int st = Mathf.Max(1, di - 6);
                foreach (float kmh in new[] { 80f, 140f })
                {
                    PutOn(car, dr, st); g.rig.SnapChase();
                    yield return Follow(car, dr, st, kmh, 25f, t => Vector3.Distance(car.transform.position, dr.pts[di]) < 6f || car.SpeedKmh >= kmh && Vector3.Distance(car.transform.position, dr.pts[di]) < 25f ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1));
                    float vb = car.SpeedKmh; float hb = car.transform.eulerAngles.y; float dist = 0; var lp = car.transform.position; ResetM(); float maxDh = 0;
                    for (float t = 0; t < 8f && car.SpeedKmh > 1f; t += Time.fixedDeltaTime)
                    {
                        car.throttle = 0; car.brake = 1; car.steer = 0; Measure(car);
                        dist += Vector3.Distance(lp, car.transform.position); lp = car.transform.position;
                        maxDh = Mathf.Max(maxDh, Mathf.Abs(Mathf.DeltaAngle(hb, car.transform.eulerAngles.y)));
                        yield return new WaitForFixedUpdate();
                    }
                    Debug.Log($"[HMD] test BRAKE DOWNHILL on {dr.name} ({dg * 100:F1}% at {V(dr.pts[di])}) from {vb:F0} km/h: {dist:F0} m to stop, heading swing {maxDh:F0} deg, {M()}");
                    car.brake = 0;
                }
            }

            // ---- 5. kerb hit: steer into the kerb at 60 km/h on a main road
            var kr = nc.Find("Al Wasl") ?? beach;
            PutOn(car, kr, 3); g.rig.SnapChase();
            yield return Follow(car, kr, 3, 60f, 20f, t => car.SpeedKmh >= 58f ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1));
            ResetM(); var kp0 = car.transform.position;
            for (float t = 0; t < 3f; t += Time.fixedDeltaTime) { car.steer = t < 1.2f ? 0.35f : 0f; car.throttle = 0.5f; car.brake = 0; Measure(car); yield return new WaitForFixedUpdate(); }
            Debug.Log($"[HMD] test KERB at 60 km/h on {kr.name} from {V(kp0)} to {V(car.transform.position)} (under the car now: {Under(car.transform.position)}): {M()}, upright {Vector3.Dot(car.transform.up, Vector3.up):F2}");

            // ---- 6. slopes and crests at speed: Beach Road near (3613,2689) and every highway crest
            {
                int bi = 0; float bd = float.MaxValue;
                for (int i = 0; i < beach.pts.Count; i++) { float d = (beach.pts[i] - new Vector3(3613, beach.pts[i].y, 2689)).sqrMagnitude; if (d < bd) { bd = d; bi = i; } }
                float maxG = 0; for (int i = Mathf.Max(0, bi - 10); i < Mathf.Min(beach.pts.Count - 1, bi + 10); i++) maxG = Mathf.Max(maxG, Mathf.Abs(Grade(beach, i)));
                foreach (bool back in new[] { false, true })
                {
                    int s = back ? Mathf.Min(beach.pts.Count - 2, bi + 14) : Mathf.Max(1, bi - 14);
                    PutOn(car, beach, s, back); g.rig.SnapChase();
                    yield return Follow(car, beach, s, 140f, 14f, null, back);
                    Debug.Log($"[HMD] test SLOPE Beach Road near point {bi} {V(beach.pts[bi])} steepest {maxG * 100:F1}% ({(back ? "backward" : "forward")}) at {car.SpeedKmh:F0} km/h: {M()}");
                }
            }
            foreach (var rd in nc.roads)
            {
                if (rd.cls != "highway" && rd.name != "Creek Bridge" && rd.name != "Deira Bridge") continue;
                // crests: local height maxima at least 4 m above the points 12 either side
                for (int i = 12; i + 12 < rd.pts.Count; i++)
                {
                    float y = rd.pts[i].y; bool top = true;
                    for (int j = i - 12; j <= i + 12; j++) if (rd.pts[j].y > y + 0.01f) { top = false; break; }
                    if (!top || y - rd.pts[i - 12].y < 3f || y - rd.pts[i + 12].y < 3f) continue;
                    float kmh = rd.cls == "highway" ? 200f : 140f;
                    PutOn(car, rd, i - 12); g.rig.SnapChase();
                    yield return Follow(car, rd, i - 12, kmh, 9f, null);   // run-up from the foot of the crest
                    // re-run from far enough back to be at speed over the top
                    PutOn(car, rd, Mathf.Max(1, i - 40)); g.rig.SnapChase();
                    yield return Follow(car, rd, Mathf.Max(1, i - 40), kmh, 60f, t => Vector3.Distance(car.transform.position, rd.pts[Mathf.Min(rd.pts.Count - 1, i + 12)]) < 10f ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1));
                    Debug.Log($"[HMD] test CREST {rd.name} at {V(rd.pts[i])} (+{y - rd.pts[i - 12].y:F1} m / +{y - rd.pts[i + 12].y:F1} m) at {car.SpeedKmh:F0} km/h: {M()}");
                    i += 24;
                }
            }

            // ---- 7. the Downtown Blvd underpass under the E11 (near 2560,1470), both ways, and the E11 over it
            if (blvd != null)
            {
                int ui = 0; float ud = float.MaxValue;
                for (int i = 0; i < blvd.pts.Count; i++) { float d = (blvd.pts[i] - new Vector3(2560, blvd.pts[i].y, 1470)).sqrMagnitude; if (d < ud) { ud = d; ui = i; } }
                float low = float.MaxValue; for (int i = 0; i < blvd.pts.Count; i++) low = Mathf.Min(low, blvd.pts[i].y);
                Debug.Log($"[HMD] test UNDERPASS Downtown Blvd point {ui} {V(blvd.pts[ui])}, lowest point y {low:F1}, distance to (2560,1470) {Mathf.Sqrt(ud):F0} m");
                // clearance: from the road surface up to the E11 deck
                var us = NewCity.Surface(blvd.pts[ui]);
                if (Physics.Raycast(us + Vector3.up * 0.2f, Vector3.up, out var ceil, 20f)) Debug.Log($"[HMD] test UNDERPASS clearance at {V(us)}: {ceil.point.y - us.y:F2} m to {ceil.collider.name}"); else Debug.Log($"[HMD] test UNDERPASS: nothing above {V(us)} within 20 m");
                foreach (bool back in new[] { false, true })
                {
                    int s = back ? Mathf.Min(blvd.pts.Count - 2, ui + 16) : Mathf.Max(1, ui - 16);
                    PutOn(car, blvd, s, back); g.rig.SnapChase();
                    int stopN = stops; float minV = 999; bool passed = false; var target = blvd.pts[back ? Mathf.Max(0, ui - 8) : Mathf.Min(blvd.pts.Count - 1, ui + 8)];
                    yield return Follow(car, blvd, s, 90f, 30f, t =>
                    {
                        if (t > 3f) minV = Mathf.Min(minV, car.SpeedKmh);
                        if (Vector3.Distance(car.transform.position, target) < 8f) passed = true;
                        return passed ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1);
                    }, back);
                    Debug.Log($"[HMD] test UNDERPASS drive {(back ? "backward" : "forward")}: {(passed ? "went through" : "DID NOT get through")}, slowest {minV:F0} km/h after the start, now {V(car.transform.position)} ({car.SpeedKmh:F0} km/h), {M()}");
                    if (!back) { Cam(us + new Vector3(0, 3f, 0) - Vector3.ProjectOnPlane(blvd.pts[Mathf.Min(blvd.pts.Count - 1, ui + 3)] - blvd.pts[ui], Vector3.up).normalized * 25f, us + Vector3.up * 2f); yield return Shot("nc_20_underpass"); g.rig.mode = CameraRig.Mode.Chase; }
                }
                // the E11 over it
                int ei = 0; float ed = float.MaxValue;
                for (int i = 0; i < e11.pts.Count; i++) { float d = (e11.pts[i] - us).sqrMagnitude; d = new Vector2(e11.pts[i].x - us.x, e11.pts[i].z - us.z).sqrMagnitude; if (d < ed) { ed = d; ei = i; } }
                Debug.Log($"[HMD] test UNDERPASS: nearest E11 point {V(e11.pts[ei])}, deck height above the boulevard {e11.pts[ei].y - us.y:F1} m");
                PutOn(car, e11, Mathf.Max(1, ei - 30)); g.rig.SnapChase();
                yield return Follow(car, e11, Mathf.Max(1, ei - 30), 180f, 40f, t => Vector3.Distance(car.transform.position, e11.pts[Mathf.Min(e11.pts.Count - 1, ei + 6)]) < 10f ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1));
                Debug.Log($"[HMD] test E11 over the underpass at {car.SpeedKmh:F0} km/h: {M()}");
            }

            // ---- 8. crash recovery: overturned, into the water, off a flyover
            PutOn(car, beach, 10); yield return new WaitForSeconds(1f);
            var fp = car.transform.position;
            car.Teleport(fp + Vector3.up * 1.5f, Quaternion.LookRotation(car.transform.forward, Vector3.down));
            yield return new WaitForSeconds(4f);
            Debug.Log($"[HMD] test RECOVER overturned at {V(fp)} -> now {V(car.transform.position)}, upright {Vector3.Dot(car.transform.up, Vector3.up):F2}, under: {Under(car.transform.position)}");
            // water: a point next to the Palm trunk / a frond, over the sea (WaterY {NewCity.WaterY})
            Vector3 wp = Vector3.zero; bool found = false;
            foreach (var rd in nc.roads)
            {
                if (rd.name != "Frond" && rd.name != "Beach Road") continue;
                for (int i = 2; i < rd.pts.Count - 2 && !found; i += 3)
                {
                    var d = rd.pts[i + 1] - rd.pts[i]; d.y = 0; d.Normalize(); var sd = Vector3.Cross(Vector3.up, d);
                    foreach (float o in new[] { 45f, -45f, 70f, -70f })
                    {
                        var q = rd.pts[i] + sd * o;
                        if (Physics.Raycast(new Vector3(q.x, 60f, q.z), Vector3.down, out var h, 200f) && h.point.y < NewCity.WaterY - 0.5f) { wp = new Vector3(q.x, NewCity.WaterY, q.z); found = true; break; }
                    }
                }
                if (found) break;
            }
            Debug.Log($"[HMD] test water level y {NewCity.WaterY:F2}, sea spot {(found ? V(wp) : "none found")}");
            if (found)
            {
                car.Teleport(wp + Vector3.up * 1f, Quaternion.identity); car.Body.linearVelocity = Vector3.forward * 15f;
                float tr = -1; var last = car.transform.position;
                for (float t = 0; t < 6f; t += Time.deltaTime) { if (tr < 0 && Vector3.Distance(car.transform.position, last) > 20f) tr = t; last = car.transform.position; yield return null; }
                Debug.Log($"[HMD] test RECOVER water at {V(wp)} -> {(tr < 0 ? "NOT reset" : "reset after " + tr.ToString("F1") + " s")}, now {V(car.transform.position)}, under: {Under(car.transform.position)}");
            }
            // off a flyover: the highest highway point, pushed off the side
            NewCity.Road hr = null; int hi = 0; float hy = -99;
            foreach (var rd in nc.roads) if (rd.cls == "highway" || rd.cls == "ramp") for (int i = 2; i < rd.pts.Count - 2; i++) if (rd.pts[i].y > hy) { hy = rd.pts[i].y; hr = rd; hi = i; }
            if (hr != null)
            {
                var d = hr.pts[hi + 1] - hr.pts[hi]; d.y = 0; d.Normalize(); var sd = Vector3.Cross(Vector3.up, d);
                var off = hr.pts[hi] + sd * (hr.width * 0.5f + 4f) + Vector3.up * 1f;
                car.Teleport(off, Quaternion.LookRotation(d)); car.Body.linearVelocity = d * 25f + sd * 4f;
                yield return new WaitForSeconds(6f);
                Debug.Log($"[HMD] test RECOVER fell off {hr.name} at {V(hr.pts[hi])} (deck y {hy:F1}) -> now {V(car.transform.position)}, under: {Under(car.transform.position)}, upright {Vector3.Dot(car.transform.up, Vector3.up):F2}");
            }

            // ---- profiles across the road edge where the car hit something
            Profiles();

            // ---- 9. ramps: json centre line against the built asphalt (sideways scan at every point)
            int rn = 0;
            foreach (var rd in nc.roads)
            {
                if (rd.cls != "ramp") continue; rn++;
                float maxOff = 0, maxDy = 0, minDy = 99, sumOff = 0; int n = 0, merged = 0, offCentre = 0; Vector3 worst = Vector3.zero, firstOff = Vector3.zero;
                // asphalt height at a spot near a reference height (the deck nearest to it), or NaN
                float AsphaltY(Vector3 q, float refY, float tol)
                {
                    float best = float.NaN, bd = tol;
                    foreach (var h in Physics.RaycastAll(q + Vector3.up * 6f, Vector3.down, 14f))
                        if (h.collider.name.ToLowerInvariant().Contains("asphalt") && Mathf.Abs(h.point.y - refY) < bd) { bd = Mathf.Abs(h.point.y - refY); best = h.point.y; }
                    return best;
                }
                for (int i = 1; i + 1 < rd.pts.Count; i++)
                {
                    var d = rd.pts[i + 1] - rd.pts[i - 1]; d.y = 0; if (d.sqrMagnitude < 0.01f) continue; d.Normalize(); var sd = Vector3.Cross(Vector3.up, d);
                    float yc = AsphaltY(rd.pts[i], rd.pts[i].y + 1f, 2.5f);
                    if (float.IsNaN(yc)) { if (offCentre++ == 0) firstOff = rd.pts[i]; continue; }
                    // walk out both ways along the same deck (height within 0.4 m of the step before) to its edges
                    float lo = 0, hiE = 0, yl = yc, yr = yc;
                    for (float o = 0.25f; o <= 20f; o += 0.25f) { float y = AsphaltY(rd.pts[i] - sd * o, yl, 0.4f); if (float.IsNaN(y)) break; lo = -o; yl = y; }
                    for (float o = 0.25f; o <= 20f; o += 0.25f) { float y = AsphaltY(rd.pts[i] + sd * o, yr, 0.4f); if (float.IsNaN(y)) break; hiE = o; yr = y; }
                    if (hiE - lo > rd.width + 2.5f) { merged++; continue; }   // joined to another road here: no edges to measure
                    float mid = (lo + hiE) * 0.5f, dy = yc - rd.pts[i].y;
                    n++; sumOff += Mathf.Abs(mid);
                    if (Mathf.Abs(mid) > maxOff) { maxOff = Mathf.Abs(mid); worst = rd.pts[i]; }
                    maxDy = Mathf.Max(maxDy, dy); minDy = Mathf.Min(minDy, dy);
                }
                Debug.Log($"[HMD] test RAMP {rn} starting {V(rd.pts[0])} width {rd.width:F1}: on {n} points with clear edges the json line is off the asphalt middle by mean {sumOff / Mathf.Max(1, n):F2} m, max {maxOff:F2} m at {V(worst)}; asphalt minus json height {minDy:+0.00;-0.00} .. {maxDy:+0.00;-0.00} m; {merged} points joined to another road; {offCentre} points with no asphalt under the json line{(offCentre > 0 ? " (first " + V(firstOff) + ")" : "")}");
            }
            Debug.Log("[HMD] test done");
        }

        /// <summary>Junction check: two junctions per district; through each along every road that meets there, both ways
        /// at 60 km/h, logging bumps, hits and air time (the old 15 cm walls across joining roads would show as hits).
        /// Also the two junction shots.</summary>
        IEnumerator JunctionTests()
        {
            var perD = new System.Collections.Generic.Dictionary<string, int>();
            int passes = 0, bad = 0, shots = 0;
            foreach (var j in nc.junctions)
            {
                string dn = "?"; float dd = float.MaxValue;
                foreach (var d in nc.districts) { float q = (d.pos - new Vector3(j.x, 0, j.z)).sqrMagnitude; if (q < dd) { dd = q; dn = d.name; } }
                perD.TryGetValue(dn, out int cnt); if (cnt >= 2) continue;
                // the roads through it (not ramps: they join highways, not junctions)
                var through = new System.Collections.Generic.List<(NewCity.Road rd, int k)>();
                foreach (var rd in nc.roads)
                {
                    if (rd.cls == "ramp") continue;
                    int bk = -1; float bd2 = 14f * 14f;
                    for (int i = 0; i < rd.pts.Count; i++) { var p = rd.pts[i]; float q = (p.x - j.x) * (p.x - j.x) + (p.z - j.z) * (p.z - j.z); if (q < bd2 && Mathf.Abs(p.y - j.y) < 1.5f) { bd2 = q; bk = i; } }
                    if (bk >= 0) through.Add((rd, bk));
                }
                if (through.Count < 2) continue;
                perD[dn] = cnt + 1;
                string kinds = ""; foreach (var t in through) kinds += t.rd.name + "(" + t.rd.cls + ") ";
                foreach (var t in through)
                    foreach (bool back in new[] { false, true })
                    {
                        var rd = t.rd; int k = t.k;
                        int s = back ? Mathf.Min(rd.pts.Count - 2, k + 5) : Mathf.Max(0, k - 5);
                        int e = back ? Mathf.Max(0, k - 4) : Mathf.Min(rd.pts.Count - 1, k + 4);
                        if (s == k) continue;   // the road starts here: it is driven the other way, into the junction
                        PutOn(car, rd, s, back);
                        yield return new WaitForFixedUpdate();
                        car.Body.linearVelocity = car.transform.forward * (60f / 3.6f);
                        bool passed = false; var endP = rd.pts[e];
                        yield return Follow(car, rd, s, 60f, 8f, tt => { if (Vector3.Distance(car.transform.position, endP) < 6f) passed = true; return passed ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1); }, back);
                        // A road that ends at the junction: Follow stops one point before the road's last point, so the
                        // car never gets within 6 m of it. Reaching that last stretch counts as through.
                        bool endsHere = back ? e == 0 : e == rd.pts.Count - 1;
                        if (!passed && endsHere && Vector3.Distance(car.transform.position, endP) < Mathf.Max(20f, Vector3.Distance(rd.pts[back ? 1 : rd.pts.Count - 2], endP) + 6f)) passed = true;
                        passes++;
                        bool fault = !passed || mBumps > 0 || mHit > 2f || mAir > 0.15f;
                        if (fault) bad++;
                        Debug.Log($"[HMD] junction {dn} at ({j.x:F0},{j.y:F1},{j.z:F0}) [{kinds.Trim()}] along {rd.name} {(back ? "backward" : "forward")}: {(passed ? "through" : "DID NOT get through")} at {car.SpeedKmh:F0} km/h, {M()}{(fault ? "  <-- CHECK" : "")}");
                    }
                if (shots < 2 && (dn == "Downtown Dubai" || dn == "Al Wasl" || dn == "Business Bay" || dn == "Al Barsha"))
                {
                    var rd = through[0].rd; int k = through[0].k;
                    Park(rd.pts[Mathf.Max(0, k - 2)] + Vector3.Cross(Vector3.up, Dir(rd, k)) * rd.width * 0.25f, Dir(rd, k));
                    yield return new WaitForSeconds(0.6f);
                    var c = new Vector3(j.x, j.y, j.z); var away = Vector3.Cross(Vector3.up, Dir(rd, k)) * 0.6f - Dir(rd, k);
                    Cam(c + away.normalized * 32f + Vector3.up * 18f, c); yield return Shot($"nc_21_junction_{shots}_{dn.Replace(' ', '_')}_top");
                    Cam(c + away.normalized * 26f + Vector3.up * 1.6f, c + Vector3.up * 1f); yield return Shot($"nc_21_junction_{shots}_{dn.Replace(' ', '_')}_street");
                    g.rig.mode = CameraRig.Mode.Chase; shots++;
                }
            }
            Debug.Log($"[HMD] junction summary: {passes} passes, {bad} flagged, districts {perD.Count}");
        }

        /// <summary>-ncdrive bridge: the Creek Bridge foot at the Downtown Ring (near 3402,2061, a short steep stretch),
        /// both ways at 80 and 120 km/h; then two shots of a ramp leaving the highway (from above, at road level).</summary>
        IEnumerator BridgeTests()
        {
            var foot = new Vector3(3405, 0, 2062);
            NewCity.Road br = null;
            foreach (var rd in nc.roads) if (rd.name == "Creek Bridge") { br = rd; break; }
            if (br == null) Debug.Log("[HMD] test BRIDGE: no road named Creek Bridge");
            else
            {
                int fi = 0; float fd = float.MaxValue;
                for (int i = 0; i < br.pts.Count; i++) { float d = new Vector2(br.pts[i].x - foot.x, br.pts[i].z - foot.z).sqrMagnitude; if (d < fd) { fd = d; fi = i; } }
                float maxG = 0; Vector3 gAt = br.pts[fi];
                for (int i = Mathf.Max(1, fi - 10); i < Mathf.Min(br.pts.Count, fi + 10); i++)
                {
                    var a = br.pts[i - 1]; var b = br.pts[i]; float h = new Vector2(b.x - a.x, b.z - a.z).magnitude;
                    if (h > 0.5f) { float gr = Mathf.Abs(b.y - a.y) / h; if (gr > maxG) { maxG = gr; gAt = b; } }
                }
                Debug.Log($"[HMD] test BRIDGE Creek Bridge foot: point {fi}/{br.pts.Count} {V(br.pts[fi])}, {Mathf.Sqrt(fd):F0} m from (3405,2062); steepest json grade nearby {maxG * 100:F1}% at {V(gAt)}");
                foreach (float kmh in new[] { 80f, 120f })
                    foreach (bool back in new[] { false, true })
                    {
                        // forward = along the json order; start 12 points before the foot, finish 10 points past it
                        int s = back ? Mathf.Min(br.pts.Count - 2, fi + 12) : Mathf.Max(0, fi - 12);
                        int e = back ? Mathf.Max(0, fi - 10) : Mathf.Min(br.pts.Count - 1, fi + 10);
                        // the road starts at the foot: forward = start at the foot already at speed and climb onto the bridge
                        if (s == fi) s = back ? Mathf.Min(br.pts.Count - 2, fi + 1) : fi;
                        PutOn(car, br, s, back); g.rig.SnapChase();
                        yield return new WaitForFixedUpdate();
                        car.Body.linearVelocity = car.transform.forward * (kmh / 3.6f);
                        bool passed = false, crossed = false; float minV = 999; var endP = br.pts[e]; var footP = br.pts[fi];
                        yield return Follow(car, br, s, kmh, 25f, t =>
                        {
                            if (t > 2f) minV = Mathf.Min(minV, car.SpeedKmh);
                            if (Vector3.Distance(car.transform.position, footP) < 8f) crossed = true;
                            if (crossed && Vector3.Distance(car.transform.position, endP) < 8f) passed = true;
                            return passed ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1);
                        }, back);
                        bool endsHere = back ? e == 0 : e == br.pts.Count - 1;
                        // a road that ends at the foot: Follow stops a point early, so reaching its last stretch counts
                        if (!passed && endsHere && Vector3.Distance(car.transform.position, endP) < 25f) passed = true;
                        if (s == fi && !back && Vector3.Distance(car.transform.position, endP) < 8f) passed = true;
                        bool fault = !passed || mBumps > 0 || mHit > 2f || mAir > 0.15f;
                        Debug.Log($"[HMD] test BRIDGE Creek Bridge foot {(back ? "backward" : "forward")} at {kmh:F0} km/h: {(passed ? "through" : "DID NOT get through")}, slowest {minV:F0} km/h, now {V(car.transform.position)} ({car.SpeedKmh:F0} km/h), {M()}{(fault ? "  <-- CHECK" : "")}");
                    }
            }
            // two shots of a ramp leaving the highway: the first ramp, about 8 points in (where the old fold was)
            NewCity.Road rp = null;
            foreach (var rd in nc.roads) if (rd.cls == "ramp") { rp = rd; break; }
            if (rp != null)
            {
                int k = Mathf.Min(rp.pts.Count - 2, 8);
                var p = rp.pts[k]; var d = Dir(rp, k); var side = Vector3.Cross(Vector3.up, d);
                Park(rp.pts[Mathf.Max(0, k - 3)], Dir(rp, Mathf.Max(0, k - 3)));
                yield return new WaitForSeconds(0.6f);
                // steep view from behind and above the split (a lower side view had a lamp-lit LED fin right in front)
                Cam(p - d * 24f - side * 6f + Vector3.up * 42f, p + d * 12f); yield return Shot("nc_22_ramp_split_top");
                Cam(rp.pts[Mathf.Max(0, k - 6)] + Vector3.up * 1.6f - d * 4f, p + Vector3.up * 1f); yield return Shot("nc_22_ramp_split_road");
                g.rig.mode = CameraRig.Mode.Chase;
                Debug.Log($"[HMD] ramp shots at ramp starting {V(rp.pts[0])}, point {k} {V(p)}");
            }
            Debug.Log("[HMD] test BRIDGE done");
        }

        /// <summary>-ncdrive look: what the player sees while driving. The car on the right-hand lane of a road in each
        /// area (villa street, Downtown boulevard, Marina, industrial street, the E11), the chase camera behind it at its
        /// own height, plus one shot looking along the pavement. Shots nc_30_look_*.</summary>
        IEnumerator LookShots()
        {
            var want = new (string district, string cls, string tag)[]
            {
                ("Dubai Hills", "street", "villa_street"), ("Jumeirah", "street", "jumeirah_street"), ("Downtown Dubai", "main", "downtown_blvd"),
                ("Dubai Marina", "main", "marina"), ("Al Quoz", "street", "industrial"), ("Business Bay", "main", "business_bay"), ("", "highway", "e11")
            };
            foreach (var w in want)
            {
                Vector3 centre = Vector3.zero; bool found = w.district == "";
                foreach (var d in nc.districts) if (d.name == w.district) { centre = d.pos; found = true; }
                if (!found) { Debug.Log($"[HMD] look {w.tag}: no district {w.district}"); continue; }
                NewCity.Road best = null; int bi = 0; float bd = float.MaxValue;
                foreach (var rd in nc.roads)
                {
                    if (rd.cls != w.cls || rd.pts.Count < 6) continue;
                    if (w.cls == "highway" && rd.name != "E11") continue;
                    for (int i = 3; i < rd.pts.Count - 3; i++)
                    {
                        float dd = w.district == "" ? Mathf.Abs(rd.pts[i].x - 2000f) : new Vector2(rd.pts[i].x - centre.x, rd.pts[i].z - centre.z).sqrMagnitude;
                        if (dd < bd) { bd = dd; best = rd; bi = i; }
                    }
                }
                if (best == null) { Debug.Log($"[HMD] look {w.tag}: no {w.cls} road"); continue; }
                var dir = Dir(best, bi); var side = Vector3.Cross(Vector3.up, dir);
                var p = best.pts[bi] + side * Mathf.Max(1.8f, best.width * 0.25f);   // right-hand lane
                Park(p, dir); g.rig.SnapChase();
                yield return new WaitForSeconds(0.8f);
                var s = NewCity.Surface(p);
                Cam(s - dir * 7.5f + Vector3.up * 2.3f, s + dir * 30f + Vector3.up * 1.2f); yield return Shot($"nc_30_look_{w.tag}");
                // along the pavement: from the kerb at eye height
                var kerb = s + side * (best.width * 0.5f + 1.5f);
                Cam(kerb + Vector3.up * 1.7f - dir * 4f, kerb + dir * 35f + Vector3.up * 1.5f); yield return Shot($"nc_30_look_{w.tag}_kerb");
                g.rig.mode = CameraRig.Mode.Chase;
                Debug.Log($"[HMD] look {w.tag}: {best.name} ({best.cls}) at {V(p)}");
            }
        }

        /// <summary>-ncdrive video: a chase-camera drive along the E11 eastwards past the Downtown tower wall towards
        /// Business Bay, recorded frame by frame at a fixed 60 fps game clock (Time.captureFramerate) as JPEGs in
        /// Shots/video/ (the Editor's MediaEncoder turns them into an MP4). -vidsecs N sets the length (default 36).</summary>
        IEnumerator VideoDrive()
        {
            NewCity.Road e11 = null; foreach (var rd in nc.roads) if (rd.name == "E11") { e11 = rd; break; }
            if (e11 == null) { Debug.Log("[HMD] video: no E11"); yield break; }
            float secs = 36f;
            var argv = System.Environment.GetCommandLineArgs();
            for (int a = 0; a + 1 < argv.Length; a++) if (argv[a] == "-vidsecs") float.TryParse(argv[a + 1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out secs);
            // start near x 1550 so the run passes the tower wall and ends by Business Bay (about 1.1 km at 110 km/h)
            int si = 0; float bd = float.MaxValue;
            for (int i = 1; i < e11.pts.Count - 2; i++) { float d = Mathf.Abs(e11.pts[i].x - 1550f); if (d < bd) { bd = d; si = i; } }
            bool back = e11.pts[Mathf.Min(e11.pts.Count - 1, si + 3)].x < e11.pts[si].x;   // drive towards +x
            if (back) si = Mathf.Min(e11.pts.Count - 2, si + 1);
            PutOn(car, e11, si, back); g.rig.mode = CameraRig.Mode.Chase; g.rig.SnapChase();
            yield return new WaitForSeconds(0.5f);
            var vdir = Path.Combine(dir, "video"); Directory.CreateDirectory(vdir);
            Application.targetFrameRate = -1; QualitySettings.vSyncCount = 0;
            Time.captureFramerate = 60;
            int frame = 0; bool done = false;
            StartCoroutine(Follow(car, e11, si, 110f, secs + 2f, t => done ? new Vector3(9, 0, 0) : new Vector3(0, 0, -1), back));
            yield return new WaitForSeconds(1.5f);   // get up to speed first
            int total = Mathf.RoundToInt(secs * 60f);
            while (frame < total)
            {
                yield return new WaitForEndOfFrame();
                var tex = ScreenCapture.CaptureScreenshotAsTexture();
                File.WriteAllBytes(Path.Combine(vdir, $"f{frame:D5}.jpg"), tex.EncodeToJPG(88));
                Destroy(tex);
                frame++;
            }
            done = true; Time.captureFramerate = 0;
            Debug.Log($"[HMD] video: {frame} frames at 60 fps in {vdir}, ended at {V(car.transform.position)} ({car.SpeedKmh:F0} km/h)");
        }

        void Profiles()
        {
            Profile("Al Wasl kerb", new Vector3(1151, 2.7f, 1863), new Vector3(1176, 2.5f, 1861) + (new Vector3(1176, 0, 1861) - new Vector3(1151, 0, 1863)).normalized * 6f);
            Profile("Downtown Blvd north lane at the sidewalk hit", new Vector3(2513.9f, 4.3f, 1323.6f) - new Vector3(0.93f, 0, -0.36f) * 9f, new Vector3(2513.9f, 4.3f, 1323.6f) + new Vector3(0.93f, 0, -0.36f) * 22f);
            Profile("Downtown Blvd along the north lane 1360 to 1290", new Vector3(2524.7f + 3.8f, 3f, 1351.5f), new Vector3(2499.4f + 3.8f, 6f, 1286.3f));
            SideClearance();
        }

        /// <summary>How close buildings stand to the highways: every 10 m along each highway, a ray sideways at bumper
        /// height from the road edge outwards (40 m) on both sides; first thing hit (building, barrier, ...).</summary>
        void SideClearance()
        {
            foreach (var rd in nc.roads)
            {
                if (rd.cls != "highway") continue;
                int samples = 0, open = 0, under10 = 0, under5 = 0; float minD = 99; Vector3 minAt = Vector3.zero;
                var close = new System.Text.StringBuilder(); int listed = 0;
                float acc = 0;
                for (int i = 1; i < rd.pts.Count; i++)
                {
                    acc += Vector3.Distance(rd.pts[i - 1], rd.pts[i]); if (acc < 10f) continue; acc = 0;
                    var d = rd.pts[i] - rd.pts[i - 1]; d.y = 0; if (d.sqrMagnitude < 0.01f) continue; d.Normalize(); var sd = Vector3.Cross(Vector3.up, d);
                    var surf = NewCity.Surface(rd.pts[i] + Vector3.up * 0.5f);
                    for (int s = -1; s <= 1; s += 2)
                    {
                        samples++;
                        var o = surf + Vector3.up * 0.6f + sd * s * (rd.width * 0.5f - 0.5f);
                        if (!Physics.Raycast(o, sd * s, out var h, 40f)) continue;
                        string n = h.collider.name;
                        if (!n.StartsWith("Dress")) continue;   // a barrier or nothing first: fine
                        open++;
                        float dist = h.distance - 0.5f;   // from the road edge
                        if (dist < 10f) under10++;
                        if (dist < 5f) under5++;
                        if (dist < minD) { minD = dist; minAt = h.point; }
                        if (dist < 6f && listed < 12) { close.Append($" ({h.point.x:F0},{h.point.z:F0}) {dist:F1} m {(s > 0 ? "R" : "L")};"); listed++; }
                    }
                }
                Debug.Log($"[HMD] side clearance {rd.name}: {samples} samples (both sides, every 10 m); a building is the first thing within 40 m of the edge (no barrier in between) at {open}, closer than 10 m at {under10}, closer than 5 m at {under5}; nearest {minD:F1} m at ({minAt.x:F0},{minAt.z:F0}); closest spots:{close}");
            }
        }

        /// <summary>Logs the surfaces along a line every 0.25 m, one entry per change of collider or height step.</summary>
        void Profile(string label, Vector3 a, Vector3 b)
        {
            var sb = new System.Text.StringBuilder(); string lastN = null; float lastY = float.NaN;
            float len = Vector3.Distance(new Vector3(a.x, 0, a.z), new Vector3(b.x, 0, b.z));
            for (float s = 0; s <= len; s += 0.25f)
            {
                var q = Vector3.Lerp(a, b, s / len); string n = "nothing"; float y = float.NaN;
                if (Physics.Raycast(new Vector3(q.x, Mathf.Max(a.y, b.y) + 12f, q.z), Vector3.down, out var h, 40f)) { n = h.collider.name; y = h.point.y; }
                if (n != lastN || float.IsNaN(lastY) || Mathf.Abs(y - lastY) > 0.05f)
                    sb.Append($" | {s:F2} m {n} y {y:F2}{(float.IsNaN(lastY) || float.IsNaN(y) ? "" : $" (step {y - lastY:+0.00;-0.00})")}");
                lastN = n; lastY = y;
            }
            Debug.Log($"[HMD] profile {label} from {V(a)} to {V(b)}:{sb}");
        }

        IEnumerator ReverseTest(CarController c, NewCity.Road rd, int i)
        {
            PutOn(c, rd, i); yield return new WaitForSeconds(1f);
            // in this game reverse is: hold the brake at a standstill (nothing sets reverseHeld)
            c.throttle = 0; c.brake = 1; c.steer = 0; var p0 = c.transform.position; float vmax = 0;
            for (float t = 0; t < 4f; t += Time.fixedDeltaTime) { vmax = Mathf.Max(vmax, -c.ForwardSpeed * 3.6f); yield return new WaitForFixedUpdate(); }
            var back = Vector3.Dot(c.transform.position - p0, c.transform.forward);
            float vr = -c.ForwardSpeed * 3.6f;
            c.handbrake = true; float tStop = -1;
            for (float t = 0; t < 4f; t += Time.fixedDeltaTime) { if (tStop < 0 && Mathf.Abs(c.ForwardSpeed) < 0.3f) tStop = t; yield return new WaitForFixedUpdate(); }
            var p1 = c.transform.position; yield return new WaitForSeconds(1.5f);
            Debug.Log($"[HMD] test REVERSE {c.spec.id} ({c.spec.drive}): gear {c.Gear}, moved {back:F1} m along the nose in 4 s (negative = backwards), top reverse {vmax:F0} km/h; handbrake while reversing at {vr:F0} km/h: {(tStop < 0 ? "did NOT stop in 4 s" : "stopped in " + tStop.ToString("F1") + " s")}, then crept {Vector3.Distance(p1, c.transform.position):F2} m in 1.5 s (handbrake and brake held)");
            c.brake = 0; c.handbrake = false;
            yield return new WaitForSeconds(0.5f);
        }

        IEnumerator Shot(string name)
        {
            yield return new WaitForSeconds(0.4f);
            yield return new WaitForEndOfFrame();
            var p = Path.Combine(dir, name + ".png");
            ScreenCapture.CaptureScreenshot(p, 1);
            Debug.Log("[HMD] shot " + p);
            yield return null;
        }
    }
}
