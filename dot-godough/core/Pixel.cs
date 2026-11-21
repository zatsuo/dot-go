// 画素ごとの情報 → ドット絵。決まりは docs/LOOK.md。
//  1. 光は段にする (素材ごとの色の段)。孤立した 1 画素の段はまわりに合わせる
//  2. 線: 外 (シルエットの外に 1 画素足す) / 内 (シルエットのふちの画素を線にする)、手前の部品と奥の部品の境目
//  3. 線の色は素材ごと (髪は紺、肌は茶…)。黒 1 色にもできる
using System.Numerics;

namespace DotGodough.Core;

public sealed class MatStyle
{
    public uint[] Ramp = { 0xFFD9A088u, 0xFFF3CFB2u, 0xFFFCEBDAu };   // 暗い → 明るい (ABGR ではなく 0xAARRGGBB)
    public uint Line = 0xFF6B3F36u;
}

public sealed class Style
{
    public List<MatStyle> Mats = new() { new MatStyle() };
    public float[] Steps = { 0.05f, 0.85f };   // 光の強さ (-1〜1) の区切り。段の数 = 区切り + 1
    public Vector3 Light = Vector3.Normalize(new Vector3(-0.45f, 0.6f, 0.65f));   // 見る座標での光の来る向き
    public int LineMode = 1;          // 0 なし / 1 外 / 2 内
    public bool InnerLines = true;    // 部品の重なりの線
    public float GapPart = 1.5f;      // ちがう部品: 奥行きの差がこれ以上 (画素) で線
    public float GapSame = 4f;        // 同じ部品
    public bool OneLineColor;         // 線を 1 色に
    public uint LineColor = 0xFF1A1420u;
    public bool Despeckle = true;
    // ふちの濃い色 (試作。ユーザーの説明待ち): シルエットの内側 RimWidth 画素を 1 段暗く。RimSide = 光と反対側だけ
    public int Rim;
    public bool RimShadowSide = true;
    // 塗りの色 → その色の段 (暗い → 明るい)。無い色は そのままの色で塗る
    public Dictionary<uint, uint[]> PaintRamps = new();
}

public static class Pixel
{
    static readonly int[] DX = { 1, -1, 0, 0 }, DY = { 0, 0, 1, -1 };

    /// 関節でつながっている部品どうしか (胴 0、頭 1、腕 2〜7、脚 8〜13。Mesher.PartOf)
    /// 段の外の色: n > 0 = いちばん明るい色より n 段明るく (白へ、少し黄みへ)、n < 0 = いちばん暗い色より暗く (少し青みへ)
    static uint Shift(uint argb, int n)
    {
        float r = ((argb >> 16) & 255) / 255f, g = ((argb >> 8) & 255) / 255f, b = (argb & 255) / 255f;
        for (int k = 0; k < Math.Abs(n); k++)
        {
            if (n > 0) { r += (1f - r) * 0.5f; g += (1f - g) * 0.47f; b += (1f - b) * 0.38f; }
            else { r *= 0.68f; g *= 0.68f; b *= 0.76f; }
        }
        return (argb & 0xFF000000u) | ((uint)(r * 255f + 0.5f) << 16) | ((uint)(g * 255f + 0.5f) << 8) | (uint)(b * 255f + 0.5f);
    }

    static bool Joined(int a, int b)
    {
        if (a > b) (a, b) = (b, a);
        if (a == 0) return b == 1 || b == 2 || b == 5 || b == 8 || b == 11 || b == 14;
        if (a == 1) return b == 15;      // 頭と髪
        if (a == 15) return false;       // 髪と、ペンで描いた房 (あいだに線を引く)
        return b == a + 1 && a != 4 && a != 7 && a != 10;
    }

