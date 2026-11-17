using System.Collections.Generic;
using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Loads the art that HMD > Setup copied from the repo into Assets/Resources/Imported,
    /// and makes materials from the template materials Setup created (so the right shaders
    /// are always inside the build, URP Lit when URP is installed, Standard otherwise).
    /// </summary>
    public static class Res
    {
        public const string Root = "Imported/";
        static readonly Dictionary<string, Object> cache = new Dictionary<string, Object>();
        static readonly Dictionary<string, Material> matCache = new Dictionary<string, Material>();

        public static T Load<T>(string path) where T : Object
        {
            string key = typeof(T).Name + ":" + path;
            if (cache.TryGetValue(key, out var o)) return o as T;
            var r = Resources.Load<T>(Root + path);
            cache[key] = r;
            return r;
        }

        public static Texture2D Tex(string path) => Load<Texture2D>(path);

        static Material litTemplate, unlitTemplate, glassTemplate, particleTemplate;

        static Material Template(ref Material slot, string name, string fallbackShader)
        {
            if (slot != null) return slot;
            slot = Resources.Load<Material>(Root + "Mats/" + name);
            if (slot == null)
            {
                var sh = Shader.Find(fallbackShader);
                if (sh == null) sh = Shader.Find("Standard");
                slot = new Material(sh);
            }
            return slot;
        }

        public static bool IsUrp => Lit().shader != null && Lit().shader.name.Contains("Universal");

        static Material Lit() => Template(ref litTemplate, "Lit", "Universal Render Pipeline/Lit");
        static Material Unlit() => Template(ref unlitTemplate, "Unlit", "Universal Render Pipeline/Unlit");
        static Material GlassT() => Template(ref glassTemplate, "Glass", "Universal Render Pipeline/Lit");
        static Material ParticleT() => Template(ref particleTemplate, "Particle", "Universal Render Pipeline/Particles/Unlit");

        /// <summary>A PBR material. smooth = 0..1, metal = 0..1.</summary>
        public static Material Mat(Color color, float smooth = 0.5f, float metal = 0f)
        {
            var m = new Material(Lit());
            SetColor(m, color);
            m.SetFloat("_Smoothness", smooth);
            m.SetFloat("_Glossiness", smooth);
            m.SetFloat("_Metallic", metal);
            return m;
        }

        /// <summary>A textured PBR material from a texture set name like "Tex/asphalt_04" (expects _diff, _nor, optional _ms).</summary>
        public static Material TexMat(string set, Vector2 tiling, float smooth = 0.5f, float metal = 0f, Color? tint = null, float normalScale = 1f, bool metalMap = true)
        {
            string key = set + tiling + smooth + metal + tint + normalScale + metalMap;
            if (matCache.TryGetValue(key, out var cached)) return cached;
            var m = Mat(tint ?? Color.white, smooth, metal);
            var d = Tex(set + "_diff");
            if (d != null) SetMainTex(m, d, tiling);
            var n = Tex(set + "_nor");
            if (n != null)
            {
                m.SetTexture("_BumpMap", n);
                m.SetTextureScale("_BumpMap", tiling);
                m.SetFloat("_BumpScale", normalScale);
                m.EnableKeyword("_NORMALMAP");
            }
            var ms = metalMap ? Tex(set + "_ms") : null;   // painted metal (walls) skips the bare-metal map, or it mirrors the dark room
            if (ms != null)
            {
                m.SetTexture("_MetallicGlossMap", ms);
                m.SetTextureScale("_MetallicGlossMap", tiling);
                m.EnableKeyword("_METALLICSPECGLOSSMAP");
                m.SetFloat("_Smoothness", smooth);      // URP: multiplier on map alpha
                m.SetFloat("_GlossMapScale", smooth);
            }
            matCache[key] = m;
            return m;
        }

        public static void SetColor(Material m, Color c)
        {
            if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
            if (m.HasProperty("_Color")) m.SetColor("_Color", c);
        }

        public static void SetMainTex(Material m, Texture t, Vector2 tiling)
        {
            if (m.HasProperty("_BaseMap")) { m.SetTexture("_BaseMap", t); m.SetTextureScale("_BaseMap", tiling); }
            if (m.HasProperty("_MainTex")) { m.SetTexture("_MainTex", t); m.SetTextureScale("_MainTex", tiling); }
        }

        public static void SetEmission(Material m, Color c, Texture map = null)
        {
            m.EnableKeyword("_EMISSION");
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
            m.SetColor("_EmissionColor", c);
            if (map != null) m.SetTexture("_EmissionMap", map);
        }

        /// <summary>Glowing material (neon, lamps, tail lights). HDR colour: intensity above 1 blooms.</summary>
        public static Material Glow(Color c, float intensity = 3f)
        {
            var m = Mat(Color.black, 0.6f, 0f);
            SetEmission(m, c * intensity);
            return m;
        }

        public static Material UnlitMat(Color c, Texture t = null)
        {
            var m = new Material(Unlit());
            SetColor(m, c);
            if (t != null) SetMainTex(m, t, Vector2.one);
            return m;
        }

        /// <summary>Tinted see-through glass (car windows, towers).</summary>
        public static Material Glass(Color c, float smooth = 0.95f)
        {
            var m = new Material(GlassT());
            SetColor(m, c);
            m.SetFloat("_Smoothness", smooth);
            m.SetFloat("_Metallic", 0.2f);
            return m;
        }

        public static Material Particle(Color c, Texture t = null)
        {
            var m = new Material(ParticleT());
            SetColor(m, c);
            if (t != null) SetMainTex(m, t, Vector2.one);
            return m;
        }

        static Font font;
        public static Font Font
        {
            get
            {
                if (font != null) return font;
                font = Load<Font>("Fonts/rajdhani_Rajdhani-Bold");
                if (font == null) font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
                return font;
            }
        }

        static Font titleFont;
        public static Font TitleFont
        {
            get
            {
                if (titleFont != null) return titleFont;
                titleFont = Load<Font>("Fonts/russoone_RussoOne-Regular");
                if (titleFont == null) titleFont = Font;
                return titleFont;
            }
        }

        /// <summary>A soft round sprite, made once (used for glows, rain, minimap dots).</summary>
        static Texture2D softDot;
        public static Texture2D SoftDot
        {
            get
            {
                if (softDot != null) return softDot;
                const int n = 64;
                softDot = new Texture2D(n, n, TextureFormat.RGBA32, false);
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float dx = (x + 0.5f) / n * 2 - 1, dy = (y + 0.5f) / n * 2 - 1;
                        float a = Mathf.Clamp01(1 - Mathf.Sqrt(dx * dx + dy * dy));
                        softDot.SetPixel(x, y, new Color(1, 1, 1, a * a));
                    }
                softDot.Apply();
                softDot.wrapMode = TextureWrapMode.Clamp;
                return softDot;
            }
        }

        /// <summary>Soft rounded-rectangle alpha, used as the dark contact shadow under cars.</summary>
        static Texture2D softBox;
        public static Texture2D SoftBox
        {
            get
            {
                if (softBox != null) return softBox;
                const int n = 64;
                softBox = new Texture2D(n, n, TextureFormat.RGBA32, false);
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float dx = Mathf.Abs((x + 0.5f) / n * 2 - 1), dy = Mathf.Abs((y + 0.5f) / n * 2 - 1);
                        // distance outside an inner rounded box, faded to the edge
                        float ox = Mathf.Max(0, dx - 0.55f) / 0.45f, oy = Mathf.Max(0, dy - 0.55f) / 0.45f;   // solid core under the body, soft fall-off past the tyres
                        float a = Mathf.Clamp01(1 - Mathf.Sqrt(ox * ox + oy * oy));
                        softBox.SetPixel(x, y, new Color(1, 1, 1, Mathf.Sqrt(a)));   // eases out slowly: stays dark well past the body, fades only at the rim
                    }
                softBox.Apply();
                softBox.wrapMode = TextureWrapMode.Clamp;
                return softBox;
            }
        }

        static Material shadowMat;
        /// <summary>Shared material of the contact shadow quads (alpha blended black, drawn after the road).</summary>
        public static Material ShadowMat
        {
            get
            {
                if (shadowMat != null) return shadowMat;
                // the alpha-blended glass template (the particle template is additive, so black added nothing);
                // black, matte and without reflections it simply darkens what is under it
                shadowMat = new Material(GlassT());
                SetColor(shadowMat, new Color(0, 0, 0, 0.9f));
                // plain alpha blending, set explicitly (the template came out additive, so black added nothing)
                shadowMat.SetFloat("_Surface", 1f); shadowMat.SetFloat("_Blend", 0f); shadowMat.SetFloat("_BlendModePreserveSpecular", 0f);
                shadowMat.SetFloat("_SrcBlend", 5f); shadowMat.SetFloat("_DstBlend", 10f);          // SrcAlpha, OneMinusSrcAlpha
                shadowMat.SetFloat("_SrcBlendAlpha", 1f); shadowMat.SetFloat("_DstBlendAlpha", 10f); // One, OneMinusSrcAlpha
                shadowMat.SetFloat("_ZWrite", 0f);
                shadowMat.DisableKeyword("_ALPHAPREMULTIPLY_ON"); shadowMat.DisableKeyword("_ALPHAMODULATE_ON"); shadowMat.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                SetMainTex(shadowMat, SoftBox, Vector2.one);
                shadowMat.SetFloat("_Smoothness", 0f);
                shadowMat.SetFloat("_Metallic", 0f);
                shadowMat.SetFloat("_SpecularHighlights", 0f); shadowMat.EnableKeyword("_SPECULARHIGHLIGHTS_OFF");
                shadowMat.SetFloat("_EnvironmentReflections", 0f); shadowMat.EnableKeyword("_ENVIRONMENTREFLECTIONS_OFF");
                shadowMat.SetFloat("_Cull", 0f);   // two-sided: the quad is visible whichever way it ends up facing
                shadowMat.renderQueue = 2950;   // after opaque ground and road paint, before car glass and glows
                return shadowMat;
            }
        }

        /// <summary>A flat dark shadow quad lying on the ground under something (local y = height above the parent origin).</summary>
        public static GameObject ContactShadow(Transform parent, float width, float length, float localY)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            Object.Destroy(go.GetComponent<Collider>());
            go.name = "ContactShadow";
            go.transform.SetParent(parent, false);
            go.transform.localPosition = new Vector3(0, localY, 0);
            go.transform.localRotation = Quaternion.Euler(90, 0, 0);
            go.transform.localScale = new Vector3(width, length, 1);
            var r = go.GetComponent<Renderer>();
            r.sharedMaterial = ShadowMat;
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            return go;
        }

        static Sprite whiteSprite;
        public static Sprite White
        {
            get
            {
                if (whiteSprite != null) return whiteSprite;
                var t = Texture2D.whiteTexture;
                whiteSprite = Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f));
                return whiteSprite;
            }
        }

        public static Sprite ToSprite(Texture2D t) =>
            t == null ? null : Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f), 100);
    }
}
