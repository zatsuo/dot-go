// SDF → 網目。格子のますごとに面の点を 1 つ置く (surface nets)。
// 継ぎ目を縫わなくても 1 枚の閉じた網目になるので、2 頭身でも 8 頭身でも同じ作り方で破れない。
// 網目は人が編集するものではなく、ドット絵に撮るためのもの: 法線は SDF の勾配から取るので、面の粗さは絵に出ない。
using System.Numerics;

namespace DotGodough.Core;

public sealed class MeshData
{
    public Vector3[] V = Array.Empty<Vector3>();     // 基本姿勢の頂点
    public Vector3[] N = Array.Empty<Vector3>();
    public int[] Tri = Array.Empty<int>();           // 反時計回りが表
    public int[] VB = Array.Empty<int>();            // 頂点ごとに骨 4 つ
    public float[] VW = Array.Empty<float>();        // その重み
    public byte[] VPart = Array.Empty<byte>();       // 部品の番号 (線を引く単位)
    public byte[] VMat = Array.Empty<byte>();        // 素材の番号 (色)
    public Bone[] Bones = Array.Empty<Bone>();
    public float Cell;
    public double Seconds;
}

public static class Mesher
{
    // 骨 → 部品。胴 0、頭 1、左の 上腕 2・前腕 3・手 4、右 5〜7、左の 太もも 8・すね 9・足 10、右 11〜13
    public static int PartOf(string bone)
    {
        int side = bone.EndsWith(".R") ? 1 : 0;
        string b = bone.Contains('.') ? bone[..bone.IndexOf('.')] : bone;
        return b switch
        {
            "head" => 1,
            "upper_arm" => 2 + side * 3, "forearm" => 3 + side * 3,
            "thigh" => 8 + side * 3, "shin" => 9 + side * 3, "foot" => 10 + side * 3,
            "hips" or "spine" or "chest" or "neck" or "shoulder" => 0,
            _ => 4 + side * 3,   // 手と指
        };
    }

    public static readonly string[] PartNames = {
        "胴", "頭", "左上腕", "左前腕", "左手", "右上腕", "右前腕", "右手", "左太もも", "左すね", "左足", "右太もも", "右すね", "右足", "すそ", "髪", "髪の房" };

    /// 重みを分け合ってよい骨 (親子。胸と上腕は肩の骨をはさんでとなり)
    static List<int>[] Neighbors(Bone[] bones)
    {
        var nb = new List<int>[bones.Length];
        for (int i = 0; i < bones.Length; i++) nb[i] = new List<int>();
        void Link(int a, int b) { if (!nb[a].Contains(b)) nb[a].Add(b); if (!nb[b].Contains(a)) nb[b].Add(a); }
        for (int i = 0; i < bones.Length; i++)
            if (bones[i].Parent >= 0) Link(i, bones[i].Parent);
        foreach (var side in new[] { ".L", ".R" })
            Link(Rig.Index["chest"], Rig.Index["upper_arm" + side]);
        Link(Rig.Index["chest"], Rig.Index["head"]);
        return nb;
    }

    public static MeshData Build(Field f, Bone[] bones, float cell, float G)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var (lo, hi) = f.Bounds();
        // 格子: x = 0 が格子の面になるように置く (形が左右対称なら、網目も左右対称になる)
        int half = (int)MathF.Ceiling(MathF.Max(MathF.Abs(lo.X), MathF.Abs(hi.X)) / cell) + 1;
        int NX = 2 * half + 1;
        int j0 = (int)MathF.Floor(lo.Y / cell) - 1, k0 = (int)MathF.Floor(lo.Z / cell) - 1;
        int NY = (int)MathF.Ceiling(hi.Y / cell) + 2 - j0, NZ = (int)MathF.Ceiling(hi.Z / cell) + 2 - k0;
        Vector3 P(int i, int j, int k) => new((i - half) * cell, (j0 + j) * cell, (k0 + k) * cell);
        var val = new float[NX * NY * NZ];
        int Id(int i, int j, int k) => i + NX * (j + NY * k);
        Parallel.For(0, NZ, k =>
        {
            for (int j = 0; j < NY; j++)
                for (int i = 0; i < NX; i++)
                    val[Id(i, j, k)] = f.Eval(P(i, j, k));
        });

