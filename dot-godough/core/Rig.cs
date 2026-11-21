// 人体の骨と肉。low-Godough の core/rig.py・core/body.py を移して、ドット絵のキャラ向けに広げたもの。
// - 骨の置き方 (身長・頭身 → 目印の高さ) は low-Godough と同じ式。だから 6 頭身では low-Godough の体になる
// - 2〜3 頭身 (ドット絵のキャラ) まで下げられるよう、頭身ごとの体型の表 (Curve) を足した
// - 手はミトン、足は丸いかたまり (ドット絵では数画素なので、指は作らない)
// 数値の根拠は docs/PROPORTIONS.md。
using System.Numerics;

namespace DotGodough.Core;

public sealed class Bone
{
    public string Name = "";
    public int Parent = -1;
    public Mat3 Basis;         // 列が X, Y (根元→先), Z (≒ 前)
    public Vector3 Origin;
    public float Length, GirthX, GirthZ;
    public float Girth => (GirthX + GirthZ) * 0.5f;
    public Vector3 Tail => Origin + Basis.Y * Length;
}

public sealed class Landmarks
{
    public float H, HeadH, B, Crotch, HipJoint, Knee, Ankle, Waist, RibBottom, Shoulder, Chin, ShoulderWidth, HipWidth, G;
}

public static class Rig
{
    public static readonly string[] Order = {
        "hips", "spine", "chest", "neck", "head",
        "shoulder.L", "upper_arm.L", "forearm.L", "hand.L",
        "thumb1.L", "thumb2.L", "index1.L", "index2.L", "middle1.L", "middle2.L", "ring1.L", "ring2.L", "pinky1.L", "pinky2.L",
        "thigh.L", "shin.L", "foot.L",
        "shoulder.R", "upper_arm.R", "forearm.R", "hand.R",
        "thumb1.R", "thumb2.R", "index1.R", "index2.R", "middle1.R", "middle2.R", "ring1.R", "ring2.R", "pinky1.R", "pinky2.R",
        "thigh.R", "shin.R", "foot.R",
    };

    public static readonly Dictionary<string, int> Index = Order.Select((n, i) => (n, i)).ToDictionary(t => t.n, t => t.i);

    // 体型の数値と既定値 (アニメ 少女 6 頭身 = low-Godough の既定)
    public static readonly (string key, float def, float min, float max)[] Params = {
        ("height", 1.55f, 0.4f, 2.2f), ("heads", 6f, 1.8f, 9f), ("sex", 1f, 0f, 1f),
        ("leg", 0.59f, 0.3f, 0.7f), ("neck", 0.07f, 0f, 0.15f),
        ("shoulder", 1f, 0.5f, 4f), ("hip", 0.87f, 0.5f, 3f), ("arm", 1f, 0.5f, 1.5f),
        ("thickness", 0.88f, 0.5f, 2.6f), ("depth", 1f, 0.5f, 2.5f), ("belly", 1f, 0.6f, 2f), ("arm_thick", 1f, 0.5f, 2f), ("leg_thick", 1f, 0.5f, 2f),
        ("taper", 0f, -0.3f, 1f),
        ("hand", 1f, 0.5f, 2f), ("foot", 1f, 0.5f, 2f),
        ("head_w", 1f, 0.7f, 1.5f), ("head_d", 1f, 0.7f, 1.5f), ("chibi", -1f, -1f, 1f),
        ("arm_angle", 45f, 0f, 90f), ("leg_angle", 0f, 0f, 25f), ("bust", 0.6f, 0f, 2f),
    };

    // 頭身ごとの体型の表: heads, height, leg, neck, thickness, shoulder, hip, arm, hand, foot, head_w, arm_thick, leg_thick, depth, belly
    // 6 頭身以上は low-Godough のひな形。それより下はドット絵のキャラの比率 (docs/PROPORTIONS.md):
    // 胴の幅は頭の幅の 0.55〜0.65、肩の関節は胴の横の面のすぐ外 (腕を下ろしても胴に埋まらない)、手足は短く太く
    static readonly float[][] Curve = {
        new[] {2.0f, 0.80f, 0.40f, 0.075f, 1.52f, 2.45f, 1.42f, 0.78f, 1.05f, 1.50f, 1.05f, 1.30f, 1.35f, 1.55f, 1.04f},
        new[] {2.5f, 0.90f, 0.42f, 0.070f, 1.38f, 2.05f, 1.32f, 0.82f, 1.08f, 1.40f, 1.04f, 1.20f, 1.22f, 1.40f, 1.03f},
        new[] {3.0f, 1.00f, 0.45f, 0.065f, 1.22f, 1.62f, 1.22f, 0.88f, 1.10f, 1.28f, 1.03f, 1.10f, 1.10f, 1.25f, 1.02f},
        new[] {4.0f, 1.10f, 0.48f, 0.060f, 1.13f, 1.40f, 1.15f, 1.00f, 1.15f, 1.15f, 1.00f, 1.00f, 1.00f, 1.12f, 1.00f},
        new[] {5.0f, 1.20f, 0.50f, 0.060f, 1.05f, 1.15f, 1.00f, 1.00f, 1.10f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f},
        new[] {6.0f, 1.55f, 0.59f, 0.070f, 0.88f, 1.00f, 0.87f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f},
        new[] {7.5f, 1.68f, 0.54f, 0.062f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f},
        new[] {8.0f, 1.80f, 0.56f, 0.060f, 1.00f, 1.05f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f, 1.00f},
    };
    static readonly string[] CurveKeys = { "heads", "height", "leg", "neck", "thickness", "shoulder", "hip", "arm", "hand", "foot", "head_w", "arm_thick", "leg_thick", "depth", "belly" };

