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

            // street level city look
            g.rig.SetFixed(car.transform.position + new Vector3(-8, 1.6f, -12), car.transform.position + new Vector3(10, 4, 30), false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("03_city_street");
            g.rig.SetFixed(City.BlockCenter(3, 3) + new Vector3(-50, 30, -60), City.BlockCenter(4, 4) + Vector3.up * 30, false);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("04_city_high");

            // garage outside: forecourt, door closed
            g.GoToGarage();
            yield return new WaitForSeconds(1.2f);
            g.rig.mode = CameraRig.Mode.Fixed;
            Vector3 door = g.garage.DoorPos;
            g.rig.SetFixed(door + new Vector3(-12, 4.5f, -22), door + new Vector3(0, 4, 0), false);
            yield return new WaitForSeconds(0.8f);
            yield return Shot("05_garage_outside_closed");
            // drive close: the door opens only now
            car.Teleport(door + new Vector3(0, 0.5f, -5.5f), Quaternion.identity);
            yield return new WaitForSeconds(2.2f);
            yield return Shot("06_garage_door_open_close");
            // drive in
            t = 0;
            while (t < 4f && g.state == Game.State.Drive) { t += Time.deltaTime; car.throttle = 0.4f; yield return null; }
            car.throttle = 0;
            yield return new WaitForSeconds(2.5f);
            yield return Shot("07_workshop");
            g.rig.SetFixed(g.shop.transform.TransformPoint(new Vector3(-10, 3.2f, 2)), g.shop.transform.TransformPoint(new Vector3(4, 1.5f, 22)), false);
            yield return new WaitForSeconds(0.5f);
            yield return Shot("08_workshop_wide");

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
