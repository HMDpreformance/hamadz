using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Engine sound from recorded loops at several rpm, on-load and off-load (the same sample set as the
    /// Godot game). The two loops nearest the current rpm play together, pitched to match, and on/off
    /// load crossfade with the throttle. Plus tyre squeal, turbo flutter on lift-off and gear-shift pops.
    /// </summary>
    public class CarAudio : MonoBehaviour
    {
        class Layer { public float rpm; public AudioSource on, off; }

        CarController car;
        readonly List<Layer> layers = new List<Layer>();
        AudioSource squeal, sfx;
        AudioClip[] pops;
        AudioClip flutter;
        float lastThrottle;
        int lastGear;
        public float master = 1f;
        // new effects (ElevenLabs / Higgsfield, unity_assets/sfx -> Resources/Imported/AudioHD)
        AudioSource brakeSq, wind, road, city, spool;
        AudioClip crash, nitroHit, bov;
        AudioSource nitroLoop;
        bool lastNitro; float lastCrash;

        /// <summary>An HD effect from AudioHD when there is one, else the old clip.</summary>
        static AudioClip Hd(string name, string fallback = null) => Res.Load<AudioClip>("AudioHD/" + name) ?? (fallback != null ? Res.Load<AudioClip>(fallback) : null);

        public void Setup(CarController c, bool player)
        {
            car = c;
            string eng = c.spec.engine;
            // new engine loops (Higgsfield, longer and steadier) when there are enough rpm points for this engine,
            // made seamless at load; otherwise the old recorded set
            var byRpm = Collect(Resources.LoadAll<AudioClip>(Res.Root + "AudioHD/engines"), eng);
            // opt-in until Hamad has heard the new V8 next to the old one (-newengine on the command line)
            hdEngine = byRpm.Count >= 3 && System.Environment.CommandLine.Contains("-newengine");
            if (hdEngine)
            {
                var looped = new SortedDictionary<int, AudioClip[]>();
                foreach (var kv in byRpm) looped[kv.Key] = new[] { MakeLoop(kv.Value[0]), MakeLoop(kv.Value[1]) };
                byRpm = looped;
            }
            else byRpm = Collect(Resources.LoadAll<AudioClip>(Res.Root + "Audio/engines"), eng);
            foreach (var kv in byRpm)
            {
                var l = new Layer { rpm = kv.Key, on = Src(kv.Value[0], player), off = Src(kv.Value[1] ?? kv.Value[0], player) };
                layers.Add(l);
            }
            // tyre squeal on slip (a real squeal loop now; the old clip was a brake squeal used for both)
            squeal = Src(Hd("tire_squeal", "Audio/car/brake_squeal"), player);
            brakeSq = Src(Hd("brake_squeal", "Audio/car/brake_squeal"), player);
            wind = Src(Hd("wind"), player);
            road = Src(Hd("road"), player);
            spool = Src(Hd("turbo_spool"), player); if (spool) spool.loop = false;
            if (player) { city = Src(Hd("amb_city", "Audio/amb_city"), true); city.spatialBlend = 0f; }
            sfx = Src(null, player);
            sfx.loop = false;
            var p = new List<AudioClip>();
            for (int i = 1; i <= 5; i++) { var a = Res.Load<AudioClip>("Audio/car/pop_" + i); if (a) p.Add(a); }
            var bf = Hd("backfire"); if (bf) { p.Add(bf); p.Add(bf); }   // the big crack comes up often
            pops = p.ToArray();
            flutter = Res.Load<AudioClip>("Audio/car/flutter_1");
            crash = Hd("crash", "Audio/crash");
            nitroHit = Hd("nitro", "Audio/nitro_start");
            if (player) { nitroLoop = Src(Res.Load<AudioClip>("Audio/nitro_loop"), player); if (nitroLoop) { nitroLoop.loop = true; nitroLoop.volume = 0f; nitroLoop.Stop(); } }
            bov = Hd("bov", "Audio/car/bov_big");
            if (player)
            {
                var hd = new List<string>();
                foreach (var n in new[] { "tire_squeal", "brake_squeal", "wind", "road", "amb_city", "turbo_spool", "bov", "crash", "nitro", "backfire" })
                    if (Res.Load<AudioClip>("AudioHD/" + n) != null) hd.Add(n);
                Debug.Log($"[HMD] car audio: engine {eng} with {layers.Count} rpm layers ({(hdEngine ? "new seamless loops" : "old loops")}); HD effects loaded: {(hd.Count > 0 ? string.Join(", ", hd) : "none")}");
            }
        }

        bool hdEngine;

        /// <summary>Clips named <engine>_<rpm>_<on|off>, grouped by rpm: [0] = on load, [1] = off load.</summary>
        static SortedDictionary<int, AudioClip[]> Collect(AudioClip[] all, string eng)
        {
            var byRpm = new SortedDictionary<int, AudioClip[]>();
            foreach (var clip in all)
            {
                var parts = clip.name.Split('_');
                if (parts.Length != 3 || parts[0] != eng) continue;
                if (!int.TryParse(parts[1], out int rpm)) continue;
                if (!byRpm.TryGetValue(rpm, out var pair)) { pair = new AudioClip[2]; byRpm[rpm] = pair; }
                pair[parts[2] == "on" ? 0 : 1] = clip;
            }
            return byRpm;
        }

        /// <summary>A seamless loop from a generated clip: trims 0.2 s off both ends (fades), then crossfades the last
        /// 0.35 s into the start with equal-power weights, so the loop point has no click or level dip.</summary>
        static AudioClip MakeLoop(AudioClip c)
        {
            if (c == null) return null;
            if (c.loadState != AudioDataLoadState.Loaded) c.LoadAudioData();
            int ch = c.channels, f = c.frequency, n = c.samples;
            var src = new float[n * ch];
            if (!c.GetData(src, 0)) return c;
            int trim = Mathf.Min((int)(0.2f * f), n / 6), xf = Mathf.Min((int)(0.35f * f), n / 4);
            int start = trim, len = n - 2 * trim - xf;
            if (len < f / 2) return c;
            var dst = new float[len * ch];
            for (int i = 0; i < len; i++)
                for (int k = 0; k < ch; k++)
                {
                    float a = src[(start + i) * ch + k];
                    if (i < xf)
                    {
                        float t = (float)i / xf;
                        float b = src[(start + len + i) * ch + k];   // the tail that flows into the start
                        a = a * Mathf.Sin(t * Mathf.PI * 0.5f) + b * Mathf.Cos(t * Mathf.PI * 0.5f);
                    }
                    dst[i * ch + k] = a;
                }
            var o = AudioClip.Create(c.name + "_loop", len, ch, f, false);
            o.SetData(dst, 0);
            return o;
        }

        /// <summary>Hits: a crash sound scaled by the impact (walls, barriers, buildings).</summary>
        void OnCollisionEnter(Collision c)
        {
            if (crash == null || sfx == null || Time.time - lastCrash < 0.4f) return;
            float imp = c.relativeVelocity.magnitude;
            if (imp < 4f) return;
            lastCrash = Time.time;
            sfx.PlayOneShot(crash, Mathf.Clamp01((imp - 4f) / 18f) * 0.9f * master);
        }

        AudioSource Src(AudioClip clip, bool player)
        {
            var s = gameObject.AddComponent<AudioSource>();
            s.clip = clip;
            s.loop = true;
            s.playOnAwake = false;
            s.volume = 0;
            s.spatialBlend = player ? 0.35f : 1f;
            s.minDistance = 6; s.maxDistance = 120;
            s.dopplerLevel = player ? 0 : 0.6f;
            if (clip != null) s.Play();
            return s;
        }

        void Update()
        {
            if (car == null || layers.Count == 0) return;
            float rpm = car.Rpm;
            float load = Mathf.Clamp01(car.EngineLoad);
            // find the two layers around the rpm
            int hi = layers.FindIndex(l => l.rpm >= rpm);
            if (hi < 0) hi = layers.Count - 1;
            int lo = Mathf.Max(0, hi - 1);
            float t = hi == lo ? 1 : Mathf.InverseLerp(layers[lo].rpm, layers[hi].rpm, rpm);
            for (int i = 0; i < layers.Count; i++)
            {
                var l = layers[i];
                float w = i == hi ? t : i == lo ? 1 - t : 0;
                if (hi == lo && i == hi) w = 1;
                float pitch = Mathf.Clamp(rpm / l.rpm, 0.5f, 2.0f);
                l.on.pitch = pitch; l.off.pitch = pitch;
                l.on.volume = w * Mathf.Lerp(0.25f, 1f, load) * master;
                l.off.volume = w * Mathf.Lerp(0.75f, 0.1f, load) * master;
            }
            if (squeal && squeal.clip)
                squeal.volume = Mathf.Clamp01((car.RearSlip - 0.35f) * 1.5f) * (car.SpeedKmh > 8 ? 0.7f : 0) * master;
            float v = car.SpeedKmh;
            // brakes: squeal when braking hard at speed
            if (brakeSq && brakeSq.clip) brakeSq.volume = (car.brake > 0.7f && v > 40f && car.ForwardSpeed > 0f ? Mathf.Clamp01((v - 40f) / 80f) * 0.45f : 0f) * master;
            // wind and road rise with speed (the old game had neither in Unity)
            if (wind && wind.clip) { wind.volume = Mathf.Clamp01(v / 260f) * Mathf.Clamp01(v / 260f) * 0.55f * master; wind.pitch = Mathf.Lerp(0.85f, 1.15f, v / 260f); }
            if (road && road.clip) { road.volume = Mathf.Clamp01(v / 120f) * 0.35f * master; road.pitch = Mathf.Lerp(0.7f, 1.3f, Mathf.Clamp01(v / 220f)); }
            if (city && city.clip) city.volume = 0.22f * master;
            // nitro: the hit when the boost fires
            if (car.NitroActive && !lastNitro && nitroHit) sfx.PlayOneShot(nitroHit, 0.8f * master);
            if (nitroLoop) { nitroLoop.volume = Mathf.MoveTowards(nitroLoop.volume, car.NitroActive ? 0.5f * master : 0f, Time.deltaTime * 3f); if (nitroLoop.volume > 0.001f && !nitroLoop.isPlaying) nitroLoop.Play(); else if (nitroLoop.volume <= 0.001f && nitroLoop.isPlaying) nitroLoop.Stop(); }
            lastNitro = car.NitroActive;
            // turbo whistle while pulling hard high in the rev range (turbo engines)
            bool turbo = car.spec.engine.Contains("tt") || car.spec.engine == "i4" || car.spec.engine == "i6" || car.spec.engine == "v6";
            if (turbo && spool && spool.clip)
            {
                bool pull = load > 0.8f && rpm > car.spec.rpmRedline * 0.45f;
                if (pull && !spool.isPlaying) spool.Play();
                spool.volume = (pull ? 0.35f : 0f) * master;
            }

            // lift-off flutter / pops, and a pop on upshift
            if (lastThrottle > 0.7f && car.EngineLoad < 0.2f && rpm > car.spec.rpmRedline * 0.55f)
            {
                if (turbo && bov) sfx.PlayOneShot(bov, 0.55f * master);   // blow-off valve
                else if (car.spec.engine == "i4" || car.spec.engine == "rotary") { if (flutter) sfx.PlayOneShot(flutter, 0.6f * master); }
                else if (pops.Length > 0) sfx.PlayOneShot(pops[Random.Range(0, pops.Length)], 0.5f * master);
            }
            if (car.Gear > lastGear && lastGear > 0 && pops.Length > 0) sfx.PlayOneShot(pops[Random.Range(0, pops.Length)], 0.35f * master);
            lastGear = car.Gear;
            lastThrottle = car.EngineLoad;
        }
    }
}
