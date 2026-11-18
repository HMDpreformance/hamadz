using UnityEditor;
using UnityEngine;

namespace HMD.EditorTools
{
    /// <summary>
    /// Music (radio tracks and the loading loop) streams from storage instead of being unpacked into memory: twenty
    /// 2-minute tracks unpacked would take several hundred MB on a phone. Compressed Vorbis, quality 0.6.
    /// </summary>
    public class MusicImport : AssetPostprocessor
    {
        void OnPreprocessAudio()
        {
            string p = assetPath.Replace('\\', '/');
            if (!p.Contains("/Imported/Audio/music/") && !p.Contains("/Imported/Music/")) return;
            var imp = (AudioImporter)assetImporter;
            var s = imp.defaultSampleSettings;
            s.loadType = AudioClipLoadType.Streaming;
            s.compressionFormat = AudioCompressionFormat.Vorbis;
            s.quality = 0.6f;
            imp.defaultSampleSettings = s;
            imp.loadInBackground = true;
        }
    }
}
