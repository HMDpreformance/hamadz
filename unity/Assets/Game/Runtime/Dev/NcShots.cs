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

        IEnumerator Start()
        {
            dir = Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".", "Shots");
            Directory.CreateDirectory(dir);
            g = Game.I; car = g.car; nc = NewCity.I;
            var pi = car.GetComponent<PlayerInput>(); if (pi) pi.enabled = false;
            yield return new WaitForSeconds(1.5f);
            yield return Shot("nc_00_spawn");
            while (g.state == Game.State.Intro) yield return null;

            // test drives: every highway, then the ramps (flyovers), at speed
            foreach (var rd in nc.roads)
                if (rd.cls == "highway") yield return Drive(rd, 230f, rd.name == "E11");
            int ramps = 0;
            foreach (var rd in nc.roads)
                if (rd.cls == "ramp" && ramps++ < 6) yield return Drive(rd, 110f, false);
            foreach (var rd in nc.roads)
                if (rd.cls == "main") { yield return Drive(rd, 150f, false); break; }
            Debug.Log($"[HMD] nc drive summary: bumps={bumps} drops={drops} stops={stops} runoffs={offs}");

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
                Vector3 under = NewCity.Surface(top + Vector3.down * 3f + Vector3.Cross(Vector3.up, d) * 22f);
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
                Cam(p + new Vector3(-90, 70, -140), p);
                yield return Shot("nc_05_palm");
            }
            if (hills != Vector3.zero)
            {
                Vector3 p = NewCity.Surface(hills + Vector3.up * 30f);
                Cam(p + new Vector3(-50, 12, -60), p + Vector3.up * 2f);
                yield return Shot("nc_06_dubai_hills");
            }
            if (nc.blocks.Count > 0)
            {
                var b = nc.blocks[0];
                Vector3 f = Quaternion.Euler(0, b.yaw, 0) * Vector3.forward;
                Cam(b.pos - f * 18f + Vector3.up * 3f + Vector3.Cross(Vector3.up, f) * 3f, b.pos + Vector3.up);
                yield return Shot("nc_07_road_block");
            }
            var c = nc.MeshBounds.center;
            Cam(c + new Vector3(-500, 650, -700), c);
            yield return Shot("nc_08_aerial");
            Debug.Log("[HMD] nc shots done");
            Application.Quit();
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
            car.Body.isKinematic = false;
            g.rig.SnapChase();
            g.rig.mode = CameraRig.Mode.Chase;
            float lane = rd.width * 0.25f;
            Vector3 d0 = Dir(rd, 1);
            Vector3 start = rd.pts[1] + Vector3.Cross(Vector3.up, d0) * lane;   // pts[0] can sit on the map edge
            car.Teleport(NewCity.Surface(start) + Vector3.up * 0.6f, Quaternion.LookRotation(d0));
            car.Body.linearVelocity = d0 * 20f;
            yield return null;
            int idx = 1; float t = 0, logT = 0, slow = 0, lastVy = 0; bool shot = false;
            float maxKmh = 0;
            while (idx < rd.pts.Count - 2 && t < 70f)
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
                if (side > rd.width * 0.5f + 3f) { offs++; Debug.Log($"[HMD] nc RUN-OFF on {rd.name} at ({p.x:F0},{p.z:F0}) {side:F1} m from the centre"); break; }
                slow = (t > 4f && v < 15f) ? slow + Time.deltaTime : 0;
                if (slow > 1.2f) { stops++; Debug.Log($"[HMD] nc STOP (wall?) on {rd.name} at ({p.x:F0},{p.y:F1},{p.z:F0})"); break; }
                if ((logT -= Time.deltaTime) <= 0) { logT = 1f; Debug.Log($"[HMD] nc {rd.name} ({p.x:F0},{p.y:F1},{p.z:F0}) {v:F0} km/h idx {idx}/{rd.pts.Count}"); }
                if (shoot && !shot && v > 180f) { shot = true; yield return Shot("nc_01_highway_chase"); }
                yield return null;
            }
            Debug.Log($"[HMD] nc drove {rd.name} ({rd.cls}) {idx}/{rd.pts.Count} points in {t:F0} s, max {maxKmh:F0} km/h");
            car.throttle = 0; car.brake = 1; car.steer = 0;
            yield return new WaitForSeconds(0.3f);
            car.brake = 0;
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