    /// その頭身の「ふつうの体型」(頭身のスライダーで、ほかの数値もいっしょに動かすときに使う)
    public static Dictionary<string, float> ForHeads(float heads)
    {
        heads = Math.Clamp(heads, Curve[0][0], Curve[^1][0]);
        int i = 0;
        while (i < Curve.Length - 2 && heads > Curve[i + 1][0]) i++;
        float t = (heads - Curve[i][0]) / (Curve[i + 1][0] - Curve[i][0]);
        var o = new Dictionary<string, float>();
        for (int k = 1; k < CurveKeys.Length; k++) o[CurveKeys[k]] = Curve[i][k] + (Curve[i + 1][k] - Curve[i][k]) * t;
        o["heads"] = heads;
        return o;
    }

    public static Dictionary<string, float> Defaults() => Params.ToDictionary(p => p.key, p => p.def);

    static float Lerp(float a, float b, float t) => a + (b - a) * t;

    public static Landmarks Measure(Dictionary<string, float> s)
    {
        var m = new Landmarks();
        m.H = MathF.Max(s["height"], 0.1f);
        float heads = Math.Clamp(s["heads"], 1.5f, 10f);
        m.HeadH = m.H / heads;
        m.B = m.H - m.HeadH;
        float B = m.B, sex = Math.Clamp(s["sex"], 0f, 1f);
        m.Chin = B;
        m.Shoulder = B * (1f - Math.Clamp(s["neck"], 0f, 0.25f));
        m.Crotch = MathF.Min(Math.Clamp(s["leg"], 0.2f, 0.8f) * B, m.Shoulder - 0.12f * B);
        float T = m.Shoulder - m.Crotch;
        m.HipJoint = m.Crotch + 0.175f * T;
        m.Waist = m.Crotch + 0.425f * T;
        m.RibBottom = m.Crotch + 0.6f * T;
        m.Knee = m.Crotch * (0.328f / 0.54f);
        m.Ankle = m.Crotch * (0.045f / 0.54f);
        m.ShoulderWidth = B * Lerp(0.298f, 0.27f, sex) * s["shoulder"];
        m.HipWidth = B * Lerp(0.22f, 0.24f, sex) * s["hip"];
        m.G = B * s["thickness"] * Lerp(1f, 0.93f, sex);
        return m;
    }

    /// ちびの頭にどれだけ寄せるか: 5.5 頭身以上で 0、2.5 頭身で 1 (chibi が 0 以上ならその値)
    public static float ChibiShape(Dictionary<string, float> s)
    {
        if (s["chibi"] >= 0f) return Math.Clamp(s["chibi"], 0f, 1f);
        return Math.Clamp((5.5f - s["heads"]) / 3f, 0f, 1f);
    }

    /// 頭の幅・奥行き (頭の高さに対する比)。6 頭身以上は同じ頭、それより下は広げる
    public static (float w, float d) HeadProportions(Dictionary<string, float> s)
    {
        float r = Math.Clamp((Math.Clamp(s["heads"], 1.5f, 10f) - 2.5f) / 3.5f, 0f, 1f);
        return (Lerp(0.95f, 0.81f, r) * s["head_w"], Lerp(0.95f, 0.886f, r) * s["head_d"]);
    }

    public static float MorphScale(Dictionary<string, float> s, string morph)
    {
        switch (morph)
        {
            case "bust": return Math.Clamp(s["sex"], 0f, 1.5f) * Math.Clamp(s["bust"], 0f, 2f) * (1f - 0.8f * ChibiShape(s));
            case "nose": return s["heads"] < 3.5f ? 0f : Lerp(0.7f, 0.81f, Math.Clamp((s["heads"] - 3.5f) / 2.5f, 0f, 1f));
            // 筋肉のふくらみなどの細部: ちびに近づくほど無くす (小さい絵では、でこぼこは汚れに見える)
            case "detail": return 1f - ChibiShape(s);
            // 肩の丸み (三角筋): 太さで大きさが決まるので、腕が短くて太いちびでは腕のつけ根より上にはみ出して、
            // 肩が首のつけ根より高く盛り上がる → ちびでは小さくする
            case "ball": return Lerp(1f, 0.5f, ChibiShape(s));
            default: return 1f;
        }
    }

