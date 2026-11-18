using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
#if HMD_URP
using UnityEngine.Rendering.Universal;
#endif

namespace HMD
{
    /// <summary>
    /// Mirror of the city on the road: a second camera, mirrored in the ground plane (y = 0) with an
    /// oblique near plane, renders the scene into a half-resolution texture just before the main camera.
    /// The WetRoad shader samples it in screen space, so neon, lamps, tower windows and tail lights
    /// show up on the wet asphalt. Phones get a cheap version: a fifth of the resolution, only the nearest 250 m, redrawn every second frame, no mips. Off with -noplanar.
    /// </summary>
    public class PlanarReflection : MonoBehaviour
    {
        public static PlanarReflection I;
        public float planeY = 0.0f;
        Camera main, refl;
        RenderTexture rt;
        float scale;
        static readonly int TexId = Shader.PropertyToID("_HMD_PlanarTex");
        static readonly int OnId = Shader.PropertyToID("_HMD_PlanarOn");

        // phones too, in the cheap form (Hamad wants the wet streets to reflect); b6 drew the full mirror every frame and was slow
        public static bool Wanted => !System.Environment.CommandLine.Contains("-noplanar");

        public void Setup(Camera mainCam)
        {
            I = this;
            main = mainCam;
            scale = GfxSetup.IsMobile ? 0.2f : 0.5f;
            var go = new GameObject("ReflectionCam");
            go.transform.SetParent(transform, false);
            refl = go.AddComponent<Camera>();
            refl.enabled = true;
            refl.depth = main.depth - 10;     // renders before the main camera
            refl.clearFlags = main.clearFlags;
            refl.backgroundColor = main.backgroundColor;
            refl.allowHDR = true;
            refl.allowMSAA = false;
            refl.cullingMask = main.cullingMask & ~(1 << LayerMask.NameToLayer("UI"));
            refl.farClipPlane = GfxSetup.IsMobile ? 250f : 420f;
            refl.useOcclusionCulling = false;
#if HMD_URP
            var d = refl.GetUniversalAdditionalCameraData();
            d.renderPostProcessing = false;
            d.renderShadows = false;
            d.requiresDepthTexture = false;
            d.requiresColorTexture = false;
            d.antialiasing = AntialiasingMode.None;
            d.SetRenderer(GfxSetup.RendererNoSsao);   // the default renderer, without SSAO (only the main view has AO)
#endif
            MakeRT();
            RenderPipelineManager.beginCameraRendering += OnBegin;
            RenderPipelineManager.endCameraRendering += OnEnd;
            Shader.SetGlobalFloat(OnId, 1f);
        }

        void MakeRT()
        {
            int w = Mathf.Max(64, (int)(Screen.width * scale)), h = Mathf.Max(64, (int)(Screen.height * scale));
            if (rt != null && rt.width == w && rt.height == h) return;
            if (rt != null) { refl.targetTexture = null; rt.Release(); Destroy(rt); }
            // phones: B10G11R11 (32 bits, no sign bit, so no negative values reach the road) where it can be rendered to,
            // instead of 64-bit half floats: half the memory traffic on a tile-based GPU. PCs keep DefaultHDR.
            bool small = GfxSetup.IsMobile && SystemInfo.IsFormatSupported(GraphicsFormat.B10G11R11_UFloatPack32, GraphicsFormatUsage.Render);
            var desc = new RenderTextureDescriptor(w, h, small ? RenderTextureFormat.RGB111110Float : RenderTextureFormat.DefaultHDR, 24)
            { useMipMap = !GfxSetup.IsMobile, autoGenerateMips = !GfxSetup.IsMobile, msaaSamples = 1 };
            rt = new RenderTexture(desc) { name = "PlanarReflection", filterMode = GfxSetup.IsMobile ? FilterMode.Bilinear : FilterMode.Trilinear, wrapMode = TextureWrapMode.Clamp };
            rt.Create();
            // a new render texture holds whatever was in that memory before; on phones the mirror camera only draws every
            // second frame, so the road could sample it once before it was ever drawn: clear it to black once here
            var prev = RenderTexture.active;
            RenderTexture.active = rt;
            GL.Clear(true, true, Color.black);
            RenderTexture.active = prev;
            refl.targetTexture = rt;
            Shader.SetGlobalTexture(TexId, rt);
            Debug.Log($"[HMD] planar mirror RT {w}x{h} {rt.graphicsFormat}");
        }

