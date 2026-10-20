## SCENERY-PLAN SC-06…SC-15: the procedural prop library. Each prefab draws itself into a MeshKit in local metres:
## X right, Y up, −Z the front, origin on the ground at the footprint centre. Sizes are real-world targets with their
## evidence (kind: borrowed = a published real structure, estimated = a design choice); test_scenery_build.gd checks
## every mesh against CATALOG. Moving parts (rotors, flags) are returned separately so they can animate on sim_clock.
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Furniture = preload("res://scenery/club_furniture.gd")
const ClubSign = preload("res://scenery/club_sign.gd")
const ClubShed = preload("res://scenery/club_shed.gd")
const PitChair = preload("res://scenery/pit_chair.gd")
const People = preload("res://scenery/people.gd")
const Vegetation = preload("res://scenery/vegetation.gd")
const PIT_ROOF_FACE := Color(1.0, 0.0, 1.0)
const PIT_ROOF_UNDER := Color(0.0, 1.0, 1.0)
const PIT_SLAB_FACE := Color(1.0, 1.0, 0.0)

## id → size (w × h × l, m), tier (landmark | standard | ornament), shadow, evidence. `size` is the expected bounding box
## of the built mesh within ±10 % (test). Flight-box props must stay ≤ 1.5 m tall (loader rule).
const CATALOG := {
	"pit_shelter": {size = Vector3(29.0, 3.45, 5.8), tier = "landmark", shadow = true, kind = "borrowed",
		source = "Covered pit rows 3 × 28 m (Aeromodelers of Perrine, FL) and OTOW pole barn eaves ≈ 3 m (scenery report 03)"},
	"pavilion": {size = Vector3(10.0, 4.6, 9.6), tier = "landmark", shadow = true, kind = "borrowed",
		source = "Club pavilions 6 × 9 m (Perrine) to 10 × 5 m (Tri-County), hip roof (OTOW); veranda added (report 03)"},
	"shed": {size = Vector3(3.4, 3.0, 2.9), tier = "standard", shadow = true, kind = "estimated", source = "Garden shed 3 × 2.4 m"},
	"picnic_table": {size = Vector3(1.8, 0.76, 1.6), tier = "standard", shadow = true, kind = "estimated", source = "Standard 6 ft picnic table"},
	"bench": {size = Vector3(1.8, 0.85, 0.5), tier = "ornament", shadow = true, kind = "estimated", source = "Park bench"},
	"flagpole": {size = Vector3(0.5, 8.1, 0.5), tier = "standard", shadow = false, kind = "estimated", source = "8 m club flagpole"},
	"club_sign": {size = Vector3(2.5, 2.2, 0.14), tier = "standard", shadow = true, kind = "estimated", source = "Club sign board"},
	"round_bale": {size = Vector3(1.2, 1.2, 1.2), tier = "standard", shadow = true, kind = "borrowed", source = "Round bale 1.2 m (scenery report 01, SC-12)"},
	"bale_stack": {size = Vector3(2.5, 1.85, 2.4), tier = "standard", shadow = true, kind = "estimated", source = "Big square bales 2.4 × 1.2 × 0.9 m, two high"},
	"shade_tree": {size = Vector3(18.0, 14.0, 18.0), tier = "standard", shadow = true, imported_vegetation = true, variable = true, kind = "estimated", source = "Conservative alias envelope including the 14 m downloaded club maple; actual dimensions use VegetationPlacement"},
	"sapling": {size = Vector3(3.0, 4.8, 3.1), tier = "standard", shadow = true, imported_vegetation = true, variable = true, kind = "estimated", source = "LU-22 Quaternius Standard CommonTree_1 and CommonTree_3, uniformly fitted to 3.2–4.8 m"},
	"bush": {size = Vector3(1.6, 0.85, 1.6), tier = "ornament", shadow = false, variable = true, kind = "estimated", source = "Garden shrub"},
	"flower_clump": {size = Vector3(0.45, 0.40, 0.45), tier = "ornament", shadow = false, variable = true, kind = "estimated", source = "Compact flower-border bouquet (visual estimate)"},
	"person_standing": {size = Vector3(0.65, 1.78, 0.36), tier = "ornament", shadow = true, kind = "estimated", source = "LU-21 MPFB posed mesh envelope; uniform adult scale"},
	"person_sitting": {size = Vector3(0.61, 1.444, 0.75), tier = "ornament", shadow = false, kind = "estimated", source = "LU-21 Anrico sitting03; seat-contact height 0.4742 m plus 0.006 m fitting offset"},
	"person_pilot": {size = Vector3(0.67, 1.78, 0.45), tier = "ornament", shadow = true, kind = "estimated", source = "LU-21 MPFB pilot pose with transmitter; uniform adult scale"},
	"avanti_cradle": {size = Vector3(0.7, 0.48, 1.63), tier = "standard", shadow = true, kind = "estimated",
		source = "Original padded trestle cradle for the gear-up Ventage Jet fleet snapshot; visual support estimate"},
	"barn": {size = Vector3(10.8, 7.5, 14.8), tier = "landmark", shadow = false, kind = "estimated", source = "Gambrel barn 10 × 14 m"},
	"silo": {size = Vector3(5.6, 15.0, 5.6), tier = "landmark", shadow = false, kind = "estimated", source = "Farm silo, 14 m min (SC-13: tall parts carry the farmstead)"},
	"farmhouse": {size = Vector3(10.0, 7.2, 8.0), tier = "standard", shadow = false, kind = "estimated", source = "Two-storey farmhouse"},
	"tractor": {size = Vector3(2.35, 2.35, 3.6), tier = "ornament", shadow = true, kind = "estimated", source = "Utility tractor"},
	"turbine": {size = Vector3(6.4, 81.6, 11.0), tier = "landmark", shadow = false, kind = "estimated",
		source = "Onshore 2–3 MW turbine, 80 m hub, 41 m blades (82 m rotor, a separate moving part); rotor 6.6 m ahead of the tower axis (SC-01 depth rule)"},
	"pylon": {size = Vector3(8.65, 30.0, 8.45), tier = "landmark", shadow = false, kind = "estimated", source = "iPoly3D CC0 transmission tower TYK3rPu7E5, uniformly fitted to 30 m"},
	"church": {size = Vector3(9.0, 32.0, 25.0), tier = "landmark", shadow = false, kind = "estimated", source = "Village church with spire"},
	"village_house": {size = Vector3(9.0, 8.0, 11.0), tier = "standard", shadow = false, variable = true, kind = "estimated", source = "Village house"},
}