        // ますごとの点
        int CX = NX - 1, CY = NY - 1, CZ = NZ - 1;
        var cellVert = new int[CX * CY * CZ];
        Array.Fill(cellVert, -1);
        int Cid(int i, int j, int k) => i + CX * (j + CY * k);
        var verts = new List<Vector3>();
        var cellOf = new List<(int i, int j, int k)>();
        Span<float> c = stackalloc float[8];
        for (int k = 0; k < CZ; k++)
            for (int j = 0; j < CY; j++)
                for (int i = 0; i < CX; i++)
                {
                    int neg = 0;
                    for (int n = 0; n < 8; n++)
                    {
                        c[n] = val[Id(i + (n & 1), j + ((n >> 1) & 1), k + ((n >> 2) & 1))];
                        if (c[n] < 0) neg++;
                    }
                    if (neg == 0 || neg == 8) continue;
                    var sum = Vector3.Zero; int cnt = 0;
                    for (int a = 0; a < 8; a++)
                        for (int ax = 0; ax < 3; ax++)
                        {
                            if ((a >> ax & 1) != 0) continue;
                            int b = a | (1 << ax);
                            if ((c[a] < 0) == (c[b] < 0)) continue;
                            float t = c[a] / (c[a] - c[b]);
                            var pa = new Vector3(a & 1, (a >> 1) & 1, (a >> 2) & 1);
                            var pb = new Vector3(b & 1, (b >> 1) & 1, (b >> 2) & 1);
                            sum += pa + (pb - pa) * t; cnt++;
                        }
                    cellVert[Cid(i, j, k)] = verts.Count;
                    verts.Add(P(i, j, k) + sum / cnt * cell);
                    cellOf.Add((i, j, k));
                }

        // 点を本当の面に寄せ、法線を勾配から取る
        int nv = verts.Count;
        var V = verts.ToArray();
        var Nn = new Vector3[nv];
        float h = cell * 0.2f;
        Parallel.For(0, nv, v =>
        {
            var p = V[v];
            var (ci, cj, ck) = cellOf[v];
            var cl = P(ci, cj, ck) - new Vector3(cell * 0.25f);
            var ch = P(ci + 1, cj + 1, ck + 1) + new Vector3(cell * 0.25f);
            for (int it = 0; it < 3; it++)
            {
                float d = f.Eval(p);
                var g = f.Gradient(p, h);
                float g2 = g.LengthSquared();
                if (g2 < 1e-8f) break;
                p = Vector3.Clamp(p - g * (d / g2), cl, ch);
            }
            V[v] = p;
            var n = f.Gradient(p, h);
            Nn[v] = n.LengthSquared() > 1e-12f ? Vector3.Normalize(n) : Vector3.UnitY;
        });

        // 面: 符号が変わる格子の辺ごとに、まわりの 4 ますの点をつなぐ
        var tri = new List<int>();
        void Quad(int a, int b, int c2, int d, bool flip)
        {
            if (a < 0 || b < 0 || c2 < 0 || d < 0) return;
            if (flip) { (b, d) = (d, b); }
            // 短いほうの対角線で割る
            if ((V[a] - V[c2]).LengthSquared() <= (V[b] - V[d]).LengthSquared())
            { tri.Add(a); tri.Add(b); tri.Add(c2); tri.Add(a); tri.Add(c2); tri.Add(d); }
            else
            { tri.Add(a); tri.Add(b); tri.Add(d); tri.Add(b); tri.Add(c2); tri.Add(d); }
        }
        for (int k = 1; k < CZ; k++)
            for (int j = 1; j < CY; j++)
                for (int i = 1; i < CX; i++)
                {
                    float v0 = val[Id(i, j, k)];
                    bool in0 = v0 < 0;
                    if (in0 != (val[Id(i + 1, j, k)] < 0))
                        Quad(cellVert[Cid(i, j - 1, k - 1)], cellVert[Cid(i, j, k - 1)], cellVert[Cid(i, j, k)], cellVert[Cid(i, j - 1, k)], !in0);
                    if (in0 != (val[Id(i, j + 1, k)] < 0))
                        Quad(cellVert[Cid(i - 1, j, k - 1)], cellVert[Cid(i, j, k - 1)], cellVert[Cid(i, j, k)], cellVert[Cid(i - 1, j, k)], in0);
                    if (in0 != (val[Id(i, j, k + 1)] < 0))
                        Quad(cellVert[Cid(i - 1, j - 1, k)], cellVert[Cid(i, j - 1, k)], cellVert[Cid(i, j, k)], cellVert[Cid(i - 1, j, k)], !in0);
                }

