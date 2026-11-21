// ポーズをつけて (スキニング)、画素ごとの情報 (どの部品・どの素材・面の向き・奥行き) に撮る。
// GPU を使わず自前で撮るので、画素の決め方をすみずみまで決められる (ドット絵ではそこが絵そのもの) し、
// 画面なし (--headless) でも同じ絵が出せる。
using System.Numerics;

namespace DotGodough.Core;

public static class Skin
{
    /// 骨ごとの回転 (親の枠の中。基本姿勢の骨は回転なし = 世界の軸のまま) から、頂点を動かす式 p' = R p + T を作る
    public static void Matrices(Bone[] bones, Quaternion[] rot, Vector3 root, Mat3[] R, Vector3[] T, Vector3[] joint)
    {
        for (int i = 0; i < bones.Length; i++)
        {
            var b = bones[i];
            var local = Mat3.FromQuat(rot[i]);
            if (b.Parent < 0)
            {
                R[i] = local;
                joint[i] = b.Origin + root;
            }
            else
            {
                R[i] = R[b.Parent] * local;
                joint[i] = joint[b.Parent] + R[b.Parent].Mul(b.Origin - bones[b.Parent].Origin);
            }
            T[i] = joint[i] - R[i].Mul(b.Origin);
        }
    }

    public static void Apply(MeshData m, Mat3[] R, Vector3[] T, Vector3[] outV, Vector3[] outN)
    {
        Parallel.For(0, m.V.Length, v =>
        {
            var p = Vector3.Zero; var n = Vector3.Zero;
            for (int a = 0; a < 4; a++)
            {
                float w = m.VW[v * 4 + a];
                if (w <= 0f) continue;
                int b = m.VB[v * 4 + a];
                p += (R[b].Mul(m.V[v]) + T[b]) * w;
                n += R[b].Mul(m.N[v]) * w;
            }
            outV[v] = p;
            outN[v] = n.LengthSquared() > 1e-12f ? Vector3.Normalize(n) : Vector3.UnitY;
        });
    }
}

public sealed class View
{
    public int W = 48, H = 48;
    public float Yaw, Pitch;        // 度。Yaw はキャラを回す (0 = 正面)、Pitch は見下ろす角度
    public float Px = 40;           // キャラの高さ (画素。見下ろしでも 1m あたりの画素は同じ)
    public float Height = 1.55f;    // キャラの身長 (m)
    public float FloorY = 46;       // 足もとの線 (この画素の境目が地面)
    public float CenterX = -1;      // 足もとの横位置 (負 = 真ん中)
    public int SS = 3;              // 画素 1 つを何 × 何の点で見るか
    public float Cover = 0.5f;      // 何割の点が体にかかっていたら画素を塗るか (小さいほど太る)
    public int Smooth = 1;          // 面の向きをならす回数 (小さい絵で、でこぼこが斑点になるのを防ぐ)

    public float Ppm => Px / MathF.Max(Height, 0.01f);
    public float Cx => CenterX < 0 ? W * 0.5f : CenterX;

    public void Axes(out Vector3 right, out Vector3 up, out Vector3 toCam)
    {
        float y = Yaw * MathF.PI / 180f, p = Pitch * MathF.PI / 180f;
        float cy = MathF.Cos(y), sy = MathF.Sin(y), cp = MathF.Cos(p), sp = MathF.Sin(p);
        // 見る座標 = Rx(見下ろし) · Ry(yaw) · p。行がそれぞれ 右・上・手前
        right = new Vector3(cy, 0, sy);
        up = new Vector3(sy * sp, cp, -cy * sp);
        toCam = new Vector3(-sy * cp, sp, cy * cp);
    }

    public Vector3 Project(Vector3 p)
    {
        Axes(out var r, out var u, out var t);
        return new Vector3(Cx + Vector3.Dot(r, p) * Ppm, FloorY - Vector3.Dot(u, p) * Ppm, Vector3.Dot(t, p));
    }
}