    static readonly (string name, float y0, float z0, float len, float spread)[] Fingers = {
        ("index", 0.56f, 0.0195f, 0.4f, 1f), ("middle", 0.57f, 0.0054f, 0.43f, 0f),
        ("ring", 0.56f, -0.0083f, 0.4f, -1f), ("pinky", 0.53f, -0.0206f, 0.32f, -2f),
    };

    public static string Partner(string b) =>
        b.EndsWith(".L") ? b[..^2] + ".R" : b.EndsWith(".R") ? b[..^2] + ".L" : b;

    /// 基本姿勢 (ポーズなし) の骨。並びは Order
    public static Bone[] Build(Dictionary<string, float> s)
    {
        var m = Measure(s);
        float B = m.B, G = m.G, T = m.Shoulder - m.Crotch;
        float sex = Math.Clamp(s["sex"], 0f, 1f);
        var bones = new Dictionary<string, Bone>();
        var fwd = Vector3.UnitZ;
        var down = -Vector3.UnitY;

        void Add(string name, string parent, Vector3 a, Vector3 b, Vector3 refZ, float gx, float gz)
        {
            bones[name] = new Bone { Name = name, Parent = parent == "" ? -1 : Index[parent], Basis = Mat3.Frame(b - a, refZ),
                                     Origin = a, Length = (b - a).Length(), GirthX = gx, GirthZ = gz };
        }

        float hipGx = G * m.HipWidth / (0.22f * B);
        float chestGx = G * MathF.Pow(m.ShoulderWidth / (0.298f * B), 0.6f);
        float Gz = G * s["depth"];   // 胴の前後の厚み (ちびは幅だけでなく厚みも足す)
        Add("hips", "", new(0, m.HipJoint, 0), new(0, m.Waist, 0), fwd, hipGx, Gz);
        Add("spine", "hips", new(0, m.Waist, 0), new(0, m.RibBottom, 0), fwd, Lerp(1f, 0.94f, sex) * MathF.Pow(hipGx * chestGx, 0.5f) * s["belly"], Gz * s["belly"]);
        Add("chest", "spine", new(0, m.RibBottom, 0), new(0, m.Shoulder, 0), fwd, chestGx, Gz);
        float neckTop = m.Chin + 0.15f * m.HeadH;
        float neckG = G * Lerp(0.86f, 1f, sex);
        Add("neck", "chest", new(0, m.Shoulder, -0.02f * B), new(0, neckTop, -0.12f * m.HeadH), fwd, neckG, neckG);
        var (hw, hd) = HeadProportions(s);
        Add("head", "neck", new(0, m.Chin, 0), new(0, m.H, 0), fwd, m.HeadH * hw / 0.75f, m.HeadH * hd / 0.85f);

        // 左腕 (+X が左)。長さは胴の長さ T が基準
        float armLen = s["arm"];
        float upper = 0.535f * T * armLen, fore = 0.42f * T * armLen;
        float hand = (0.155f * T + 0.062f * B) * armLen * s["hand"];
        var clavA = new Vector3(0.015f * B, m.Shoulder - 0.02f * B, 0);
        // ちびは なで肩: 腕のつけ根を首のつけ根より下げる (下げないと、太い腕の上の面が首のつけ根より高くなる)
        var shoulderJ = new Vector3(m.ShoulderWidth / 2 - 0.04f * G, m.Shoulder - (0.012f + 0.035f * ChibiShape(s)) * B, 0);
        float th = Math.Clamp(s["arm_angle"], 0f, 90f) * MathF.PI / 180f;
        var armDir = new Vector3(MathF.Sin(th), -MathF.Cos(th), 0);
        var elbow = shoulderJ + armDir * upper;
        var wrist = elbow + armDir * fore;
        var tip = wrist + armDir * hand;
        float ag = G * s["arm_thick"];
        Add("shoulder.L", "chest", clavA, shoulderJ, fwd, G, G);
        Add("upper_arm.L", "shoulder.L", shoulderJ, elbow, fwd, ag, ag);
        Add("forearm.L", "upper_arm.L", elbow, wrist, fwd, ag, ag);
        Add("hand.L", "forearm.L", wrist, tip, fwd, ag * s["hand"], ag * s["hand"]);

        // 指の骨 (肉はミトンなので重みは無い。penInk の骨の並びに合わせて置くだけ)
        var hb = bones["hand.L"];
        float hg = hb.GirthX;
        Vector3 Hp(float x, float y, float z) => hb.Origin + hb.Basis.Mul(new Vector3(x * hg, y * hand, z * hg));
        foreach (var (name, y0, z0, ln, spread) in Fingers)
        {
            var root = Hp(0, y0, z0);
            var d = Vector3.Normalize(hb.Basis.Y + hb.Basis.Z * MathF.Tan(spread * MathF.PI / 180f));
            var mid = root + d * (ln * 0.5f * hand);
            Add(name + "1.L", "hand.L", root, mid, hb.Basis.Z, hg, hg);
            Add(name + "2.L", name + "1.L", mid, root + d * (ln * hand), hb.Basis.Z, hg, hg);
        }
        var tRoot = Hp(0.004f, 0.12f, 0.014f);
        var tDir = Vector3.Normalize(hb.Basis.Y * 0.85f + hb.Basis.Z * 0.33f + hb.Basis.X * 0.4f);
        var tMid = tRoot + tDir * (0.23f * hand);
        Add("thumb1.L", "hand.L", tRoot, tMid, hb.Basis.X, hg, hg);
        Add("thumb2.L", "thumb1.L", tMid, tMid + tDir * (0.21f * hand), hb.Basis.X, hg, hg);

        // 左脚。基本姿勢で少し開ける (leg_angle): ちびの太い脚がくっつかないように
        float hipX = m.HipWidth / 2 - 0.055f * G;
        float la = Math.Clamp(s["leg_angle"], 0f, 30f) * MathF.PI / 180f;
        var hipJ = new Vector3(hipX, m.HipJoint, 0);
        var knee = new Vector3(hipX * 0.85f, m.Knee, 0);
        var ankle = new Vector3(hipX * 0.8f, m.Ankle, 0);
        if (la > 0f)
        {
            // 股関節のまわりに、足首の高さは変えずに外へ
            knee.X += (m.HipJoint - m.Knee) * MathF.Tan(la);
            ankle.X += (m.HipJoint - m.Ankle) * MathF.Tan(la);
        }
        float footLen = 0.175f * B * s["foot"];
        var toe = new Vector3(ankle.X + 0.1f * footLen, m.Ankle, 0.75f * footLen);
        float lg = G * s["leg_thick"];
        Add("thigh.L", "hips", hipJ, knee, fwd, lg, lg);
        Add("shin.L", "thigh.L", knee, ankle, fwd, lg, lg);
        Add("foot.L", "shin.L", ankle, toe, down, lg * s["foot"], m.Ankle / 0.045f);

        // 右 = 左の鏡
        foreach (var n in Order.Where(n => n.EndsWith(".L")))
        {
            var l = bones[n];
            string pn = l.Parent < 0 ? "" : Order[l.Parent];
            bones[Partner(n)] = new Bone {
                Name = Partner(n), Parent = pn == "" ? -1 : Index[pn.EndsWith(".L") ? Partner(pn) : pn],
                Basis = l.Basis.Mirrored, Origin = new Vector3(-l.Origin.X, l.Origin.Y, l.Origin.Z),
                Length = l.Length, GirthX = l.GirthX, GirthZ = l.GirthZ };
        }
        return Order.Select(n => bones[n]).ToArray();
    }
}

