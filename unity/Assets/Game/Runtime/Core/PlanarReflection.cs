using UnityEngine;
using UnityEngine.Rendering;
#if HMD_URP
using UnityEngine.Rendering.Universal;
#endif

namespace HMD
{
    /// <summary>
    /// Mirror of the city on the road: a second camera, mirrored in the ground plane (y = 0) with an
    /// oblique near plane, renders the scene into a half-resolution texture just before the main camera.
    /// The WetRoad shader samples it in screen space, so neon, lamps, tower windows and tail lights
    /// show up on the wet asphalt. Quarter resolution on phones; off with -noplanar.
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

        public static bool Wanted => !System.Environment.CommandLine.Contains("-noplanar");

        public void Setup(Camera mainCam)
        {
            I = this;
            main = mainCam;
            scale = GfxSetup.IsMobile ? 0.25f : 0.5f;
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
            refl.farClipPlane = 420f;
            refl.useOcclusionCulling = false;
#if HMD_URP
            var d = refl.GetUniversalAdditionalCameraData();
            d.renderPostProcessing = false;
            d.renderShadows = false;
            d.requiresDepthTexture = false;
            d.requiresColorTexture = false;
            d.antialiasing = AntialiasingMode.None;
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
            rt = new RenderTexture(w, h, 24, RenderTextureFormat.DefaultHDR) { name = "PlanarReflection", useMipMap = true, autoGenerateMips = true, filterMode = FilterMode.Trilinear, wrapMode = TextureWrapMode.Clamp };
            rt.Create();
            refl.targetTexture = rt;
            Shader.SetGlobalTexture(TexId, rt);
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

        public void SetActive(bool on)
        {
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
