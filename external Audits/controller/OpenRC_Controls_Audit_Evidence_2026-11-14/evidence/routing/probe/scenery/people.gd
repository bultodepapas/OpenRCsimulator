## Original low-poly club people. Bodies stay in the cell batch; only a few selected arms
## get a small sim_clock sway so the scenery does not add one draw per spectator.
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")


static func build(k: MeshKit, seed: int, pose: String) -> Array:
	var height: float = 1.62 + 0.26 * Palette.hash01(seed, 1)
	var scale: float = height / 1.78
	var shirt: Color = Palette.pick(Palette.SHIRTS, seed, 2)
	var trousers: Color = Palette.pick(Palette.TROUSERS, seed, 3)
	var skin: Color = Palette.pick(Palette.SKIN, seed, 4)
	var shoe: Color = Palette.col("box_black")
	var seated := pose == "sitting"
	var hip_y: float = 0.45 if seated else 0.84 * scale
	var shoulder_y: float = hip_y + (0.50 * scale if seated else 0.56 * scale)
	var neck_y: float = shoulder_y + 0.055 * scale
	var head_c := Vector3(0.0, neck_y + 0.13 * scale, 0.015 * scale if pose == "pilot" else 0.0)
	var variant := int(Palette.hash01(seed, 12) * 4.0)

	if seated:
		_seated_legs(k, scale, trousers, shoe, variant)
	else:
		_standing_legs(k, hip_y, scale, trousers, shoe, variant)
	_torso(k, hip_y, shoulder_y, scale, shirt, seed)
	# The low-poly head's chin sits just above the shoulders; run the neck slightly
	# into the head so the two surfaces overlap instead of leaving a bright seam.
	k.cylinder(0.055 * scale, 0.05 * scale, 0.11 * scale, 6,
		Vector3(0.0, shoulder_y - 0.02 * scale, 0.0), skin)
	_head(k, head_c, scale, skin, seed, pose)

	var moving: Array = []
	var animate_arm := pose == "pilot" or Palette.hash01(seed, 91) < 0.30
	var moving_side := 1.0 if animate_arm else 0.0
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector3(side * 0.215 * scale, shoulder_y - 0.055 * scale, 0.0)
		var elbow: Vector3
		var hand: Vector3
		if pose == "pilot":
			elbow = Vector3(side * 0.14 * scale, shoulder_y - 0.19 * scale, -0.17 * scale)
			hand = Vector3(side * 0.095 * scale, shoulder_y - 0.29 * scale, -0.30 * scale)
		elif seated:
			elbow = Vector3(side * 0.20 * scale, hip_y + 0.34 * scale, -0.10 * scale)
			hand = Vector3(side * (0.20 if variant % 2 == 0 else 0.12) * scale,
				hip_y + 0.08 * scale, -0.30 * scale)
		else:
			if variant == 0:
				elbow = Vector3(side * 0.30 * scale, hip_y + 0.36 * scale, 0.01)
				hand = Vector3(side * 0.31 * scale, hip_y + 0.04 * scale, -0.015)
			elif variant == 1:
				elbow = Vector3(side * 0.31 * scale, hip_y + 0.43 * scale, 0.015)
				hand = Vector3(side * 0.25 * scale, hip_y + 0.20 * scale, -0.10 * scale)
			elif variant == 2:
				elbow = Vector3(side * 0.30 * scale, hip_y + 0.32 * scale, 0.0)
				hand = Vector3(side * 0.14 * scale, hip_y + 0.28 * scale, -0.18 * scale)
			else:
				elbow = Vector3(side * 0.29 * scale, hip_y + 0.46 * scale, -0.02)
				hand = Vector3(side * 0.33 * scale, hip_y + 0.18 * scale, 0.04)

		if animate_arm and side == moving_side:
			var arm := MeshKit.new()
			_arm(arm, Vector3.ZERO, elbow - shoulder, hand - shoulder, scale, shirt, skin, seed + 23)
			var rate_ticks := 70 + posmod(seed, 35)
			moving.append({kind = "person", motion_mode = 2, kit = arm, pivot = shoulder,
				axis = Vector3.UP, rate = float(rate_ticks) / 1024.0, phase = Palette.hash01(seed, 77)})
		else:
			_arm(k, shoulder, elbow, hand, scale, shirt, skin, seed + int(side * 19.0))

	if pose == "pilot":
		var tx := Vector3(0.0, shoulder_y - 0.275 * scale, -0.32 * scale)
		k.box(Vector3(0.23, 0.15, 0.09) * scale, tx, Palette.col("box_black"), true)
		k.box(Vector3(0.16, 0.025, 0.035) * scale, tx + Vector3(0.0, 0.085 * scale, -0.012),
			Palette.col("steel_dark"), true)
		for side: float in [-1.0, 1.0]:
			k.beam(tx + Vector3(side * 0.075 * scale, 0.08 * scale, 0.005),
				tx + Vector3(side * 0.10 * scale, 0.28 * scale, 0.05), 0.012 * scale, Palette.col("steel_dark"))

	return moving


static func _standing_legs(k: MeshKit, hip_y: float, scale: float, trousers: Color, shoe: Color, variant: int) -> void:
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(side * 0.095 * scale, hip_y, 0.0)
		var knee_z: float = 0.06 * scale if (variant == 1 and side > 0.0) else 0.0
		var knee := Vector3(side * 0.105 * scale, 0.47 * scale, knee_z)
		var ankle := Vector3(side * (0.12 if variant == 2 else 0.10) * scale, 0.075 * scale,
			(-0.035 if variant == 3 and side < 0.0 else 0.015) * scale)
		k.beam(hip, knee, 0.145 * scale, trousers)
		k.beam(knee, ankle, 0.12 * scale, trousers.darkened(0.04))
		var shoe_center := Vector3(ankle.x, 0.0375 * scale, ankle.z - 0.055 * scale)
		k.box(Vector3(0.14, 0.075, 0.235) * scale, shoe_center, shoe, true)