## Draws prefab `id` into `kit` (local frame). Returns moving parts: [{kind, kit, pivot (local), axis, rate}] (may be empty).
static func build(id: String, kit: MeshKit, seed: int, theme: String) -> Array:
	match id:
		"pit_shelter": return _pit_shelter(kit, seed)
		"pavilion": return _pavilion(kit, seed)
		"shed": _shed(kit)
		"picnic_table": _picnic_table(kit)
		"bench": _bench(kit)
		"flagpole": return _flagpole(kit)
		"club_sign": _club_sign(kit)
		"round_bale": _round_bale(kit, seed)
		"bale_stack": _bale_stack(kit)
		"shade_tree": return Vegetation.shade_tree(kit, seed, theme)
		"bush": return Vegetation.bush(kit, seed, theme)
		"flower_clump": _flower_clump(kit, seed, theme)
		"person_standing": return People.build(kit, seed, "standing")
		"person_sitting": return People.build(kit, seed, "sitting")
		"person_pilot": return People.build(kit, seed, "pilot")
		"avanti_cradle": _avanti_cradle(kit)
		"barn": _barn(kit)
		"silo": _silo(kit)
		"farmhouse": _farmhouse(kit)
		"tractor": _tractor(kit)
		"turbine": return _turbine(kit, seed)
		"pylon": _pylon(kit)
		"church": _church(kit)
		"village_house": _village_house(kit, seed)
		_: push_error("scenery: unknown prefab %s" % id)
	return []


static func _c(name: String) -> Color:
	return Palette.col(name)


# ---------------- the club ----------------

## Open pole-barn pit shelter: 28 m long (X), 5 m deep (Z), roof sloping back, corrugated light steel, furniture under it.
static func _pit_shelter(k: MeshKit, seed: int) -> Array:
	var length := 28.0
	var depth := 5.0
	var front_h := 3.2
	var back_h := 2.7
	# The yellow top-face tag selects the existing CC0 concrete material. The
	# exposed edge retains its quieter plain-concrete tone in the same mesh.
	k.block(Vector3(length + 0.6, 0.1, depth + 0.6), Vector3(0, 0, 0), _c("concrete"), PIT_SLAB_FACE)
	# Fine saw cuts divide the existing slab without adding a raised border.
	for joint in 4:
		var joint_x := -length * 0.5 + length * (joint + 1) / 5.0
		k.block(Vector3(0.014, 0.004, depth + 0.5), Vector3(joint_x, 0.1, 0), _c("concrete_dark"))
	for i in 9:
		var x := -length * 0.5 + i * length / 8.0
		var brace_direction := 1.0 if i < 4 else -1.0
		# Blue tags select lengthwise photographed timber only for these structural posts.
		var timber := Color(0.0, 0.0, 0.90 + 0.10 * Palette.hash01(seed, i, 31))
		for post_z: float in [-depth * 0.5 + 0.1, depth * 0.5 - 0.1]:
			var post_height := (front_h if post_z < 0.0 else back_h) - 0.04
			k.block(Vector3(0.16, post_height, 0.16),
				Vector3(x, 0.14, post_z), timber, timber)
			# A raised steel standoff keeps the timber clear of standing water on the slab.
			k.box(Vector3(0.21, 0.015, 0.21), Vector3(x, 0.1075, post_z), _c("steel_dark"))
			for face: float in [-1.0, 1.0]:
				k.box(Vector3(0.16, 0.16, 0.008), Vector3(x, 0.195, post_z + face * 0.083), _c("steel"))
				# Flush bolt heads read at close range without building hidden box faces.
				var bolt_z := post_z + face * 0.088
				if face > 0.0:
					k.quad(Vector3(x - 0.009, 0.221, bolt_z), Vector3(x + 0.009, 0.221, bolt_z),
						Vector3(x + 0.009, 0.239, bolt_z), Vector3(x - 0.009, 0.239, bolt_z), _c("steel_dark"))
				else:
					k.quad(Vector3(x + 0.009, 0.221, bolt_z), Vector3(x - 0.009, 0.221, bolt_z),
						Vector3(x - 0.009, 0.239, bolt_z), Vector3(x + 0.009, 0.239, bolt_z), _c("steel_dark"))
			# Both post rows transfer longitudinal loads into their rails. The lean
			# changes at the centre rather than repeating one rake for 28 m.
			var frame_h := front_h if post_z < 0.0 else back_h
			var brace_timber := Color(1.0, 0.5, 0.0) if brace_direction > 0.0 else Color(0.0, 0.5, 1.0)
			k.beam(Vector3(x, frame_h - 0.6, post_z),
				Vector3(x + brace_direction * 0.5, frame_h + 0.05, post_z),
				0.08, brace_timber)
			_pit_roof_joint(k, x, frame_h + 0.05, post_z, brace_direction)
		# A transverse rafter spans the two longitudinal rails at each frame.
		# The rafter bears on the lengthwise rails and stays below the roof sheet.
		k.beam(Vector3(x, front_h + 0.05, -depth * 0.5), Vector3(x, back_h + 0.05, depth * 0.5), 0.14, Color(0.0, 0.77, 0.0))
	k.beam(Vector3(-length * 0.5, front_h + 0.05, -depth * 0.5 + 0.1), Vector3(length * 0.5, front_h + 0.05, -depth * 0.5 + 0.1), 0.2, Color(0.88, 0.0, 0.0))
	k.beam(Vector3(-length * 0.5, back_h + 0.05, depth * 0.5 - 0.1), Vector3(length * 0.5, back_h + 0.05, depth * 0.5 - 0.1), 0.2, Color(0.85, 0.0, 0.0))
	# Folded standing-seam roof overhangs 0.4 m front/back and 0.3 m at the ends.
	var y0 := front_h + 0.2
	var y1 := back_h + 0.2
	var hx := length * 0.5 + 0.3
	var z0 := -depth * 0.5 - 0.4
	var z1 := depth * 0.5 + 0.4
	var slope := (y1 - y0) / (depth)
	var yf := y0 - 0.4 * slope
	var yb := y1 + 0.4 * slope
	# Folded standing seams are part of the sheet, with sloping shoulders and a
	# closed crest. The photograph contributes finer corrugation and fasteners.
	var panels := int(roundf((2.0 * hx) / 0.75))
	var panel_width := (2.0 * hx) / float(panels)
	for panel in panels:
		var x0 := -hx + panel * panel_width
		var x1 := x0 + panel_width
		var x_profile := [x0, x0 + 0.012, x0 + 0.030, x1 - 0.030, x1 - 0.012, x1]
		var rise_profile := [0.028, 0.028, 0.0, 0.0, 0.028, 0.028]
		for section in 5:
			var left_x: float = x_profile[section]
			var right_x: float = x_profile[section + 1]
			var left_rise: float = rise_profile[section]
			var right_rise: float = rise_profile[section + 1]
			k.quad(Vector3(left_x, yf + left_rise, z0), Vector3(left_x, yb + left_rise, z1),
				Vector3(right_x, yb + right_rise, z1), Vector3(right_x, yf + right_rise, z0), PIT_ROOF_FACE)
	k.quad(Vector3(-hx, yf - 0.05, z0), Vector3(hx, yf - 0.05, z0),
		Vector3(hx, yb - 0.05, z1), Vector3(-hx, yb - 0.05, z1), PIT_ROOF_UNDER)
	for purlin_z: float in [-1.55, 0.0, 1.55]:
		var purlin_y := lerpf(yf, yb, (purlin_z - z0) / (z1 - z0)) - 0.10
		k.beam(Vector3(-length * 0.5, purlin_y, purlin_z),
			Vector3(length * 0.5, purlin_y, purlin_z), 0.10, Color(0.81, 0.0, 0.0))
	k.quad(Vector3(-hx, yf - 0.22, z0), Vector3(hx, yf - 0.22, z0), Vector3(hx, yf, z0), Vector3(-hx, yf, z0), Color(0.90, 0.0, 0.0)) # fascia
	var gutter_col := _c("roof_metal_dark").darkened(0.25)
	# Folded front drip lip conceals the open sheet edge above the timber fascia.
	k.quad(Vector3(hx, yf - 0.045, z0 - 0.003), Vector3(-hx, yf - 0.045, z0 - 0.003),
		Vector3(-hx, yf + 0.018, z0 - 0.003), Vector3(hx, yf + 0.018, z0 - 0.003), gutter_col)
	# Three thin folded steel strips form an open low-side gutter, not a solid rail.
	var outlet_x := length * 0.5 - 0.04
	var gutter_z := z1 + 0.04
	var bottom_limits := [-hx, -outlet_x - 0.045, -outlet_x + 0.045,
		outlet_x - 0.045, outlet_x + 0.045, hx]
	for segment in 3:
		var start_x: float = bottom_limits[segment * 2]
		var stop_x: float = bottom_limits[segment * 2 + 1]
		k.box(Vector3(stop_x - start_x, 0.012, 0.13),
			Vector3((start_x + stop_x) * 0.5, yb - 0.135, gutter_z), gutter_col, true)
	# Narrow bottom rails leave two 90 mm square outlet holes, one at each end.
	for side: float in [-1.0, 1.0]:
		for rail_z: float in [-0.055, 0.055]:
			k.box(Vector3(0.09, 0.012, 0.02),
				Vector3(side * outlet_x, yb - 0.135, gutter_z + rail_z), gutter_col, true)
	k.box(Vector3(2.0 * hx, 0.105, 0.012), Vector3(0, yb - 0.083, z1 - 0.025), gutter_col, true)
	k.box(Vector3(2.0 * hx, 0.105, 0.012), Vector3(0, yb - 0.083, z1 + 0.10), gutter_col, true)
	# Rake caps fold over the sheet and down both exposed ends. The channels
	# terminate at outlet/downpipe assemblies attached to the back corner posts.
	for side: float in [-1.0, 1.0]:
		var outer_x := side * hx
		var inner_x := side * (hx - 0.10)
		if side > 0.0:
			k.quad(Vector3(inner_x, yf + 0.035, z0), Vector3(inner_x, yb + 0.035, z1),
				Vector3(outer_x, yb + 0.035, z1), Vector3(outer_x, yf + 0.035, z0), gutter_col)
			k.quad(Vector3(outer_x + 0.003, yf - 0.065, z0), Vector3(outer_x + 0.003, yf + 0.035, z0),
				Vector3(outer_x + 0.003, yb + 0.035, z1), Vector3(outer_x + 0.003, yb - 0.065, z1), gutter_col)
		else:
			k.quad(Vector3(outer_x, yf + 0.035, z0), Vector3(outer_x, yb + 0.035, z1),
				Vector3(inner_x, yb + 0.035, z1), Vector3(inner_x, yf + 0.035, z0), gutter_col)
			k.quad(Vector3(outer_x - 0.003, yb - 0.065, z1), Vector3(outer_x - 0.003, yb + 0.035, z1),
				Vector3(outer_x - 0.003, yf + 0.035, z0), Vector3(outer_x - 0.003, yf - 0.065, z0), gutter_col)
		k.box(Vector3(0.012, 0.105, 0.13), Vector3(side * (hx - 0.006), yb - 0.083, z1 + 0.04), gutter_col, true)
		var pipe_x := side * outlet_x
		var pipe_z := depth * 0.5 + 0.04
		_pit_pipe_segment(k, Vector3(pipe_x, yb - 0.105, gutter_z),
			Vector3(pipe_x, yb - 0.24, pipe_z), 0.034, gutter_col)
		_pit_pipe_segment(k, Vector3(pipe_x, yb - 0.24, pipe_z),
			Vector3(pipe_x, 0.20, pipe_z), 0.034, gutter_col)
		# The outlet discharges beyond the slab edge rather than onto the pit floor.
		_pit_pipe_segment(k, Vector3(pipe_x, 0.20, pipe_z),
			Vector3(pipe_x, 0.17, pipe_z + 0.40), 0.034, gutter_col)
		for band_y: float in [0.85, 2.15]:
			k.cylinder(0.043, 0.043, 0.025, 8,
				Vector3(pipe_x, band_y - 0.0125, pipe_z), _c("steel"), false)
			k.beam(Vector3(pipe_x, band_y, pipe_z - 0.025),
				Vector3(pipe_x, band_y, depth * 0.5 - 0.015), 0.025, _c("steel_dark"))
	# Furniture under the roof: tables along the back, stands, boxes, chairs, coolers. Seeded variety.
	for i in 6:
		var tx := -length * 0.5 + 2.4 + i * 4.6
		var service := "charger" if i == 1 else "fuel" if i == 4 else ""
		_pit_table(k, Vector3(tx, 0.1, depth * 0.5 - 1.1), seed * 31 + i, service)
	for i in 5:
		var cx := -length * 0.5 + 4.2 + i * 5.3 + (Palette.hash01(seed, i, 7) - 0.5) * 1.2
		if Palette.hash01(seed, i, 3) < 0.75:
			_folding_chair(k, Vector3(cx, 0.1, -0.4 + Palette.hash01(seed, i, 5) * 0.8), Palette.hash01(seed, i, 9) * 1.2 - 0.6, seed + i)
		if Palette.hash01(seed, i, 11) < 0.45:
			var cool: Color = Palette.pick([_c("cooler_blue"), _c("cooler_red"), _c("cooler_white")], seed, i)
			k.block(Vector3(0.6, 0.42, 0.38), Vector3(cx + 1.2, 0.1, 0.9), cool, _c("cooler_white"))
	# a flight box and a model stand in the open front strip
	for i in 3:
		var bx := -length * 0.5 + 6.0 + i * 8.5
		k.block(Vector3(0.75, 0.32, 0.32), Vector3(bx, 0.1, -1.4), Palette.pick([_c("box_black"), _c("box_orange"), _c("wood_light")], seed, i, 1))
		k.block(Vector3(0.14, 0.3, 0.14), Vector3(bx + 0.55, 0.1, -1.35), Palette.pick([_c("fuel_red"), _c("fuel_green")], seed, i, 2))
	return []


