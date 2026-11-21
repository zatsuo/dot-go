// 画面 (GDScript) から呼ぶ窓口。体を作る → ポーズをつける → ドット絵に撮る → penInk 用に書き出す。
using System;
using System.Linq;
using Godot;
using DotGodough.Core;
using NVec3 = System.Numerics.Vector3;
using NQuat = System.Numerics.Quaternion;
using GDict = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

namespace DotGodough;

[GlobalClass]
public partial class DotCore : RefCounted
{
    System.Collections.Generic.Dictionary<string, float> _s = Rig.Defaults();
    Bone[] _bones;
    Field _field;
    float[] _cloth;      // 頂点ごとの、服の厚み (m)
    Landmarks _lm;
    MeshData _mesh;
    readonly System.Collections.Generic.Dictionary<string, NQuat> _poseRot = new();
    NVec3 _root;
    Mat3[] _R;
    NVec3[] _T, _joint, _pv, _pn;
    bool _skinned;
    readonly View _view = new();
    readonly Style _style = new();
    GBuffer _g;
    readonly PaintLayer _paint = new();
    Hair _hairSpec;      // null = 髪なし
    float _cell;

    static NVec3 N(Vector3 v) => new(v.X, v.Y, v.Z);
    static Vector3 G(NVec3 v) => new(v.X, v.Y, v.Z);
    static uint Argb(Color c) => ((uint)c.A8 << 24) | ((uint)c.R8 << 16) | ((uint)c.G8 << 8) | (uint)c.B8;

    // ---- 体型 ----

    /// 体型の数値の一覧: [{key, def, min, max}]
    public GArray ParamList()
    {
        var a = new GArray();
        foreach (var (key, def, min, max) in Rig.Params)
            a.Add(new GDict { ["key"] = key, ["def"] = def, ["min"] = min, ["max"] = max });
        return a;
    }

    /// その頭身の「ふつうの体型」の数値
    public GDict ForHeads(float heads)
    {
        var d = new GDict();
        foreach (var kv in Rig.ForHeads(heads)) d[kv.Key] = kv.Value;
        return d;
    }

    /// 体を作り直す。res = 身長を何ますに割るか (網目の細かさ)
    /// 体を作り直す。res = 身長を何ますに割るか (網目の細かさ)。
    /// wear = 服の並び (下に着るものから): [{kind, from, to, thick, flare, sleeve, sleeve_flare, follow}]
    public GDict Build(GDict settings, float res, GArray wear)
    {
        foreach (var k in settings.Keys)
        {
            string key = k.AsString();
            if (_s.ContainsKey(key)) _s[key] = settings[k].AsSingle();
        }
        foreach (var (key, _, min, max) in Rig.Params) _s[key] = Math.Clamp(_s[key], min, max);
        var m = Rig.Measure(_s);
        float cell = m.H / Math.Clamp(res, 24f, 200f);
        _bones = Rig.Build(_s);
        var specs = new System.Collections.Generic.List<GarmentSpec>();
        if (wear != null)
            foreach (var wv in wear)
            {
                var w = wv.AsGodotDictionary();
                float F(string k, float def) => w.ContainsKey(k) ? w[k].AsSingle() : def;
                specs.Add(new GarmentSpec {
                    Kind = w.ContainsKey("kind") ? w["kind"].AsString() : "body",
                    From = F("from", 1f), To = F("to", 3f), Thick = F("thick", 1f), Flare = F("flare", 0f),
                    Sleeve = F("sleeve", 0f), SleeveFlare = F("sleeve_flare", 0f), Follow = F("follow", 0.8f) });
            }
        _field = Body.BuildField(_s, _bones, cell, specs);
        if (_hairSpec != null) _hairSpec.Attach(_field, m.H, m.Waist, m.Knee);
        _lm = m;
        _mesh = Mesher.Build(_field, _bones, cell, m.G);
        _cell = cell;
        _paint.Resolve(_field, _bones, m.H, cell);
        _cloth = new float[_mesh.V.Length];
        if (_field.Garments.Count > 0)
            System.Threading.Tasks.Parallel.For(0, _cloth.Length, v => _cloth[v] = MathF.Max(0f, _field.EvalBody(_mesh.V[v])));
        int n = _bones.Length;
        _R = new Mat3[n]; _T = new NVec3[n]; _joint = new NVec3[n];
        _pv = new NVec3[_mesh.V.Length]; _pn = new NVec3[_mesh.V.Length];
        _skinned = false;
        _view.Height = m.H;
        return new GDict {
            ["verts"] = _mesh.V.Length, ["tris"] = _mesh.Tri.Length / 3, ["seconds"] = _mesh.Seconds,
            ["height"] = m.H, ["head_h"] = m.HeadH, ["cell"] = cell,
        };
    }

