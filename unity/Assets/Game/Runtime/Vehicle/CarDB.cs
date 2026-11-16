using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    public enum Drive { RWD, FWD, AWD }

    /// <summary>One car in the catalogue. Numbers are real-world units (hp, Nm, kg, m).</summary>
    public class CarSpec
    {
        public string id, name, tag, engine, cyl;
        public int price;
        public float hp, torqueNm, topKmh, weightKg, handling;
        public Drive drive;
        public float length = 4.4f;          // body length in metres (the model is scaled to it)
        public float rpmIdle = 900, rpmRedline = 7400;
        public float[] gears = { 3.2f, 2.1f, 1.5f, 1.15f, 0.92f, 0.76f };
        public float finalDrive = 3.9f;
        public Color paint = new Color(0.78f, 0.03f, 0.03f);
        public float wheelRadius = 0.33f;
        public float rideHeight = 0.0f;
    }

    /// <summary>The same 8 original cars as the Godot game (names and specs carried over).</summary>
    public static class CarDB
    {
        public static readonly string[] Order = { "tuner", "classic", "muscle", "sedan", "rotary", "euro", "suv", "exotic" };
        static Dictionary<string, CarSpec> cars;

        public static CarSpec Get(string id)
        {
            if (cars == null) Build();
            return cars.TryGetValue(id, out var s) ? s : cars["tuner"];
        }

        public static IEnumerable<CarSpec> All()
        {
            if (cars == null) Build();
            foreach (var id in Order) yield return cars[id];
        }

        static void Add(CarSpec s) => cars[s.id] = s;

        static void Build()
        {
            cars = new Dictionary<string, CarSpec>();
            Add(new CarSpec { id = "tuner", name = "KAIDO RS-7", tag = "JAPANESE TUNER COUPE", price = 0, hp = 276, torqueNm = 353, topKmh = 245, weightKg = 1280, handling = 78, drive = Drive.RWD, engine = "i4", cyl = "2.0L TURBO I4", length = 4.45f, rpmRedline = 8000, paint = new Color(0.62f, 0.85f, 0.22f) });
            Add(new CarSpec { id = "muscle", name = "BRAWLER 427", tag = "AMERICAN MUSCLE", price = 18500, hp = 390, torqueNm = 624, topKmh = 254, weightKg = 1620, handling = 58, drive = Drive.RWD, engine = "v8", cyl = "7.0L V8", length = 4.75f, rpmRedline = 6500, gears = new[] { 2.9f, 1.9f, 1.35f, 1.0f, 0.8f }, finalDrive = 3.5f, paint = new Color(0.02f, 0.02f, 0.025f) });
            Add(new CarSpec { id = "euro", name = "VERANO GT", tag = "EUROPEAN PERFORMANCE", price = 32000, hp = 340, torqueNm = 420, topKmh = 275, weightKg = 1390, handling = 88, drive = Drive.RWD, engine = "i6", cyl = "3.6L FLAT 6", length = 4.5f, rpmRedline = 7800, paint = new Color(0.45f, 0.95f, 0.1f) });
            Add(new CarSpec { id = "classic", name = "CORONADO '64", tag = "CLASSIC LOWRIDER", price = 14000, hp = 250, torqueNm = 475, topKmh = 196, weightKg = 1760, handling = 46, drive = Drive.RWD, engine = "v8", cyl = "5.4L V8", length = 5.3f, rpmRedline = 5800, gears = new[] { 2.5f, 1.5f, 1.0f }, finalDrive = 3.3f, paint = new Color(0.95f, 0.15f, 0.55f) });
            Add(new CarSpec { id = "sedan", name = "VANTA S6", tag = "LUXURY SPORT SEDAN", price = 21000, hp = 305, torqueNm = 393, topKmh = 250, weightKg = 1640, handling = 70, drive = Drive.RWD, engine = "v6", cyl = "3.5L V6", length = 4.9f, rpmRedline = 7000, paint = new Color(0.08f, 0.1f, 0.18f) });
            Add(new CarSpec { id = "rotary", name = "AKAGI RZ-8", tag = "ROTARY SPORTS COUPE", price = 26000, hp = 265, torqueNm = 298, topKmh = 254, weightKg = 1240, handling = 85, drive = Drive.RWD, engine = "rotary", cyl = "1.3L TWIN-ROTOR TURBO", length = 4.3f, rpmRedline = 9000, paint = new Color(0.8f, 0.04f, 0.04f) });
            Add(new CarSpec { id = "suv", name = "TITAN LX", tag = "LUXURY SUV", price = 38000, hp = 410, torqueNm = 705, topKmh = 222, weightKg = 2480, handling = 50, drive = Drive.AWD, engine = "v8sc", cyl = "6.2L SUPERCHARGED V8", length = 5.1f, rpmRedline = 6200, wheelRadius = 0.38f, finalDrive = 3.6f, paint = new Color(0.06f, 0.06f, 0.07f) });
            Add(new CarSpec { id = "exotic", name = "ARDENTE V12", tag = "ITALIAN EXOTIC", price = 125000, hp = 580, torqueNm = 637, topKmh = 330, weightKg = 1480, handling = 92, drive = Drive.AWD, engine = "exotic", cyl = "6.0L V12", length = 4.7f, rpmRedline = 9000, gears = new[] { 3.1f, 2.2f, 1.65f, 1.3f, 1.05f, 0.87f, 0.72f }, finalDrive = 3.6f, paint = new Color(0.78f, 0.03f, 0.03f) });
        }
    }

    /// <summary>Per-model data from unity_cars/&lt;id&gt;_cfg.json (tools/unity_prep_cars.py). Lengths are in body lengths;
    /// the model faces +Z, is centred on x/z and its tyres touch y = 0.</summary>
    [System.Serializable]
    public class CarModelCfg
    {
        public WheelSpot front, rear;
        public float[] size;
        public string key;

        [System.Serializable]
        public class WheelSpot { public float x, y, z, r; }

        public static CarModelCfg Load(string id)
        {
            var t = Res.Load<TextAsset>("Cars/" + id + "_cfg");
            if (t == null) return null;
            try { return JsonUtility.FromJson<CarModelCfg>(t.text); }
            catch { return null; }
        }
    }
}