/// 肉 1 つのひな形 (骨基準の値)。位置 y と (Stretch なら) 大きさ y は骨の長さを 1、それ以外は骨の太さを 1 とした値。
/// Meters なら骨の枠の中のメートル。
public sealed class Flesh
{
    public string Name = "", Bone = "", Group = "", Morph = "";
    public PrimType Type = PrimType.Sphere;
    public PrimOp Op = PrimOp.Add;
    public Vector3 Pos, Size;
    public float Blend, Round;
    public bool Stretch = true, Sym = true, Meters;
    public Vector3? Aim;
    public bool AllowFar;   // 遠くにあってもよい (削る箱など)
}

/// 服 1 枚の設計 (画面の数値そのまま)
public sealed class GarmentSpec
{
    public string Kind = "body";     // body (胴と脚、そでつきにもできる) / arm (腕だけ) / skirt (すそ)
    public float From, To, Thick, Flare, Sleeve, SleeveFlare, Follow = 0.8f;
}

public static class Body
{
    public static readonly string[] GroupNames = { "", "head", "arm.L", "arm.R", "leg.L", "leg.R", "hand.L", "hand.R", "foot.L", "foot.R" };
    static readonly (string parent, float join)[] GroupDefs = {
        ("", 0f), ("", 0.018f), ("", 0.04f), ("", 0.04f), ("", 0.04f), ("", 0.04f),
        ("arm.L", 0.012f), ("arm.R", 0.012f), ("leg.L", 0.02f), ("leg.R", 0.02f),
    };

    static Vector3 V(float x, float y, float z) => new(x, y, z);