    /// 確かめ用: 基本姿勢の、肩のあたりの上の輪郭。x を 0 から xmax (あごから下の長さ B が単位) まで n 等分して、
    /// 肩の高さから測った面のいちばん上の高さ (B が単位) を返す。z は前後の幅ぜんぶで探す。clothed = 服も入れる
    public float[] ShoulderProfile(int n, float xmax, bool clothed)   // 0.068 = 首か頭に当たった (それより上は見ない)
    {
        var o = new float[n + 1];
        if (_field == null) return o;
        float B = _lm.B, step = B * 0.002f;
        for (int i = 0; i <= n; i++)
        {
            float x = xmax * B * i / n, top = -1f;
            for (float z = -0.12f * B; z <= 0.1201f * B; z += 0.02f * B)
                for (float y = _lm.Shoulder + 0.068f * B; y > _lm.Shoulder - 0.4f * B; y -= step)
                {
                    var p = new NVec3(x, y, z);
                    if ((clothed ? _field.Eval(p) : _field.EvalBody(p)) < 0f) { top = MathF.Max(top, (y - _lm.Shoulder) / B); break; }
                }
            o[i] = top;
        }
        return o;
    }

    /// 髪の数値 (次の Build から効く)。on が false なら髪なし。
    /// {on, vol, puff, bangs, bangs_w, side, back, tips}。長さは頭のてっぺんから、頭の高さが単位
    public void SetHair(GDict h)
    {
        bool on = h != null && h.ContainsKey("on") && h["on"].AsBool();
        var locks = new System.Collections.Generic.List<float[]>();
        if (h != null && h.ContainsKey("locks"))
            foreach (var lv in h["locks"].AsGodotArray())
            {
                var a = lv.AsFloat32Array();
                if (a.Length >= 8) locks.Add(a);
            }
        if (!on && locks.Count == 0) { _hairSpec = null; return; }
        float F(string k, float def) => h.ContainsKey(k) ? h[k].AsSingle() : def;
        _hairSpec = new Hair {
            Shell = on, Separate = h.ContainsKey("lock_sep") && h["lock_sep"].AsBool(),
            Vol = Math.Clamp(F("vol", 0.05f), 0.01f, 0.2f), Puff = Math.Clamp(F("puff", 0.02f), 0f, 0.2f),
            Bangs = Math.Clamp(F("bangs", 0.42f), 0.05f, 1f), BangsW = Math.Clamp(F("bangs_w", 42f), 10f, 90f),
            Side = Math.Clamp(F("side", 0.92f), 0.1f, 4f), Back = Math.Clamp(F("back", 0.98f), 0.1f, 4f),
            Tips = Math.Clamp(F("tips", 0.3f), 0f, 1f), Curl = Math.Clamp(F("curl", 0.5f), 0f, 1f),
            Gloss = Math.Clamp(F("gloss", 0.8f), 0f, 1f) };
        _hairSpec.Locks.AddRange(locks);
    }