        bool active = true;
        int frame;
        // phones: the mirror is redrawn every second frame; the texture keeps the last one in between
        void Update()
        {
            if (refl == null || !GfxSetup.IsMobile) return;
            refl.enabled = active && !PanelOff && (++frame & 1) == 0;
        }

        /// <summary>Perf panel: mirror off (the road keeps its wet sheen and the paint probe reflection).</summary>
        public static bool PanelOff;
        public void SetPanelOff(bool off)
        {
            PanelOff = off;
            bool on = active && !off;
            if (refl) refl.enabled = on;
            Shader.SetGlobalFloat(OnId, on ? 1f : 0f);
        }

        void OnApplicationQuit() => Shutdown();
        void OnDestroy() => Shutdown();

        void Shutdown()
        {
            RenderPipelineManager.beginCameraRendering -= OnBegin;
            RenderPipelineManager.endCameraRendering -= OnEnd;
            GL.invertCulling = false;
            Shader.SetGlobalFloat(OnId, 0f);
            if (refl) { refl.enabled = false; refl.targetTexture = null; }
            if (rt != null) { rt.Release(); rt = null; }
        }

        public bool IsCamera(Camera c) => c == refl;

        public void SetActive(bool on)
        {
            active = on;   // (phones: Update re-enabled the camera every other frame, so the mirror kept rendering in the workshop)
            on &= !PanelOff;
            if (refl) refl.enabled = on;
            Shader.SetGlobalFloat(OnId, on ? 1f : 0f);
        }

        void OnBegin(ScriptableRenderContext ctx, Camera cam)
        {
            if (cam != refl || main == null) return;
            MakeRT();
            // mirror the main camera in the plane y = planeY
            Vector3 n = Vector3.up;
            float dPlane = -planeY;
            Matrix4x4 R = Matrix4x4.identity;
            R.m00 = 1 - 2 * n.x * n.x; R.m01 = -2 * n.x * n.y; R.m02 = -2 * n.x * n.z; R.m03 = -2 * dPlane * n.x;
            R.m10 = -2 * n.y * n.x; R.m11 = 1 - 2 * n.y * n.y; R.m12 = -2 * n.y * n.z; R.m13 = -2 * dPlane * n.y;
            R.m20 = -2 * n.z * n.x; R.m21 = -2 * n.z * n.y; R.m22 = 1 - 2 * n.z * n.z; R.m23 = -2 * dPlane * n.z;
            Vector3 p = main.transform.position;
            Vector3 mp = new Vector3(p.x, 2 * planeY - p.y, p.z);
            refl.transform.position = mp;
            Vector3 f = main.transform.forward; f.y = -f.y;
            Vector3 u = main.transform.up; u.y = -u.y;
            refl.transform.rotation = Quaternion.LookRotation(f, u);
            refl.fieldOfView = main.fieldOfView;
            refl.aspect = main.aspect;
            refl.nearClipPlane = main.nearClipPlane;
            refl.worldToCameraMatrix = main.worldToCameraMatrix * R;
            // oblique near plane = the ground, so nothing below the road leaks into the mirror
            Vector4 clip = CameraSpacePlane(refl.worldToCameraMatrix, new Vector3(0, planeY + 0.02f, 0), n);
            refl.projectionMatrix = main.CalculateObliqueMatrix(clip);
            GL.invertCulling = true;
        }

        void OnEnd(ScriptableRenderContext ctx, Camera cam)
        {
            if (cam == refl) GL.invertCulling = false;
        }

        static Vector4 CameraSpacePlane(Matrix4x4 w2c, Vector3 pos, Vector3 normal)
        {
            Vector3 cpos = w2c.MultiplyPoint(pos);
            Vector3 cnormal = w2c.MultiplyVector(normal).normalized;
            return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
        }
    }
}