## A folded seat plate and flush fasteners tie the rafter, rail, and post
## together. The small strap marks the brace termination on the rail face.
static func _pit_roof_joint(k: MeshKit, x: float, y: float, post_z: float, brace_direction: float) -> void:
	var outward := -1.0 if post_z < 0.0 else 1.0
	var plate_z := post_z + outward * 0.103
	k.box(Vector3(0.15, 0.12, 0.006), Vector3(x, y, plate_z), _c("steel"))
	var bolt_z := post_z + outward * 0.107
	for bolt_x: float in [-0.043, 0.043]:
		_pit_face_quad(k, x + bolt_x, y - 0.008, bolt_z,
			0.018, 0.018, outward, _c("steel_dark"))
	var brace_x := x + brace_direction * 0.5
	var strap_z := post_z + outward * 0.105
	_pit_face_quad(k, brace_x, y - 0.025, strap_z,
		0.075, 0.11, outward, _c("steel"))
	_pit_face_quad(k, brace_x, y - 0.03, strap_z + outward * 0.001,
		0.016, 0.016, outward, _c("steel_dark"))


static func _pit_face_quad(k: MeshKit, x: float, y: float, z: float,
		width: float, height: float, outward: float, color: Color) -> void:
	var left := x - width * 0.5
	var right := x + width * 0.5
	var bottom := y - height * 0.5
	var top := y + height * 0.5
	if outward < 0.0:
		k.quad(Vector3(right, bottom, z), Vector3(left, bottom, z),
			Vector3(left, top, z), Vector3(right, top, z), color)
	else:
		k.quad(Vector3(left, bottom, z), Vector3(right, bottom, z),
			Vector3(right, top, z), Vector3(left, top, z), color)


