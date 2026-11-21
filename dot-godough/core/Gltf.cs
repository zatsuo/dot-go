// penInk が読むキャラのフォルダを書き出す: <名前>.gltf + <名前>.bin + <名前>.cel.json
// (penInk の tools/lgd2godot.py が書くものと同じ形。骨の名前も Low-Godough と同じなので、penInk Animator でそのまま開ける)
using System.Numerics;
using System.Text;
using System.Text.Json;

namespace DotGodough.Core;

public static class Gltf
{
    static float ToLinear(float c) => c <= 0.04045f ? c / 12.92f : MathF.Pow((c + 0.055f) / 1.055f, 2.4f);

    /// parts: 素材の番号ごとの (キー, 色 sRGB 0〜1)。素材 0 は "skin"
    public static void Write(MeshData m, string dir, string name, (string key, Vector3 rgb)[] parts, float[][][] bandColours)
    {
        Directory.CreateDirectory(dir);
        var blob = new MemoryStream();
        var views = new List<object>();
        var accessors = new List<object>();
        var meshes = new List<object>();
        var nodes = new List<Dictionary<string, object>>();
        var mats = new List<object>();

        int View(byte[] data, int? target)
        {
            while (blob.Length % 4 != 0) blob.WriteByte(0);
            var v = new Dictionary<string, object> { ["buffer"] = 0, ["byteOffset"] = (int)blob.Length, ["byteLength"] = data.Length };
            if (target.HasValue) v["target"] = target.Value;
            blob.Write(data);
            views.Add(v);
            return views.Count - 1;
        }

        int Acc(byte[] data, int count, string kind, int comp, int? target, float[] min = null, float[] max = null)
        {
            var a = new Dictionary<string, object> { ["bufferView"] = View(data, target), ["componentType"] = comp, ["count"] = count, ["type"] = kind };
            if (min != null) { a["min"] = min; a["max"] = max; }
            accessors.Add(a);
            return accessors.Count - 1;
        }

        static byte[] F(IEnumerable<float> xs) { var a = xs.ToArray(); var b = new byte[a.Length * 4]; Buffer.BlockCopy(a, 0, b, 0, b.Length); return b; }

        int headBone = Rig.Index["head"], neckBone = Rig.Index["neck"];
        for (int pi = 0; pi < parts.Length; pi++)
        {
            // この素材の三角形と、その頂点
            var remap = new Dictionary<int, int>();
            var src = new List<int>();
            var idx = new List<uint>();
            for (int t = 0; t < m.Tri.Length; t += 3)
            {
                int a = m.Tri[t], b = m.Tri[t + 1], c = m.Tri[t + 2];
                int mat = m.VMat[a];
                if (m.VMat[b] == m.VMat[c]) mat = m.VMat[b];
                if (Math.Min(mat, parts.Length - 1) != pi) continue;
                foreach (int v in new[] { a, b, c })
                {
                    if (!remap.TryGetValue(v, out int nv)) { nv = src.Count; remap[v] = nv; src.Add(v); }
                    idx.Add((uint)nv);
                }
            }
            if (src.Count == 0) continue;
            var lo = new Vector3(1e9f); var hi = new Vector3(-1e9f);
            foreach (int v in src) { lo = Vector3.Min(lo, m.V[v]); hi = Vector3.Max(hi, m.V[v]); }
            var attrs = new Dictionary<string, object>
            {
                ["POSITION"] = Acc(F(src.SelectMany(v => new[] { m.V[v].X, m.V[v].Y, m.V[v].Z })), src.Count, "VEC3", 5126, 34962,
                                   new[] { lo.X, lo.Y, lo.Z }, new[] { hi.X, hi.Y, hi.Z }),
                ["NORMAL"] = Acc(F(src.SelectMany(v => new[] { m.N[v].X, m.N[v].Y, m.N[v].Z })), src.Count, "VEC3", 5126, 34962),
            };
            if (pi == 0)
            {
                // 頭にどれだけ乗っているか (penInk はこれで肌を「顔」と「体」に切り分けて、あごの線を引く)
                attrs["COLOR_0"] = Acc(F(src.SelectMany(v =>
                {
                    float h = 0;
                    for (int a = 0; a < 4; a++) if (m.VB[v * 4 + a] == headBone) h += m.VW[v * 4 + a];
                    return new[] { h, h, h, 1f };
                })), src.Count, "VEC4", 5126, 34962);
            }
            var jb = new byte[src.Count * 8];
            for (int i = 0; i < src.Count; i++)
                for (int a = 0; a < 4; a++)
                    BitConverter.TryWriteBytes(new Span<byte>(jb, (i * 4 + a) * 2, 2), (ushort)m.VB[src[i] * 4 + a]);
            attrs["JOINTS_0"] = Acc(jb, src.Count, "VEC4", 5123, 34962);
            attrs["WEIGHTS_0"] = Acc(F(src.SelectMany(v => Enumerable.Range(0, 4).Select(a => m.VW[v * 4 + a]))), src.Count, "VEC4", 5126, 34962);
            var ib = new byte[idx.Count * 4];
            Buffer.BlockCopy(idx.ToArray(), 0, ib, 0, ib.Length);
            int ia = Acc(ib, idx.Count, "SCALAR", 5125, 34963);
            var rgb = parts[pi].rgb;
            mats.Add(new Dictionary<string, object>
            {
                ["name"] = parts[pi].key, ["doubleSided"] = true,
                ["pbrMetallicRoughness"] = new Dictionary<string, object>
                {
                    ["baseColorFactor"] = new[] { ToLinear(rgb.X), ToLinear(rgb.Y), ToLinear(rgb.Z), 1f },
                    ["metallicFactor"] = 0f, ["roughnessFactor"] = 1f,
                },
            });
            meshes.Add(new Dictionary<string, object>
            {
                ["name"] = parts[pi].key,
                ["primitives"] = new[] { new Dictionary<string, object> { ["attributes"] = attrs, ["indices"] = ia, ["material"] = mats.Count - 1 } },
            });
            nodes.Add(new Dictionary<string, object> { ["name"] = parts[pi].key, ["mesh"] = meshes.Count - 1, ["skin"] = 0 });
        }

        var roots = Enumerable.Range(0, nodes.Count).ToList();
        int first = nodes.Count;
        var bones = m.Bones;
        for (int i = 0; i < bones.Length; i++)
        {
            var o = bones[i].Origin - (bones[i].Parent >= 0 ? bones[bones[i].Parent].Origin : Vector3.Zero);
            nodes.Add(new Dictionary<string, object> { ["name"] = bones[i].Name, ["translation"] = new[] { o.X, o.Y, o.Z } });
        }
        for (int i = 0; i < bones.Length; i++)
        {
            if (bones[i].Parent < 0) { roots.Add(first + i); continue; }
            var pn = nodes[first + bones[i].Parent];
            if (!pn.ContainsKey("children")) pn["children"] = new List<int>();
            ((List<int>)pn["children"]).Add(first + i);
        }
        // 骨は動かすだけ (回転なし) なので、逆行列は位置を戻すだけ。glTF の行列は列が先
        var ibm = new float[bones.Length * 16];
        for (int i = 0; i < bones.Length; i++)
        {
            ibm[i * 16] = ibm[i * 16 + 5] = ibm[i * 16 + 10] = ibm[i * 16 + 15] = 1f;
            ibm[i * 16 + 12] = -bones[i].Origin.X; ibm[i * 16 + 13] = -bones[i].Origin.Y; ibm[i * 16 + 14] = -bones[i].Origin.Z;
        }
        var skin = new Dictionary<string, object>
        {
            ["name"] = "body", ["joints"] = Enumerable.Range(first, bones.Length).ToArray(), ["skeleton"] = first + Rig.Index["hips"],
            ["inverseBindMatrices"] = Acc(F(ibm), bones.Length, "MAT4", 5126, null),
        };
        File.WriteAllBytes(Path.Combine(dir, name + ".bin"), blob.ToArray());
        var gltf = new Dictionary<string, object>
        {
            ["asset"] = new Dictionary<string, object> { ["version"] = "2.0", ["generator"] = "dot-Godough" },
            ["scene"] = 0,
            ["scenes"] = new[] { new Dictionary<string, object> { ["name"] = name, ["nodes"] = roots } },
            ["nodes"] = nodes, ["meshes"] = meshes, ["materials"] = mats, ["accessors"] = accessors, ["bufferViews"] = views,
            ["buffers"] = new[] { new Dictionary<string, object> { ["uri"] = name + ".bin", ["byteLength"] = (int)blob.Length } },
            ["skins"] = new[] { skin },
        };
        var opt = new JsonSerializerOptions { WriteIndented = true };
        File.WriteAllText(Path.Combine(dir, name + ".gltf"), JsonSerializer.Serialize(gltf, opt), new UTF8Encoding(false));

        // 色の表
        string Hex(Vector3 c) => $"#{(int)MathF.Round(c.X * 255):X2}{(int)MathF.Round(c.Y * 255):X2}{(int)MathF.Round(c.Z * 255):X2}";
        var celParts = new Dictionary<string, object>();
        int id = 1;
        for (int pi = 0; pi < parts.Length; pi++)
        {
            float lum = parts[pi].rgb.X * 0.30f + parts[pi].rgb.Y * 0.59f + parts[pi].rgb.Z * 0.11f;
            var e = new Dictionary<string, object>
            {
                ["role"] = "cel",
                ["material"] = pi == 0 ? "face" : lum > 0.8f ? "sign" : lum < 0.2f ? "ink_mark" : "concrete",
                ["id"] = id++, ["value"] = pi == 0 ? 0.95f : 0.8f, ["resist"] = pi == 0 ? 0.85f : 0f,
                ["colours"] = bandColours[pi],
            };
            if (pi == 0) e["head_id"] = id++;
            celParts[parts[pi].key] = e;
        }
        var cel = new Dictionary<string, object>
        {
            ["name"] = name, ["source"] = "dot-Godough",
            ["slots"] = new Dictionary<string, object> { ["warm"] = Hex(parts[0].rgb), ["organic"] = "#4A332A", ["paper"] = "#F6F6F8" },
            ["ink"] = new[] { 0.07843f, 0.08627f, 0.12157f }, ["paper"] = new[] { 0.96471f, 0.96471f, 0.97255f },
            ["bands"] = new[] { 0.8f, 0.56f, 0.34f }, ["tone_lift"] = 0.03f,
            ["light"] = new Dictionary<string, object>
            {
                ["key"] = 0.78f, ["fill"] = 0.34f, ["ambient"] = 0.28f, ["sky"] = 0.12f,
                ["key_dir"] = new[] { -0.42569f, -0.85138f, -0.3065f }, ["fill_dir"] = new[] { 0.26649f, 0.15228f, -0.95173f },
            },
            ["parts"] = celParts, ["paint"] = "raw",
        };
        File.WriteAllText(Path.Combine(dir, name + ".cel.json"), JsonSerializer.Serialize(cel, opt), new UTF8Encoding(false));
    }
}
