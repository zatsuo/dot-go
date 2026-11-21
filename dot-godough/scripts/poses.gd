## ポーズの入れ物と、最初から入っているポーズ。
## ポーズ = {"bones": {骨の名前: Vector3 (度。Godot の YXZ の順 = penInk と同じ)}, "root": Vector3 (m)}
## 骨の回転は「親の枠の中」。基本姿勢の骨は回転なし (世界の軸のまま) なので、
##   x = 前へ倒す (+ でうなずく・腕や脚は後ろへ)、y = 左へひねる、z = 左へ倒す (体の左 = +X)
extends RefCounted


static func to_quats(pose: Dictionary) -> Dictionary:
	var out := {}
	var bones: Dictionary = pose.get("bones", {})
	for b in bones:
		var e: Vector3 = bones[b]
		out[b] = Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)), EULER_ORDER_YXZ).get_rotation_quaternion()
	return out


static func mirror(pose: Dictionary) -> Dictionary:
	var out := {"bones": {}, "root": pose.get("root", Vector3.ZERO) * Vector3(-1, 1, 1)}
	var bones: Dictionary = pose.get("bones", {})
	for b in bones:
		var o: String = b
		if b.ends_with(".L"):
			o = b.left(-2) + ".R"
		elif b.ends_with(".R"):
			o = b.left(-2) + ".L"
		var e: Vector3 = bones[b]
		out.bones[o] = Vector3(e.x, -e.y, -e.z)
	return out


static func names() -> Array:
	return ["立ち", "気をつけ", "歩き 1", "歩き 2", "走り", "ばんざい", "すわる", "T の字"]


## 下ろした腕が体からどれだけ開くか (度)。ちびは おなかが丸いので、腕を外へ逃がす
static func hang_for(heads: float) -> float:
	return lerpf(30.0, 12.0, clampf((heads - 2.0) / 2.5, 0.0, 1.0))


## arm_angle: 作るときの姿勢の腕の開き (体型の数値)。hang: 下ろした腕の開き
static func named(name: String, arm_angle := 45.0, hang := 12.0) -> Dictionary:
	var d := arm_angle - hang     # 腕を体の横へ下ろす
	match name:
		"立ち", "stand":
			return {"bones": {"upper_arm.L": Vector3(0, 0, -d), "upper_arm.R": Vector3(0, 0, d),
					"forearm.L": Vector3(-8, 0, 0), "forearm.R": Vector3(-8, 0, 0)}}
		"気をつけ":
			return {"bones": {"upper_arm.L": Vector3(0, 0, -arm_angle + 4), "upper_arm.R": Vector3(0, 0, arm_angle - 4)}}
		"歩き 1", "walk":
			return {"bones": {
					"upper_arm.L": Vector3(-28, 0, -d), "upper_arm.R": Vector3(28, 0, d),
					"forearm.L": Vector3(-25, 0, 0), "forearm.R": Vector3(-12, 0, 0),
					"thigh.L": Vector3(28, 0, 0), "shin.L": Vector3(12, 0, 0), "foot.L": Vector3(-12, 0, 0),
					"thigh.R": Vector3(-30, 0, 0), "shin.R": Vector3(8, 0, 0), "foot.R": Vector3(10, 0, 0),
					"chest": Vector3(2, 6, 0), "hips": Vector3(0, -6, 0)}}
		"歩き 2":
			return mirror(named("歩き 1", arm_angle, hang))
		"走り", "run":
			return {"bones": {
					"hips": Vector3(12, -8, 0), "chest": Vector3(4, 14, 0), "head": Vector3(-10, 0, 0),
					"upper_arm.L": Vector3(-55, 0, -d), "upper_arm.R": Vector3(50, 0, d),
					"forearm.L": Vector3(-85, 0, 0), "forearm.R": Vector3(-80, 0, 0),
					"thigh.L": Vector3(35, 0, 0), "shin.L": Vector3(85, 0, 0), "foot.L": Vector3(20, 0, 0),
					"thigh.R": Vector3(-60, 0, 0), "shin.R": Vector3(35, 0, 0)}}
		"ばんざい":
			return {"bones": {"upper_arm.L": Vector3(0, 0, 150 - arm_angle), "upper_arm.R": Vector3(0, 0, -150 + arm_angle),
					"forearm.L": Vector3(0, 0, 15), "forearm.R": Vector3(0, 0, -15), "head": Vector3(-8, 0, 0)}}
		"すわる", "sit":
			return {"bones": {"thigh.L": Vector3(-85, 0, 4), "thigh.R": Vector3(-85, 0, -4),
					"shin.L": Vector3(85, 0, 0), "shin.R": Vector3(85, 0, 0),
					"upper_arm.L": Vector3(-25, 0, -d), "upper_arm.R": Vector3(-25, 0, d),
					"forearm.L": Vector3(-45, 0, 0), "forearm.R": Vector3(-45, 0, 0)}, "sit": true}
		"T の字":
			return {"bones": {"upper_arm.L": Vector3(0, 0, 90 - arm_angle), "upper_arm.R": Vector3(0, 0, -90 + arm_angle)}}
	return {"bones": {}}
