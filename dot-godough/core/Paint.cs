// 塗り: ドット絵の上を塗った色を、体の面に貼りつける。
//  - 塗った 1 画素 = 「点」1 つ (基本姿勢での体の上の場所 + 半径 + 色)。絵を描くとき、画素ごとに
//    「その画素に写っている体の場所 (GBuffer.Rest)」が、どの点の中にあるかを調べて色を決める。
//    だから 向きやポーズを変えても、塗った所についてくる
//  - 点の場所は「いちばん近い骨の枠の中の、骨の長さ・太さで割った位置」で持つ。体型を変えたら、
//    新しい骨から場所を出し直して、面の上に寄せる (頭身や服の厚みを変えても、塗りは残る)。
//    点の大きさも骨の長さ・太さで割って持つ (頭が大きくなれば、点もいっしょに大きくなる。そうしないと、すき間があく)
//  - あとから塗った点が勝つ。消しゴムも点 (その場所の塗りを無かったことにする)
using System.Numerics;

namespace DotGodough.Core;

public struct Dab
{
    public int Bone;            // いちばん近い骨
    public Vector3 Local;       // その骨の枠の中の位置 ÷ (太さ X, 長さ, 太さ Z)
    public Vector3 R;           // 半径 ÷ (太さ X, 長さ, 太さ Z)
    public uint Argb;
    public int Flags;           // Flat / Erase
    public Vector3 Pos;         // いまの体での、基本姿勢の位置 (Resolve で出す)
    public Vector3 Rad;         // いまの体での半径 (骨の枠の X, Y, Z の向き)
    public float RadMax;
}

public sealed class PaintLayer
{
    public const int Flat = 1;   // 光の段を使わず、塗った色そのまま (線よりも上)
    public const int Erase = 2;
    // 明るさのペン: 色を置かずに、その場所の色の段を上げ下げする (ハイライト・影)。Strong = 2 段。
    // 色の塗りとは別の層: 色の上に重ねても色は消えない。Tone のついた消しゴムは、明るさだけを消す
    public const int Light = 4, Dark = 8, Strong = 16, Tone = 32;

    public readonly List<Dab> Dabs = new();
    Dictionary<long, List<int>> _hash;
    Bone[] _bones;
    float _cell = 1f;

    static Vector3 Scale(Bone b) =>
        new(MathF.Max(b.GirthX, 1e-4f), MathF.Max(b.Length, 1e-4f), MathF.Max(b.GirthZ, 1e-4f));

    static long Key(int x, int y, int z) => ((long)(x & 0x1FFFFF) << 42) | ((long)(y & 0x1FFFFF) << 21) | (long)(z & 0x1FFFFF);

    /// 体を作り直したあと: 点の場所を新しい骨から出し直して、面の上に寄せる
    public void Resolve(Field f, Bone[] bones, float height, float cell)
    {
        if (f == null) return;
        _bones = bones;
        float lim = 0.03f * height;
        System.Threading.Tasks.Parallel.For(0, Dabs.Count, i =>
        {
            var d = Dabs[i];
            var b = bones[Math.Clamp(d.Bone, 0, bones.Length - 1)];
            var p = b.Origin + b.Basis.Mul(d.Local * Scale(b));
            for (int k = 0; k < 4; k++)
            {
                float dist = f.Eval(p);
                // もう面のそばにある点は動かさない (点の半径は 0.8 ますほど。髪の式は本当の距離ではないので、
                // わずかなずれを寄せ直すと かえって大きく動き、作り直すたびに髪の上の塗りがずれた)
                if (MathF.Abs(dist) < cell * (k == 0 ? 0.75f : 0.05f)) break;
                var g = f.Gradient(p, cell * 0.5f);
                float l = g.Length();
                if (l < 1e-4f) break;
                p -= g / l * Math.Clamp(dist, -lim, lim);
            }
            d.Pos = p;
            d.Rad = d.R * Scale(b);
            d.RadMax = MathF.Max(d.Rad.X, MathF.Max(d.Rad.Y, d.Rad.Z));
            lock (Dabs) Dabs[i] = d;
        });
        _hash = null;
    }

    /// 基本姿勢の位置 rest に点を 1 つ足す。r = 半径 (m)
    public void Add(Field f, Bone[] bones, float height, Vector3 rest, float r, uint argb, int flags)
    {
        Span<float> dist = stackalloc float[bones.Length];
        f.BoneDistance(rest, dist);
        int bi = 0;
        for (int i = 1; i < dist.Length; i++) if (dist[i] < dist[bi]) bi = i;
        var b = bones[bi];
        Dabs.Add(new Dab { Bone = bi, Local = b.Basis.TMul(rest - b.Origin) / Scale(b), R = new Vector3(r) / Scale(b), Argb = argb, Flags = flags,
                           Pos = rest, Rad = new Vector3(r), RadMax = r });
        _bones = bones;
        _hash = null;
    }

    float _min;

    void BuildHash(float min)
    {
        _hash = new Dictionary<long, List<int>>();
        _min = min;
        float mr = MathF.Max(min, 1e-4f);
        foreach (var d in Dabs) mr = MathF.Max(mr, d.RadMax);
        _cell = mr * 2f;
        for (int i = 0; i < Dabs.Count; i++)
        {
            var d = Dabs[i];
            int x0 = (int)MathF.Floor((d.Pos.X - MathF.Max(d.RadMax, min)) / _cell), x1 = (int)MathF.Floor((d.Pos.X + MathF.Max(d.RadMax, min)) / _cell);
            int y0 = (int)MathF.Floor((d.Pos.Y - MathF.Max(d.RadMax, min)) / _cell), y1 = (int)MathF.Floor((d.Pos.Y + MathF.Max(d.RadMax, min)) / _cell);
            int z0 = (int)MathF.Floor((d.Pos.Z - MathF.Max(d.RadMax, min)) / _cell), z1 = (int)MathF.Floor((d.Pos.Z + MathF.Max(d.RadMax, min)) / _cell);
            for (int x = x0; x <= x1; x++)
                for (int y = y0; y <= y1; y++)
                    for (int z = z0; z <= z1; z++)
                    {
                        long k = Key(x, y, z);
                        if (!_hash.TryGetValue(k, out var l)) _hash[k] = l = new List<int>();
                        l.Add(i);
                    }
        }
    }

    /// その場所 (基本姿勢) をおおっている点のうち、いちばん あとに塗ったものの番号。無ければ -1。
    /// min = 点の半径の下限 (m)。体の部分が小さくなって点が 1 画素より小さくなっても、絵から消えないように
    public int Find(Vector3 p, float min, bool tone = false)
    {
        if (Dabs.Count == 0) return -1;
        if (_hash == null || min != _min) BuildHash(min);
        long k = Key((int)MathF.Floor(p.X / _cell), (int)MathF.Floor(p.Y / _cell), (int)MathF.Floor(p.Z / _cell));
        if (!_hash.TryGetValue(k, out var l)) return -1;
        for (int n = l.Count - 1; n >= 0; n--)
        {
            var d = Dabs[l[n]];
            if (((d.Flags & Tone) != 0) != tone) continue;
            var q = _bones[d.Bone].Basis.TMul(p - d.Pos) / Vector3.Max(d.Rad, new Vector3(min));
            if (q.LengthSquared() <= 1f) return l[n];
        }
        return -1;
    }

    public void Clear() { Dabs.Clear(); _hash = null; }
    public void Touch() { _hash = null; }
}
