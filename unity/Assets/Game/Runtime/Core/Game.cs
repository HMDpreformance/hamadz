using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// Starts and runs the game: builds the city, the LSX garage, the workshop, the player car,
    /// traffic, weather, camera and HUD, plays the rear-view car intro, then lets you drive.
    /// Drive into the LSX door (or press GARAGE / GO TO GARAGE) to reach the workshop.
    /// </summary>
    public class Game : MonoBehaviour
    {
        public static Game I;
        public enum State { Intro, Drive, Garage, Dyno }
        public State state;

        public City city;
        public NewCity newCity;
        public GarageBuilding garage;
        public Workshop shop;
        public CarController car;
        public CameraRig rig;
        public Hud hud;
        public GarageUI garageUI;
        public Dyno dyno;
        public Traffic traffic;
        public GfxSetup gfx;
        Image fade;
        string carId;

        public static bool AutoShots => System.Environment.CommandLine.Contains("-hmdshots");

        void Awake()
        {
            I = this;
            carId = PlayerPrefs.GetString("car", "sport");
            // -car <id> on the command line picks the car for this run (used for screenshots)
            var argv = System.Environment.GetCommandLineArgs();
            for (int a = 0; a + 1 < argv.Length; a++) if (argv[a] == "-car") carId = argv[a + 1];
            if (System.Array.IndexOf(CarDB.Order, carId) < 0) carId = "sport";
        }

        IEnumerator Start()
        {
            // camera
            var camGo = Camera.main ? Camera.main.gameObject : new GameObject("Main Camera", typeof(Camera), typeof(AudioListener));
            camGo.tag = "MainCamera";
            rig = camGo.GetComponent<CameraRig>() ?? camGo.AddComponent<CameraRig>();
            rig.Setup();

            // weather first (it decides the fog and road)
            var wx = new GameObject("Weather").AddComponent<Weather>();
            bool? forceRain = null;
            string cl = System.Environment.CommandLine;
            if (cl.Contains("-rain")) forceRain = true;
            if (cl.Contains("-dry")) forceRain = false;

            gfx = new GameObject("Gfx").AddComponent<GfxSetup>();

            Vector3 startPos; Quaternion startRot; Vector3 garageDoor;
            if (NewCity.Wanted)
            {
                // -newcity: part 1 of the Dubai city instead of the grid (no grid props, lamps or traffic yet)
                newCity = new GameObject("NewCity").AddComponent<NewCity>();
                newCity.Build();
                wx.Setup(camGo.transform, forceRain);
                gfx.Setup(rig.Cam);
                var dress = new GameObject("NewCityDressing").AddComponent<NewCityDressing>();
                dress.Build(newCity);
                if (dress.lampHeads.Count > 0) new GameObject("LampLights").AddComponent<LampLights>().Setup(dress.lampHeads, camGo.transform, dress.lampCool);
                else new GameObject("LampLights").AddComponent<LampLights>().Setup(newCity.lampHeads, camGo.transform);
                // the sky glows over the tallest landmark (the needle tower in Downtown)
                float tallest = 0; foreach (var lm in NewCityDressing.Landmarks) if (lm.h > tallest) { tallest = lm.h; GfxSetup.SkyGlowCentre = lm.p; }
                yield return null;
                startPos = newCity.SpawnPos; startRot = newCity.SpawnRot;
                garageDoor = newCity.Garage;   // the real LSX building at json.garage (Al Quoz), door facing -Z
            }
            else
            {
                city = new GameObject("City").AddComponent<City>();
                city.Build();
                new GameObject("StreetProps").AddComponent<StreetProps>().Build(city);
                wx.Setup(camGo.transform, forceRain);
                gfx.Setup(rig.Cam);
                new GameObject("LampLights").AddComponent<LampLights>().Setup(city, camGo.transform);
                yield return null;
                startPos = city.PlayerStart; startRot = city.PlayerStartRot; garageDoor = city.GarageDoor;
            }

            car = CarFactory.Build(carId, startPos, startRot, true);
            car.gameObject.AddComponent<PlayerInput>();
            car.Body.isKinematic = false;
            car.Body.ResetInertiaTensor();   // recompute now that only the body box and wheels are left
            car.inputLocked = true;

            garage = new GameObject("LSX_Garage").AddComponent<GarageBuilding>();
            garage.transform.rotation = Quaternion.identity;
            garage.Build(garageDoor, car.transform);
            if (newCity != null) Driveway(garageDoor);
            garage.OnEnter = () => StartCoroutine(EnterGarage());

            shop = new GameObject("Workshop").AddComponent<Workshop>();
            shop.Build();
            dyno = shop.gameObject.AddComponent<Dyno>();
            dyno.Setup(shop, rig);

            if (!NewCity.Wanted) { traffic = new GameObject("Traffic").AddComponent<Traffic>();
            traffic.Setup(car.transform); }

            hud = new GameObject("HUD").AddComponent<Hud>();
            hud.Build(car, car.transform);
            hud.OnGarage = GoToGarage;
            hud.Map.OnGoGarage = GoToGarage;
            hud.SetVisible(false);

            garageUI = new GameObject("GarageUI").AddComponent<GarageUI>();
            garageUI.Build();
            garageUI.SetVisible(false);
            garageUI.OnPrev = () => SwitchCar(-1);
            garageUI.OnNext = () => SwitchCar(1);
            garageUI.OnDyno = RunDyno;
            garageUI.OnDriveOut = () => StartCoroutine(LeaveGarage());
            garageUI.OnTv = () => dyno.ZoomTv();
            dyno.OnDone = () =>
            {
                garageUI.ShowResult(dyno.PeakHp, dyno.PeakNm, car.spec.rpmRedline);
                garageUI.SetBusy(false);
            };

            var fc = UIKit.MakeCanvas("Fade", 100);
            fade = UIKit.Img("Black", fc.transform, Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero, Color.black);
            UIKit.Stretch(fade.rectTransform);
            fade.raycastTarget = false;

            // the car intro: from the back
            rig.target = car.transform;
            state = State.Intro;
            rig.OnIntroDone = () =>
            {
                state = State.Drive;
                car.inputLocked = false;
                hud.SetVisible(true);
                hud.SetTouchVisible(Application.isMobilePlatform || Input.touchSupported || System.Environment.CommandLine.Contains("-touchui"));
            };
            rig.StartIntro();
            yield return Fade(1, 0, 1.2f);

            if (AutoShots) { if (newCity) gameObject.AddComponent<NcShots>(); else gameObject.AddComponent<AutoShots>(); }
        }

        /// <summary>New city: a concrete driveway from the LSX forecourt down/up to the road in front (door faces -Z).</summary>
        void Driveway(Vector3 door)
        {
            Physics.SyncTransforms();
            Vector3 road = door + Vector3.back * 12f;
            for (float dz = 12f; dz < 40f; dz += 1f)
            {
                var p = door + Vector3.back * dz;
                if (Physics.Raycast(p + Vector3.up * 15f, Vector3.down, out var hit, 40f) && (hit.collider.name.ToLowerInvariant().Contains("asphalt")))
                { road = hit.point; break; }
            }
            Vector3 a = door + Vector3.back * 11.5f, b = road + Vector3.back * 1.5f;
            float len = Vector3.Distance(new Vector3(a.x, 0, a.z), new Vector3(b.x, 0, b.z));
            var slab = GameObject.CreatePrimitive(PrimitiveType.Cube);
            slab.name = "LSX_Driveway";
            slab.transform.position = (a + b) * 0.5f + Vector3.down * 0.12f;
            slab.transform.rotation = Quaternion.LookRotation(b - a);
            slab.transform.localScale = new Vector3(14f, 0.3f, Mathf.Max(1f, (b - a).magnitude));
            slab.GetComponent<Renderer>().sharedMaterial = Res.TexMat("Tex/concrete_pavement", Vector2.one / 4f, 0.45f, 0f, new Color(0.62f, 0.62f, 0.62f));
            Debug.Log($"[HMD] LSX driveway: door y {door.y:F2}, road at {road} ({len:F1} m, rise {road.y - door.y:F2} m)");
        }

        IEnumerator Fade(float from, float to, float time)
        {
            float t = 0;
            while (t < time)
            {
                t += Time.unscaledDeltaTime;
                fade.color = new Color(0, 0, 0, Mathf.Lerp(from, to, t / time));
                yield return null;
            }
            fade.color = new Color(0, 0, 0, to);
        }

        /// <summary>GARAGE button: puts you on the forecourt facing the LSX door; you drive in yourself.</summary>
        public void GoToGarage()
        {
            if (state != State.Drive) return;
            StartCoroutine(GoToGarageRoutine());
        }

        IEnumerator GoToGarageRoutine()
        {
            yield return Fade(0, 1, 0.35f);
            car.Teleport(garage.Forecourt + Vector3.up * 0.5f, Quaternion.identity);   // facing +Z = the door
            rig.SnapChase();
            yield return Fade(1, 0, 0.45f);
        }

        IEnumerator EnterGarage()
        {
            if (state != State.Drive) yield break;
            state = State.Garage;
            car.inputLocked = true;
            hud.SetVisible(false);
            yield return Fade(0, 1, 0.5f);
            ParkInShop();
            gfx.SetProbeActive(false);
            shop.Probe.RenderProbe();
            garageUI.ShowCar(car.spec);
            garageUI.SetVisible(true);
            yield return Fade(1, 0, 0.6f);
        }

        void ParkInShop()
        {
            car.Body.isKinematic = true;
            car.dynoMode = false;
            car.Place(shop.DisplaySpot + Vector3.up * (car.RestHeight + 0.005f), shop.DisplayRot);   // tyres on the floor
            rig.target = car.transform;
            rig.mode = CameraRig.Mode.Orbit;
            rig.orbitDistance = car.spec.length * 1.35f;
        }

        void SwitchCar(int dir)
        {
            if (dyno.Running) return;
            int i = System.Array.IndexOf(CarDB.Order, carId);
            i = (i + dir + CarDB.Order.Length) % CarDB.Order.Length;
            carId = CarDB.Order[i];
            PlayerPrefs.SetString("car", carId);
            var old = car;
            car = CarFactory.Build(carId, shop.DisplaySpot, shop.DisplayRot, true);
            car.gameObject.AddComponent<PlayerInput>();
            Destroy(old.gameObject);
            ParkInShop();
            car.inputLocked = true;
            hud.car = car;
            garageUI.ShowCar(car.spec);
            ReTarget();
        }

        void ReTarget()
        {
            garage.SetPlayer(car.transform);
            if (traffic) traffic.SetPlayer(car.transform);
        }

        void RunDyno()
        {
            if (dyno.Running) return;
            state = State.Dyno;
            garageUI.SetBusy(true);
            garageUI.ShowCar(car.spec);
            dyno.Run(car);
        }

        void LeaveGarageNow() => StartCoroutine(LeaveGarage());

        IEnumerator LeaveGarage()
        {
            if (dyno.Running) yield break;
            garageUI.SetVisible(false);
            yield return Fade(0, 1, 0.5f);
            car.dynoMode = false;
            car.Body.isKinematic = false;
            car.Body.ResetInertiaTensor();   // recompute now that only the body box and wheels are left
            // out on the forecourt, facing away from the door towards the road
            car.Teleport(garage.DoorPos + new Vector3(0, 0.5f, -7f), Quaternion.Euler(0, 180, 0));
            garage.ForceClosed();
            gfx.SetProbeActive(true);
            rig.target = car.transform;
            rig.SnapChase();
            state = State.Drive;
            car.inputLocked = false;
            hud.car = car;
            hud.SetVisible(true);
            yield return Fade(1, 0, 0.6f);
        }

        float stuckT;

        void Update()
        {
            // in the garage, tapping the TV zooms in on it
            if ((state == State.Garage || state == State.Dyno) && !dyno.Running && Input.GetMouseButtonDown(0) && shop.Tv != null)
            {
                var ray = rig.Cam.ScreenPointToRay(Input.mousePosition);
                if (Physics.Raycast(ray, out var hit, 60f) && hit.transform.IsChildOf(shop.Tv)) dyno.ZoomTv();
            }
            // fell off the world or flipped: put the car back on the road
            if (state == State.Drive && car != null)
            {
                var cp = car.transform.position;
                bool flipped = Vector3.Dot(car.transform.up, Vector3.up) < 0.2f && car.SpeedKmh < 3f;
                bool inWater = newCity && cp.y < NewCity.WaterY - 0.3f;   // the sea has no collider: the car sinks to the bed
                stuckT = (flipped || inWater) ? stuckT + Time.deltaTime : 0f;
                if (cp.y < -5f || stuckT > (inWater ? 0.8f : 1.2f))
                {
                    stuckT = 0;
                    Vector3 pos; Quaternion rot;
                    if (newCity && newCity.NearestLane(cp, car.transform.forward, out pos, out rot))
                        car.Teleport(pos + Vector3.up * 0.8f, rot);   // back on the nearest road lane, on its own deck
                    else
                        car.Teleport(newCity ? NewCity.Surface(cp) + Vector3.up * 0.8f : new Vector3(cp.x, 0.8f, cp.z), Quaternion.Euler(0, car.transform.eulerAngles.y, 0));
                    rig.SnapChase();
                    Debug.Log($"[HMD] car reset from ({cp.x:F0},{cp.y:F1},{cp.z:F0}) to ({car.transform.position.x:F0},{car.transform.position.y:F1},{car.transform.position.z:F0}) ({(cp.y < -5f ? "fell" : inWater ? "water" : "flipped")})");
                }
            }
        }
    }
}
