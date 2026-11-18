using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace HMD
{
    /// <summary>
    /// The car radio: mid-2000s old-school tracks (Hamad's pick), shuffled, playing while you drive. A small pop-up in
    /// the top-left corner shows the station and the track when one starts; NEXT (top-left button, or R) skips.
    /// The music dips a little under a loud engine, pauses in the workshop, and keeps the saved volume.
    /// Not in the playlist (Hamad did not like them): Block Shaker, Main Theme, Night Rollin. No DJ voice yet.
    /// </summary>
    public class Radio : MonoBehaviour
    {
        public static Radio I;
        public const string Station = "NIGHT FM 99.1";
        static readonly string[] Excluded = { "block_shaker", "main_theme", "night_rollin" };

        readonly List<AudioClip> tracks = new List<AudioClip>();
        AudioSource src;
        int index = -1;
        bool paused;
        CanvasGroup pop; Text popTrack; float popT;

        public static void Ensure(Transform parent)
        {
            if (I != null || Game.AutoShots && !System.Environment.CommandLine.Contains("-radio")) return;   // test runs: quiet
            I = new GameObject("Radio").AddComponent<Radio>();
            I.transform.SetParent(parent, false);
            I.Setup();
        }

        void Setup()
        {
            foreach (var c in Resources.LoadAll<AudioClip>(Res.Root + "Audio/music"))
                if (System.Array.IndexOf(Excluded, c.name) < 0) tracks.Add(c);
            tracks.AddRange(Resources.LoadAll<AudioClip>(Res.Root + "Music/Radio"));
            // shuffle
            for (int i = tracks.Count - 1; i > 0; i--) { int j = Random.Range(0, i + 1); (tracks[i], tracks[j]) = (tracks[j], tracks[i]); }
            src = gameObject.AddComponent<AudioSource>();
            src.spatialBlend = 0; src.loop = false; src.playOnAwake = false; src.volume = 0;
            BuildUi();
            Debug.Log($"[HMD] radio: {tracks.Count} tracks");
        }

        void BuildUi()
        {
            var canvas = UIKit.MakeCanvas("RadioUI", 12);
            canvas.transform.SetParent(transform, false);
            var root = canvas.transform;
            UIKit.Btn("RadioNext", root, new Vector2(0, 1), new Vector2(0, 1), new Vector2(28, -24), new Vector2(190, 76), "NEXT ▶▶", Next, new Color(0.24f, 0.63f, 1f), 30);
            var panel = UIKit.Img("RadioPop", root, new Vector2(0, 1), new Vector2(0, 1), new Vector2(236, -24), new Vector2(560, 76), new Color(0.01f, 0.03f, 0.09f, 0.78f), UIKit.RoundedSprite);
            panel.raycastTarget = false;
            pop = panel.gameObject.AddComponent<CanvasGroup>(); pop.alpha = 0; pop.blocksRaycasts = false;
            UIKit.Label("Station", panel.transform, new Vector2(0, 1), new Vector2(0, 1), new Vector2(18, -6), new Vector2(520, 30), Station, 22, new Color(0.55f, 0.8f, 1f), TextAnchor.MiddleLeft, Res.TitleFont).raycastTarget = false;
            popTrack = UIKit.Label("Track", panel.transform, new Vector2(0, 0), new Vector2(0, 0), new Vector2(18, 6), new Vector2(530, 38), "", 30, new Color(1f, 0.93f, 0.8f), TextAnchor.MiddleLeft, Res.TitleFont);
            popTrack.raycastTarget = false;
        }

        public void Next()
        {
            if (tracks.Count == 0) return;
            index = (index + 1) % tracks.Count;
            src.clip = tracks[index];
            src.time = 0;
            src.Play();
            popTrack.text = Pretty(tracks[index].name);
            popT = 4.5f;
            Debug.Log("[HMD] radio: now playing " + tracks[index].name);
        }

        static string Pretty(string n)
        {
            var parts = n.Replace('-', '_').Split('_');
            for (int i = 0; i < parts.Length; i++) if (parts[i].Length > 0) parts[i] = char.ToUpperInvariant(parts[i][0]) + parts[i].Substring(1);
            return string.Join(" ", parts).Trim();
        }

        void Update()
        {
            var g = Game.I;
            bool driving = g != null && g.state == Game.State.Drive;
            if (Input.GetKeyDown(KeyCode.R) && driving) Next();
            if (driving && index < 0) Next();
            if (driving && paused) { src.UnPause(); paused = false; }
            if (!driving && src.isPlaying) { src.Pause(); paused = true; }
            if (driving && !paused && index >= 0 && !src.isPlaying && src.clip != null && src.time <= 0.01f) Next();   // track ended

            // a little lower under a loud engine (full throttle at high revs), never silent
            float duck = 1f;
            if (g != null && g.car != null) duck = 1f - 0.3f * g.car.EngineLoad * Mathf.Clamp01(g.car.Rpm / Mathf.Max(1f, g.car.spec.rpmRedline));
            float want = driving ? FrontEnd.MusicVolume * 0.55f * duck : 0f;
            src.volume = Mathf.MoveTowards(src.volume, want, Time.unscaledDeltaTime * 0.8f);

            if (popT > 0) popT -= Time.unscaledDeltaTime;
            float a = popT > 4.2f ? (4.5f - popT) / 0.3f : popT < 0.6f ? popT / 0.6f : 1f;
            pop.alpha = driving ? Mathf.Clamp01(a) : 0f;
        }
    }
}
