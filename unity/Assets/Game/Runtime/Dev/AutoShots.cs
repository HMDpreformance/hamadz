using System.Collections;
using System.IO;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Run the game with -hmdshots to take a set of screenshots and quit (used to show Hamad each
    /// change before any APK). Pictures go to a "Shots" folder next to the game (or the project).
    /// Shots: rear intro, driving, city, garage outside, door open, workshop, dyno run, dyno graph, TV zoom, map.
    /// </summary>
    public class AutoShots : MonoBehaviour
    {
        string dir;

        IEnumerator Start()
        {
            dir = Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".", "Shots");
            Directory.CreateDirectory(dir);
            var g = Game.I;
            var pi = g.car.GetComponent<PlayerInput>();
            if (pi) pi.enabled = false;   // the script drives
            yield return new WaitForSeconds(1.2f);
            yield return Shot("01_intro_rear");
            yield return new WaitForSeconds(5.0f);

            // drive a little with the throttle held
            var car = g.car;
            car.inputLocked = false;
            float t = 0;
            while (t < 6f) { t += Time.deltaTime; car.throttle = 1; car.steer = 0; yield return null; }
            yield return Shot("02_driving");
            car.throttle = 0; car.brake = 1;
            yield return new WaitForSeconds(2f);
            car.brake = 0;
            // the car from the front: headlight glows and the beam pools on the wet road
            g.rig.SetFixed(car.transform.position + car.transform.forward * 11f + car.transform.right * 2.5f + Vector3.up * 1.3f, car.transform.position + car.transform.forward * 3f + Vector3.up * 0.4f, false);
            yield return new WaitForSeconds(0.5f);
            yield return Shot("02b_headlights");
            // higher speed in the chase view: the needles mid-scale (about 150 km/h)
            g.rig.SnapChase();
            car.brake = 0; car.throttle = 1f;
            car.Body.linearVelocity = car.transform.forward * 41.7f;
            t = 0;
            while (t < 0.9f) { t += Time.deltaTime; car.throttle = 1f; car.steer = 0; yield return null; }
            Debug.Log($"[HMD] 02c speed={car.SpeedKmh:F0} rpm={car.Rpm:F0} gear={car.Gear}");
            yield return Shot("02c_speed_dials");
            car.throttle = 0; car.brake = 1;
            yield return new WaitForSeconds(2.5f);
            car.brake = 0;

            // street level city look
            g.rig.SetFixed(car.transform.position + new Vector3(-8, 1.6f, -12), car.transform.position + new Vector3(10, 4, 30), false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("03_city_street");
            g.rig.SetFixed(City.BlockCenter(1, 1) + new Vector3(-60, 170, -60), City.BlockCenter(4, 4) + Vector3.up * 10, false);   // aerial, above the towers
            yield return new WaitForSeconds(0.6f);
            yield return Shot("04_city_high");
            // street level at a crossing, looking up at the tower facades
            Vector3 cross = City.BlockCenter(3, 3) + new Vector3(City.Block * 0.5f + City.Road * 0.5f, 0, City.Block * 0.5f + City.Road * 0.5f);
            g.rig.SetFixed(cross + new Vector3(-6, 1.7f, -6), City.BlockCenter(4, 4) + Vector3.up * 55, false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("04b_towers_up");

            // street furniture: traffic lights over the crossing, bus stop, benches, billboard
            g.rig.SetFixed(cross + new Vector3(-9, 1.7f, -30), cross + new Vector3(3, 6, 10), false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("04c_crossing_lights");
            Vector3 b22 = City.BlockCenter(2, 2);
            g.rig.SetFixed(b22 + new Vector3(-30, 1.7f, City.Block * 0.5f + 7), b22 + new Vector3(-8, 2.5f, City.Block * 0.5f - 3), false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("04d_bus_stop");
            Vector3 b30 = City.BlockCenter(0, 0);   // block (0,0): its billboard stands on the north side
            g.rig.SetFixed(b30 + new Vector3(-16, 1.7f, City.Block * 0.5f + 9), b30 + new Vector3(City.Block * 0.125f, 8, City.Block * 0.5f - 0.5f), false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("04e_billboard");

            // garage outside: forecourt, door closed
            g.GoToGarage();
            yield return new WaitForSeconds(1.2f);
            g.rig.mode = CameraRig.Mode.Fixed;
            Vector3 door = g.garage.DoorPos;
            g.rig.SetFixed(door + new Vector3(14, 3.4f, -19), door + new Vector3(-2, 3.6f, 0), false);
            yield return new WaitForSeconds(0.8f);
            yield return Shot("05_garage_outside_closed");
            // drive close: the door opens only now
            car.Teleport(door + new Vector3(0, 0.5f, -5.5f), Quaternion.identity);
            yield return new WaitForSeconds(2.2f);
            yield return Shot("06_garage_door_open_close");
            // drive in
            t = 0;
            car.inputLocked = false; car.brake = 0;
            float logT = 0;
            while (t < 10f && g.state == Game.State.Drive)
            {
                t += Time.deltaTime; car.throttle = 0.6f; car.brake = 0; car.steer = 0;
                if ((logT -= Time.deltaTime) <= 0)
                {
                    logT = 0.5f;
                    Vector3 rel = car.transform.position - door;
                    Debug.Log($"[HMD] drive-in t={t:F1} rel=({rel.x:F2},{rel.y:F2},{rel.z:F2}) kmh={car.SpeedKmh:F1} gear={car.Gear} rpm={car.Rpm:F0} locked={car.inputLocked} fwd={car.transform.forward}");
                }
                yield return null;
            }
            if (g.state == Game.State.Drive) { Debug.LogWarning("[HMD] shots: car did not reach the door, entering directly"); g.StartCoroutine("EnterGarage"); }
            car.throttle = 0;
            yield return new WaitForSeconds(2.5f);
            yield return Shot("07_workshop");
            g.rig.SetFixed(g.shop.transform.TransformPoint(new Vector3(-10, 3.2f, 2)), g.shop.transform.TransformPoint(new Vector3(4, 1.5f, 22)), false);
            yield return new WaitForSeconds(0.5f);
            yield return Shot("08_workshop_wide");
            // the west wall: tool chests, tool wall, workbench, banners
            g.rig.SetFixed(g.shop.transform.TransformPoint(new Vector3(-2, 2.0f, 6)), g.shop.transform.TransformPoint(new Vector3(-14, 1.4f, 18)), false);
            yield return new WaitForSeconds(0.5f);
            yield return Shot("08b_workshop_tools");
            // the east side: lift, tyre stacks, tool chest, back wall banners
            g.rig.SetFixed(g.shop.transform.TransformPoint(new Vector3(-5, 2.2f, 4)), g.shop.transform.TransformPoint(new Vector3(10, 1.4f, 16)), false);
            yield return new WaitForSeconds(0.5f);
            yield return Shot("08c_workshop_props");

            // dyno
            g.SendMessage("RunDyno", SendMessageOptions.DontRequireReceiver);
            yield return new WaitForSeconds(4.5f);
            yield return Shot("09_dyno_pull");
            while (g.dyno.Running) yield return null;
            yield return new WaitForSeconds(1.5f);
            yield return Shot("10_dyno_graph");
            g.dyno.ZoomTv();
            yield return new WaitForSeconds(1.6f);
            yield return Shot("11_tv_zoom");

            // out and the map
            g.SendMessage("LeaveGarageNow", SendMessageOptions.DontRequireReceiver);
            yield return new WaitForSeconds(2f);
            g.hud.Map.Open();
            yield return new WaitForSeconds(0.5f);
            yield return Shot("12_map");
            g.hud.Map.Close();
            yield return new WaitForSeconds(0.3f);
            yield return Shot("13_hud");
            Debug.Log("[HMD] shots done: " + dir);
            Application.Quit();
        }

        IEnumerator Shot(string name)
        {
            yield return new WaitForEndOfFrame();
            var p = Path.Combine(dir, name + ".png");
            ScreenCapture.CaptureScreenshot(p, 1);
            Debug.Log("[HMD] shot " + p);
            yield return null;
        }
    }
}
