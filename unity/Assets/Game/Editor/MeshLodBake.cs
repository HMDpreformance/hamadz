using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace HMD.EditorTools
{
    /// <summary>
    /// Bakes Unity 6 Mesh LODs (MeshLodUtility, screen-space error) into copies of the heavy models, so far buildings,
    /// palms, landmarks and the car bodies cost a fraction of their triangles while close ones keep full detail. Same
    /// vertices, UVs, materials and textures: nothing changes in the look, the renderer just picks fewer triangles when
    /// the extra ones would be smaller than a pixel. Output: Assets/Resources/Imported/MeshLod/*.asset (read by
    /// MeshLodStore). Only redone when a source model changed. Runs in HMD > Setup Project, or HMD > Bake Mesh LODs.
    /// </summary>
    public static class MeshLodBake
    {
        const string Imp = "Assets/Resources/Imported";
        const string Out = Imp + "/MeshLod";
        const int MaxLods = 6;

        [System.Serializable] class J { public string id, kind; public float yaw; }
        [System.Serializable] class JList { public J[] models; }

        [MenuItem("HMD/Bake Mesh LODs")]
        public static void BakeAll()
        {
            Directory.CreateDirectory(Out);
            int made = 0, kept = 0;
            long before = 0, after = 0;
            try
            {
                AssetDatabase.StartAssetEditing();
                foreach (var j in List(Imp + "/Buildings/buildings.json")) Model("Buildings", Imp + "/Buildings/" + j.id + ".glb", j.id, j.yaw, ref made, ref kept);
                foreach (var j in List(Imp + "/Trees/trees.json")) if (j.kind == "palm") Model("Trees", Imp + "/Trees/" + j.id + ".glb", j.id, 0f, ref made, ref kept);
                foreach (var j in List(Imp + "/Buildings/Landmarks/landmarks.json")) Model("Landmarks", Imp + "/Buildings/Landmarks/" + j.id + ".glb", j.id, j.yaw, ref made, ref kept);
                foreach (var guid in AssetDatabase.FindAssets("t:GameObject", new[] { Imp + "/Cars" }))
                {
                    var path = AssetDatabase.GUIDToAssetPath(guid);
                    if (!path.EndsWith(".glb") || path.EndsWith("_lod.glb")) continue;   // traffic _lod models are already light
                    var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                    if (prefab == null) continue;
                    var seen = new HashSet<Mesh>();
                    foreach (var mf in prefab.GetComponentsInChildren<MeshFilter>(true))
                    {
                        var src = mf.sharedMesh;
                        if (src == null || !seen.Add(src) || MeshLodStore.IndexCount(src) < 6000) continue;
                        var key = MeshLodStore.MeshKey("Cars", src);
                        long idx = MeshLodStore.IndexCount(src);
                        if (UpToDate(key, idx)) { kept++; continue; }
                        var m = Object.Instantiate(src);
                        Save(m, key, idx, ref before, ref after); made++;
                    }
                }
            }
            finally { AssetDatabase.StopAssetEditing(); }
            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            Debug.Log($"[HMD] Mesh LODs: {made} baked ({before / 3000}k -> lowest level {after / 3000}k tris), {kept} already up to date");
        }

        static IEnumerable<J> List(string jsonPath)
        {
            var ta = AssetDatabase.LoadAssetAtPath<TextAsset>(jsonPath);
            if (ta == null) yield break;
            JList l = null;
            try { l = JsonUtility.FromJson<JList>(ta.text); } catch { }
            if (l?.models == null) yield break;
            foreach (var j in l.models) if (!string.IsNullOrEmpty(j.id)) yield return j;
        }

        static void Model(string folder, string glbPath, string id, float yaw, ref int made, ref int kept)
        {
            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(glbPath);
            if (prefab == null) return;
            var mats = new List<Material>();
            var m = NewCityDressing.MergeModel(prefab, folder, id, yaw, mats, false);
            if (m == null) return;
            var key = MeshLodStore.ModelKey(folder, id, yaw);
            long idx = MeshLodStore.IndexCount(m);
            if (UpToDate(key, idx)) { kept++; Object.DestroyImmediate(m); return; }
            long b = 0, a = 0;
            Save(m, key, idx, ref b, ref a);
            made++;
        }

        static string PathOf(string key, long srcIndices) => Out + "/" + MeshLodStore.FileName(key, srcIndices) + ".asset";

        static bool UpToDate(string key, long srcIndices)
        {
            var old = AssetDatabase.LoadAssetAtPath<Mesh>(PathOf(key, srcIndices));
            return old != null && old.lodCount > 1;
        }

        static void Save(Mesh m, string key, long srcIndices, ref long before, ref long after)
        {
            // an older bake of the same model (other index count) is out of date
            foreach (var f in Directory.GetFiles(Out, key + "*.asset"))
            {
                var rel = f.Replace('\\', '/');
                var name = Path.GetFileNameWithoutExtension(rel);
                if (name.StartsWith(key + "_i") || name == key) AssetDatabase.DeleteAsset(rel);
            }
            MeshLodUtility.GenerateMeshLods(m, (MeshLodUtility.LodGenerationFlags)0, MaxLods);
            for (int s = 0; s < m.subMeshCount; s++)
            {
                before += m.GetLod(s, 0).indexCount;
                after += m.GetLod(s, m.lodCount - 1).indexCount;
            }
            m.RecalculateBounds();
            AssetDatabase.CreateAsset(m, PathOf(key, srcIndices));
        }
    }
}