    /// 肉のひな形。胴・首・腕・脚は low-Godough の core/body.py の flesh() と同じ値
    static List<Flesh> Template(Dictionary<string, float> s, Landmarks m, float cell)
    {
        var L = new List<Flesh>();
        float taper = s["taper"];
        // 先細り: 0 = low-Godough のまま。+ で手首・足首のほうを太く (ドット絵のキャラの「先太り」の手足)
        float F(float t) => 1f + taper * t;

        void Add(string name, string bone, PrimType type, Vector3 pos, Vector3 size, float blend, string group = "",
                 bool stretch = true, Vector3? aim = null, string morph = "")
        {
            L.Add(new Flesh { Name = name, Bone = bone, Type = type, Pos = pos, Size = size, Blend = blend, Group = group,
                              Stretch = stretch, Aim = aim, Morph = morph });
        }

        // 胴
        Add("骨盤", "hips", PrimType.Sphere, V(0, 0.3f, -0.005f), V(0.1f, 0.95f, 0.07f), 0f);
        Add("お尻", "hips", PrimType.Sphere, V(0.05f, 0.05f, -0.035f), V(0.055f, 0.055f, 0.05f), 0.04f, stretch: false, morph: "detail");
        Add("下腹", "hips", PrimType.Sphere, V(0, -0.25f, 0.03f), V(0.065f, 0.5f, 0.042f), 0.05f, morph: "detail");
        Add("おなか", "spine", PrimType.Sphere, V(0, 0.3f, 0.008f), V(0.1f, 1.0f, 0.068f), 0.06f);
        Add("胸郭", "chest", PrimType.Sphere, V(0, 0.45f, 0f), V(0.115f, 0.62f, 0.078f), 0.06f);
        Add("胸", "chest", PrimType.Sphere, V(0.045f, 0.4f, 0.06f), V(0.045f, 0.045f, 0.04f), 0.03f, stretch: false, morph: "bust");
        Add("僧帽筋", "chest", PrimType.Sphere, V(0.052f, 0.96f, -0.004f), V(0.046f, 0.035f, 0.04f), 0.05f, stretch: false, morph: "detail");
        Add("首", "neck", PrimType.Capsule, V(0, 0.5f, -0.014f), V(0.039f, 0.6f, 0.034f), 0.05f);
        // 頭 (太さの 1 = 頭の高さ。y はあご 0 → てっぺん 1)
        Add("頭", "head", PrimType.Head, V(0, 0, 0), V(1, 1, 1), 0f, "head");
        var a = V(0, 0.43f, 0.28f); var b = V(0, 0.29f, 0.35f);
        Add("鼻", "head", PrimType.Capsule, (a + b) * 0.5f, V(0.05f, (b - a).Length() * 0.5f, 0.04f), 0.04f, "head",
            stretch: false, aim: b - a, morph: "nose");
        a = V(0, 0.313f, 0.24f); b = V(0, 0.137f, 0.168f);
        Add("口元", "head", PrimType.Capsule, (a + b) * 0.5f, V(0.14f, (b - a).Length() * 0.5f, 0.11f), 0.06f, "head",
            stretch: false, aim: b - a, morph: "nose");
        // 腕
        Add("肩のつなぎ", "shoulder.L", PrimType.Capsule, V(0.02f, 0.45f, 0), V(0.036f, 0.45f, 0.025f), 0.04f);
        Add("肩", "upper_arm.L", PrimType.Sphere, V(0.002f, 0.22f, 0), V(0.0315f, 0.055f, 0.0295f), 0.012f, "arm.L", stretch: false, morph: "ball");
        Add("上腕", "upper_arm.L", PrimType.Capsule, V(0, 0.56f, 0), V(0.031f, 0.44f, 0.027f * F(0.5f)), 0.03f, "arm.L");
        Add("前腕", "forearm.L", PrimType.Capsule, V(0, 0.5f, 0), V(0.028f * F(0.5f), 0.5f, 0.0125f * F(1f) * (1f + 0.9f * taper)), 0.012f, "arm.L");
        Add("手首", "forearm.L", PrimType.Sphere, V(0, 0.93f, 0), V(0.0145f, 0.04f, 0.019f) * F(1f), 0.006f, "arm.L", stretch: false);
        // 手 (ミトン): 手のひら + 指 4 本をまとめたかたまり + 親指。幅は前後 (z)、厚みは左右 (x)
        Add("手のひら", "hand.L", PrimType.Sphere, V(0, 0.32f, 0), V(0.0125f, 0.29f, 0.0275f), 0f, "hand.L");
        Add("手のひらの付け根", "hand.L", PrimType.Sphere, V(0, 0.07f, 0), V(0.0142f, 0.14f, 0.021f), 0.008f, "hand.L");
        Add("指", "hand.L", PrimType.Sphere, V(0, 0.68f, -0.002f), V(0.0105f, 0.33f, 0.0255f), 0.012f, "hand.L");
        // 脚
        Add("太もも", "thigh.L", PrimType.Capsule, V(0, 0.5f, 0), V(0.058f, 0.5f, 0.04f * F(0.5f)), 0.04f, "leg.L");
        Add("太もものふくらみ", "thigh.L", PrimType.Sphere, V(0.012f, 0.28f, 0.008f), V(0.05f, 0.2f, 0.05f), 0.05f, "leg.L", morph: "detail");
        Add("すね", "shin.L", PrimType.Capsule, V(0, 0.5f, 0), V(0.038f * F(0.5f), 0.5f, 0.024f * F(1f) * (1f + 0.5f * taper)), 0.03f, "leg.L");
        Add("ふくらはぎ", "shin.L", PrimType.Sphere, V(0, 0.3f, -0.012f), V(0.036f, 0.2f, 0.036f) * F(0.6f), 0.05f, "leg.L", morph: "detail");
        return L;
    }