    /// ペンで引いた線 (いま描いてある絵の画素の座標) を、髪の房 1 本にする。
    /// size = 根元の太さ (半径。頭の高さが単位)、taper = 先をどれだけ細くするか 0〜1、mirror = 左右反対側にも。
    /// 奥行き: 線が頭や髪の上を通る所は その面の上。面から外へ出たら、最後に通った面の奥行きのまま。
    /// 返すのは房の並び (SetHair の locks に足す形)。体を作り直すまで形は変わらない
    /// cut = 切るペン: 房を足すのではなく、線の形だけ髪を削る (分け目・前髪の切れ込み・毛先を切る)。半径を負にして返す
    public GArray HairStroke(Vector2[] px, float size, float taper, bool mirror, bool cut)
    {
        var res = new GArray();
        if (_g == null || _field == null || px == null || px.Length == 0) return res;
        EnsureSkin();
        var head = _field.Prims.First(p => p.Type == PrimType.Head);
        int hb = Rig.Index["head"];
        float headH = head.Size.Y;
        float ppm = _g.Ppm;
        // size = ペンの太さ (画素)。絵の上で塗った幅が、そのまま髪の幅になる
        float rad = MathF.Max(Math.Clamp(size, 1f, 64f) * 0.5f, 0.6f) / ppm;
        _view.Axes(out var ar, out var au, out var at);
        // 点の間をそろえる (半径の 0.6 倍ごと)
        float total = 0f;
        for (int i = 1; i < px.Length; i++) total += (px[i] - px[i - 1]).Length();
        float step = MathF.Max(MathF.Max(1f, rad * ppm * 0.6f), total / 400f);
        var pts = new System.Collections.Generic.List<Vector2> { px[0] };
        float acc = 0f;
        for (int i = 1; i < px.Length; i++)
        {
            var a = px[i - 1]; var b = px[i];
            float l = (b - a).Length();
            while (acc + l >= step && l > 1e-5f)
            {
                float t = (step - acc) / l;
                a = a.Lerp(b, t);
                pts.Add(a);
                l = (b - a).Length();
                acc = 0f;
            }
            acc += l;
        }
        if (pts.Count == 1 || (px[^1] - pts[^1]).Length() > 0.3f * step) pts.Add(px[^1]);
        int n = pts.Count;
        // 手ぶれをならす (端は動かさない)
        for (int pass = 0; pass < 1 && n > 2; pass++)
        {
            var q = pts.ToArray();
            for (int i = 1; i < n - 1; i++) pts[i] = (q[i - 1] + q[i] * 2f + q[i + 1]) * 0.25f;
        }
        // 奥行き
        var depth = new float[n];
        var has = new bool[n];
        var front = new float[n];       // その画素に写っている面の奥行き (何も写っていなければ -∞)
        bool any = false, onHair = false;
        for (int i = 0; i < n; i++)
        {
            front[i] = float.NegativeInfinity;
            int ix = (int)MathF.Floor(pts[i].X), iy = (int)MathF.Floor(pts[i].Y);
            if (ix < 0 || iy < 0 || ix >= _g.W || iy >= _g.H) continue;
            int o = ix + _g.W * iy;
            if (!_g.Hit[o]) continue;
            front[i] = _g.Depth[o];
            if (_g.Part[o] == 15 || _g.Part[o] == 16) onHair = true;
            if (_g.Part[o] != 1 && _g.Part[o] != 15 && _g.Part[o] != 16) continue;
            depth[i] = _g.Depth[o] - (cut ? 0f : rad * 0.45f);      // 房は面に半分ほど埋める。切る線は面の上
            has[i] = any = true;
        }
        if (!any)
        {
            // 頭に触れていない線: 頭の真ん中を通る、絵と平行な面の上
            var c = _R[hb].Mul(head.Pos + head.Basis.Mul(new NVec3(0, 0.5f, -0.08f) * head.Size)) + _T[hb];
            float d0 = NVec3.Dot(at, c);
            for (int i = 0; i < n; i++) depth[i] = d0;
        }
        else
        {
            int first = Array.IndexOf(has, true);
            for (int i = 0; i < first; i++) depth[i] = depth[first];
            for (int i = first + 1; i < n; i++) if (!has[i]) depth[i] = depth[i - 1];
            // 面を出入りする所の段をならす
            for (int pass = 0; pass < 2; pass++)
            {
                var q = (float[])depth.Clone();
                for (int i = 1; i < n - 1; i++) depth[i] = (q[i - 1] + q[i] * 2f + q[i + 1]) * 0.25f;
            }
        }
        // 消しゴム: 髪に 1 度も触れなければ、何もしない (ペンの幅のぶんも見る)
        if (cut && !onHair)
        {
            int ext = (int)MathF.Ceiling(rad * ppm);
            for (int i = 0; i < n && !onHair; i++)
                for (int dy = -ext; dy <= ext && !onHair; dy++)
                    for (int dx = -ext; dx <= ext; dx++)
                    {
                        int ix = (int)MathF.Floor(pts[i].X) + dx, iy = (int)MathF.Floor(pts[i].Y) + dy;
                        if (ix < 0 || iy < 0 || ix >= _g.W || iy >= _g.H) continue;
                        int o = ix + _g.W * iy;
                        if (_g.Hit[o] && (_g.Part[o] == 15 || _g.Part[o] == 16)) { onHair = true; break; }
                    }
            if (!onHair) return res;
        }
        // 描いた所は必ず見えるように: 体や頭の面より奥へは置かない (胸の前に垂らした髪が、体の中に隠れないように)
        if (!cut)
            for (int i = 0; i < n; i++)
                depth[i] = MathF.Max(depth[i], front[i] - rad * 0.45f);
        var hair = _field.Hair ?? new Hair { Head = head };
        if (hair.Head == null) hair.Head = head;
        // 消しゴム: 見る向き (頭の枠で) と、奥へ押し抜く長さ。頭の高さの半分まで = 前髪を消しても、頭の向こうの後ろ髪は残る
        var dirH = head.Basis.TMul(_R[hb].TMul(at));
        var all = new System.Collections.Generic.List<float[]>();
        for (int side = 0; side < (mirror ? 2 : 1); side++)
        {
            var f = new float[n * 4];
            all.Add(f);
            for (int i = 0; i < n; i++)
            {
                var posed = ar * ((pts[i].X - _view.Cx) / ppm) + au * ((_view.FloorY - pts[i].Y) / ppm) + at * depth[i];
                var rest = _R[hb].TMul(posed - _T[hb]);
                var u = hair.ToHead(rest);
                float s = n > 1 ? (float)i / (n - 1) : 0f;
                f[i * 4] = side == 0 ? u.X : -u.X; f[i * 4 + 1] = u.Y; f[i * 4 + 2] = u.Z;
                f[i * 4 + 3] = MathF.Max(rad * (1f - Math.Clamp(taper, 0f, 0.95f) * s * s), 0.45f / ppm) / headH * (cut ? -1f : 1f);
            }
        }
        // 長い線は 24 点ごとに分ける (遠い所の計算を、かたまりごとに飛ばせるように)
        for (int side = 0; side < all.Count; side++)
            for (int i0 = 0; i0 < n - 1 || i0 == 0; i0 += 23)
            {
                int cnt = Math.Min(24, n - i0);
                if (cnt < 2) break;
                var f = new float[(cnt + (cut ? 1 : 0)) * 4];
                Array.Copy(all[side], i0 * 4, f, 0, cnt * 4);
                if (cut)
                {
                    f[cnt * 4] = side == 0 ? dirH.X : -dirH.X; f[cnt * 4 + 1] = dirH.Y; f[cnt * 4 + 2] = dirH.Z;
                    f[cnt * 4 + 3] = 0.5f;
                }
                res.Add(f);
            }
        return res;
    }