        // 重みと部品: 骨ごとの肉までの距離から。いちばん近い骨と、そのとなりの骨だけで分け合う
        var nb = Neighbors(bones);
        int nbn = bones.Length;
        var VB = new int[nv * 4];
        var VW = new float[nv * 4];
        var VPart = new byte[nv];
        var VMat = new byte[nv];
        float eps = cell * 0.4f;
        int bHips = Rig.Index["hips"], bThL = Rig.Index["thigh.L"], bThR = Rig.Index["thigh.R"];
        float hipX = MathF.Max(bones[bThL].Origin.X, 1e-4f);
        var partOf = bones.Select(b => (byte)PartOf(b.Name)).ToArray();
        var soft = bones.Select(b =>
        {
            string n = b.Name;
            float k = n is "hips" or "spine" or "chest" ? 0.03f : n.StartsWith("neck") || n.StartsWith("head") ? 0.012f
                : n.StartsWith("hand") || n.StartsWith("foot") ? 0.01f : 0.014f;
            return k * G;
        }).ToArray();
        Parallel.For(0, nv, v =>
        {
            f.Classify(V[v], eps, out int mat, out int skirt);
            VMat[v] = (byte)Math.Min(mat, 255);
            if (skirt == -2)
            {
                // 髪: 頭についていく。あごより下へ垂れた分は、下へ行くほど胸についていく (首を回しても、背中の髪は背中に残る)
                var hr = f.Hair;
                float t = Math.Clamp((hr.ChinY - V[v].Y) / (0.45f * hr.HeadH), 0f, 1f);
                t = t * t * (3f - 2f * t);
                // ペンで描いた房 (ツインテールなど) は、下へ垂れていても頭についていく
                bool lockV = hr.Locks.Count > 0 && hr.LockDistance(V[v], out _) < 0.01f * hr.HeadH;
                if (lockV) t = 0f;
                VPart[v] = (byte)(lockV && hr.Separate ? 16 : 15);
                VB[v * 4] = Rig.Index["head"]; VW[v * 4] = 1f - t;
                VB[v * 4 + 1] = Rig.Index["chest"]; VW[v * 4 + 1] = t;
                VB[v * 4 + 2] = 0; VW[v * 4 + 2] = 0f;
                VB[v * 4 + 3] = 0; VW[v * 4 + 3] = 0f;
                return;
            }
            if (skirt >= 0)
            {
                // すそ: 腰についていき、下へ行くほど、その側の太ももにもついていく (歩く・すわるで脚がすそから突き出ない)
                var gs = f.Garments[skirt];
                float u = Math.Clamp((gs.YTop - V[v].Y) / MathF.Max(gs.YTop - gs.YBot, 1e-4f), 0f, 1f);
                float fl = gs.Follow * u;
                float sl = Math.Clamp(0.5f + V[v].X / (hipX * 1.6f), 0f, 1f);
                VPart[v] = 14;
                VB[v * 4] = bHips; VW[v * 4] = 1f - fl;
                VB[v * 4 + 1] = bThL; VW[v * 4 + 1] = fl * sl;
                VB[v * 4 + 2] = bThR; VW[v * 4 + 2] = fl * (1f - sl);
                VB[v * 4 + 3] = 0; VW[v * 4 + 3] = 0f;
                return;
            }
            Span<float> dist = stackalloc float[nbn];
            f.BoneDistance(V[v], dist);
            int best = 0;
            for (int b = 1; b < nbn; b++) if (dist[b] < dist[best]) best = b;
            VPart[v] = partOf[best];
            Span<int> cand = stackalloc int[8];
            Span<float> w = stackalloc float[8];
            int nc = 0;
            cand[nc] = best; w[nc++] = 1f;
            foreach (int o in nb[best])
            {
                if (nc >= 8 || dist[o] > 1e8f) continue;
                float s = MathF.Max(soft[best], soft[o]);
                float x = MathF.Max(0f, dist[o] - dist[best]) / s;
                float wo = MathF.Exp(-x * x - x);
                if (wo < 0.02f) continue;
                cand[nc] = o; w[nc++] = wo;
            }
            // 重い順に 4 つ
            for (int a = 0; a < nc; a++)
                for (int b = a + 1; b < nc; b++)
                    if (w[b] > w[a]) { (w[a], w[b]) = (w[b], w[a]); (cand[a], cand[b]) = (cand[b], cand[a]); }
            int m = Math.Min(nc, 4);
            float sum = 0; for (int a = 0; a < m; a++) sum += w[a];
            for (int a = 0; a < 4; a++)
            {
                VB[v * 4 + a] = a < m ? cand[a] : 0;
                VW[v * 4 + a] = a < m ? w[a] / sum : 0f;
            }
        });

        sw.Stop();
        return new MeshData { V = V, N = Nn, Tri = tri.ToArray(), VB = VB, VW = VW, VPart = VPart, VMat = VMat,
                              Bones = bones, Cell = cell, Seconds = sw.Elapsed.TotalSeconds };
    }
}