    /// 骨の枠の中のメートルで置く肉 (親指・足・太ももの内側)
    static void Metric(List<Flesh> L, Dictionary<string, float> s, Landmarks m, Bone[] bones, float cell)
    {
        // 親指: 手の骨の枠 (Y = 手首→指先、Z = 手の幅で親指側、X = 手のひら側)
        var hb = bones[Rig.Index["hand.L"]];
        float hg = hb.GirthX, hl = hb.Length;
        var tRoot = V(0.004f * hg, 0.14f * hl, 0.016f * hg);
        var tDir = Vector3.Normalize(V(0.35f, 0.85f, 0.45f));
        float tLen = 0.4f * hl;
        L.Add(new Flesh { Name = "親指", Bone = "hand.L", Group = "hand.L", Type = PrimType.Capsule, Meters = true,
                          Pos = tRoot + tDir * (tLen * 0.5f), Size = V(0.0115f * hg, tLen * 0.5f, 0.0085f * hg), Blend = 0.008f * hg, Aim = tDir });

        // 足: 足の骨の枠 (原点 = 足首、y = つま先の向き、z = 下、x = 外側)。地面は z = 足首の高さ。
        // かかとは足首の 0.25L 後ろ、いちばん広いのは指の付け根 (かかとから 70%) で幅 0.38L、甲の高さ 0.23〜0.25L (low-Godough docs/FOOT.md)
        float f = 0.175f * m.B * s["foot"], A = m.Ankle;
        float taper = s["taper"];
        float fw = 1f + 0.35f * taper;   // 先太りの脚には幅のある足
        void Foot(string name, PrimType type, Vector3 pos, Vector3 size, float blend, PrimOp op = PrimOp.Add, string group = "foot.L")
        {
            L.Add(new Flesh { Name = name, Bone = "foot.L", Group = group, Type = type, Meters = true, Pos = pos, Size = size, Blend = blend, Op = op });
        }
        Foot("足", PrimType.Sphere, V(0.01f * f, 0.27f * f, A - 0.03f * f), V(0.185f * f * fw, 0.52f * f, 0.2f * f), 0f);
        Foot("かかと", PrimType.Sphere, V(0, -0.08f * f, A - 0.09f * f), V(0.135f * f * fw, 0.17f * f, 0.15f * f), 0.05f * f);
        Foot("甲", PrimType.Sphere, V(0, 0.06f * f, A - 0.2f * f), V(0.12f * f * fw, 0.2f * f, 0.16f * f), 0.07f * f);
        Foot("足の裏", PrimType.Box, V(0, 0.25f * f, A - 0.5f * f), V(0.7f * f * fw, 1.0f * f, 0.5f * f), 0.012f * f, PrimOp.Intersect);

        // 太ももの内側を、真ん中の少し手前で平らに削る (左右の脚がくっつくと、1 枚の網目になってポーズで破れる)。
        // すき間は網目のます 1.4 個ぶんより狭くしない
        float gap = MathF.Max(0.004f * m.B, cell * 0.7f);
        float top = m.Crotch + 0.1f * m.B, bottom = -0.05f * m.B;
        float cy = (top + bottom) / 2, hy = (top - bottom) / 2;
        float k = 0.012f * m.B;
        foreach (var (side, sx) in new[] { ("L", 1f), ("R", -1f) })
        {
            L.Add(new Flesh { Name = "脚の内側 " + side, Bone = "", Group = "leg." + side, Type = PrimType.Box, Op = PrimOp.Subtract, Meters = true,
                              Sym = false, Pos = V(sx * (-0.5f + gap), cy, 0f), Size = V(0.5f, hy, 0.5f), Blend = k });
            L.Add(new Flesh { Name = "足の内側 " + side, Bone = "", Group = "foot." + side, Type = PrimType.Box, Op = PrimOp.Subtract, Meters = true,
                              Sym = false, Pos = V(sx * (-0.5f + gap), cy, 0f), Size = V(0.5f, hy, 0.5f), Blend = k * 0.5f });
        }
    }