    /// その画素に写っている房の番号 (SetHair の locks の並びで)。房でなければ -1
    public int HairLockAt(int x, int y)
    {
        if (_g == null || _field?.Hair == null || x < 0 || y < 0 || x >= _g.W || y >= _g.H) return -1;
        int i = x + _g.W * y;
        if (!_g.Hit[i]) return -1;
        var hr = _field.Hair;
        if (_g.Part[i] == 16)
        {
            float d = hr.LockDistance(_g.Rest[i], out int which);
            if (d < 0.03f * hr.HeadH) return which;
        }
        // 房でなければ、切り口の近く (切って見えた肌や、切り口の壁) → その切った線
        return _g.Part[i] == 1 || _g.Part[i] == 15 || _g.Part[i] == 16 ? hr.CutAt(_g.Rest[i], 0.04f * hr.HeadH) : -1;
    }

    /// 基本姿勢の骨: [{name, parent, origin, tail}]
    public GArray Bones()
    {
        var a = new GArray();
        foreach (var b in _bones)
            a.Add(new GDict { ["name"] = b.Name, ["parent"] = b.Parent < 0 ? "" : _bones[b.Parent].Name,
                              ["origin"] = G(b.Origin), ["tail"] = G(b.Tail) });
        return a;
    }

    // ---- ポーズ ----

    /// rots: 骨の名前 → Quaternion (親の枠の中の回転。基本姿勢は回転なし)。root: 体全体の移動
    public void SetPose(GDict rots, Vector3 root)
    {
        _poseRot.Clear();
        foreach (var k in rots.Keys)
        {
            var q = rots[k].AsQuaternion();
            _poseRot[k.AsString()] = NQuat.Normalize(new NQuat(q.X, q.Y, q.Z, q.W));
        }
        _root = N(root);
        _skinned = false;
    }

    void EnsureSkin()
    {
        if (_skinned || _mesh == null) return;
        var rot = new NQuat[_bones.Length];
        for (int i = 0; i < rot.Length; i++)
            rot[i] = _poseRot.TryGetValue(_bones[i].Name, out var q) ? q : NQuat.Identity;
        Core.Skin.Matrices(_bones, rot, _root, _R, _T, _joint);
        Core.Skin.Apply(_mesh, _R, _T, _pv, _pn);
        _skinned = true;
    }

    /// いまのポーズでの関節の位置: 名前 → Vector3。骨の先は "名前/tail"、骨の向きは "名前/basis" (Basis)
    public GDict Joints()
    {
        EnsureSkin();
        var d = new GDict();
        for (int i = 0; i < _bones.Length; i++)
        {
            var b = _bones[i];
            d[b.Name] = G(_joint[i]);
            d[b.Name + "/tail"] = G(_joint[i] + _R[i].Mul(b.Tail - b.Origin));
            d[b.Name + "/basis"] = new Basis(G(_R[i].X), G(_R[i].Y), G(_R[i].Z));
        }
        return d;
    }

    /// いまのポーズでいちばん低い所の高さ (地面に立たせるのに使う)
    public float LowestY()
    {
        if (_mesh == null) return 0f;
        EnsureSkin();
        float y = float.MaxValue;
        foreach (var p in _pv) y = MathF.Min(y, p.Y);
        return y;
    }

    /// 腕が胴・脚・服にどれだけ近いか (網目のます が単位。負 = めり込んでいる)。side = "L" / "R"。
    /// いまのポーズの腕の点を、胸 (腰より下は腰) の骨といっしょに基本姿勢へ戻して、腕を除いた形で測る
    public float ArmClearance(string side)
    {
        if (_mesh == null) return 99f;
        EnsureSkin();
        bool left = side == "L";
        int chest = Rig.Index["chest"], hips = Rig.Index["hips"];
        var ua = _bones[Rig.Index[left ? "upper_arm.L" : "upper_arm.R"]];
        float min = 1e9f;
        for (int v = 0; v < _mesh.V.Length; v++)
        {
            int part = _mesh.VPart[v];
            if (left ? (part < 2 || part > 4) : (part < 5 || part > 7)) continue;
            if (NVec3.Dot(_mesh.V[v] - ua.Origin, ua.Basis.Y) < 0.45f * ua.Length) continue;   // 肩の近くは、もともと胴についている
            var pc = _R[chest].TMul(_pv[v] - _T[chest]);
            var p = pc.Y > _lm.Waist ? pc : _R[hips].TMul(_pv[v] - _T[hips]);
            // そでの布が胴の服に少し重なるのは許す (布の厚みの 8 割まで)。腕の中身が入るのは許さない
            min = MathF.Min(min, _field.EvalNoArms(p) + 0.8f * _cloth[v]);
        }
        return min / _mesh.Cell;
    }

