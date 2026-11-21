// 形の組み合わせ (SDF)。low-Godough の core/sdf.py・core/head.py と同じ式を、点 1 つずつ測る形に直したもの。
// - グループの中はプリミティブを順に足し引き (なめらかさ = Blend)
// - グループは木。子は親とだけなめらかにつながり (なめらかさ = Join)、兄弟どうしはただの最小値
// 座標は low-Godough と同じ: Y が上、+Z が前、+X が体の左。
using System.Numerics;

namespace DotGodough.Core;

public struct Mat3
{
    public Vector3 X, Y, Z;   // 列

    public Mat3(Vector3 x, Vector3 y, Vector3 z) { X = x; Y = y; Z = z; }

    public static readonly Mat3 Identity = new(Vector3.UnitX, Vector3.UnitY, Vector3.UnitZ);

    public Vector3 Mul(Vector3 v) => X * v.X + Y * v.Y + Z * v.Z;

    public Vector3 TMul(Vector3 v) => new(Vector3.Dot(X, v), Vector3.Dot(Y, v), Vector3.Dot(Z, v));

    public static Mat3 operator *(Mat3 a, Mat3 b) => new(a.Mul(b.X), a.Mul(b.Y), a.Mul(b.Z));

    public Mat3 T => new(new Vector3(X.X, Y.X, Z.X), new Vector3(X.Y, Y.Y, Z.Y), new Vector3(X.Z, Y.Z, Z.Z));

    /// 左右を入れかえた向き (M b M、M = diag(-1, 1, 1))
    public Mat3 Mirrored => new(new Vector3(X.X, -X.Y, -X.Z), new Vector3(-Y.X, Y.Y, Y.Z), new Vector3(-Z.X, Z.Y, Z.Z));

    /// Y がこの向きを向き、Z がなるべく ref (前) を保つ
    public static Mat3 Frame(Vector3 dir, Vector3 refZ)
    {
        var y = Vector3.Normalize(dir);
        var z = refZ - y * Vector3.Dot(refZ, y);
        if (z.LengthSquared() < 1e-12f) z = Vector3.UnitZ - y * y.Z;
        if (z.LengthSquared() < 1e-12f) z = Vector3.UnitX - y * y.X;
        z = Vector3.Normalize(z);
        var x = Vector3.Normalize(Vector3.Cross(y, z));
        return new Mat3(x, y, z);
    }

    public static Mat3 FromQuat(Quaternion q)
    {
        var m = Matrix4x4.CreateFromQuaternion(q);
        return new Mat3(new Vector3(m.M11, m.M12, m.M13), new Vector3(m.M21, m.M22, m.M23), new Vector3(m.M31, m.M32, m.M33));
    }
}

public enum PrimType { Sphere, Capsule, Box, Head }

public enum PrimOp { Add, Subtract, Intersect }

/// パーツ座標に置いたプリミティブ 1 つ
public sealed class RPrim
{
    public string Name = "";
    public PrimType Type;
    public PrimOp Op;
    public Mat3 Basis = Mat3.Identity;
    public Vector3 Pos;
    public Vector3 Size;     // Sphere = 半径 (楕円体)、Capsule = (根元の半径, 半分の長さ, 先の半径)、Box = 半分の幅
    public float Round, Blend;
    public int Group;
    public int Bone = -1;
    public float Shape;      // 頭: 0 ふつう 〜 1 ちび
    public Vector3 BC;       // 外接球
    public float BR;

    public void Bound()
    {
        switch (Type)
        {
            case PrimType.Head:
                BC = Pos + Basis.Mul(new Vector3(0, 0.5f * Size.Y, -0.1f * Size.Z));
                BR = new Vector3(0.375f * Size.X, 0.5f * Size.Y, 0.45f * Size.Z).Length() * 1.05f;
                break;
            case PrimType.Capsule:
                BC = Pos; BR = Size.Y + MathF.Max(Size.X, Size.Z);
                break;
            case PrimType.Box:
                BC = Pos; BR = Size.Length();
                break;
            default:
                BC = Pos; BR = MathF.Max(Size.X, MathF.Max(Size.Y, Size.Z));
                break;
        }
    }

    public float Distance(Vector3 p)
    {
        var q = Basis.TMul(p - Pos);
        switch (Type)
        {
            case PrimType.Box: return Sd.Box(q, Size, Round);
            case PrimType.Capsule: return Sd.RoundCone(q, Size.X, Size.Z, Size.Y);
            case PrimType.Head:
                return HeadModel.Distance(q / Size, Shape) * MathF.Min(Size.X, MathF.Min(Size.Y, Size.Z));
            default: return Sd.Ellipsoid(q, Size);
        }
    }
}

public static class Sd
{
    public static float Box(Vector3 q, Vector3 size, float rnd)
    {
        float r = MathF.Min(rnd, MathF.Min(size.X, MathF.Min(size.Y, size.Z)));
        var a = Vector3.Abs(q) - (size - new Vector3(r));
        float outside = Vector3.Max(a, Vector3.Zero).Length();
        return outside + MathF.Min(MathF.Max(a.X, MathF.Max(a.Y, a.Z)), 0f) - r;
    }

    public static float Ellipsoid(Vector3 q, Vector3 s)
    {
        if (MathF.Abs(s.X - s.Y) < 1e-6f && MathF.Abs(s.Y - s.Z) < 1e-6f) return q.Length() - s.X;
        float k0 = (q / s).Length();
        float k1 = (q / (s * s)).Length();
        if (k1 < 1e-12f) return -MathF.Min(s.X, MathF.Min(s.Y, s.Z));
        return k0 * (k0 - 1f) / k1;
    }

