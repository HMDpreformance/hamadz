using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEngine;

namespace HMD.EditorTools
{
    /// <summary>
    /// Phone builds: glTFast decodes images embedded in a .glb into uncompressed textures inside the model asset, where
    /// no platform compression can reach them (a 4096 px building texture is 64 MB; the Android build came to 5.7 GB).
    /// Setup therefore writes each imported model's images next to it as normal image files (name_gltex0.jpg ...) and
    /// points the .glb at them (image "uri" instead of "bufferView"); glTFast then uses those files as ordinary texture
    /// assets. The texture importer keeps them uncompressed at full size by default (the PC game is unchanged) and adds an
    /// Android override: ASTC 6x6 for colour, ASTC 4x4 for normal / data maps, same resolution.
    /// </summary>
    public static class GlbTextures
    {
        public const string Tag = "_gltex";

        /// <summary>Copies src to dst (an Assets path on disk) with its images moved out; skips when already done for
        /// this exact source (a size stamp in Library/), so Setup does not reimport every model every time.</summary>
        public static void CopyExternalized(string src, string dst)
        {
            string stampDir = Path.Combine(Application.dataPath, "..", "Library", "HMDGlbStamp");
            Directory.CreateDirectory(stampDir);
            string stamp = Path.Combine(stampDir, Path.GetFileName(Path.GetDirectoryName(dst)) + "__" + Path.GetFileName(dst) + ".txt");
            string sig = new FileInfo(src).Length + " " + File.GetLastWriteTimeUtc(src).Ticks;
            if (File.Exists(dst) && File.Exists(stamp) && File.ReadAllText(stamp) == sig) return;
            var bytes = File.ReadAllBytes(src);
            var outBytes = Externalize(bytes, dst, out int images);
            File.WriteAllBytes(dst, outBytes);
            File.WriteAllText(stamp, sig);
            if (images > 0) Debug.Log($"[HMD] glb textures: {Path.GetFileName(dst)}: {images} images moved to files (Android ASTC)");
        }