    static NQuat ToQuat(Mat3 m)
    {
        var mm = new System.Numerics.Matrix4x4(m.X.X, m.X.Y, m.X.Z, 0, m.Y.X, m.Y.Y, m.Y.Z, 0, m.Z.X, m.Z.Y, m.Z.Z, 0, 0, 0, 0, 1);
        return NQuat.Normalize(NQuat.CreateFromRotationMatrix(mm));
    }

    /// 腕が胴・頭・脚・服に入っていたら、入らなくなるまで上腕を回す (胸の前後の軸のまわりに 2° ずつ。
    /// 離れていくほうの向きを選ぶ: 下ろした腕は外へ開き、上げた腕は頭から離れる)。
    /// need = 残すすき間 (網目のます)。変えた骨 → 新しい回転 を返す
    public GDict FixArms(float need)
    {
        var changed = new GDict();
        if (_mesh == null) return changed;
        int chest = Rig.Index["chest"];
        foreach (var side in new[] { "L", "R" })
        {
            string name = "upper_arm." + side;
            int par = _bones[Rig.Index[name]].Parent;
            float c0 = ArmClearance(side);
            if (c0 >= need) continue;
            var start = _poseRot.TryGetValue(name, out var q0) ? q0 : NQuat.Identity;
            var best = start;
            float bestC = c0;
            float outward = side == "L" ? 1f : -1f;
            foreach (float sgn in new[] { outward, -outward })
            {
                var q = start;
                float prev = c0;
                for (int i = 0; i < 45; i++)
                {
                    var turn = Mat3.FromQuat(NQuat.CreateFromAxisAngle(NVec3.Normalize(_R[chest].Z), sgn * 2f * MathF.PI / 180f));
                    var rp = _R[par];
                    q = ToQuat(rp.T * turn * rp * Mat3.FromQuat(q));
                    _poseRot[name] = q;
                    _skinned = false;
                    float c = ArmClearance(side);
                    if (c > bestC) { bestC = c; best = q; }
                    if (c >= need) break;
                    if (i >= 3 && c < prev && c < bestC) break;   // こちらの向きは、入っていくだけ
                    prev = c;
                }
                if (bestC >= need) break;
            }
            _poseRot[name] = best;
            _skinned = false;
            if (best != start) changed[name] = new Quaternion(best.X, best.Y, best.Z, best.W);
        }
        return changed;
    }

    // ---- 見る ----

    public void SetView(GDict v)
    {
        if (v.ContainsKey("w")) _view.W = Math.Clamp(v["w"].AsInt32(), 8, 512);
        if (v.ContainsKey("h")) _view.H = Math.Clamp(v["h"].AsInt32(), 8, 512);
        if (v.ContainsKey("yaw")) _view.Yaw = v["yaw"].AsSingle();
        if (v.ContainsKey("pitch")) _view.Pitch = v["pitch"].AsSingle();
        if (v.ContainsKey("px")) _view.Px = v["px"].AsSingle();
        if (v.ContainsKey("floor")) _view.FloorY = v["floor"].AsSingle();
        if (v.ContainsKey("center")) _view.CenterX = v["center"].AsSingle();
        if (v.ContainsKey("ss")) _view.SS = v["ss"].AsInt32();
        if (v.ContainsKey("cover")) _view.Cover = v["cover"].AsSingle();
        if (v.ContainsKey("smooth")) _view.Smooth = v["smooth"].AsInt32();
    }

    public void SetStyle(GDict s)
    {
        if (s.ContainsKey("mats"))
        {
            _style.Mats.Clear();
            foreach (var mv in s["mats"].AsGodotArray())
            {
                var md = mv.AsGodotDictionary();
                var ms = new MatStyle();
                var ramp = md["ramp"].AsGodotArray();
                ms.Ramp = new uint[ramp.Count];
                for (int i = 0; i < ramp.Count; i++) ms.Ramp[i] = Argb(ramp[i].AsColor());
                ms.Line = Argb(md["line"].AsColor());
                _style.Mats.Add(ms);
            }
            if (_style.Mats.Count == 0) _style.Mats.Add(new MatStyle());
        }
        if (s.ContainsKey("steps")) _style.Steps = s["steps"].AsFloat32Array();
        if (s.ContainsKey("light")) { var l = N(s["light"].AsVector3()); if (l.LengthSquared() > 1e-8f) _style.Light = NVec3.Normalize(l); }
        if (s.ContainsKey("line_mode")) _style.LineMode = s["line_mode"].AsInt32();
        if (s.ContainsKey("inner")) _style.InnerLines = s["inner"].AsBool();
        if (s.ContainsKey("gap_part")) _style.GapPart = s["gap_part"].AsSingle();
        if (s.ContainsKey("gap_same")) _style.GapSame = s["gap_same"].AsSingle();
        if (s.ContainsKey("one_line")) _style.OneLineColor = s["one_line"].AsBool();
        if (s.ContainsKey("line_color")) _style.LineColor = Argb(s["line_color"].AsColor());
        if (s.ContainsKey("despeckle")) _style.Despeckle = s["despeckle"].AsBool();
        if (s.ContainsKey("rim")) _style.Rim = s["rim"].AsInt32();
        if (s.ContainsKey("rim_shadow")) _style.RimShadowSide = s["rim_shadow"].AsBool();
        if (s.ContainsKey("paints"))
        {
            _style.PaintRamps.Clear();
            foreach (var pv in s["paints"].AsGodotArray())
            {
                var pd = pv.AsGodotDictionary();
                var ramp = pd["ramp"].AsGodotArray();
                var r = new uint[ramp.Count];
                for (int i = 0; i < r.Length; i++) r[i] = Argb(ramp[i].AsColor()) | 0xFF000000u;
                _style.PaintRamps[Argb(pd["color"].AsColor()) | 0xFF000000u] = r;
            }
        }
    }