    /// 服の設計 (画面の数値) → 形。縦の目盛り: 0 あご・1 肩・2 くびれ・3 股・4 ひざ・5 足首・6 地面。
    /// 腕の目盛り: 0 肩・1 ひじ・2 手首・3 指先。厚みは身長の 100 分の 1 が単位
    static void AddGarments(Field f, Landmarks m, Bone[] bones, float cell, IReadOnlyList<GarmentSpec> wear)
    {
        if (wear == null || wear.Count == 0) return;
        float[] lm = { m.Chin, m.Shoulder, m.Waist, m.Crotch, m.Knee, m.Ankle, 0f };
        float Y(float t)
        {
            t = Math.Clamp(t, 0f, 6f);
            int i = Math.Min((int)t, 5);
            return lm[i] + (lm[i + 1] - lm[i]) * (t - i);
        }
        var ua = bones[Rig.Index["upper_arm.L"]];
        float l1 = ua.Length, l2 = l1 + bones[Rig.Index["forearm.L"]].Length, l3 = l2 + bones[Rig.Index["hand.L"]].Length * 1.25f;
        float[] al = { 0f, l1, l2, l3 };
        float A(float t)
        {
            t = Math.Clamp(t, 0f, 3f);
            int i = Math.Min((int)t, 2);
            return al[i] + (al[i + 1] - al[i]) * (t - i);
        }
        f.ArmO = ua.Origin; f.ArmD = ua.Basis.Y;
        f.Slit = MathF.Max(0.004f * m.B, cell * 0.7f);
        float unit = m.H * 0.01f;
        float hipX = bones[Rig.Index["thigh.L"]].Origin.X;
        var neck = bones[Rig.Index["neck"]];
        foreach (var w in wear)
        {
            var g = new Garment { Thick = MathF.Max(0f, w.Thick) * unit, Flare = w.Flare * unit, Follow = Math.Clamp(w.Follow, 0f, 1f) };
            float from = MathF.Min(w.From, w.To), to = MathF.Max(w.From, w.To);
            switch (w.Kind)
            {
                case "arm":
                    g.Kind = 2; g.HasArm = true;
                    g.ArmU0 = A(from);
                    g.ArmFrom = from <= 0.02f ? -1e9f : A(from);
                    g.ArmTo = to >= 2.95f ? 1e9f : A(to);
                    g.ArmSpan = MathF.Max(A(to) - A(from), 1e-3f);
                    g.ArmFlare = g.Flare; g.Flare = 0f;
                    break;
                case "skirt":
                    g.Kind = 3;
                    g.YTop = Y(from);
                    g.YBot = MathF.Max(Y(to), cell * 0.5f);
                    MeasureSkirt(f, g, m, hipX, cell);
                    break;
                default:
                    g.Kind = 0;
                    g.YTop = Y(from);
                    g.YBot = to >= 5.95f ? -1e9f : Y(to);
                    // 肩より上から始まる服は、えりぐりで切る (肩より下から始まる服は、まっ平らに)
                    g.NeckR = 0.039f * neck.Girth + g.Thick;
                    g.NeckZ = neck.Origin.Z - 0.014f * neck.GirthZ;
                    g.NeckSlope = 1.2f * Math.Clamp((1.5f - from) / 0.5f, 0f, 1f);
                    if (w.Sleeve > 0.02f)
                    {
                        g.HasArm = true;
                        g.ArmFrom = -1e9f; g.ArmU0 = 0f;
                        g.ArmTo = w.Sleeve >= 2.95f ? 1e9f : A(w.Sleeve);
                        g.ArmSpan = MathF.Max(A(w.Sleeve), 1e-3f);
                        g.ArmFlare = w.SleeveFlare * unit;
                    }
                    break;
            }
            f.AddGarment(g);
        }
    }

    /// すその形を、いまの体 (下に着ている服も) に合わせる: 上の端は体にぴったり、
    /// 下へは、立ち姿の脚より必ず外になるだけ広げる (頼まれた広がりで足りなければ足す)
    static void MeasureSkirt(Field f, Garment g, Landmarks m, float hipX, float cell)
    {
        float step = cell * 0.5f, far = m.H * 0.6f;
        float ScanX(float y)
        {
            float best = 0f;
            foreach (float z in new[] { -0.03f * m.H, 0f, 0.03f * m.H })
                for (float x = far; x > 0f; x -= step)
                    if (f.EvalNoArms(new Vector3(x, y, z)) < 0f) { best = MathF.Max(best, x + step); break; }
            return best;
        }
        float ScanZ(float y, float sign)
        {
            float best = 0f;
            foreach (float x in new[] { 0f, hipX * 0.6f, hipX })
                for (float z = far; z > -far * 0.3f; z -= step)
                    if (f.EvalNoArms(new Vector3(x, y, z * sign)) < 0f) { best = MathF.Max(best, z + step); break; }
            return best;
        }
        float L = MathF.Max(g.YTop - g.YBot, cell);
        float th = g.Thick;
        float x0 = ScanX(g.YTop), f0 = ScanZ(g.YTop, 1f), b0 = ScanZ(g.YTop, -1f);
        if (x0 <= 0f) { x0 = 0.08f * m.H; f0 = b0 = 0.06f * m.H; }
        g.RxT = x0 + th; g.ZfT = f0 + th; g.ZbT = -(b0 + th);
        float slope = g.Flare / L;
        g.RxS = g.ZfS = g.ZbS = slope;
        for (int k = 1; k <= 6; k++)
        {
            float h = L * k / 6f, y = g.YTop - h;
            g.RxS = MathF.Max(g.RxS, (ScanX(y) + th - g.RxT) / h);
            g.ZfS = MathF.Max(g.ZfS, (ScanZ(y, 1f) + th - g.ZfT) / h);
            g.ZbS = MathF.Max(g.ZbS, (ScanZ(y, -1f) + th + g.ZbT) / h);
        }
        g.Flare = 0f;
    }