static func _seated_legs(k: MeshKit, scale: float, trousers: Color, shoe: Color, variant: int) -> void:
	var seat_y := 0.45
	for side: float in [-1.0, 1.0]:
		var hip := Vector3(side * 0.09 * scale, seat_y, 0.0)
		var knee := Vector3(side * 0.105 * scale, seat_y - 0.035 * scale,
			-0.40 * scale - (0.04 * scale if variant == 1 and side > 0.0 else 0.0))
		var ankle := Vector3(side * 0.11 * scale, 0.09 * scale, knee.z - 0.04 * scale)
		k.beam(hip, knee, 0.15 * scale, trousers)
		k.beam(knee, ankle, 0.12 * scale, trousers.darkened(0.04))
		var shoe_center := Vector3(ankle.x, 0.0375 * scale, ankle.z - 0.045 * scale)
		k.box(Vector3(0.14, 0.075, 0.22) * scale, shoe_center, shoe, true)


static func _torso(k: MeshKit, hip_y: float, shoulder_y: float, scale: float, shirt: Color, seed: int) -> void:
	var torso_h: float = shoulder_y - hip_y
	k.block(Vector3(0.34, 0.17, 0.22) * scale, Vector3(0.0, hip_y, 0.0), shirt.darkened(0.04))
	k.block(Vector3(0.42 * scale, maxf(0.12 * scale, torso_h - 0.12 * scale), 0.235 * scale),
		Vector3(0.0, hip_y + 0.13 * scale, 0.0), shirt, shirt.lightened(0.04))
	var belt_y := hip_y + 0.08 * scale
	k.box(Vector3(0.35, 0.035, 0.23) * scale, Vector3(0.0, belt_y, 0.0),
		Palette.col("box_black").darkened(0.1), true)
	k.box(Vector3(0.06, 0.045, 0.018) * scale, Vector3(0.0, belt_y, -0.124 * scale),
		Palette.col("steel"), true)
	# A small collar/placket breaks up the single-colour torso without adding textures.
	k.box(Vector3(0.11, 0.07, 0.025) * scale, Vector3(0.0, shoulder_y - 0.055 * scale, -0.13 * scale),
		shirt.lightened(0.16), true)
	var seam := Palette.col("trim") if Palette.hash01(seed, 44) < 0.18 else shirt.darkened(0.12)
	k.box(Vector3(0.025, maxf(0.16, torso_h * 0.55), 0.018) * scale,
		Vector3(0.0, hip_y + torso_h * 0.52, -0.121 * scale), seam, true)
	if Palette.hash01(seed, 46) < 0.42:
		for side: float in [-1.0, 1.0]:
			k.box(Vector3(0.09, 0.085, 0.025) * scale,
				Vector3(side * 0.12 * scale, shoulder_y - 0.20 * scale, -0.127 * scale),
				shirt.darkened(0.06), true)


static func _head(k: MeshKit, center: Vector3, scale: float, skin: Color, seed: int, pose: String) -> void:
	var face: Color = skin.lightened(0.035)
	k.ellipsoid(center, Vector3(0.19, 0.245, 0.19) * scale, face, seed, 8, 4)
	for side: float in [-1.0, 1.0]:
		k.ellipsoid(center + Vector3(side * 0.095 * scale, -0.015 * scale, 0.0),
			Vector3(0.045, 0.065, 0.045) * scale, skin, seed + int(side * 3.0), 6, 3)
	# Nose and brows face the local −Z direction, which reads better at the close pit cameras.
	k.box(Vector3(0.035, 0.048, 0.055) * scale, center + Vector3(0.0, -0.018 * scale, -0.105 * scale), face, true)
	var hair: Color = Palette.pick([Color("#3b2a1e"), Color("#6b4a2b"), Color("#a08060"), Color("#1e1e1e"), Color("#9d9a8e")], seed, 8)
	if Palette.hash01(seed, 6) < 0.38:
		var hat: Color = Palette.pick(Palette.HATS, seed, 7)
		k.ellipsoid(center + Vector3(0.0, 0.095 * scale, 0.005), Vector3(0.205, 0.115, 0.205) * scale, hat, seed + 7, 7, 3)
		k.box(Vector3(0.25, 0.025, 0.14) * scale,
			center + Vector3(0.0, 0.065 * scale, -0.105 * scale), hat.darkened(0.05), true)
	else:
		k.ellipsoid(center + Vector3(0.0, 0.075 * scale, 0.02 * scale),
			Vector3(0.195, 0.10, 0.19) * scale, hair, seed + 8, 7, 3)
	if pose == "pilot":
		# A narrow visor gives the pilot an upward, field-facing silhouette.
		k.box(Vector3(0.20, 0.035, 0.16) * scale,
			center + Vector3(0.0, 0.055 * scale, -0.10 * scale), Palette.col("steel_dark"), true)


static func _arm(k: MeshKit, shoulder: Vector3, elbow: Vector3, hand: Vector3,
		scale: float, shirt: Color, skin: Color, seed: int) -> void:
	k.ellipsoid(shoulder, Vector3(0.16, 0.15, 0.17) * scale, shirt, seed, 7, 3)
	k.beam(shoulder, elbow, 0.115 * scale, shirt.darkened(0.035))
	k.ellipsoid(elbow, Vector3(0.105, 0.105, 0.105) * scale, shirt, seed + 1, 6, 3)
	k.beam(elbow, hand, 0.082 * scale, shirt)
	k.ellipsoid(hand, Vector3(0.075, 0.085, 0.07) * scale, skin, seed + 2, 7, 3)
