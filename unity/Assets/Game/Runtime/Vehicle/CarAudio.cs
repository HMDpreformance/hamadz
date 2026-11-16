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

        public void Setup(CarController c, bool player)
        {
            car = c;
            string eng = c.spec.engine;
            var all = Resources.LoadAll<AudioClip>(Res.Root + "Audio/engines");
            var byRpm = new SortedDictionary<int, AudioClip[]>();
            foreach (var clip in all)
            {
                // name: <engine>_<rpm>_<on|off>
                var parts = clip.name.Split('_');
                if (parts.Length != 3 || parts[0] != eng) continue;
                if (!int.TryParse(parts[1], out int rpm)) continue;
                if (!byRpm.TryGetValue(rpm, out var pair)) { pair = new AudioClip[2]; byRpm[rpm] = pair; }
                pair[parts[2] == "on" ? 0 : 1] = clip;
            }
            foreach (var kv in byRpm)
            {
                var l = new Layer { rpm = kv.Key, on = Src(kv.Value[0], player), off = Src(kv.Value[1] ?? kv.Value[0], player) };
                layers.Add(l);
            }
            squeal = Src(Res.Load<AudioClip>("Audio/car/brake_squeal"), player);
            sfx = Src(null, player);
            sfx.loop = false;
            var p = new List<AudioClip>();
            for (int i = 1; i <= 5; i++) { var a = Res.Load<AudioClip>("Audio/car/pop_" + i); if (a) p.Add(a); }
            pops = p.ToArray();
            flutter = Res.Load<AudioClip>("Audio/car/flutter_1");
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

            // lift-off flutter / pops, and a pop on upshift
            if (lastThrottle > 0.7f && car.EngineLoad < 0.2f && rpm > car.spec.rpmRedline * 0.55f)
            {
                if (car.spec.engine == "i4" || car.spec.engine == "rotary") { if (flutter) sfx.PlayOneShot(flutter, 0.6f * master); }
                else if (pops.Length > 0) sfx.PlayOneShot(pops[Random.Range(0, pops.Length)], 0.5f * master);
            }
            if (car.Gear > lastGear && lastGear > 0 && pops.Length > 0) sfx.PlayOneShot(pops[Random.Range(0, pops.Length)], 0.35f * master);
            lastGear = car.Gear;
            lastThrottle = car.EngineLoad;
        }
    }
}
