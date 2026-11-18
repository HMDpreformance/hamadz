using System.Collections;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Video;

namespace HMD
{
    /// <summary>
    /// What you see before you drive, old-school street-racer style (Hamad: "loading screen like Midnight Club 3 and
    /// Need for Speed, the intro and the music"):
    ///  1. the intro film (first start only, a tap skips it),
    ///  2. the title screen: a loading picture, the game title and a blinking PRESS START,
    ///  3. the loading screen while the city is built: one of the four loading pictures, the title, a chunky segmented
    ///     bar that follows the real build steps, and a rotating tip.
    /// Music: the loading loop Hamad picked (D, boom-bap with a dark piano) on the title and loading screens, faded
    /// out when the city is ready. Test runs (-hmdshots) skip the film and the title screen.
    /// </summary>
    public class FrontEnd : MonoBehaviour
    {
        public static FrontEnd I;
        Canvas canvas;
        RawImage picture;
        Image[] segs;
        Text tip, title, press, pct;
        AudioSource music;
        float target, shown;
        int tipIndex; float tipTimer;
        Texture2D[] pictures;

        static readonly string[] Tips =
        {
            "Hold NOS for a burst of speed. The tank refills by itself.",
            "Drive into the LSX garage door to tune your car and run the dyno.",
            "Roads are wet tonight: brake a little earlier.",
            "Tap the map in the corner to see the whole city.",
            "E-BRK in a turn to slide the back out.",
            "The E11 and the E311 are the fastest way across Dubai.",
            "Press NEXT on the radio to skip a track.",
        };

        public static FrontEnd Create()
        {
            I = new GameObject("FrontEnd").AddComponent<FrontEnd>();
            I.Build();
            return I;
        }