    /// いまの体・ポーズ・見る向き・画風でドット絵を 1 枚
    public Image Render()
    {
        if (_mesh == null) return Image.CreateEmpty(_view.W, _view.H, false, Image.Format.Rgba8);
        EnsureSkin();
        _g = Raster.Draw(_mesh, _pv, _pn, _view);
        uint[] pc = null; bool[] pf = null;
        sbyte[] tone = null;
        int n = _g.W * _g.H;
        float pmin = 0.55f / _g.Ppm;
        if (_paint.Dabs.Count > 0)
        {
            pc = new uint[n]; pf = new bool[n];
            bool anyTone = _paint.Dabs.Exists(d => (d.Flags & PaintLayer.Tone) != 0);
            if (anyTone) tone = new sbyte[n];
            for (int i = 0; i < n; i++)
            {
                if (!_g.Hit[i]) continue;
                int k = _paint.Find(_g.Rest[i], pmin);
                if (k >= 0)
                {
                    var d = _paint.Dabs[k];
                    if ((d.Flags & PaintLayer.Erase) == 0) { pc[i] = d.Argb; pf[i] = (d.Flags & PaintLayer.Flat) != 0; }
                }
                if (!anyTone) continue;
                k = _paint.Find(_g.Rest[i], pmin, true);
                if (k < 0) continue;
                int fl = _paint.Dabs[k].Flags;
                if ((fl & PaintLayer.Erase) != 0) continue;
                int amt = (fl & PaintLayer.Strong) != 0 ? 2 : 1;
                tone[i] = (sbyte)((fl & PaintLayer.Dark) != 0 ? -amt : amt);
            }
        }
        if (_field.Hair != null && _field.Hair.Gloss > 0f)
        {
            // つやの帯: 髪の、こちらを向いている面だけ (ふちには出さない)。塗った所・描いた髪には出さない
            tone ??= new sbyte[n];
            var hr = _field.Hair;
            for (int i = 0; i < n; i++)
                if (_g.Hit[i] && (_g.Part[i] == 15 || _g.Part[i] == 16) && _g.Nrm[i].Z > 0.35f && (pc == null || pc[i] == 0) && tone[i] == 0
                    && hr.InGloss(_g.Rest[i]) && (hr.Locks.Count == 0 || hr.LockDistance(_g.Rest[i], out _) > 0.02f * hr.HeadH))
                    tone[i] = 1;
        }
        _cls = new int[n];
        return Image.CreateFromData(_view.W, _view.H, false, Image.Format.Rgba8, Pixel.Compose(_g, _style, pc, pf, tone, _cls));
    }

    int[] _cls;
    /// 最後に描いた絵の、画素ごとの「どの素材のどの色か」(素材 × 8 + 段。線 = 素材 × 8 + 7。無い = -1、塗り = -2)
    public int[] Classes() => _cls ?? System.Array.Empty<int>();

    // ---- 塗る ----

    /// いま描いてある絵 (最後の Render) の画素 (x, y) のあたりを塗る。size = ペンの太さ (画素)。
    /// flat = 光の段を使わず そのままの色。erase = 消しゴム。mirror = 体の左右反対側にも。足した点の数を返す
    public int PaintAt(float x, float y, float size, Color c, bool flat, bool erase, bool mirror) =>
        PaintKind(x, y, size, c, flat, erase, mirror, 0);

    /// kind: 0 = 色を塗る、1 = 明るく、2 = もっと明るく、-1 = 暗く、-2 = もっと暗く (色は置かず、その場所の色の段をずらす)。
    /// 消しゴムは、色も明るさも消す
    public int PaintKind(float x, float y, float size, Color c, bool flat, bool erase, bool mirror, int kind)
    {
        if (erase) return PaintCore(x, y, size, c, false, true, mirror, 0) + PaintCore(x, y, size, c, false, true, mirror, 1);
        return PaintCore(x, y, size, c, flat, false, mirror, kind);
    }