        /// <summary>Returns the .glb with every bufferView image turned into an external file beside dst. The binary
        /// chunk is kept as it is (the image bytes in it are simply no longer referenced).</summary>
        static byte[] Externalize(byte[] glb, string dst, out int moved)
        {
            moved = 0;
            if (glb.Length < 20 || System.BitConverter.ToUInt32(glb, 0) != 0x46546C67) return glb;   // "glTF"
            int jsonLen = (int)System.BitConverter.ToUInt32(glb, 12);
            if (System.BitConverter.ToUInt32(glb, 16) != 0x4E4F534A) return glb;                     // "JSON"
            string json = Encoding.UTF8.GetString(glb, 20, jsonLen);
            int binStart = 20 + jsonLen;
            byte[] bin = null;
            if (binStart + 8 <= glb.Length && System.BitConverter.ToUInt32(glb, binStart + 4) == 0x004E4942)   // "BIN\0"
            {
                int binLen = (int)System.BitConverter.ToUInt32(glb, binStart);
                bin = new byte[binLen]; System.Array.Copy(glb, binStart + 8, bin, 0, binLen);
            }
            if (bin == null) return glb;

            var views = new List<(int off, int len)>();
            var vm = Regex.Match(json, @"""bufferViews""\s*:\s*\[(.*?)\]\s*[,}]", RegexOptions.Singleline);
            if (vm.Success)
                foreach (Match o in Regex.Matches(vm.Groups[1].Value, @"\{[^{}]*\}"))
                {
                    int off = 0, len = 0;
                    var mo = Regex.Match(o.Value, @"""byteOffset""\s*:\s*(\d+)"); if (mo.Success) off = int.Parse(mo.Groups[1].Value);
                    var ml = Regex.Match(o.Value, @"""byteLength""\s*:\s*(\d+)"); if (ml.Success) len = int.Parse(ml.Groups[1].Value);
                    views.Add((off, len));
                }
            // which images are normal or data maps (linear), from the materials
            var texSource = new List<int>();
            var tm = Regex.Match(json, @"""textures""\s*:\s*\[(.*?)\]\s*[,}]", RegexOptions.Singleline);
            if (tm.Success)
                foreach (Match o in Regex.Matches(tm.Groups[1].Value, @"\{[^{}]*\}"))
                {
                    var s = Regex.Match(o.Value, @"""source""\s*:\s*(\d+)"); texSource.Add(s.Success ? int.Parse(s.Groups[1].Value) : -1);
                }
            var linear = new HashSet<int>(); var normal = new HashSet<int>();
            foreach (Match m in Regex.Matches(json, @"""(normalTexture|metallicRoughnessTexture|occlusionTexture)""\s*:\s*\{[^{}]*""index""\s*:\s*(\d+)"))
            {
                int t = int.Parse(m.Groups[2].Value); if (t < 0 || t >= texSource.Count || texSource[t] < 0) continue;
                linear.Add(texSource[t]); if (m.Groups[1].Value == "normalTexture") normal.Add(texSource[t]);
            }

            var im = Regex.Match(json, @"""images""\s*:\s*\[(.*?)\]\s*[,}]", RegexOptions.Singleline);
            if (!im.Success) return glb;
            string baseName = Path.GetFileNameWithoutExtension(dst), dir = Path.GetDirectoryName(dst);
            int idx = 0; int movedLocal = 0;
            string newImages = Regex.Replace(im.Groups[1].Value, @"\{[^{}]*\}", o =>
            {
                int i = idx++;
                var bv = Regex.Match(o.Value, @"""bufferView""\s*:\s*(\d+)");
                if (!bv.Success) return o.Value;
                int v = int.Parse(bv.Groups[1].Value); if (v < 0 || v >= views.Count) return o.Value;
                var mime = Regex.Match(o.Value, @"""mimeType""\s*:\s*""([^""]+)""");
                string ext = mime.Success && mime.Groups[1].Value.Contains("png") ? ".png" : ".jpg";
                string kind = normal.Contains(i) ? "N" : linear.Contains(i) ? "L" : "C";
                string file = $"{baseName}{Tag}{kind}{i}{ext}";
                var data = new byte[views[v].len]; System.Array.Copy(bin, views[v].off, data, 0, views[v].len);
                File.WriteAllBytes(Path.Combine(dir, file), data);
                movedLocal++;
                var nm = Regex.Match(o.Value, @"""name""\s*:\s*""([^""]*)""");
                return "{\"uri\":\"" + file + "\"" + (nm.Success ? ",\"name\":\"" + nm.Groups[1].Value + "\"" : "") + "}";
            });
            moved = movedLocal;
            if (moved == 0) return glb;
            string newJson = json.Substring(0, im.Groups[1].Index) + newImages + json.Substring(im.Groups[1].Index + im.Groups[1].Length);
            var jb = Encoding.UTF8.GetBytes(newJson);
            int pad = (4 - jb.Length % 4) % 4;
            var jsonChunk = new byte[jb.Length + pad]; System.Array.Copy(jb, jsonChunk, jb.Length); for (int k = 0; k < pad; k++) jsonChunk[jb.Length + k] = 0x20;
            int total = 12 + 8 + jsonChunk.Length + 8 + bin.Length;
            var o2 = new byte[total];
            void U32(int at, uint val) { var b = System.BitConverter.GetBytes(val); System.Array.Copy(b, 0, o2, at, 4); }
            U32(0, 0x46546C67); U32(4, 2); U32(8, (uint)total);
            U32(12, (uint)jsonChunk.Length); U32(16, 0x4E4F534A); System.Array.Copy(jsonChunk, 0, o2, 20, jsonChunk.Length);
            int b0 = 20 + jsonChunk.Length; U32(b0, (uint)bin.Length); U32(b0 + 4, 0x004E4942); System.Array.Copy(bin, 0, o2, b0 + 8, bin.Length);
            return o2;
        }
    }

    /// <summary>Import settings for the moved-out model images: PC unchanged (uncompressed, full size), Android ASTC at
    /// the same resolution (6x6 colour, 4x4 normal and data maps), mipmaps on, linear for data maps.</summary>
    public class GlbTexturePostprocessor : AssetPostprocessor
    {
        void OnPreprocessTexture()
        {
            string file = Path.GetFileNameWithoutExtension(assetPath);
            int t = file.LastIndexOf(GlbTextures.Tag, System.StringComparison.Ordinal);
            if (t < 0) return;
            char kind = file.Length > t + GlbTextures.Tag.Length ? file[t + GlbTextures.Tag.Length] : 'C';
            var ti = (TextureImporter)assetImporter;
            ti.textureType = TextureImporterType.Default;
            ti.textureShape = TextureImporterShape.Texture2D;
            ti.sRGBTexture = kind == 'C';
            ti.mipmapEnabled = true;
            ti.alphaSource = TextureImporterAlphaSource.FromInput;
            ti.maxTextureSize = 8192;
            ti.textureCompression = TextureImporterCompression.Uncompressed;   // PC: as before
            var a = ti.GetPlatformTextureSettings("Android");
            a.overridden = true;
            a.maxTextureSize = 8192;                                           // keep the resolution
            a.format = kind == 'C' ? TextureImporterFormat.ASTC_6x6 : TextureImporterFormat.ASTC_4x4;
            a.compressionQuality = 100;
            ti.SetPlatformTextureSettings(a);
        }
    }
}