    /// 段の番号 (0 = いちばん暗い) を画素ごとに
    public static int[] Bands(GBuffer g, Style st)
    {
        int n = g.W * g.H;
        var band = new int[n];
        for (int i = 0; i < n; i++)
        {
            if (!g.Hit[i]) { band[i] = -1; continue; }
            float l = Vector3.Dot(g.Nrm[i], st.Light);
            int b = 0;
            foreach (float s in st.Steps) if (l > s) b++;
            band[i] = b;
        }
        if (!st.Despeckle) return band;
        // 孤立した 1 画素の段は、まわり (同じ素材) でいちばん多い段に合わせる
        var o = (int[])band.Clone();
        Span<int> cnt = stackalloc int[8];
        for (int y = 0; y < g.H; y++)
            for (int x = 0; x < g.W; x++)
            {
                int i = x + g.W * y;
                if (band[i] < 0) continue;
                cnt.Clear();
                int same = 0, total = 0;
                for (int d = 0; d < 4; d++)
                {
                    int nx = x + DX[d], ny = y + DY[d];
                    if (nx < 0 || ny < 0 || nx >= g.W || ny >= g.H) continue;
                    int j = nx + g.W * ny;
                    if (band[j] < 0 || g.Mat[j] != g.Mat[i]) continue;
                    total++;
                    if (band[j] == band[i]) same++;
                    cnt[band[j] & 7]++;
                }
                if (same > 0 || total < 2) continue;
                int best = 0;
                for (int b = 1; b < 8; b++) if (cnt[b] > cnt[best]) best = b;
                o[i] = best;
            }
        return o;
    }