        void Build()
        {
            canvas = UIKit.MakeCanvas("FrontEndCanvas", 200);
            canvas.transform.SetParent(transform, false);
            var root = canvas.transform;
            var bg = UIKit.Img("Black", root, Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero, Color.black);
            UIKit.Stretch(bg.rectTransform);

            pictures = new Texture2D[0];
            var list = new System.Collections.Generic.List<Texture2D>();
            foreach (var n in new[] { "load_coupe", "load_pickup", "load_startline", "load_garage" }) { var t = Res.Tex("Loading/" + n); if (t) list.Add(t); }
            pictures = list.ToArray();

            var pgo = new GameObject("Picture", typeof(RectTransform)); pgo.transform.SetParent(root, false);
            picture = pgo.AddComponent<RawImage>(); picture.raycastTarget = false;
            UIKit.Stretch(picture.rectTransform);
            var fitter = pgo.AddComponent<AspectRatioFitter>(); fitter.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
            PickPicture();

            // the dark band along the bottom of the pictures holds the bar and the tip
            var band = UIKit.Img("Band", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), Vector2.zero, new Vector2(4000, 230), new Color(0, 0, 0, 0.62f));
            band.raycastTarget = false;
            title = UIKit.Label("Title", root, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -40), new Vector2(1600, 140), "HMD NIGHT CLUB", 104, new Color(1f, 0.93f, 0.8f), TextAnchor.MiddleCenter, Res.TitleFont);
            var sh = title.gameObject.AddComponent<Outline>(); sh.effectColor = new Color(0, 0, 0, 0.85f); sh.effectDistance = new Vector2(4, -4);
            var sub = UIKit.Label("Sub", root, new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -170), new Vector2(1200, 50), "DUBAI  ·  AFTER DARK", 34, new Color(0.55f, 0.8f, 1f), TextAnchor.MiddleCenter, Res.TitleFont);
            sub.gameObject.AddComponent<Outline>().effectColor = new Color(0, 0, 0, 0.8f);

            // chunky segmented bar, MC3 style
            const int N = 28; const float segW = 40f, gap = 8f;
            float total = N * segW + (N - 1) * gap;
            var barBg = UIKit.Img("BarFrame", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 118), new Vector2(total + 24, 50), new Color(0.75f, 0.8f, 0.9f, 0.9f));
            barBg.raycastTarget = false;
            var barIn = UIKit.Img("BarBack", barBg.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(total + 16, 42), new Color(0.02f, 0.03f, 0.07f, 1f));
            barIn.raycastTarget = false;
            segs = new Image[N];
            for (int i = 0; i < N; i++)
            {
                segs[i] = UIKit.Img("Seg" + i, barIn.transform, new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(8 + i * (segW + gap), 0), new Vector2(segW, 30), new Color(0.12f, 0.16f, 0.24f));
                segs[i].raycastTarget = false;
            }
            pct = UIKit.Label("Pct", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(total * 0.5f + 120, 118), new Vector2(160, 50), "0%", 34, new Color(1f, 0.85f, 0.5f), TextAnchor.MiddleLeft, Res.TitleFont);
            var loadLbl = UIKit.Label("Loading", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(-total * 0.5f + 90, 172), new Vector2(400, 40), "LOADING", 30, new Color(0.55f, 0.8f, 1f), TextAnchor.MiddleLeft, Res.TitleFont);
            tip = UIKit.Label("Tip", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 40), new Vector2(1700, 60), "", 32, new Color(0.9f, 0.92f, 0.95f), TextAnchor.MiddleCenter, Res.Font);
            press = UIKit.Label("Press", root, new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 120), new Vector2(1200, 90), "PRESS START", 70, new Color(1f, 0.85f, 0.35f), TextAnchor.MiddleCenter, Res.TitleFont);
            press.gameObject.AddComponent<Outline>().effectColor = new Color(0, 0, 0, 0.85f);
            press.gameObject.SetActive(false);
            tipIndex = Random.Range(0, Tips.Length); tip.text = Tips[tipIndex];

            // the loading music (Hamad picked D)
            music = gameObject.AddComponent<AudioSource>();
            music.clip = Res.Load<AudioClip>("Music/loading_d_boombap");
            music.loop = true; music.spatialBlend = 0; music.volume = 0.0f; music.playOnAwake = false;
            if (music.clip) music.Play();
            SetLoadingVisible(true);
        }

        void PickPicture()
        {
            if (pictures.Length == 0) return;
            var t = pictures[Random.Range(0, pictures.Length)];
            picture.texture = t;
            picture.GetComponent<AspectRatioFitter>().aspectRatio = t.width / (float)t.height;
        }

        void SetLoadingVisible(bool v)
        {
            foreach (var n in new[] { "BarFrame", "Pct", "Loading", "Tip" })
            {
                var tr = canvas.transform.Find(n); if (tr) tr.gameObject.SetActive(v);
            }
        }

        /// <summary>Build progress 0..1 (the bar eases towards it).</summary>
        public void Progress(float p) { target = Mathf.Max(target, Mathf.Clamp01(p)); Paint(); }

        void Paint()
        {
            int lit = Mathf.RoundToInt(shown * segs.Length);
            for (int i = 0; i < segs.Length; i++)
            {
                // blue to hot orange along the bar
                var on = Color.Lerp(new Color(0.25f, 0.65f, 1f), new Color(1f, 0.6f, 0.15f), i / (float)(segs.Length - 1));
                segs[i].color = i < lit ? on : new Color(0.12f, 0.16f, 0.24f);
            }
            if (pct) pct.text = Mathf.RoundToInt(shown * 100f) + "%";
        }

        void Update()
        {
            if (music && music.clip) music.volume = Mathf.MoveTowards(music.volume, fadingOut ? 0f : MusicVolume, Time.unscaledDeltaTime * (fadingOut ? 0.5f : 0.8f));
            shown = Mathf.MoveTowards(shown, target, Time.unscaledDeltaTime * 1.5f);
            if (segs != null) Paint();
            tipTimer += Time.unscaledDeltaTime;
            if (tipTimer > 3.5f && tip) { tipTimer = 0; tipIndex = (tipIndex + 1) % Tips.Length; tip.text = Tips[tipIndex]; }
            if (press && press.gameObject.activeSelf) { var c = press.color; c.a = 0.35f + 0.65f * Mathf.Abs(Mathf.Sin(Time.unscaledTime * 2.6f)); press.color = c; }
        }

        /// <summary>Test hook: presses START from a script.</summary>
        public static bool PressNow;
        public static float MusicVolume => PlayerPrefs.GetFloat("hmd_music_vol", 0.7f);
        /// <summary>True until the loading screen has faded out.</summary>
        public bool Showing => canvas != null && canvas.gameObject.activeSelf;
        bool fadingOut;

        static bool Tapped() => Input.GetMouseButtonDown(0) || Input.touchCount > 0 && Input.GetTouch(0).phase == TouchPhase.Began || Input.anyKeyDown;

        /// <summary>The intro film, first start only; a tap skips it.</summary>
        public IEnumerator IntroFilm()
        {
            if (PlayerPrefs.GetInt("hmd_intro_seen", 0) == 1) yield break;
            string path = System.IO.Path.Combine(Application.streamingAssetsPath, "Video/intro.mp4");
            var vgo = new GameObject("IntroFilm");
            vgo.transform.SetParent(transform, false);
            var vp = vgo.AddComponent<VideoPlayer>();
            vp.playOnAwake = false; vp.isLooping = false; vp.url = path; vp.skipOnDrop = true;
            vp.audioOutputMode = VideoAudioOutputMode.Direct;
            var rt = new RenderTexture(1920, 1080, 0);
            vp.renderMode = VideoRenderMode.RenderTexture; vp.targetTexture = rt;
            var cover = new GameObject("Film", typeof(RectTransform)); cover.transform.SetParent(canvas.transform, false);
            var ri = cover.AddComponent<RawImage>(); ri.texture = rt; ri.color = Color.black; UIKit.Stretch(ri.rectTransform);
            var skip = UIKit.Label("Skip", cover.transform, new Vector2(1, 0), new Vector2(1, 0), new Vector2(-40, 30), new Vector2(400, 50), "TAP TO SKIP", 28, new Color(1, 1, 1, 0.6f), TextAnchor.MiddleRight, Res.TitleFont);
            float vol = music ? music.volume : 0; if (music) music.Pause();
            vp.Prepare();
            float t = 0;
            while (!vp.isPrepared && t < 6f) { t += Time.unscaledDeltaTime; if (Tapped()) break; yield return null; }
            if (vp.isPrepared)
            {
                vp.Play(); ri.color = Color.white;
                yield return null;
                t = 0;
                while ((vp.isPlaying || t < 0.5f) && t < 120f) { t += Time.unscaledDeltaTime; if (t > 0.4f && Tapped()) break; yield return null; }
            }
            else Debug.Log("[HMD] intro film: could not prepare " + path);
            PlayerPrefs.SetInt("hmd_intro_seen", 1); PlayerPrefs.Save();
            vp.Stop(); Destroy(vgo); Destroy(cover); rt.Release();
            if (music) { music.UnPause(); music.volume = vol; }
            yield return null;   // the skip tap must not also press START
        }

        /// <summary>The title screen: waits for a tap.</summary>
        public IEnumerator Title()
        {
            SetLoadingVisible(false);
            press.gameObject.SetActive(true);
            yield return null;
            // test runs: -autostart (or hmd_autostart in the Editor) presses START after 3 s
            bool auto = System.Environment.CommandLine.Contains("-autostart") || Application.isEditor && PlayerPrefs.GetInt("hmd_autostart", 0) == 1;
            float wait = 0;
            PressNow = false;
            while (!Tapped() && !PressNow && !(auto && (wait += Time.unscaledDeltaTime) > 3f)) yield return null;
            press.gameObject.SetActive(false);
            PickPicture();
            SetLoadingVisible(true);
            yield return null;
        }

        /// <summary>The city is ready: fade the music and the screen out, then remove everything.</summary>
        public IEnumerator Finish()
        {
            target = 1f;
            while (shown < 0.999f) yield return null;
            yield return new WaitForSecondsRealtime(0.25f);
            fadingOut = true;
            var group = canvas.gameObject.AddComponent<CanvasGroup>();
            float t = 0;
            while (t < 0.6f) { t += Time.unscaledDeltaTime; group.alpha = 1f - t / 0.6f; yield return null; }
            canvas.gameObject.SetActive(false);
            while (music && music.volume > 0.01f) yield return null;
            Destroy(gameObject);
            I = null;
        }
    }
}