static func _pit_pipe_segment(k: MeshKit, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var delta := b - a
	var axis := delta.normalized()
	var side := axis.cross(Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var forward := side.cross(axis)
	var saved := k.xf
	k.xf = saved * Transform3D(Basis(side, axis, forward), a)
	k.cylinder(radius, radius, delta.length(), 8, Vector3.ZERO, color, false)
	k.xf = saved


static func _pit_table(k: MeshKit, at: Vector3, seed: int, service: String = "") -> void:
	var top := _c("wood_light") if Palette.hash01(seed, 1) < 0.6 else _c("tablecloth")
	k.block(Vector3(2.4, 0.06, 0.8), at + Vector3(0, 0.74, 0), top)
	for sx: float in [-1.1, 1.1]:
		for sz: float in [-0.32, 0.32]:
			k.block(Vector3(0.06, 0.74, 0.06), at + Vector3(sx, 0, sz), _c("steel"))
	# model stand (foam cradle) and a field box / transmitter on top
	if Palette.hash01(seed, 2) < 0.7:
		k.block(Vector3(0.3, 0.22, 0.5), at + Vector3(-0.5, 0.8, 0), _c("foam"))
		k.block(Vector3(0.3, 0.22, 0.5), at + Vector3(0.5, 0.8, 0), _c("foam"))
	if Palette.hash01(seed, 3) < 0.6:
		k.block(Vector3(0.24, 0.1, 0.18), at + Vector3(0.8, 0.8, 0.15), _c("box_black"))
	if Palette.hash01(seed, 4) < 0.5:
		k.block(Vector3(0.5, 0.25, 0.3), at + Vector3(-0.9, 0.8, 0.2), Palette.pick([_c("box_orange"), _c("box_black"), _c("cooler_blue")], seed, 5))
	match service:
		"charger":
			_battery_charger(k, at + Vector3(0, 0.8, 0), seed)
		"fuel":
			_fuel_jug(k, at + Vector3(0, 0.8, 0), seed)


## Compact charger and LiPo pack, kept in the gap between the table's two foam cradles.
static func _battery_charger(k: MeshKit, at: Vector3, seed: int) -> void:
	var case: Color = Palette.pick([_c("box_black"), _c("steel_dark")], seed, 17)
	k.block(Vector3(0.27, 0.14, 0.22), at, case, _c("steel"))
	k.block(Vector3(0.11, 0.045, 0.014), at + Vector3(-0.03, 0.065, -0.116), _c("fabric_green"))
	k.block(Vector3(0.022, 0.026, 0.014), at + Vector3(0.07, 0.04, -0.116), _c("fuel_red"))
	k.block(Vector3(0.022, 0.026, 0.014), at + Vector3(0.10, 0.04, -0.116), _c("fuel_green"))
	var pack := at + Vector3(0.235, 0, 0.01)
	k.block(Vector3(0.14, 0.08, 0.13), pack, _c("box_black"), _c("tablecloth"))
	k.beam(at + Vector3(0.13, 0.09, 0.02), pack + Vector3(-0.07, 0.06, -0.025), 0.009, _c("fuel_red"))
	k.beam(at + Vector3(0.13, 0.075, 0.04), pack + Vector3(-0.07, 0.045, 0.005), 0.009, _c("steel_dark"))


## Small moulded fuel can with a raised handle, filler neck and cap.
static func _fuel_jug(k: MeshKit, at: Vector3, seed: int) -> void:
	var body: Color = Palette.pick([_c("fuel_red"), _c("fuel_green")], seed, 29)
	k.block(Vector3(0.16, 0.19, 0.13), at, body, body.darkened(0.1))
	var left := at + Vector3(-0.045, 0.17, 0.02)
	var right := at + Vector3(0.045, 0.17, 0.02)
	k.beam(left, left + Vector3(0, 0.09, 0), 0.016, body.darkened(0.1))
	k.beam(right, right + Vector3(0, 0.09, 0), 0.016, body.darkened(0.1))
	k.beam(left + Vector3(0, 0.09, 0), right + Vector3(0, 0.09, 0), 0.016, body)
	var neck := at + Vector3(0.035, 0.19, -0.025)
	k.cylinder(0.023, 0.023, 0.035, 8, neck, body.lightened(0.12))
	k.cylinder(0.031, 0.031, 0.012, 8, neck + Vector3(0, 0.035, 0), _c("wood_light"))


static func _folding_chair(k: MeshKit, at: Vector3, yaw: float, seed: int) -> void:
	PitChair.build(k,at,yaw,seed)


## The club pavilion: white walls with windows and a door, hip roof, veranda toward the field (−Z).
static func _pavilion(k: MeshKit, seed: int) -> Array:
	var w := 9.0
	var d := 6.0
	var h := 2.7
	k.block(Vector3(w + 1.0, 0.15, d + 3.6), Vector3(0, 0, -1.3), _c("concrete"), _c("concrete"))
	# Two fine joints break the broad porch slab into realistic pours.
	for joint_x: float in [-1.7, 1.7]:
		k.block(Vector3(0.012, 0.003, 2.7), Vector3(joint_x, 0.15, -4.55), _c("concrete_dark"))
	k.block(Vector3(w, h, d), Vector3(0, 0.15, 0), _c("wall_white"))
	k.block(Vector3(w + 0.04, 0.3, d + 0.04), Vector3(0, 0.15, 0), _c("concrete_dark")) # plinth
	for sx: float in [-1.0, 1.0]: # corner trims
		for sz: float in [-1.0, 1.0]:
			k.block(Vector3(0.14, h, 0.14), Vector3(sx * w * 0.5, 0.15, sz * d * 0.5), _c("trim"))
	var f := -d * 0.5 - 0.02
	_window(k, Vector3(-2.8, 1.05, f), 1.5, 1.05, false, true)
	_window(k, Vector3(2.8, 1.05, f), 1.5, 1.05, false, true)
	_door(k, Vector3(0, 0.15, f), 1.0, 2.1, _c("door_green"), false, true)
	# Flush, slightly wider concrete threshold at the existing entry.
	k.block(Vector3(1.14, 0.035, 0.16), Vector3(0, 0.15, f - 0.06), _c("concrete_dark"))
	var b := d * 0.5 + 0.02
	_window(k, Vector3(-2.2, 1.3, b), 1.0, 0.7, true, true)
	_window(k, Vector3(2.2, 1.3, b), 1.0, 0.7, true, true)
	var saved := k.xf
	for side: float in [-1.0, 1.0]: # side windows: rotate the frame
		k.xf = saved * Transform3D(Basis(Vector3.UP, side * PI / 2.0), Vector3.ZERO)
		_window(k, Vector3(0, 1.1, -w * 0.5 - 0.02), 1.2, 0.9, false, true)
	k.xf = saved
	_pavilion_wall_course(k, w, d)
	k.hip_roof(w, d, h + 0.15, 1.8, 0.5, _c("roof_slate"))
	# Thin capped ridges give the slate a constructed termination above the roof skin.
	var hip_ridge_half := 5.0 - 3.5 * 0.98
	var ridge_left := Vector3(-hip_ridge_half, 4.70, 0)
	var ridge_right := Vector3(hip_ridge_half, 4.70, 0)
	var ridge_col := _c("roof_slate").lightened(0.18)
	k.beam(ridge_left, ridge_right, 0.075, ridge_col)
	for p: Vector3 in [Vector3(-5.0, 2.88, -3.5), Vector3(-5.0, 2.88, 3.5)]:
		k.beam(p, ridge_left, 0.067, ridge_col)
	for p: Vector3 in [Vector3(5.0, 2.88, -3.5), Vector3(5.0, 2.88, 3.5)]:
		k.beam(p, ridge_right, 0.067, ridge_col)
	# Eave boards follow the existing hip roof, staying inside its overhang.
	var eave_x := w * 0.5 + 0.5 - 0.05
	var eave_z := d * 0.5 + 0.5 - 0.05
	var fascia_y := h + 0.15 - 0.05
	var fascia_col := _c("roof_slate").darkened(0.14)
	for side: float in [-1.0, 1.0]:
		k.beam(Vector3(-eave_x, fascia_y, side * eave_z), Vector3(eave_x, fascia_y, side * eave_z), 0.1, fascia_col)
		k.beam(Vector3(side * eave_x, fascia_y, -eave_z), Vector3(side * eave_x, fascia_y, eave_z), 0.1, fascia_col)
	# Rear rain leaders sit on the wall beneath the existing eave and return to the gutter.
	for side: float in [-1.0, 1.0]:
		var pipe_x := side * 4.28
		k.beam(Vector3(pipe_x, 0.16, d * 0.5 + 0.045), Vector3(pipe_x, h + 0.03, d * 0.5 + 0.045), 0.045, _c("steel_dark"))
		k.beam(Vector3(pipe_x, h + 0.03, d * 0.5 + 0.045), Vector3(pipe_x, h + 0.03, d * 0.5 + 0.43), 0.045, _c("steel_dark"))
	# veranda: mono-pitch roof on four posts in front
	var vz0 := -d * 0.5
	var vz1 := -d * 0.5 - 3.0
	for x: float in [-4.2, -1.4, 1.4, 4.2]:
		k.block(Vector3(0.14, 2.45, 0.14), Vector3(x, 0.15, vz1 + 0.15), _c("trim"))
	k.quad(Vector3(-w * 0.5 - 0.2, 2.62, vz1 - 0.2), Vector3(-w * 0.5 - 0.2, 2.95, vz0), Vector3(w * 0.5 + 0.2, 2.95, vz0),
		Vector3(w * 0.5 + 0.2, 2.62, vz1 - 0.2), _c("roof_metal_dark"))
	k.quad(Vector3(-w * 0.5 - 0.2, 2.58, vz1 - 0.2), Vector3(w * 0.5 + 0.2, 2.58, vz1 - 0.2), Vector3(w * 0.5 + 0.2, 2.91, vz0),
		Vector3(-w * 0.5 - 0.2, 2.91, vz0), _c("wood_light"))
	# Raised longitudinal seams at realistic sheet spacing on the lean-to roof.
	for i in 18:
		var seam_x := -4.35 + float(i) * 0.51
		k.beam(Vector3(seam_x, 2.655, vz1 - 0.18),
			Vector3(seam_x, 2.985, vz0 - 0.02), 0.017, _c("roof_metal_dark").lightened(0.16))
	# The veranda's front fascia and slim side barge trim close the exposed sheet edges.
	k.beam(Vector3(-4.62, 2.64, vz1 - 0.16), Vector3(4.62, 2.64, vz1 - 0.16), 0.08, _c("wood_light"))
	for side: float in [-1.0, 1.0]:
		k.beam(Vector3(side * 4.62, 2.62, vz1 - 0.16), Vector3(side * 4.62, 2.95, vz0 + 0.08), 0.055, _c("wood_light"))
	k.beam(Vector3(-w * 0.5 - 0.2, 2.55, vz1 + 0.15), Vector3(w * 0.5 + 0.2, 2.55, vz1 + 0.15), 0.14, _c("trim"))
	# railing between the posts, open at the steps in the middle
	for seg: Array in [[-4.2, -1.4], [1.4, 4.2]]:
		k.beam(Vector3(seg[0], 0.95, vz1 + 0.15), Vector3(seg[1], 0.95, vz1 + 0.15), 0.06, _c("trim"))
		for i in 6:
			var x: float = lerpf(seg[0], seg[1], (i + 0.5) / 6.0)
			k.block(Vector3(0.04, 0.8, 0.04), Vector3(x, 0.15, vz1 + 0.15), _c("trim"))
	# a bench against the front wall
	var bs := k.xf
	k.xf = bs * Transform3D(Basis.IDENTITY, Vector3(-2.8, 0.15, -d * 0.5 - 0.5))
	_bench(k)
	k.xf = bs
	return []


## A quiet plaster base course separates the pavilion wall from its concrete plinth.
## It is part of the same prefab cell mesh and sits below the windows and door panels.
static func _pavilion_wall_course(k: MeshKit, w: float, d: float) -> void:
	var y0 := 0.49
	var y1 := 0.63
	var color := _c("wall_white").darkened(0.09)
	var x0 := -w * 0.5 + 0.1
	var x1 := w * 0.5 - 0.1
	var z_front := -d * 0.5 - 0.006
	var z_back := d * 0.5 + 0.006
	k.quad(Vector3(x0, y0, z_front), Vector3(x1, y0, z_front), Vector3(x1, y1, z_front), Vector3(x0, y1, z_front), color)
	k.quad(Vector3(x1, y0, z_back), Vector3(x0, y0, z_back), Vector3(x0, y1, z_back), Vector3(x1, y1, z_back), color)
	var z0 := -d * 0.5 + 0.1
	var z1 := d * 0.5 - 0.1
	var x_left := -w * 0.5 - 0.006
	var x_right := w * 0.5 + 0.006
	k.quad(Vector3(x_right, y0, z0), Vector3(x_right, y0, z1), Vector3(x_right, y1, z1), Vector3(x_right, y1, z0), color)
	k.quad(Vector3(x_left, y0, z1), Vector3(x_left, y0, z0), Vector3(x_left, y1, z0), Vector3(x_left, y1, z1), color)


static func _window(k: MeshKit, c: Vector3, w: float, h: float, back: bool, detailed: bool = false) -> void:
	var s := 1.0 if back else -1.0 # the wall's outward normal along z
	var z := c.z
	var g := _c("glass")
	var p := [Vector3(c.x - w * 0.5, c.y, z), Vector3(c.x + w * 0.5, c.y, z), Vector3(c.x + w * 0.5, c.y + h, z), Vector3(c.x - w * 0.5, c.y + h, z)]
	if back:
		k.quad(p[1], p[0], p[3], p[2], g)
	else:
		k.quad(p[0], p[1], p[2], p[3], g)
	var t := 0.07
	var trim := _c("trim")
	k.box(Vector3(w + 2 * t, t, 0.06), Vector3(c.x, c.y - t * 0.5, z + s * 0.02), trim, true)
	k.box(Vector3(w + 2 * t, t, 0.06), Vector3(c.x, c.y + h + t * 0.5, z + s * 0.02), trim, true)
	k.box(Vector3(t, h, 0.06), Vector3(c.x - w * 0.5 - t * 0.5, c.y + h * 0.5, z + s * 0.02), trim, true)
	k.box(Vector3(t, h, 0.06), Vector3(c.x + w * 0.5 + t * 0.5, c.y + h * 0.5, z + s * 0.02), trim, true)
	k.box(Vector3(0.04, h, 0.04), Vector3(c.x, c.y + h * 0.5, z + s * 0.02), trim, true) # mullion
	k.box(Vector3(w + 0.3, 0.06, 0.16), Vector3(c.x, c.y - 0.1, z + s * 0.08), trim, true) # sill
	if detailed:
		# A simple transom divides the glass into readable upper and lower sashes.
		k.box(Vector3(w - 0.16, 0.035, 0.045), Vector3(c.x, c.y + h * 0.58, z + s * 0.035), trim.darkened(0.06), true)


static func _door(k: MeshKit, base: Vector3, w: float, h: float, col: Color, back: bool, detailed: bool = false) -> void:
	var s := 1.0 if back else -1.0
	k.box(Vector3(w, h, 0.05), base + Vector3(0, h * 0.5, s * 0.02), col, true)
	k.box(Vector3(w + 0.16, 0.08, 0.07), base + Vector3(0, h + 0.04, s * 0.03), _c("trim"), true)
	k.box(Vector3(0.08, h, 0.07), base + Vector3(-w * 0.5 - 0.04, h * 0.5, s * 0.03), _c("trim"), true)
	k.box(Vector3(0.08, h, 0.07), base + Vector3(w * 0.5 + 0.04, h * 0.5, s * 0.03), _c("trim"), true)
	k.box(Vector3(0.06, 0.06, 0.06), base + Vector3(w * 0.35, 1.0, s * 0.06), _c("steel"), true)
	if detailed:
		# Two shallow raised panels and slim edge moulding keep the entry legible at club scale.
		var panel_w := w * 0.58
		var panel_h := h * 0.26
		var panel_z := base.z + s * 0.052
		var frame_z := base.z + s * 0.056
		for fraction: float in [0.30, 0.70]:
			var cy := base.y + h * fraction
			k.box(Vector3(panel_w, panel_h, 0.012), Vector3(base.x, cy, panel_z), col.darkened(0.12), true)
			var half_w := panel_w * 0.5
			var half_h := panel_h * 0.5
			var left := base.x - half_w
			var right := base.x + half_w
			var bottom := cy - half_h
			var top := cy + half_h
			var frame_col := col.lightened(0.16)
			k.beam(Vector3(left, bottom, frame_z), Vector3(left, top, frame_z), 0.018, frame_col)
			k.beam(Vector3(right, bottom, frame_z), Vector3(right, top, frame_z), 0.018, frame_col)
			k.beam(Vector3(left, bottom, frame_z), Vector3(right, bottom, frame_z), 0.018, frame_col)
			k.beam(Vector3(left, top, frame_z), Vector3(right, top, frame_z), 0.018, frame_col)
		# Three small hinge plates align on the latch edge opposite the handle.
		for hinge_y: float in [0.42, 1.02, 1.72]:
			k.box(Vector3(0.045, 0.12, 0.012), base + Vector3(-w * 0.42, hinge_y, s * 0.045), _c("steel"), true)


static func _shed(k: MeshKit) -> void:
	ClubShed.build(k)


static func _picnic_table(k: MeshKit) -> void:
	Furniture.picnic(k)


static func _bench(k: MeshKit) -> void:
	Furniture.bench(k)


static func _flagpole(k: MeshKit) -> Array:
	k.cylinder(0.06, 0.04, 8.0, 8, Vector3.ZERO, _c("trim"))
	k.cylinder(0.25, 0.25, 0.25, 8, Vector3.ZERO, _c("concrete"))
	k.blob(Vector3(0, 8.03, 0), Vector3(0.12, 0.12, 0.12), Color("#c9a64a"), 3, 0.05)
	# The club flag: 1.5 × 0.9 m, subdivided so the flag shader can wave it; pivot on the pole at the hoist.
	var flag := MeshKit.new()
	var cols := 10
	var rows := 4
	for i in cols:
		for j in rows:
			var x0 := 1.5 * i / cols
			var x1 := 1.5 * (i + 1) / cols
			var y0 := -0.9 * (j + 1) / rows
			var y1 := -0.9 * j / rows
			var c: Color = _c("flag_blue") if j == 0 or j == rows - 1 else (_c("flag_white") if j == 1 else _c("flag_red"))
			flag.quad(Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0), c)
			flag.quad(Vector3(x1, y0, 0), Vector3(x0, y0, 0), Vector3(x0, y1, 0), Vector3(x1, y1, 0), c.darkened(0.12))
	return [{kind = "flag", kit = flag, pivot = Vector3(0.06, 7.85, 0), axis = Vector3.UP, rate = 0.0}]


static func _club_sign(k: MeshKit) -> void:
	ClubSign.build(k)


# ---------------- hay and vegetation ----------------

static func _round_bale(k: MeshKit, seed: int) -> void:
	var tone := 0.92 + 0.12 * Palette.hash01(seed, 1)
	k.roll(0.6, 1.2, 14, Vector3.ZERO, _c("hay") * Color(tone, tone, tone), _c("hay_end"), _c("hay_ring"))


static func _bale_stack(k: MeshKit) -> void:
	for i in 2:
		for j in 2:
			var c := Vector3(-0.61 + i * 1.22, j * 0.91, 0)
			k.block(Vector3(1.2, 0.9, 2.4), c, _c("hay"), _c("hay").lightened(0.05))
			for s: float in [-0.6, 0.0, 0.6]: # twine
				k.box(Vector3(1.22, 0.02, 0.03), c + Vector3(0, 0.9, s), _c("hay_ring"), true)


static func _flower_clump(k: MeshKit, seed: int, theme: String) -> void:
	# A compact border bouquet: visible stems, paired leaves and cupped petals replace the old green cushion mound.
	# Geometry stays in this cell's existing mesh and within the flower-clump catalog footprint.
	var stem := Palette.veg("stem", theme)
	var leaf := Palette.veg("leaf", theme)
	var species: Array = Palette.FLOWERS.keys()
	for i in 6:
		var a := TAU * (float(i) / 6.0 + 0.04 * (Palette.hash01(seed, i, 1) - 0.5))
		var r := 0.025 + 0.085 * Palette.hash01(seed, i, 2)
		var base := Vector3(cos(a) * r, 0.012, sin(a) * r)
		var lean := a + 0.28 * (Palette.hash01(seed, i, 3) - 0.5)
		var height := 0.25 + 0.11 * Palette.hash01(seed, i, 4)
		var head := base + Vector3(cos(lean) * 0.035, height, sin(lean) * 0.035)
		k.beam(base, head, 0.012, stem)

		var attach := base.lerp(head, 0.48)
		var leaf_angle := a + (0.85 if i % 2 == 0 else -0.85)
		var leaf_dir := Vector3(cos(leaf_angle), 0.0, sin(leaf_angle))
		var tip := attach + leaf_dir * (0.08 + 0.04 * Palette.hash01(seed, i, 5)) + Vector3(0, 0.035, 0)
		var side := Vector3(-leaf_dir.z, 0.0, leaf_dir.x) * 0.013
		var p0 := attach - side * 0.55
		var p1 := tip - side * 0.10
		var p2 := tip + side * 0.10
		var p3 := attach + side * 0.55
		k.quad(p0, p1, p2, p3, leaf)
		k.quad(p3, p2, p1, p0, leaf.darkened(0.08)) # back face stays visible from the path

		# One species per bouquet; rounded petals with a shallow cup replace star-like spikes.
		var index := int(Palette.hash01(seed, 6) * species.size()) % species.size()
		var petal: Color = Palette.FLOWERS[species[index]]
		if theme == "autumn":
			petal = Palette.vegetation(petal, theme)
		var center := head + Vector3(0, 0.008, 0)
		var petals := 8 if species[index] == "daisy" else 6
		for petal_index in petals:
			var pa := TAU * float(petal_index) / float(petals) + 0.18 * float(i % 3)
			var root := center + Vector3(cos(pa) * 0.018, 0, sin(pa) * 0.018)
			var left := center + Vector3(cos(pa - 0.22) * 0.060, 0.009, sin(pa - 0.22) * 0.060)
			var outer := center + Vector3(cos(pa) * 0.075, 0.012, sin(pa) * 0.075)
			var right := center + Vector3(cos(pa + 0.22) * 0.060, 0.009, sin(pa + 0.22) * 0.060)
			k.tri(root, left, outer, petal)
			k.tri(root, outer, left, petal)
			k.tri(root, outer, right, petal)
			k.tri(root, right, outer, petal)
		var pollen_a := center + Vector3(0.012, 0.008, 0.0)
		var pollen_b := center + Vector3(-0.006, 0.008, 0.010)
		var pollen_c := center + Vector3(-0.006, 0.008, -0.010)
		k.tri(pollen_a, pollen_c, pollen_b, Color("#d7b64a"))


# ---------------- the Avanti display cradle ----------------

static func _avanti_cradle(k: MeshKit) -> void:
	var steel := _c("steel_dark")
	var foam := _c("foam")
	for z: float in [-0.62, 0.62]:
		# Two padded trestles lift the gear-up airframe clear of the gravel.
		k.beam(Vector3(-0.31, 0.02, z - 0.16), Vector3(0.0, 0.40, z), 0.055, steel)
		k.beam(Vector3(0.31, 0.02, z + 0.16), Vector3(0.0, 0.40, z), 0.055, steel)
		k.beam(Vector3(0.31, 0.02, z - 0.16), Vector3(0.0, 0.40, z), 0.055, steel)
		k.beam(Vector3(-0.31, 0.02, z + 0.16), Vector3(0.0, 0.40, z), 0.055, steel)
		k.block(Vector3(0.70, 0.07, 0.34), Vector3(0.0, 0.40, z), foam, foam.lightened(0.12))
		k.box(Vector3(0.52, 0.035, 0.18), Vector3(0.0, 0.46, z), _c("box_black"), true)


# ---------------- the farmstead ----------------

static func _barn(k: MeshKit) -> void:
	var w := 10.0
	var l := 14.0
	var wall := 3.6
	var red := _c("barn_red")
	k.block(Vector3(w, wall, l), Vector3.ZERO, red)
	# gambrel profile (half-widths and heights): eave, knee, ridge
	var knee_x := 3.3
	var knee_y := wall + 2.2
	var ridge_y := wall + 3.7
	var o := 0.35
	var hl := l * 0.5 + o
	var roof := _c("roof_metal_dark")
	for side: float in [-1.0, 1.0]:
		var e := Vector3(side * (w * 0.5 + o), wall - 0.25, 0)
		var kn := Vector3(side * knee_x, knee_y, 0)
		var r := Vector3(0, ridge_y, 0)
		if side < 0.0:
			k.quad(Vector3(e.x, e.y, -hl), Vector3(e.x, e.y, hl), Vector3(kn.x, kn.y, hl), Vector3(kn.x, kn.y, -hl), roof)
			k.quad(Vector3(kn.x, kn.y, -hl), Vector3(kn.x, kn.y, hl), Vector3(0, r.y, hl), Vector3(0, r.y, -hl), roof.lightened(0.05))
		else:
			k.quad(Vector3(e.x, e.y, hl), Vector3(e.x, e.y, -hl), Vector3(kn.x, kn.y, -hl), Vector3(kn.x, kn.y, hl), roof)
			k.quad(Vector3(kn.x, kn.y, hl), Vector3(kn.x, kn.y, -hl), Vector3(0, r.y, -hl), Vector3(0, r.y, hl), roof.lightened(0.05))
	for zs: float in [-1.0, 1.0]: # gable ends (pentagon above the walls)
		var z := zs * l * 0.5
		var pts := PackedVector3Array([Vector3(-w * 0.5, wall, z), Vector3(w * 0.5, wall, z), Vector3(knee_x, knee_y, z), Vector3(0, ridge_y, z), Vector3(-knee_x, knee_y, z)])
		if zs < 0.0:
			pts.reverse()
		k.poly(pts, red)
	# big front doors (−Z end) with white X bracing, hayloft door, corner trims
	var f := -l * 0.5 - 0.03
	k.box(Vector3(4.2, 3.2, 0.06), Vector3(0, 1.6, f), red.darkened(0.15), true)
	for x: float in [-1.05, 1.05]:
		k.beam(Vector3(x - 1.0, 0.1, f - 0.04), Vector3(x + 1.0, 3.1, f - 0.04), 0.12, _c("barn_trim"))
		k.beam(Vector3(x + 1.0, 0.1, f - 0.04), Vector3(x - 1.0, 3.1, f - 0.04), 0.12, _c("barn_trim"))
		k.box(Vector3(2.1, 3.2, 0.03), Vector3(x, 1.6, f - 0.02), red.darkened(0.15), true)
	k.box(Vector3(4.4, 0.15, 0.1), Vector3(0, 3.27, f - 0.05), _c("barn_trim"), true)
	k.box(Vector3(1.6, 1.4, 0.06), Vector3(0, wall + 1.2, f), _c("barn_trim"), true)
	k.box(Vector3(1.3, 1.1, 0.07), Vector3(0, wall + 1.2, f - 0.01), red.darkened(0.25), true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.block(Vector3(0.18, wall, 0.18), Vector3(sx * w * 0.5, 0, sz * l * 0.5), _c("barn_trim"))


static func _silo(k: MeshKit) -> void:
	k.cylinder(2.6, 2.6, 13.0, 16, Vector3.ZERO, _c("silo"), false)
	for i in 4:
		k.cylinder(2.64, 2.64, 0.18, 16, Vector3(0, 2.0 + i * 3.2, 0), _c("silo").darkened(0.2), false)
	k.cylinder(2.7, 0.4, 1.9, 16, Vector3(0, 13.0, 0), _c("silo_dome"))
	k.beam(Vector3(0, 0.3, -2.75), Vector3(0, 13.2, -2.75), 0.08, _c("steel_dark"))
	k.beam(Vector3(0.35, 0.3, -2.72), Vector3(0.35, 13.2, -2.72), 0.08, _c("steel_dark"))


static func _farmhouse(k: MeshKit) -> void:
	var w := 9.0
	var d := 7.0
	k.block(Vector3(w, 5.2, d), Vector3.ZERO, _c("wall_cream"))
	k.gable_roof(w, d, 5.2, 2.0, 0.4, _c("roof_terracotta"), _c("wall_cream"))
	k.block(Vector3(0.7, 2.4, 0.7), Vector3(2.4, 5.0, 0.8), _c("wall_brick"))
	var f := -d * 0.5 - 0.02
	for x: float in [-3.0, 3.0]:
		_window(k, Vector3(x, 1.0, f), 1.1, 1.2, false)
		_window(k, Vector3(x, 3.4, f), 1.1, 1.0, false)
	_window(k, Vector3(0, 3.4, f), 0.9, 1.0, false)
	_door(k, Vector3(0, 0, f), 1.0, 2.1, _c("door"), false)


static func _tractor(k: MeshKit) -> void:
	var g := _c("tractor")
	k.block(Vector3(0.9, 0.8, 2.2), Vector3(0, 0.75, -0.6), g)
	k.block(Vector3(1.1, 0.5, 1.4), Vector3(0, 0.55, 0.9), g.darkened(0.15))
	for sx: float in [-1.0, 1.0]: # roll() lays the axle along X already
		k.roll(0.78, 0.45, 12, Vector3(sx * 0.95, 0, 1.0), _c("tyre"), _c("tractor_yellow"))
		k.roll(0.45, 0.3, 10, Vector3(sx * 0.8, 0, -1.3), _c("tyre"), _c("tractor_yellow"))
	for sx: float in [-0.55, 0.55]: # cab frame
		for sz: float in [0.35, 1.45]:
			k.block(Vector3(0.07, 1.2, 0.07), Vector3(sx, 1.05, sz), _c("steel_dark"))
	k.block(Vector3(1.25, 0.08, 1.3), Vector3(0, 2.25, 0.9), g)
	k.box(Vector3(1.0, 0.9, 0.04), Vector3(0, 1.65, 0.36), _c("glass_light"), true)
	k.cylinder(0.05, 0.05, 1.0, 6, Vector3(0.3, 1.1, -1.2), _c("steel_dark"))


# ---------------- far landmarks ----------------

static func _turbine(k: MeshKit, seed: int) -> Array:
	var hub_h := 80.0
	k.cylinder(2.1, 1.35, hub_h - 1.6, 12, Vector3.ZERO, _c("turbine"), false)
	k.cylinder(3.2, 3.2, 0.8, 12, Vector3.ZERO, _c("concrete"))
	k.block(Vector3(3.2, 3.2, 11.0), Vector3(0, hub_h - 1.6, -1.0), _c("turbine"))
	var rotor := MeshKit.new() # blades in the rotor's XY plane, spinning about Z; the hub sits 6.6 m ahead of the tower
	for i in 3:
		var a := TAU * i / 3.0
		var dir := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-sin(a), cos(a), 0.0)
		var root := dir * 1.2
		var tip := dir * 41.0
		var w_root := 1.25
		var w_tip := 0.35
		var t := Vector3(0, 0, 0.35)
		var p := [root - side * w_root, tip - side * w_tip, tip + side * w_tip * 0.3, root + side * w_root * 0.6]
		rotor.quad(p[0] - t, p[1] - t, p[2] - t, p[3] - t, _c("turbine"))
		rotor.quad(p[3] + t, p[2] + t, p[1] + t, p[0] + t, _c("turbine").darkened(0.06))
		rotor.quad(p[1] - t, p[1] + t, p[2] + t, p[2] - t, _c("turbine"))
		rotor.quad(p[0] + t, p[0] - t, p[3] - t, p[3] + t, _c("turbine"))
	# the spinner cone points forward (−Z)
	var cone := MeshKit.new()
	cone.xf = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO)
	cone.cylinder(1.3, 0.0, 2.6, 10, Vector3.ZERO, _c("turbine"))
	rotor.verts.append_array(cone.verts)
	rotor.norms.append_array(cone.norms)
	rotor.cols.append_array(cone.cols)
	# 1/1024-Hz multiple: 0.25 Hz = 15 rpm, a typical rated speed; phase from the seed so turbines are not in step
	return [{kind = "rotor", kit = rotor, pivot = Vector3(0, hub_h, -6.6), axis = Vector3(0, 0, 1),
		rate = 256.0 / 1024.0, phase = Palette.hash01(seed, 5)}]