    /// paint = 画素ごとの塗りの色 (0 = 塗っていない)、paintFlat = 段を使わず そのままの色 (線よりも上)
    /// tone = その画素の段を上げ下げする数 (髪のつやの帯、明るさのペン)。いちばん明るい段より上は、白へ寄せた色を作る
    public static byte[] Compose(GBuffer g, Style st, uint[] paint = null, bool[] paintFlat = null, sbyte[] tone = null, int[] cls = null)
    {
        // cls = 画素ごとに、どの素材のどの色か (素材 × 8 + 段。線は 素材 × 8 + 7。何も無い = -1、塗り・明るさのペン = -2)
        int W = g.W, H = g.H, n = W * H;
        if (cls != null) Array.Fill(cls, -1);
        var band = Bands(g, st);
        var color = new uint[n];
        var isLine = new bool[n];

        MatStyle M(int mat) => st.Mats[Math.Min(mat, st.Mats.Count - 1)];
        uint LineOf(int mat) => st.OneLineColor ? st.LineColor : M(mat).Line;

        // ふちまでの距離 (シルエットの内側へ何画素か)。Rim で使う
        int[] edge = null;
        if (st.Rim > 0)
        {
            edge = new int[n];
            Array.Fill(edge, 99);
            for (int pass = 0; pass <= st.Rim; pass++)
                for (int y = 0; y < H; y++)
                    for (int x = 0; x < W; x++)
                    {
                        int i = x + W * y;
                        if (!g.Hit[i] || edge[i] != 99) continue;
                        for (int d = 0; d < 4; d++)
                        {
                            int nx = x + DX[d], ny = y + DY[d];
                            bool outside = nx < 0 || ny < 0 || nx >= W || ny >= H || !g.Hit[nx + W * ny];
                            if (pass == 0 ? outside : (!outside && edge[nx + W * ny] == pass - 1)) { edge[i] = pass; break; }
                        }
                    }
        }

        for (int i = 0; i < n; i++)
        {
            if (!g.Hit[i]) continue;
            var ramp = M(g.Mat[i]).Ramp;
            if (paint != null && paint[i] != 0 && !paintFlat[i])
                ramp = st.PaintRamps.TryGetValue(paint[i], out var pr) && pr.Length > 0 ? pr : new[] { paint[i] };
            int b = Math.Clamp(band[i] * ramp.Length / (st.Steps.Length + 1), 0, ramp.Length - 1);
            if (ramp.Length == st.Steps.Length + 1) b = Math.Clamp(band[i], 0, ramp.Length - 1);
            if (edge != null && edge[i] < st.Rim + (st.LineMode == 2 ? 1 : 0) && edge[i] >= (st.LineMode == 2 ? 1 : 0))
            {
                // 光の来る側のふちはそのまま (RimShadowSide)。面が光と反対を向いているふちだけ 1 段暗く
                var nr = g.Nrm[i];
                float side = nr.X * st.Light.X + nr.Y * st.Light.Y;
                if (!st.RimShadowSide || side < 0f) b = Math.Max(0, b - 1);
            }
            color[i] = ramp[b];
            if (cls != null) cls[i] = (paint != null && paint[i] != 0) || (tone != null && tone[i] != 0) ? -2 : g.Mat[i] * 8 + b;
            if (tone != null && tone[i] != 0)
            {
                int t = b + tone[i];
                color[i] = t >= ramp.Length ? Shift(ramp[^1], t - ramp.Length + 1) : t < 0 ? Shift(ramp[0], t) : ramp[t];
            }
        }

        // 線
        if (st.LineMode != 0 || st.InnerLines)
        {
            float ppm = g.Ppm;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    int i = x + W * y;
                    if (!g.Hit[i])
                    {
                        if (st.LineMode != 1) continue;
                        // 外の線: 体のとなりの空の画素。色は、となりのうちいちばん手前の素材の線の色
                        float bz = float.NegativeInfinity; int bm = -1;
                        for (int d = 0; d < 4; d++)
                        {
                            int nx = x + DX[d], ny = y + DY[d];
                            if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
                            int j = nx + W * ny;
                            if (g.Hit[j] && g.Depth[j] > bz) { bz = g.Depth[j]; bm = g.Mat[j]; }
                        }
                        if (bm >= 0) { color[i] = LineOf(bm); isLine[i] = true; if (cls != null) cls[i] = bm * 8 + 7; }
                        continue;
                    }
                    for (int d = 0; d < 4; d++)
                    {
                        int nx = x + DX[d], ny = y + DY[d];
                        bool inb = nx >= 0 && ny >= 0 && nx < W && ny < H;
                        int j = inb ? nx + W * ny : -1;
                        if (!inb || !g.Hit[j])
                        {
                            if (st.LineMode == 2) { color[i] = LineOf(g.Mat[i]); isLine[i] = true; if (cls != null) cls[i] = g.Mat[i] * 8 + 7; }
                            continue;
                        }
                        if (!st.InnerLines) continue;
                        float gap = (g.Depth[j] - g.Depth[i]) * ppm;   // + なら となりが手前
                        // つながっていない部品どうし (手と太ももなど) は、奥行きの差が小さくても線で分ける
                        float need = g.Part[j] == g.Part[i] ? st.GapSame : Joined(g.Part[i], g.Part[j]) ? st.GapPart : 0.05f;
                        if (st.LineMode == 2)
                        {
                            // 内の線: 手前の部品のふちの画素を線に
                            if (-gap > need) { color[i] = LineOf(g.Mat[i]); isLine[i] = true; if (cls != null) cls[i] = g.Mat[i] * 8 + 7; }
                        }
                        else if (gap > need)
                        {
                            // 外の線: 奥の部品の、手前の部品に接する画素を線に (色は手前の素材の線の色)
                            color[i] = LineOf(g.Mat[j]); isLine[i] = true; if (cls != null) cls[i] = g.Mat[j] * 8 + 7;
                        }
                    }
                }
        }

        var rgba = new byte[n * 4];
        for (int i = 0; i < n; i++)
        {
            uint c = color[i];
            if (paint != null && paint[i] != 0 && paintFlat[i] && g.Hit[i]) { c = paint[i]; if (cls != null) cls[i] = -2; }
            if (c == 0) continue;
            rgba[i * 4] = (byte)(c >> 16); rgba[i * 4 + 1] = (byte)(c >> 8); rgba[i * 4 + 2] = (byte)c; rgba[i * 4 + 3] = (byte)(c >> 24);
        }
        return rgba;
    }
}