    static Vector3 SizeFactors(Flesh p, Bone b)
    {
        float g = b.Girth;
        float along = p.Stretch ? b.Length : g;
        return p.Type == PrimType.Capsule ? new Vector3(g, along, g) : new Vector3(b.GirthX, along, b.GirthZ);
    }

    static Mat3 AimY(Vector3 v)
    {
        var y = Vector3.Normalize(v);
        var z = Vector3.UnitZ - y * y.Z;
        if (z.LengthSquared() < 1e-12f) z = Vector3.UnitX - y * y.X;
        z = Vector3.Normalize(z);
        return new Mat3(Vector3.Cross(y, z), y, z);
    }

    static RPrim On(Bone b, int boneIndex, Flesh p, bool mirror, float morph, int group, float shape)
    {
        var local = p.Aim.HasValue ? AimY(p.Aim.Value) : Mat3.Identity;
        Vector3 pos, size;
        float round, blend;
        if (p.Meters)
        {
            pos = p.Pos; size = p.Size * morph; round = p.Round; blend = p.Blend;
        }
        else
        {
            pos = new Vector3(p.Pos.X * b.GirthX, p.Pos.Y * b.Length, p.Pos.Z * b.GirthZ);
            size = p.Size * SizeFactors(p, b) * morph;
            round = p.Round * b.Girth; blend = p.Blend * b.Girth;
        }
        if (mirror) { pos.X = -pos.X; local = local.Mirrored; }
        return new RPrim { Name = p.Name, Type = p.Type, Op = p.Op, Basis = b.Basis * local, Pos = b.Origin + b.Basis.Mul(pos),
                           Size = size, Round = round, Blend = blend, Group = group, Bone = boneIndex, Shape = shape };
    }

    public static Field BuildField(Dictionary<string, float> s, Bone[] bones, float cell, IReadOnlyList<GarmentSpec> wear = null)
    {
        var m = Rig.Measure(s);
        var f = new Field();
        for (int i = 0; i < GroupNames.Length; i++)
            f.Groups.Add(new Group { Name = GroupNames[i], Parent = i == 0 ? -1 : Array.IndexOf(GroupNames, GroupDefs[i].parent), Join = GroupDefs[i].join * m.G });
        // つなぎが効く場所: 腕は肩の関節のまわり、脚は股関節のまわりだけ
        foreach (var side in new[] { "L", "R" })
        {
            var ua = bones[Rig.Index["upper_arm." + side]];
            var ga = f.Groups[Array.IndexOf(GroupNames, "arm." + side)];
            ga.JoinC = ua.Origin; ga.JoinR0 = ua.Length * 0.45f; ga.JoinR1 = ua.Length * 0.9f;
            var th = bones[Rig.Index["thigh." + side]];
            var gl = f.Groups[Array.IndexOf(GroupNames, "leg." + side)];
            gl.JoinC = th.Origin; gl.JoinR0 = th.Length * 0.55f; gl.JoinR1 = th.Length * 1.0f;
        }
        var flesh = Template(s, m, cell);
        Metric(flesh, s, m, bones, cell);
        float shape = Rig.ChibiShape(s);
        foreach (var p in flesh)
        {
            float morph = Rig.MorphScale(s, p.Morph);
            if (morph < 0.02f) continue;
            int g = Array.IndexOf(GroupNames, p.Group);
            if (p.Bone == "")
            {
                f.Prims.Add(new RPrim { Name = p.Name, Type = p.Type, Op = p.Op, Pos = p.Pos, Size = p.Size, Round = p.Round, Blend = p.Blend, Group = g, Bone = -1 });
                continue;
            }
            int bi = Rig.Index[p.Bone];
            f.Prims.Add(On(bones[bi], bi, p, false, morph, g, shape));
            if (!p.Sym) continue;
            string other = Rig.Partner(p.Bone);
            if (other != p.Bone)
                f.Prims.Add(On(bones[Rig.Index[other]], Rig.Index[other], p, true, morph, Array.IndexOf(GroupNames, Rig.Partner(p.Group)), shape));
            else if (MathF.Abs(p.Pos.X) > 1e-4f)
                f.Prims.Add(On(bones[bi], bi, p, true, morph, g, shape));
        }
        f.Finish(0.02f * m.H);
        AddGarments(f, m, bones, cell, wear);
        return f;
    }
}