static func _pylon(k: MeshKit) -> void:
	preload("res://scenery/power_lines.gd").append_tower(k)


static func _church(k: MeshKit) -> void:
	var stone := _c("stone")
	k.block(Vector3(8.0, 7.0, 18.0), Vector3(0, 0, 3.5), stone)
	k.gable_roof(8.0, 18.0, 7.0, 4.5, 0.3, _c("roof_slate"), stone)
	k.block(Vector3(5.0, 17.0, 5.0), Vector3(0, 0, -7.5), _c("stone_dark"))
	k.cylinder(3.4, 0.05, 12.0, 4, Vector3(0, 17.0, -7.5), _c("roof_slate"))
	k.beam(Vector3(0, 29.0, -7.5), Vector3(0, 32.0, -7.5), 0.15, Color("#c9a64a"))
	k.beam(Vector3(-0.6, 31.0, -7.5), Vector3(0.6, 31.0, -7.5), 0.12, Color("#c9a64a"))
	for i in 4: # tall dark windows on the nave
		for side: float in [-1.0, 1.0]:
			k.box(Vector3(0.06, 2.4, 0.9), Vector3(side * 4.02, 3.2, -1.0 + i * 3.6), _c("glass"), true)
	k.box(Vector3(1.4, 2.8, 0.06), Vector3(0, 1.4, -10.02), _c("door"), true)


static func _village_house(k: MeshKit, seed: int) -> void:
	var w := 7.0 + 2.0 * Palette.hash01(seed, 1)
	var d := 8.0 + 3.0 * Palette.hash01(seed, 2)
	var wall: Color = Palette.pick([_c("wall_white"), _c("wall_cream"), _c("wall_brick"), _c("wall_cream")], seed, 3)
	var roof: Color = Palette.pick([_c("roof_terracotta"), _c("roof_slate"), _c("roof_terracotta")], seed, 4)
	var eave := 5.2 if Palette.hash01(seed, 5) < 0.6 else 3.0
	k.block(Vector3(w, eave, d), Vector3.ZERO, wall)
	k.gable_roof(w, d, eave, 2.4, 0.3, roof, wall)
	k.block(Vector3(0.6, 2.2, 0.6), Vector3(w * 0.25, eave, d * 0.2), _c("wall_brick"))
	for x: float in [-w * 0.28, w * 0.28]:
		_window(k, Vector3(x, 1.0, -d * 0.5 - 0.02), 1.0, 1.1, false)