    int PaintCore(float x, float y, float size, Color c, bool flat, bool erase, bool mirror, int kind)
    {
        if (_g == null || _field == null) return 0;
        bool tn = kind != 0;
        uint argb = tn ? 0xFF000000u : Argb(c) | 0xFF000000u;
        int flags = tn ? PaintLayer.Tone | (erase ? PaintLayer.Erase : (kind > 0 ? PaintLayer.Light : PaintLayer.Dark) | (Math.Abs(kind) >= 2 ? PaintLayer.Strong : 0))
                       : (flat ? PaintLayer.Flat : 0) | (erase ? PaintLayer.Erase : 0);
        float rad = 0.62f / _g.Ppm;       // 1 画素より少し大きい玉 (向きを変えても、すき間があかないように)
        float half = MathF.Max(size, 1f) * 0.5f;
        int added = 0;
        int cx = (int)MathF.Floor(x), cy = (int)MathF.Floor(y);
        int ext = (int)MathF.Ceiling(half) + 1;
        for (int iy = cy - ext; iy <= cy + ext; iy++)
            for (int ix = cx - ext; ix <= cx + ext; ix++)
            {
                if (ix < 0 || iy < 0 || ix >= _g.W || iy >= _g.H) continue;
                bool inside = size <= 1.01f ? (ix == cx && iy == cy)
                    : (ix + 0.5f - x) * (ix + 0.5f - x) + (iy + 0.5f - y) * (iy + 0.5f - y) <= half * half;
                if (!inside) continue;
                int i = ix + _g.W * iy;
                if (!_g.Hit[i]) continue;
                var rest = _g.Rest[i];
                for (int side = 0; side < (mirror ? 2 : 1); side++)
                {
                    var p = side == 0 ? rest : new NVec3(-rest.X, rest.Y, rest.Z);
                    int k = _paint.Find(p, 0.55f / _g.Ppm, tn);
                    if (k >= 0 && _paint.Dabs[k].Flags == flags && (erase || _paint.Dabs[k].Argb == argb)) continue;   // もう同じ色
                    if (k < 0 && erase) continue;
                    _paint.Add(_field, _bones, _lm.H, p, rad, argb, flags);
                    added++;
                }
            }
        return added;
    }

    public int PaintCount() => _paint.Dabs.Count;

    public void ClearPaint() => _paint.Clear();

    /// 塗りに使っている色 (段をつける色だけ。SetStyle の paints に、色ごとの段を入れて返してもらう)
    public GArray PaintColors()
    {
        var seen = new System.Collections.Generic.HashSet<uint>();
        var a = new GArray();
        foreach (var d in _paint.Dabs)
            if ((d.Flags & (PaintLayer.Flat | PaintLayer.Erase | PaintLayer.Tone)) == 0 && seen.Add(d.Argb))
                a.Add(new Color(((d.Argb >> 16) & 255) / 255f, ((d.Argb >> 8) & 255) / 255f, (d.Argb & 255) / 255f));
        return a;
    }

    /// 塗りのデータ: f = 点ごとに [骨, x, y, z, 半径 x, y, z]、i = 点ごとに [色, 種類]
    public GDict GetPaint()
    {
        var f = new float[_paint.Dabs.Count * 7];
        var n = new int[_paint.Dabs.Count * 2];
        for (int k = 0; k < _paint.Dabs.Count; k++)
        {
            var d = _paint.Dabs[k];
            f[k * 7] = d.Bone; f[k * 7 + 1] = d.Local.X; f[k * 7 + 2] = d.Local.Y; f[k * 7 + 3] = d.Local.Z;
            f[k * 7 + 4] = d.R.X; f[k * 7 + 5] = d.R.Y; f[k * 7 + 6] = d.R.Z;
            n[k * 2] = unchecked((int)d.Argb); n[k * 2 + 1] = d.Flags;
        }
        return new GDict { ["f"] = f, ["i"] = n };
    }

    public void SetPaint(GDict data)
    {
        _paint.Clear();
        if (data == null || !data.ContainsKey("f") || !data.ContainsKey("i")) return;
        var f = data["f"].AsFloat32Array();
        var n = data["i"].AsInt32Array();
        int cnt = Math.Min(f.Length / 7, n.Length / 2);
        int nb = Rig.Order.Length;
        for (int k = 0; k < cnt; k++)
            _paint.Dabs.Add(new Dab { Bone = Math.Clamp((int)f[k * 7], 0, nb - 1), Local = new NVec3(f[k * 7 + 1], f[k * 7 + 2], f[k * 7 + 3]),
                                      R = new NVec3(f[k * 7 + 4], f[k * 7 + 5], f[k * 7 + 6]), Argb = unchecked((uint)n[k * 2]) | 0xFF000000u, Flags = n[k * 2 + 1] });
        if (_field != null) _paint.Resolve(_field, _bones, _lm.H, _cell);
    }

    /// 3D の点 → 画素の位置 (x, y) と奥行き z
    public Vector3 Project(Vector3 p) => G(_view.Project(N(p)));

