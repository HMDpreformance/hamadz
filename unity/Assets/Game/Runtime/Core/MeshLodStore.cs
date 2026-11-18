using UnityEngine;

namespace HMD
{
    /// <summary>
    /// Meshes with Unity 6 Mesh LODs baked in by the Editor (HMD > Bake Mesh LODs, also part of HMD > Setup Project):
    /// Resources/Imported/MeshLod/*.asset. A MeshRenderer picks the level of detail on its own from the size on screen
    /// (screen-space error, so the switch is not visible): full detail close up, fewer triangles when far, same textures,
    /// materials and glow. The building, palm and landmark models and the car bodies load these when present and fall
    /// back to the plain GLB meshes when a baked copy is missing or out of date (the file name ends in _i + source index count).
    /// </summary>
    public static class MeshLodStore
    {
        public const string Dir = "MeshLod/";
        public static int Hits, Misses;

        public static string Safe(string s)
        {
            var c = s.ToCharArray();
            for (int i = 0; i < c.Length; i++) if (!char.IsLetterOrDigit(c[i]) && c[i] != '_' && c[i] != '-') c[i] = '_';
            return new string(c);
        }

        /// <summary>Key of a merged model (building, palm, landmark): folder, id and the extra turn it was baked with.</summary>
        public static string ModelKey(string folder, string id, float yaw) => Safe(folder + "_" + id + "_y" + Mathf.RoundToInt(yaw));

        /// <summary>Key of one mesh of a prefab (car bodies, wheels).</summary>
        public static string MeshKey(string folder, Mesh m) => Safe(folder + "_" + m.name + "_v" + m.vertexCount);

        public static long IndexCount(Mesh m)
        {
            long n = 0;
            for (int s = 0; s < m.subMeshCount; s++) n += m.GetIndexCount(s);
            return n;
        }

        /// <summary>File name of a baked copy: the key plus the source's index count, so a changed model is never matched
        /// with an old bake.</summary>
        public static string FileName(string key, long srcIndices) => key + "_i" + srcIndices;

        /// <summary>The baked copy, if it exists and was made from a source with this many indices (lod 0).</summary>
        public static Mesh Load(string key, long srcIndices)
        {
            var m = Res.Load<Mesh>(Dir + FileName(key, srcIndices));
            if (m != null && m.lodCount > 1) { Hits++; return m; }
            Misses++;
            return null;
        }

        /// <summary>Swaps every mesh under 'root' for its baked copy (same vertices and sub-meshes, plus LODs).</summary>
        public static void SwapIn(GameObject root, string folder)
        {
            if (root == null) return;
            foreach (var mf in root.GetComponentsInChildren<MeshFilter>(true))
            {
                var src = mf.sharedMesh;
                if (src == null) continue;
                var m = Load(MeshKey(folder, src), IndexCount(src));
                if (m != null && m.vertexCount == src.vertexCount && m.subMeshCount == src.subMeshCount) mf.sharedMesh = m;
            }
        }
    }
}