    /// Y 軸に沿った先細りカプセル。r1 = 根元 (y = -h)、r2 = 先 (y = +h)
    public static float RoundCone(Vector3 p, float r1, float r2, float h)
    {
        float l2 = 4f * h * h;
        float rr = r1 - r2;
        float a2 = l2 - rr * rr;
        var pa = new Vector3(p.X, p.Y + h, p.Z);
        if (a2 <= 1e-10f)
            return MathF.Min(pa.Length() - r1, new Vector3(p.X, p.Y - h, p.Z).Length() - r2);
        float il2 = 1f / l2;
        float y = pa.Y * 2f * h;
        float z = y - l2;
        var xv = pa * l2 - new Vector3(0, 2f * h, 0) * y;
        float x2 = xv.LengthSquared();
        float y2 = y * y * l2;
        float z2 = z * z * l2;
        float k = (rr < 0 ? -1f : 1f) * rr * rr * x2;
        if (MathF.Sign(z) * a2 * z2 > k) return MathF.Sqrt(x2 + z2) * il2 - r2;
        if (MathF.Sign(y) * a2 * y2 < k) return MathF.Sqrt(x2 + y2) * il2 - r1;
        return (MathF.Sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
    }

    /// a から b への先細りカプセル (向きは自由)。r1 = a の半径、r2 = b の半径
    public static float RoundCone(Vector3 p, Vector3 a, Vector3 b, float r1, float r2)
    {
        var ba = b - a;
        float l2 = ba.LengthSquared();
        float rr = r1 - r2;
        float a2 = l2 - rr * rr;
        var pa = p - a;
        if (l2 < 1e-10f || a2 <= 1e-10f)
            return MathF.Min(pa.Length() - r1, (p - b).Length() - r2);
        float il2 = 1f / l2;
        float y = Vector3.Dot(pa, ba);
        float z = y - l2;
        float x2 = (pa * l2 - ba * y).LengthSquared();
        float y2 = y * y * l2;
        float z2 = z * z * l2;
        float k = (rr < 0 ? -1f : 1f) * rr * rr * x2;
        if (MathF.Sign(z) * a2 * z2 > k) return MathF.Sqrt(x2 + z2) * il2 - r2;
        if (MathF.Sign(y) * a2 * y2 < k) return MathF.Sqrt(x2 + y2) * il2 - r1;
        return (MathF.Sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
    }

    public static float SMin(float d, float di, float k)
    {
        if (k <= 1e-6f) return MathF.Min(d, di);
        float h = Math.Clamp(0.5f + 0.5f * (di - d) / k, 0f, 1f);
        return di + (d - di) * h - k * h * (1f - h);
    }

    public static float SSub(float d, float di, float k)
    {
        if (k <= 1e-6f) return MathF.Max(d, -di);
        float h = Math.Clamp(0.5f - 0.5f * (d + di) / k, 0f, 1f);
        return d + (-di - d) * h + k * h * (1f - h);
    }

    public static float SInt(float d, float di, float k)
    {
        if (k <= 1e-6f) return MathF.Max(d, di);
        float h = Math.Clamp(0.5f - 0.5f * (di - d) / k, 0f, 1f);
        return di + (d - di) * h + k * h * (1f - h);
    }
}

/// くっつきグループ
public sealed class Group
{
    public string Name = "";
    public int Parent = -1;
    public float Join;
    // つなぎが効く場所: 中心から R0 までは全部、R1 で 0 (R1 <= 0 ならどこでも)。
    // 腕が腰に、太ももがおなかに、離れた所でくっつかないように
    public Vector3 JoinC;
    public float JoinR0, JoinR1;
}

/// 服 1 枚。体の決まった範囲を外へふくらませたもの (Kind 0・2) か、腰から下がる すそ (Kind 3)
public sealed class Garment
{
    public int Kind;                    // 0 胴と脚 (+ そで) / 2 腕だけ / 3 すそ (スカート)
    public float YTop, YBot;            // 縦の範囲 (m)
    // えりぐり: 上の端は首のまわり (半径 NeckR) だけ YTop の高さで切り、首から離れるほど高い所で切る (すり鉢の形)。
    // まっ平らに切ると、肩の上にそでの布だけが残って盛り上がる
    public float NeckR, NeckZ, NeckSlope;
    public float Thick, Flare;          // 厚み、下の端で足す厚み (m)
    public bool HasArm;
    public float ArmFrom, ArmTo, ArmFlare, ArmU0, ArmSpan;   // 腕に沿った範囲 (肩からの長さ m)
    public float RxT, RxS, ZfT, ZfS, ZbT, ZbS, Follow;       // すそ: 上の端の半径と、下へ行くほど広がる割合
}

/// 髪。頭を厚みだけふくらませた殻を、下の端で切ったもの (docs/HAIR.md)。
/// 頭のいちばん広い高さより下は、その輪切りのまままっすぐ下へ垂れる。
/// 下の端と厚みは、頭のまわりの向き (0° = 正面、180° = 後ろ) で 前髪・横・後ろ の 3 つに分ける。
/// 長さ: 0 = 頭のてっぺん、1 = あご、2 = くびれ、3 = ひざ、4 = 地面 (あごから下は体の目印で測るので、頭身が変わっても同じ所まで届く)
public sealed class Hair
{
    public float Vol = 0.05f, Puff = 0.02f;      // 厚み (頭の高さが単位)、横と後ろに足す厚み
    public float Bangs = 0.42f, BangsW = 42f;    // 前髪の長さ、幅 (正面から左右へ何度まで)
    public float Side = 0.92f, Back = 0.98f;     // 横・後ろの長さ
    public float Tips = 0.3f;                    // 毛先のギザギザ 0〜1
    public float Curl = 0.5f;                    // 毛先の内巻き 0〜1 (下の端に近づくほど内へすぼめる。0 だと箱に見える)
    public float Gloss = 0.8f;                   // つやの帯の高さ (頭の高さが単位。0 = なし)
    public bool Shell = true;                    // false = ひな形の殻なし (ペンで描いた房だけ)
    // ペンで描いた房: 1 本 = [x, y, z, 半径] の並び。場所は頭の枠 (÷ 頭の大きさ)、半径は頭の高さが単位。
    // 頭の大きさが変わると、房もいっしょに伸び縮みする
    public readonly List<float[]> Locks = new();
    Vector3[][] _lp = Array.Empty<Vector3[]>();  // いまの体での房の点 (基本姿勢)
    float[][] _lr = Array.Empty<float[]>();
    Vector3[] _lc = Array.Empty<Vector3>();      // 房ごとの外接球
    float[] _lR = Array.Empty<float>();
    // 消しゴムの線 (半径を負で持っている)。線の形を、描いたときの見る向きへ奥に押し抜いた形だけ髪を消す
    // (絵の上で消した画素から、髪が見えなくなるように)。並びの最後の 4 つが [向き x, y, z (頭の枠), 奥行き (頭の高さが単位)]
    bool[] _lcut = Array.Empty<bool>();
    Vector3[] _ldir = Array.Empty<Vector3>();
    float[] _lL = Array.Empty<float>();
    public bool Separate;                        // 描いた髪を別の部品にする (ひな形との境に線が出る)。ふだんは ひとかたまり
    public RPrim Head;
    public float Yw = 0.55f, Zc = -0.08f, MinEnd;
    public float ChinY, HeadH;
    public float WaistU, KneeU, GroundU;         // くびれ・ひざ・地面の高さ (頭の枠で。あご = 0、てっぺん = 1)

    /// 長さ → 下の端の高さ (頭の枠で)
    public float Map(float len)
    {
        if (len <= 1f) return 1f - len;
        if (len <= 2f) return WaistU * (len - 1f);
        if (len <= 3f) return WaistU + (KneeU - WaistU) * (len - 2f);
        return KneeU + (GroundU - KneeU) * MathF.Min(len - 3f, 1f);
    }

    static float Smooth(float x, float a, float b)
    {
        float t = Math.Clamp((x - a) / (b - a), 0f, 1f);
        return t * t * (3f - 2f * t);
    }

    float One(int i, Vector3 p)
    {
        float best = 1e9f;
        var pts = _lp[i]; var rs = _lr[i];
        if (_lcut[i])
        {
            // 押し抜き: 見る向きを落とした面の上で線までの距離を測り、奥行きは 面の少し手前 〜 奥行き L まで
            var dir = _ldir[i];
            float tp = Vector3.Dot(p, dir), ts = 0f, rr = 0f;
            var pp = p - dir * tp;
            for (int k = 0; k + 1 < pts.Length; k++)
            {
                float ta = Vector3.Dot(pts[k], dir), tb = Vector3.Dot(pts[k + 1], dir);
                var a = pts[k] - dir * ta; var ab = pts[k + 1] - dir * tb - a;
                float l2 = ab.LengthSquared();
                float h = l2 < 1e-12f ? 0f : Math.Clamp(Vector3.Dot(pp - a, ab) / l2, 0f, 1f);
                float r = rs[k] + (rs[k + 1] - rs[k]) * h;
                float d = (pp - a - ab * h).Length() - r;
                if (d < best) { best = d; ts = ta + (tb - ta) * h; rr = r; }
            }
            return MathF.Max(best, MathF.Max(tp - (ts + rr + 0.02f * HeadH), ts - _lL[i] - tp));
        }
        for (int k = 0; k + 1 < pts.Length; k++)
            best = MathF.Min(best, Sd.RoundCone(p, pts[k], pts[k + 1], rs[k], rs[k + 1]));
        return best;
    }

    /// 切った線のうち、その場所が切った形の中 (か、near より近く) にあるものの番号 (あとの線が先)。無ければ -1
    public int CutAt(Vector3 p, float near)
    {
        for (int i = _lp.Length - 1; i >= 0; i--)
            if (_lcut[i] && (p - _lc[i]).Length() - _lR[i] < near && One(i, p) < near) return i;
        return -1;
    }

    /// 房 (足した線) までの距離。which にいちばん近い房の番号。遠い房は外接球までの控えめな距離で代える
    public float LockDistance(Vector3 p, out int which)
    {
        float best = 1e9f;
        which = -1;
        for (int i = 0; i < _lp.Length; i++)
        {
            if (_lcut[i]) continue;
            float dc = (p - _lc[i]).Length() - _lR[i];
            if (dc >= best) continue;
            if (dc > 0.1f * HeadH) { best = dc; which = i; continue; }
            var pts = _lp[i]; var rs = _lr[i];
            for (int k = 0; k + 1 < pts.Length; k++)
            {
                float d = Sd.RoundCone(p, pts[k], pts[k + 1], rs[k], rs[k + 1]);
                if (d < best) { best = d; which = i; }
            }
        }
        return best;
    }

    public float Distance(Vector3 p)
    {
        // 殻 → 描いた順に、房を足す・切る
        float d = 1e9f;
        bool far = true;
        if (Shell) d = ShellDistance(p, out far);
        float k = 0.02f * HeadH, cull = 0.1f * HeadH;
        for (int i = 0; i < _lp.Length; i++)
        {
            float dc = (p - _lc[i]).Length() - _lR[i];
            if (_lcut[i])
            {
                if (dc > cull) continue;
                d = Sd.SSub(d, One(i, p), far ? 0f : 0.25f * k);
            }
            else if (dc > cull) d = MathF.Min(d, dc);
            else { d = far ? MathF.Min(d, One(i, p)) : Sd.SMin(d, One(i, p), k); far = false; }
        }
        return d;
    }

    float ShellDistance(Vector3 p, out bool far)
    {
        far = true;
        var r = Head;
        var u = r.Basis.TMul(p - r.Pos) / r.Size;
        float sy = r.Size.Y;
        float thickMax = Vol + Puff;
        // 遠い所は、ざっくりした箱までの距離で代える (頭の式は重い)
        float below = (MinEnd - 0.05f - u.Y) * sy;
        float rad = MathF.Sqrt(u.X * u.X * r.Size.X * r.Size.X + (u.Z - Zc) * (u.Z - Zc) * r.Size.Z * r.Size.Z) - (0.62f + thickMax) * MathF.Max(r.Size.X, r.Size.Z);
        float above = (u.Y - 1f - thickMax) * sy;
        float box = MathF.Max(below, MathF.Max(rad, above));
        if (box > 0.06f * sy) return box;
        far = false;

        float scale = MathF.Min(r.Size.X, MathF.Min(sy, r.Size.Z));
        float col = HeadModel.Distance(new Vector3(u.X, MathF.Max(u.Y, Yw), u.Z), r.Shape) * scale;
        float phi = MathF.Atan2(MathF.Abs(u.X * r.Size.X), (u.Z - Zc) * r.Size.Z) * (180f / MathF.PI);
        float a = Smooth(phi, BangsW - 6f, BangsW + 6f), b = Smooth(phi, 96f, 116f);
        float len = Bangs + (Side - Bangs) * a;
        len += (Back - len) * b;
        float end = Map(len);
        // 毛先: 向きに沿った三角の波
        float w = phi / 24f + 0.25f;
        float tri = MathF.Abs(w - MathF.Floor(w) - 0.5f) * 2f;
        end += Tips * 0.13f * (tri - 0.5f);
        end = MathF.Max(end, MinEnd);
        // 内巻き: 下の端の手前から、内へすぼめる (前髪は半分)
        float g = 1f - Smooth(u.Y - end, 0f, 0.24f);
        float curl = Curl * 0.075f * g * g * (0.5f + 0.5f * a);
        // あごより下は、下へ行くほど細く (くびれの高さで頭の高さの 0.16 ぶん)。そのままだと板になる
        float narrow = 0.16f * Math.Clamp(-u.Y / MathF.Max(-WaistU, 0.1f), 0f, 2f);
        return MathF.Max(col - (Vol + Puff * a - curl - narrow) * sy, (end - u.Y) * sy);
    }

    /// つやの帯: その場所 (基本姿勢) が帯の中なら true。帯は頭のまわりの決まった高さで、少し波うつ
    public bool InGloss(Vector3 p)
    {
        if (Gloss <= 0f || !Shell) return false;
        var r = Head;
        var u = r.Basis.TMul(p - r.Pos) / r.Size;
        float phi = MathF.Atan2(MathF.Abs(u.X * r.Size.X), (u.Z - Zc) * r.Size.Z) * (180f / MathF.PI);
        float w = phi / 30f;
        float tri = MathF.Abs(w - MathF.Floor(w) - 0.5f) * 2f;
        float y = Gloss + 0.025f * (tri - 0.5f);
        return u.Y > y - 0.03f && u.Y < y + 0.03f;
    }

    public Vector3 ToHead(Vector3 p) => Head.Basis.TMul(p - Head.Pos) / Head.Size;
    public Vector3 FromHead(Vector3 u) => Head.Pos + Head.Basis.Mul(u * Head.Size);

    /// 房をぜんぶ入れる箱
    public void LockBounds(ref Vector3 lo, ref Vector3 hi)
    {
        for (int i = 0; i < _lp.Length; i++)
            for (int k = 0; k < _lp[i].Length && !_lcut[i]; k++)
            {
                lo = Vector3.Min(lo, _lp[i][k] - new Vector3(_lr[i][k]));
                hi = Vector3.Max(hi, _lp[i][k] + new Vector3(_lr[i][k]));
            }
    }

    /// 頭の肉を見つけて、髪を体につなぐ。地面より下へは伸ばさない
    public void Attach(Field f, float height, float waistY, float kneeY)
    {
        Head = f.Prims.First(p => p.Type == PrimType.Head);
        Yw = 0.62f + (0.53f - 0.62f) * Math.Clamp(Head.Shape, 0f, 1f);
        ChinY = Head.Pos.Y; HeadH = Head.Size.Y;
        MinEnd = (0.03f * height - Head.Pos.Y) / Head.Size.Y;
        WaistU = (waistY - ChinY) / HeadH; KneeU = (kneeY - ChinY) / HeadH; GroundU = MinEnd;
        int n = Locks.Count;
        _lp = new Vector3[n][]; _lr = new float[n][]; _lc = new Vector3[n]; _lR = new float[n]; _lcut = new bool[n];
        _ldir = new Vector3[n]; _lL = new float[n];
        for (int i = 0; i < n; i++)
        {
            int m = Locks[i].Length / 4;
            if (Locks[i][3] < 0f)
            {
                m--;
                _lcut[i] = true;
                var dv = Head.Basis.Mul(new Vector3(Locks[i][m * 4], Locks[i][m * 4 + 1], Locks[i][m * 4 + 2]));
                _ldir[i] = dv.LengthSquared() > 1e-8f ? Vector3.Normalize(dv) : new Vector3(0, 0, 1);
                _lL[i] = MathF.Abs(Locks[i][m * 4 + 3]) * HeadH;
            }
            _lp[i] = new Vector3[m]; _lr[i] = new float[m];
            var lo = new Vector3(1e9f); var hi = new Vector3(-1e9f);
            for (int k = 0; k < m; k++)
            {
                var q = FromHead(new Vector3(Locks[i][k * 4], Locks[i][k * 4 + 1], Locks[i][k * 4 + 2]));
                float rad = MathF.Abs(Locks[i][k * 4 + 3]) * HeadH;
                _lp[i][k] = q; _lr[i][k] = rad;
                lo = Vector3.Min(lo, q - new Vector3(rad)); hi = Vector3.Max(hi, q + new Vector3(rad));
                if (_lcut[i])
                {
                    var q2 = q - _ldir[i] * _lL[i];
                    lo = Vector3.Min(lo, q2 - new Vector3(rad)); hi = Vector3.Max(hi, q2 + new Vector3(rad));
                }
            }
            _lc[i] = (lo + hi) * 0.5f; _lR[i] = (hi - lo).Length() * 0.5f;
        }
        f.Hair = this;
    }
}

public sealed class Field
{
    public Hair Hair;
    public readonly List<RPrim> Prims = new();
    public readonly List<Group> Groups = new();
    public readonly List<Garment> Garments = new();
    public float Far = 0.05f, BaseFar = 0.05f, MaxThick;
    public Vector3 ArmO, ArmD;          // 左の肩の関節と、腕の向き (右は鏡)
    public float Slit;                  // 左右の脚の服のあいだのすき間 (片側)
    int[][] _kids;
    int[] _order;
    // くっつきグループの番号 (Body.GroupNames の並び): 0 胴、1 頭、2・3 腕、4・5 脚、6・7 手、8・9 足
    const int NC = 6;

    public void Finish(float margin)
    {
        float k = 0;
        foreach (var p in Prims) { p.Bound(); k = MathF.Max(k, p.Blend); }
        foreach (var g in Groups) k = MathF.Max(k, g.Join);
        BaseFar = Far = 2f * k + margin;
        int n = Groups.Count;
        _kids = new int[n][];
        for (int g = 0; g < n; g++)
            _kids[g] = Enumerable.Range(0, n).Where(c => Groups[c].Parent == g).ToArray();
        int Depth(int g) { int d = 0; while (Groups[g].Parent >= 0) { g = Groups[g].Parent; d++; } return d; }
        _order = Enumerable.Range(0, n).OrderByDescending(Depth).ToArray();
    }

    public void AddGarment(Garment g)
    {
        Garments.Add(g);
        MaxThick = MathF.Max(MaxThick, g.Thick + MathF.Max(g.Flare, g.ArmFlare));
        Far = BaseFar + MaxThick;
    }

    /// 体だけの距離。cell には「どの部分に近いか」を比べるための距離を入れる (胴・頭・左腕・右腕・左脚・右脚)
    float Body(Vector3 p, Span<float> cell, bool noArms)
    {
        int n = Groups.Count;
        Span<float> own = stackalloc float[n];
        Span<bool> has = stackalloc bool[n];
        foreach (var r in Prims)
        {
            int g = r.Group;
            if (noArms && (g == 2 || g == 3 || g == 6 || g == 7)) continue;
            if (r.Op != PrimOp.Intersect)
            {
                float dc = (p - r.BC).Length() - r.BR;
                if (dc > Far)
                {
                    // 十分遠い: 足す・削るの結果は変わらない (なめらかさの幅の外)。距離は外接球までの控えめな値で代える
                    if (r.Op == PrimOp.Add) { own[g] = has[g] ? MathF.Min(own[g], dc) : dc; has[g] = true; }
                    continue;
                }
            }
            float di = r.Distance(p);
            if (!has[g])
            {
                if (r.Op == PrimOp.Add) { own[g] = di; has[g] = true; }
                continue;
            }
            own[g] = r.Op switch
            {
                PrimOp.Add => Sd.SMin(own[g], di, r.Blend),
                PrimOp.Subtract => Sd.SSub(own[g], di, r.Blend),
                _ => Sd.SInt(own[g], di, r.Blend),
            };
        }
        Span<float> res = stackalloc float[n];
        Span<bool> hasRes = stackalloc bool[n];
        foreach (int g in _order)
        {
            float mine = own[g];
            float best = mine;
            bool any = has[g], first = true;
            foreach (int c in _kids[g])
            {
                if (!hasRes[c]) continue;
                float v = res[c];
                if (has[g])
                {
                    var gc = Groups[c];
                    float k = gc.Join;
                    if (gc.JoinR1 > 0f)
                    {
                        float t = Math.Clamp(((p - gc.JoinC).Length() - gc.JoinR0) / MathF.Max(gc.JoinR1 - gc.JoinR0, 1e-6f), 0f, 1f);
                        k *= 1f - t * t * (3f - 2f * t);
                    }
                    v = Sd.SMin(mine, v, k);
                }
                best = first ? v : MathF.Min(best, v);
                first = false;
                any = true;
            }
            res[g] = best;
            hasRes[g] = any;
        }
        float o = 1e9f;
        for (int g = 0; g < n; g++)
            if (Groups[g].Parent < 0 && hasRes[g]) o = MathF.Min(o, res[g]);
        cell[0] = has[0] ? own[0] : 1e9f;
        for (int i = 1; i < NC; i++) cell[i] = i < n && hasRes[i] ? res[i] : 1e9f;
        return o;
    }

    /// その部分がほかのどの部分よりも近ければ負 (体のまわりの空間を、部分ごとの「なわばり」に分ける)
    static float Owns(ReadOnlySpan<float> cell, int i)
    {
        float o = 1e9f;
        for (int j = 0; j < NC; j++) if (j != i) o = MathF.Min(o, cell[j]);
        return cell[i] - o;
    }

    float SkirtDist(Garment g, Vector3 p)
    {
        float hc = Math.Clamp(g.YTop - p.Y, 0f, g.YTop - g.YBot);
        float a = g.RxT + g.RxS * hc;
        float zf = g.ZfT + g.ZfS * hc, zb = g.ZbT - g.ZbS * hc;
        float b = (zf - zb) * 0.5f, zc = (zf + zb) * 0.5f;
        float kx = p.X / a, kz = (p.Z - zc) / b;
        float side = (MathF.Sqrt(kx * kx + kz * kz) - 1f) * MathF.Min(a, b);
        return MathF.Max(side, MathF.Max(p.Y - g.YTop, g.YBot - p.Y));
    }

    /// 服の上の端より上なら正 (えりぐり)
    static float Top(Garment g, Vector3 p)
    {
        float top = p.Y - g.YTop;
        if (g.NeckSlope <= 0f) return top;
        float dz = p.Z - g.NeckZ;
        float r = MathF.Sqrt(p.X * p.X + dz * dz);
        return (top - g.NeckSlope * MathF.Max(0f, r - g.NeckR)) / MathF.Sqrt(1f + g.NeckSlope * g.NeckSlope);
    }

    /// 服 1 枚の距離: 体をその厚みだけ外へふくらませたものを、服の範囲で切る。
    /// 体そのものをふくらませるので、体の面は必ず服の内側 (肌が服から出ない)
    float GarmentDist(Garment g, Vector3 p, float body, ReadOnlySpan<float> cell, bool noArms)
    {
        if (g.Kind == 3) return SkirtDist(g, p);
        float best = 1e9f;
        if (g.Kind == 0)
        {
            float slab = MathF.Max(Top(g, p), g.YBot - p.Y);
            float u = Math.Clamp((g.YTop - p.Y) / MathF.Max(g.YTop - MathF.Max(g.YBot, 0f), 1e-4f), 0f, 1f);
            float inner = body - (g.Thick + g.Flare * u);
            best = MathF.Max(inner, MathF.Max(slab, Owns(cell, 0)));
            // 脚: 左右の服がくっついて 1 本にならないよう、真ん中にすき間を残す
            best = MathF.Min(best, MathF.Max(inner, MathF.Max(slab, MathF.Max(Owns(cell, 4), Slit - p.X))));
            best = MathF.Min(best, MathF.Max(inner, MathF.Max(slab, MathF.Max(Owns(cell, 5), Slit + p.X))));
        }
        if (g.HasArm && !noArms)
        {
            for (int side = 0; side < 2; side++)
            {
                var o = side == 0 ? ArmO : new Vector3(-ArmO.X, ArmO.Y, ArmO.Z);
                var d = side == 0 ? ArmD : new Vector3(-ArmD.X, ArmD.Y, ArmD.Z);
                float sl = Vector3.Dot(p - o, d);
                float clip = MathF.Max(g.ArmFrom - sl, sl - g.ArmTo);
                float u = Math.Clamp((sl - g.ArmU0) / g.ArmSpan, 0f, 1f);
                if (g.Kind == 0) clip = MathF.Max(clip, Top(g, p));
                float v = MathF.Max(body - (g.Thick + g.ArmFlare * u), MathF.Max(clip, Owns(cell, 2 + side)));
                best = MathF.Min(best, v);
            }
        }
        return best;
    }

    float Full(Vector3 p, bool noArms, float eps, out int mat, out int skirt)
    {
        Span<float> cell = stackalloc float[NC];
        float body = Body(p, cell, noArms);
        mat = 0; skirt = -1;
        float d = body;
        for (int i = 0; i < Garments.Count; i++)
        {
            float gd = GarmentDist(Garments[i], p, body, cell, noArms);
            if (gd < d) d = gd;
            // 色は「ここをおおっている、いちばん上 (並びの後ろ) の服」。厚みの大小では決めない
            if (gd < eps) { mat = i + 1; skirt = Garments[i].Kind == 3 ? i : -1; }
        }
        if (Hair != null && !noArms)
        {
            // 髪: 素材は服の次の番号。skirt = -2 が「髪」の印。腕のめり込みを測るとき (noArms) は入れない:
            // 長い髪を腕がよけると、腕が真横に開いてしまう。髪には腕が重なってよい
            float hd = Hair.Distance(p);
            if (hd < d) d = hd;
            if (hd < eps) { mat = Garments.Count + 1; skirt = -2; }
        }
        return d;
    }

    public float Eval(Vector3 p) => Full(p, false, -1e9f, out _, out _);

    /// 服を除いた、体だけの距離 (その点で服がどれだけ厚いかを知るのに使う)
    public float EvalBody(Vector3 p)
    {
        Span<float> cell = stackalloc float[NC];
        return Body(p, cell, false);
    }

    /// 腕を除いた形 (腕が胴や服に入っていないかを測るのに使う)
    public float EvalNoArms(Vector3 p) => Full(p, true, -1e9f, out _, out _);

    /// 面の上の点が、どの素材 (0 = 肌、i + 1 = 服 i) か。すその上なら skirt にその服の番号
    public void Classify(Vector3 p, float eps, out int mat, out int skirt) => Full(p, false, eps, out mat, out skirt);

    public Vector3 Gradient(Vector3 p, float h)
    {
        var g = new Vector3(
            Eval(new Vector3(p.X + h, p.Y, p.Z)) - Eval(new Vector3(p.X - h, p.Y, p.Z)),
            Eval(new Vector3(p.X, p.Y + h, p.Z)) - Eval(new Vector3(p.X, p.Y - h, p.Z)),
            Eval(new Vector3(p.X, p.Y, p.Z + h)) - Eval(new Vector3(p.X, p.Y, p.Z - h)));
        return g / (2f * h);
    }

    /// 骨ごとの「その骨の肉までの距離」(足す肉だけ)。重みと部品の番号に使う
    public void BoneDistance(Vector3 p, Span<float> dist)
    {
        dist.Fill(1e9f);
        foreach (var r in Prims)
        {
            if (r.Op != PrimOp.Add || r.Bone < 0) continue;
            float dc = (p - r.BC).Length() - r.BR;
            if (dc > dist[r.Bone]) continue;
            float d = r.Distance(p);
            if (d < dist[r.Bone]) dist[r.Bone] = d;
        }
    }

    public (Vector3 lo, Vector3 hi) Bounds()
    {
        var lo = new Vector3(1e9f);
        var hi = new Vector3(-1e9f);
        foreach (var r in Prims)
        {
            if (r.Op != PrimOp.Add) continue;
            lo = Vector3.Min(lo, r.BC - new Vector3(r.BR));
            hi = Vector3.Max(hi, r.BC + new Vector3(r.BR));
        }
        lo -= new Vector3(MaxThick); hi += new Vector3(MaxThick);
        if (Hair != null) Hair.LockBounds(ref lo, ref hi);
        if (Hair != null && Hair.Shell)
        {
            var hp = Hair.Head;
            float hr = (0.62f + Hair.Vol + Hair.Puff) * MathF.Max(hp.Size.X, hp.Size.Z) + 0.1f * hp.Size.Z;
            float hEnd = MathF.Max(Hair.MinEnd, Hair.Map(MathF.Max(Hair.Side, Hair.Back))) - 0.1f;
            lo = Vector3.Min(lo, new Vector3(-hr, hp.Pos.Y + hEnd * hp.Size.Y, hp.Pos.Z - hr));
            hi = Vector3.Max(hi, new Vector3(hr, hp.Pos.Y + (1.05f + Hair.Vol + Hair.Puff) * hp.Size.Y, hp.Pos.Z + hr));
        }
        foreach (var g in Garments)
        {
            if (g.Kind != 3) continue;
            float L = g.YTop - g.YBot;
            float rx = g.RxT + g.RxS * L;
            lo = Vector3.Min(lo, new Vector3(-rx, g.YBot, g.ZbT - g.ZbS * L));
            hi = Vector3.Max(hi, new Vector3(rx, g.YTop, g.ZfT + g.ZfS * L));
        }
        return (lo, hi);
    }
}

/// 三面図で作る頭 (low-Godough core/head.py の HeadModel)。正面と横の輪郭線から、どの高さの輪切りも
/// 「その高さの正面の幅 × 横の奥行き」に収まる卵形にする。座標は頭の高さを 1: y = 0 があご先の下、1 がてっぺん。
public sealed class HeadModel
{
    const int N = 384;
    readonly float[] _w = new float[N], _xc = new float[N], _zb = new float[N], _zf = new float[N];
    readonly float _y0, _y1, _egg, _fp, _bp, _eggMax;

    // 正面 (x, y) の右半分・横 (z, y)。ふつうの頭 = low-Godough の「アニメ 少女」(ユーザーが作った輪郭)
    static readonly float[,] FrontHalf = {
        {0f, 1f}, {0.17f, 0.98f}, {0.27343f, 0.90851f}, {0.34578f, 0.8f}, {0.375f, 0.65f}, {0.37f, 0.5f}, {0.355f, 0.4f},
        {0.33f, 0.3f}, {0.28973f, 0.19876f}, {0.18125f, 0.11118f}, {0.09224f, 0.0479f}, {0f, 0f} };
    static readonly float[,] Side = {
        {0.2f, 0f}, {0.245f, 0.045f}, {0.265f, 0.12f}, {0.285f, 0.2f}, {0.3f, 0.27f}, {0.31f, 0.4f}, {0.33f, 0.53f},
        {0.315f, 0.66f}, {0.255f, 0.8f}, {0.13f, 0.935f}, {-0.05f, 1f}, {-0.25f, 0.975f}, {-0.42f, 0.87f}, {-0.52f, 0.69f},
        {-0.535f, 0.5f}, {-0.49f, 0.34f}, {-0.4f, 0.22f}, {-0.28f, 0.15f}, {-0.13f, 0.12f}, {0.02f, 0.06f}, {0.12f, 0.015f} };
    // ちび: まんじゅう形。上は楕円どおりに丸く (角ばらせない)、いちばん広いのは真ん中より少し下、
    // ほっぺたは楕円より少しふくらませ、あごはとがらせない (上が大きく下がすぼまると宇宙人に見える)
    static readonly float[,] ChibiFrontHalf = {
        {0f, 1f}, {0.15f, 0.972f}, {0.27f, 0.900f}, {0.345f, 0.795f}, {0.390f, 0.665f}, {0.402f, 0.530f}, {0.397f, 0.410f},
        {0.375f, 0.295f}, {0.335f, 0.180f}, {0.260f, 0.085f}, {0.160f, 0.025f}, {0.070f, 0.004f}, {0f, 0f} };
    static readonly float[,] ChibiSide = {
        {0.100f, 0f}, {0.200f, 0.035f}, {0.270f, 0.115f}, {0.310f, 0.240f}, {0.322f, 0.390f}, {0.312f, 0.530f}, {0.280f, 0.670f},
        {0.210f, 0.800f}, {0.100f, 0.915f}, {-0.040f, 0.982f}, {-0.165f, 0.993f}, {-0.290f, 0.940f}, {-0.396f, 0.835f},
        {-0.466f, 0.690f}, {-0.490f, 0.525f}, {-0.470f, 0.365f}, {-0.410f, 0.225f}, {-0.310f, 0.115f}, {-0.185f, 0.045f},
        {-0.050f, 0.012f}, {0.030f, 0.002f} };

    static readonly Lazy<HeadModel> Normal = new(() => new HeadModel(Mirror(FrontHalf), Pts(Side), 0.16f, 2.7f, 2.1f));
    static readonly Lazy<HeadModel> Chibi = new(() => new HeadModel(Mirror(ChibiFrontHalf), Pts(ChibiSide), 0.04f, 2.08f, 2.0f));

    static Vector2[] Pts(float[,] a)
    {
        var o = new Vector2[a.GetLength(0)];
        for (int i = 0; i < o.Length; i++) o[i] = new Vector2(a[i, 0], a[i, 1]);
        return o;
    }

    static Vector2[] Mirror(float[,] half)
    {
        var h = Pts(half);
        var o = new List<Vector2>(h);
        for (int i = h.Length - 2; i >= 1; i--) o.Add(new Vector2(-h[i].X, h[i].Y));
        return o.ToArray();
    }

    static Vector2[] CatmullClosed(Vector2[] pts, int per)
    {
        int n = pts.Length;
        var o = new Vector2[n * per];
        for (int i = 0; i < n; i++)
        {
            var p0 = pts[(i - 1 + n) % n]; var p1 = pts[i]; var p2 = pts[(i + 1) % n]; var p3 = pts[(i + 2) % n];
            for (int k = 0; k < per; k++)
            {
                float t = k / (float)per, t2 = t * t, t3 = t2 * t;
                o[i * per + k] = 0.5f * (2f * p1 + (-p0 + p2) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 + (-p0 + 3f * p1 - 3f * p2 + p3) * t3);
            }
        }
        return o;
    }

    static void Spans(Vector2[] poly, float y, out float lo, out float hi)
    {
        lo = float.PositiveInfinity; hi = float.NegativeInfinity;
        for (int i = 0; i < poly.Length; i++)
        {
            var p = poly[i]; var q = poly[(i + 1) % poly.Length];
            if ((p.Y - y) * (q.Y - y) > 0 || p.Y == q.Y) continue;
            float x = p.X + (q.X - p.X) * ((y - p.Y) / (q.Y - p.Y));
            lo = MathF.Min(lo, x); hi = MathF.Max(hi, x);
        }
    }

    HeadModel(Vector2[] frontClosed, Vector2[] sideClosed, float egg, float fp, float bp)
    {
        var front = CatmullClosed(frontClosed, 12);
        var side = CatmullClosed(sideClosed, 12);
        _y0 = MathF.Max(front.Min(p => p.Y), side.Min(p => p.Y)) + 1e-4f;
        _y1 = MathF.Min(front.Max(p => p.Y), side.Max(p => p.Y)) - 1e-4f;
        _egg = egg; _fp = fp; _bp = bp;
        for (int i = 0; i < N; i++)
        {
            float y = _y0 + (_y1 - _y0) * i / (N - 1);
            Spans(front, y, out float x0, out float x1);
            if (x1 >= x0) { _w[i] = MathF.Max(0, (x1 - x0) * 0.5f); _xc[i] = (x0 + x1) * 0.5f; }
            Spans(side, y, out float z0, out float z1);
            if (z1 >= z0) { _zb[i] = z0; _zf[i] = z1; }
            else if (i > 0) { _zb[i] = _zb[i - 1]; _zf[i] = _zf[i - 1]; }
        }
        float m = 0;
        for (int i = 0; i <= 400; i++) m = MathF.Max(m, HalfWidth(-1f + 2f * i / 400f));
        _eggMax = m;
    }

    float HalfWidth(float u)
    {
        float n = u > 0 ? _fp : _bp;
        return MathF.Pow(MathF.Max(1f - MathF.Pow(MathF.Abs(u), n), 0f), 1f / n) * (1f - _egg * u);
    }

    void Section(float y, out float a, out float b, out float zc, out float xc)
    {
        float f = (y - _y0) / (_y1 - _y0) * (N - 1);
        int i = Math.Clamp((int)f, 0, N - 2);
        float t = Math.Clamp(f - i, 0f, 1f);
        a = MathF.Max(_w[i] + (_w[i + 1] - _w[i]) * t, 1e-3f);
        float zf = _zf[i] + (_zf[i + 1] - _zf[i]) * t, zb = _zb[i] + (_zb[i + 1] - _zb[i]) * t;
        b = MathF.Max((zf - zb) * 0.5f, 1e-3f);
        zc = (zf + zb) * 0.5f;
        xc = _xc[i] + (_xc[i + 1] - _xc[i]) * t;
    }

    float FieldAt(float x, float y, float z)
    {
        Section(y, out float a, out float b, out float zc, out float xc);
        float u = (z - zc) / b;
        float n = u > 0 ? _fp : _bp;
        float s = (1f - _egg * Math.Clamp(u, -1f, 1f)) / _eggMax;
        return MathF.Pow(MathF.Pow(MathF.Abs((x - xc) / (a * s)), n) + MathF.Pow(MathF.Abs(u), n), 1f / n) - 1f;
    }

    /// 高さ y の輪切りの中での横方向の距離 (内側が負)
    float Slice(float x, float y, float z)
    {
        Section(y, out float a, out float b, out float zc, out float xc);
        float u = (z - zc) / b;
        float n = u > 0 ? _fp : _bp;
        float sa = a * (1f - _egg * Math.Clamp(u, -1f, 1f)) / _eggMax;
        float X = MathF.Abs(x - xc) / sa, U = MathF.Abs(u);
        float k = MathF.Pow(MathF.Pow(X, n) + MathF.Pow(U, n), 1f / n);
        if (k < 1e-6f) return -MathF.Min(sa, b);
        float kp = MathF.Pow(k, 1f - n);
        float gx = kp * MathF.Pow(X, n - 1f) / sa;
        float gz = kp * MathF.Pow(U, n - 1f) / b;
        float d = (k - 1f) / MathF.Max(MathF.Sqrt(gx * gx + gz * gz), 1e-6f);
        if (k > 1f)
        {
            float bx = MathF.Max(MathF.Abs(x - xc) - a, 0f), bz = MathF.Max(MathF.Abs(z - zc) - b, 0f);
            d = MathF.Max(d, MathF.Sqrt(bx * bx + bz * bz));
        }
        return d;
    }

    static float Hyp(float a, float b) => MathF.Sqrt(a * a + b * b);

    float Dist(Vector3 q)
    {
        float x = q.X, yq = q.Y, z = q.Z;
        float y = Math.Clamp(yq, _y0, _y1);
        float d0 = Slice(x, y, z);
        if (d0 < 0 && y == yq)
        {
            const float h = 0.002f;
            float g = FieldAt(x, y, z);
            float gx = FieldAt(x + h, y, z) - g;
            float gz = FieldAt(x, y, z + h) - g;
            bool up = y + h <= _y1;
            float gy = (FieldAt(x, up ? y + h : y - h, z) - g) * (up ? 1f : -1f);
            return MathF.Max(g / MathF.Max(MathF.Sqrt(gx * gx + gy * gy + gz * gz) / h, 1e-3f), d0);
        }
        float best = Hyp(MathF.Max(d0, 0f), yq - y);
        float lo = MathF.Max(_y0, yq - best), hi = MathF.Min(_y1, yq + best);
        if (hi <= lo) return best;
        // 粗く見てから、いちばん近かった輪切りのまわりを細かく
        const int coarse = 12, fine = 6;
        float bestY = y;
        for (int i = 0; i <= coarse; i++)
        {
            float yy = lo + (hi - lo) * i / coarse;
            float c = Hyp(MathF.Max(Slice(x, yy, z), 0f), yq - yy);
            if (c < best) { best = c; bestY = yy; }
        }
        float step = (hi - lo) / coarse;
        for (int i = -fine; i <= fine; i++)
        {
            float yy = Math.Clamp(bestY + step * i / fine, _y0, _y1);
            best = MathF.Min(best, Hyp(MathF.Max(Slice(x, yy, z), 0f), yq - yy));
        }
        return best;
    }

    /// 頭の単位での距離。shape = 0 ふつう 〜 1 ちび (あいだは距離を混ぜる)
    public static float Distance(Vector3 q, float shape)
    {
        shape = Math.Clamp(shape, 0f, 1f);
        if (shape <= 0f) return Normal.Value.Dist(q);
        if (shape >= 1f) return Chibi.Value.Dist(q);
        return Normal.Value.Dist(q) * (1f - shape) + Chibi.Value.Dist(q) * shape;
    }
}