public sealed class GBuffer
{
    public int W, H;
    public bool[] Hit;
    public byte[] Part, Mat;
    public Vector3[] Nrm;      // 見る座標 (x 右、y 上、z 手前)
    public float[] Depth;      // 手前ほど大きい (m)
    public float[] Cover;      // かかっている点の割合
    public Vector3[] Rest;     // 基本姿勢での位置 (体の上の場所。顔の絵などを貼る目印に使う)
    public float Ppm;

    public GBuffer(int w, int h)
    {
        W = w; H = h;
        int n = w * h;
        Hit = new bool[n]; Part = new byte[n]; Mat = new byte[n]; Nrm = new Vector3[n]; Depth = new float[n];
        Cover = new float[n]; Rest = new Vector3[n];
    }
}

public static class Raster
{
    public static GBuffer Draw(MeshData m, Vector3[] PV, Vector3[] PN, View view)
    {
        int S = Math.Clamp(view.SS, 1, 5);
        int W = view.W, H = view.H, SW = W * S, SH = H * S;
        view.Axes(out var right, out var up, out var toCam);
        float ppm = view.Ppm;
        int nv = PV.Length;
        var sx = new float[nv]; var sy = new float[nv]; var sz = new float[nv];
        for (int v = 0; v < nv; v++)
        {
            sx[v] = (view.Cx + Vector3.Dot(right, PV[v]) * ppm) * S;
            sy[v] = (view.FloorY - Vector3.Dot(up, PV[v]) * ppm) * S;
            sz[v] = Vector3.Dot(toCam, PV[v]);
        }
        var zbuf = new float[SW * SH];
        var tbuf = new int[SW * SH];
        Array.Fill(zbuf, float.NegativeInfinity);
        Array.Fill(tbuf, -1);
        int nt = m.Tri.Length / 3;
        for (int t = 0; t < nt; t++)
        {
            int a = m.Tri[t * 3], b = m.Tri[t * 3 + 1], c = m.Tri[t * 3 + 2];
            float ax = sx[a], ay = sy[a], bx = sx[b], by = sy[b], cx = sx[c], cy = sy[c];
            // 画面は y が下向きなので、表 (見る座標で反時計回り) は画面では時計回り = 面積が負
            float area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
            if (area >= -1e-9f) continue;
            int x0 = Math.Max(0, (int)MathF.Floor(MathF.Min(ax, MathF.Min(bx, cx)) - 0.5f));
            int x1 = Math.Min(SW - 1, (int)MathF.Ceiling(MathF.Max(ax, MathF.Max(bx, cx)) - 0.5f));
            int y0 = Math.Max(0, (int)MathF.Floor(MathF.Min(ay, MathF.Min(by, cy)) - 0.5f));
            int y1 = Math.Min(SH - 1, (int)MathF.Ceiling(MathF.Max(ay, MathF.Max(by, cy)) - 0.5f));
            float inv = 1f / area;
            for (int y = y0; y <= y1; y++)
            {
                float py = y + 0.5f;
                for (int x = x0; x <= x1; x++)
                {
                    float px = x + 0.5f;
                    float w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) * inv;
                    float w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) * inv;
                    float w2 = 1f - w0 - w1;
                    if (w0 < 0f || w1 < 0f || w2 < 0f) continue;
                    float z = w0 * sz[a] + w1 * sz[b] + w2 * sz[c];
                    int i = x + SW * y;
                    if (z > zbuf[i]) { zbuf[i] = z; tbuf[i] = t; }
                }
            }
        }

        // 画素にまとめる: かかっている点が Cover 以上なら塗る。部品は多数決、中身はその部品のうち真ん中に近い点から
        var g = new GBuffer(W, H) { Ppm = ppm };
        int need = Math.Max(1, (int)MathF.Ceiling(view.Cover * S * S - 1e-4f));
        Span<int> cnt = stackalloc int[32];
        float mid = (S - 1) * 0.5f;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                cnt.Clear();
                int covered = 0;
                for (int j = 0; j < S; j++)
                    for (int i = 0; i < S; i++)
                    {
                        int t = tbuf[x * S + i + SW * (y * S + j)];
                        if (t < 0) continue;
                        covered++;
                        cnt[TriPart(m, t) & 31]++;
                    }
                int o = x + W * y;
                g.Cover[o] = covered / (float)(S * S);
                if (covered < need) continue;
                int part = 0;
                for (int p = 1; p < 32; p++) if (cnt[p] > cnt[part]) part = p;
                // 真ん中の点がいちばん多い部品と同数なら、真ん中の点の部品にする (ちらつきを減らす)
                int tc = tbuf[x * S + S / 2 + SW * (y * S + S / 2)];
                if (tc >= 0 && cnt[TriPart(m, tc) & 31] == cnt[part]) part = TriPart(m, tc) & 31;
                float bestD = 1e9f; int bi = 0, bj = 0, bt = -1;
                for (int j = 0; j < S; j++)
                    for (int i = 0; i < S; i++)
                    {
                        int t = tbuf[x * S + i + SW * (y * S + j)];
                        if (t < 0 || (TriPart(m, t) & 31) != part) continue;
                        float d = (i - mid) * (i - mid) + (j - mid) * (j - mid);
                        if (d < bestD) { bestD = d; bi = i; bj = j; bt = t; }
                    }
                if (bt < 0) continue;
                int a = m.Tri[bt * 3], b = m.Tri[bt * 3 + 1], c = m.Tri[bt * 3 + 2];
                float px = x * S + bi + 0.5f, py = y * S + bj + 0.5f;
                float area = (sx[b] - sx[a]) * (sy[c] - sy[a]) - (sy[b] - sy[a]) * (sx[c] - sx[a]);
                float w0 = ((sx[b] - px) * (sy[c] - py) - (sy[b] - py) * (sx[c] - px)) / area;
                float w1 = ((sx[c] - px) * (sy[a] - py) - (sy[c] - py) * (sx[a] - px)) / area;
                float w2 = 1f - w0 - w1;
                var n = PN[a] * w0 + PN[b] * w1 + PN[c] * w2;
                n = n.LengthSquared() > 1e-12f ? Vector3.Normalize(n) : toCam;
                g.Hit[o] = true;
                g.Part[o] = (byte)part;
                g.Mat[o] = m.VMat[w0 >= w1 && w0 >= w2 ? a : w1 >= w2 ? b : c];
                g.Nrm[o] = new Vector3(Vector3.Dot(right, n), Vector3.Dot(up, n), Vector3.Dot(toCam, n));
                g.Depth[o] = w0 * sz[a] + w1 * sz[b] + w2 * sz[c];
                g.Rest[o] = m.V[a] * w0 + m.V[b] * w1 + m.V[c] * w2;
            }
        // 面の向きをならす: 同じ部品で奥行きの近いとなりと平均する
        for (int pass = 0; pass < view.Smooth; pass++)
        {
            var src = (Vector3[])g.Nrm.Clone();
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    int o = x + W * y;
                    if (!g.Hit[o]) continue;
                    var sum = src[o] * 2f;
                    for (int dy = -1; dy <= 1; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            int nx = x + dx, ny = y + dy;
                            if ((dx == 0 && dy == 0) || nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
                            int j = nx + W * ny;
                            if (!g.Hit[j] || g.Part[j] != g.Part[o] || MathF.Abs(g.Depth[j] - g.Depth[o]) * ppm > 2.5f) continue;
                            sum += src[j];
                        }
                    g.Nrm[o] = Vector3.Normalize(sum);
                }
        }
        return g;
    }

    static int TriPart(MeshData m, int t)
    {
        byte a = m.VPart[m.Tri[t * 3]], b = m.VPart[m.Tri[t * 3 + 1]], c = m.VPart[m.Tri[t * 3 + 2]];
        return b == c ? b : a;
    }
}