    /// 画面の 右・上・手前 が 3D のどの向きか
    public GArray Axes()
    {
        _view.Axes(out var r, out var u, out var t);
        return new GArray { G(r), G(u), G(t) };
    }

    public float Ppm() => _view.Ppm;

    /// その画素に写っている部品の番号 (なければ -1) と名前
    public GDict Pick(int x, int y)
    {
        var d = new GDict { ["part"] = -1, ["name"] = "" };
        if (_g == null || x < 0 || y < 0 || x >= _g.W || y >= _g.H) return d;
        int i = x + _g.W * y;
        if (!_g.Hit[i]) return d;
        d["part"] = (int)_g.Part[i];
        d["name"] = Mesher.PartNames[Math.Min(_g.Part[i], Mesher.PartNames.Length - 1)];
        d["rest"] = G(_g.Rest[i]);
        d["mat"] = (int)_g.Mat[i];
        return d;
    }

    /// 3D の表示用の網目 (いまのポーズ)
    public ArrayMesh MakeMesh()
    {
        var am = new ArrayMesh();
        if (_mesh == null) return am;
        EnsureSkin();
        int nv = _pv.Length;
        var v = new Vector3[nv]; var nn = new Vector3[nv]; var col = new Color[nv];
        for (int i = 0; i < nv; i++)
        {
            v[i] = G(_pv[i]); nn[i] = G(_pn[i]);
            col[i] = Color.FromHsv((_mesh.VPart[i] * 0.381966f) % 1f, 0.35f, 0.95f);
        }
        // Godot は時計回りが表
        var idx = new int[_mesh.Tri.Length];
        for (int t = 0; t < idx.Length; t += 3) { idx[t] = _mesh.Tri[t]; idx[t + 1] = _mesh.Tri[t + 2]; idx[t + 2] = _mesh.Tri[t + 1]; }
        var arrays = new GArray();
        arrays.Resize((int)Mesh.ArrayType.Max);
        arrays[(int)Mesh.ArrayType.Vertex] = v;
        arrays[(int)Mesh.ArrayType.Normal] = nn;
        arrays[(int)Mesh.ArrayType.Color] = col;
        arrays[(int)Mesh.ArrayType.Index] = idx;
        am.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
        return am;
    }

    /// 網目の確かめ: 穴 (片側にしか面のない辺) の数、左右のずれ、重みの合計のずれ
    public GDict Check()
    {
        var d = new GDict();
        if (_mesh == null) return d;
        var edges = new System.Collections.Generic.Dictionary<(int, int), int>();
        for (int t = 0; t < _mesh.Tri.Length; t += 3)
            for (int e = 0; e < 3; e++)
            {
                int a = _mesh.Tri[t + e], b = _mesh.Tri[t + (e + 1) % 3];
                var key = a < b ? (a, b) : (b, a);
                edges[key] = edges.GetValueOrDefault(key) + (a < b ? 1 : -1);
            }
        d["open_edges"] = edges.Values.Count(c => c != 0);
        float minX = 1e9f, maxX = -1e9f, minY = 1e9f, maxY = -1e9f;
        foreach (var p in _mesh.V) { minX = MathF.Min(minX, p.X); maxX = MathF.Max(maxX, p.X); minY = MathF.Min(minY, p.Y); maxY = MathF.Max(maxY, p.Y); }
        d["x_asym"] = MathF.Abs(minX + maxX);
        d["min_y"] = minY; d["max_y"] = maxY; d["half_width"] = maxX;
        var parts = new int[Mesher.PartNames.Length];
        foreach (byte p in _mesh.VPart) parts[Math.Min(p, parts.Length - 1)]++;
        d["parts"] = parts;
        return d;
    }

    // ---- penInk ----

    /// penInk 用のキャラのフォルダ (gltf + bin + cel.json) を書く。mats: [{key, ramp}]
    public string ExportPenink(string dir, string name)
    {
        if (_mesh == null) return "体がまだありません";
        try
        {
            var parts = new (string, NVec3)[_style.Mats.Count];
            var bands = new float[parts.Length][][];
            for (int i = 0; i < parts.Length; i++)
            {
                var ramp = _style.Mats[i].Ramp;
                NVec3 C(uint c) => new(((c >> 16) & 255) / 255f, ((c >> 8) & 255) / 255f, (c & 255) / 255f);
                parts[i] = (i == 0 ? "skin" : $"part{i:00}", C(ramp[^1]));
                bands[i] = new float[4][];
                for (int b = 0; b < 4; b++)
                {
                    // 明るい → 暗いの 4 段
                    var c = C(ramp[Math.Clamp(ramp.Length - 1 - b * ramp.Length / 4, 0, ramp.Length - 1)]);
                    bands[i][b] = new[] { c.X, c.Y, c.Z };
                }
            }
            Gltf.Write(_mesh, dir, name, parts, bands);
            return "";
        }
        catch (Exception e)
        {
            return e.Message;
        }
    }
}
