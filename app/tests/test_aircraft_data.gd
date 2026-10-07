# D1: the aircraft physics data: loads, makes physical sense, agrees with the visual geometry,
# and rejects broken data with a specific message.
# Run: godot --headless --path . --script res://tests/test_aircraft_data.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


## Expect the mutated data to fail with an error containing `needle`.
func _rejects(label: String, mutate: Callable, needle: String) -> void:
	var raw := _raw()
	mutate.call(raw)
	var r := AD.validate_and_derive(raw)
	var hit := false
	for e in r.errors:
		hit = hit or needle in e
	_check("rejects: " + label, not r.ok and hit, str(r.errors))


func _initialize() -> void:
	var r := AD.load_file(PATH)
	_check("real file loads", r.ok, str(r.errors))
	if not r.ok:
		quit(1)
		return
	var m: Dictionary = r.model

	# Physical sense
	_check("mass in the Stick .60 range", m.mass_kg > 2.3 and m.mass_kg < 3.4, str(m.mass_kg))
	var j: PackedFloat64Array = m.inertia
	_check("principal moments positive", j[0] > 0 and j[1] > 0 and j[2] > 0, str(j))
	_check("triangle inequalities (a real body)", j[0] + j[1] >= j[2] and j[1] + j[2] >= j[0] and j[0] + j[2] >= j[1], str(j))
	_check("airplane-like ordering Jzz > Jyy > Jxx", j[2] > j[1] and j[1] > j[0], str(j))
	_check("plan CG 4.76 in aft of LE (39 % chord)", absf(m.cg_le[0] - 0.1209) < 1e-9 and absf(m.cg_le[0] / m.reference.c - 0.397) < 0.01)
	_check("flight CG and inertia share inventory centre", m.cg_le == m.cg_inventory_le and absf(m.cg_le[1]) < 1e-12 and absf(m.cg_le[2]) < 1e-12)

	# Inertia of a known shape: a 1 kg box 0.3 × 1.5 × 0.04 m about its centre (body axes).
	var box := AD.inertia_about([[1.0, PackedFloat64Array([0, 0, 0]), PackedFloat64Array([0.3, 1.5, 0.04])]], PackedFloat64Array([0, 0, 0]))
	_check("box inertia formula", absf(box[0] - (1.5 * 1.5 + 0.04 * 0.04) / 12.0) < 1e-12 and absf(box[2] - (0.09 + 2.25) / 12.0) < 1e-12, str(box))
	# Parallel axis and product of inertia: 1 kg point 1 m forward (x_aft = -1) and 1 m up → Jxz = -m·x·z = -(1)(-1) = +1.
	var pt := AD.inertia_about([[1.0, PackedFloat64Array([-1, 0, 1]), PackedFloat64Array([0, 0, 0])]], PackedFloat64Array([0, 0, 0]))
	_check("parallel axis + product term", absf(pt[1] - 2.0) < 1e-12 and absf(pt[4] - 1.0) < 1e-12, str(pt))

	# Agreement with the visual geometry (one source of truth per team; numbers must match).
	_check("span matches visual geometry", absf(m.reference.b - Geometry.DATA.wing.span) < 0.001, "%s vs %s" % [m.reference.b, Geometry.DATA.wing.span])
	_check("chord matches visual geometry", absf(m.reference.c - Geometry.DATA.wing.chord) / m.reference.c < 0.01, "%s vs %s" % [m.reference.c, Geometry.DATA.wing.chord])

	# E0b2: visual [right,up,aft] -> LE [aft,right,up]. The vertical datum is the shaft,
	# not the visual assembly origin; subtracting shaft_y makes the hub height exactly zero.
	var hub_le: PackedFloat64Array = PackedFloat64Array([
		Geometry.DATA.equipment.prop_z - Geometry.DATA.wing.leading_z, 0.0, 0.0])
	for axis in 3:
		_check("E0b2 hub/geometry agreement axis %d" % axis,
			absf(m.cg_le[axis] + m.propulsion.offset[axis] - hub_le[axis]) < 1e-12)
	_check("E0b2 propeller diameter matches visual geometry",
		absf(m.propulsion.diameter - Geometry.DATA.equipment.prop_diameter) < 1e-12)
	_check("E0b2 hub is explicitly ahead of the CG", m.propulsion.offset[0] < -0.4)
	# Moving a force along its own axial line leaves r x F unchanged, including windmill drag.
	var previous_prop: Dictionary = m.propulsion.duplicate(true)
	previous_prop.offset = PackedFloat64Array([0.0, 0.0, 0.0])
	var identical_loads: bool = true
	var signed_zero_changes: int = 0
	for speed: float in [-10.0, 0.0, 5.0, 15.0, 50.0]:
		for rpm: float in [0.0, m.propulsion.idle_rpm, m.propulsion.max_rpm]:
			var velocity: PackedFloat64Array = PackedFloat64Array([speed, 2.0, -3.0])
			var now: PackedFloat64Array = Propulsion.loads(velocity, rpm, m.propulsion, 1.225)
			var before: PackedFloat64Array = Propulsion.loads(velocity, rpm, previous_prop, 1.225)
			for component in 6:
				identical_loads = identical_loads and now[component] == before[component]
			if now.to_byte_array() != before.to_byte_array():
				signed_zero_changes += 1
	_check("E0b2 axial hub move preserves every propulsion component exactly", identical_loads)
	print("E0b2: 15 propulsion cases equal numerically; %d signed-zero byte differences" % signed_zero_changes)

	# Control throws are aircraft data with provenance (D5.9), in degrees in the file.
	_check("throws loaded (aileron 20°, elevator 20°, rudder 25°)", m.controls.throw_deg.aileron == 20.0 and m.controls.throw_deg.elevator == 20.0 and m.controls.throw_deg.rudder == 25.0, str(m.controls))
	_check("throws also in radians", absf(m.controls.throw_rad.rudder - deg_to_rad(25.0)) < 1e-15)
	_check("servo rate = 1 / full-throw time (D6c)", absf(m.controls.servo_rate - 1.0 / 0.14) < 1e-12, str(m.controls.servo_rate))

	# Aero conventions are present, so D3+ cannot guess them.
	for key in ["rates", "elevator", "aileron", "rudder", "drag", "axes"]:
		_check("convention documented: " + key, m.conventions.has(key))

	# Broken data is rejected with a specific message.
	_rejects("wrong format", func(d): d.format = "v0", "format")
	_rejects("mass in grams", func(d): d.inventory[0].mass.unit = "g", "unit 'g'")
	_rejects("unknown evidence kind", func(d): d.inventory[0].mass.kind = "guess", "kind 'guess'")
	_rejects("empty source", func(d): d.reference.wing_span.source = " ", "empty source")
	_rejects("missing unit", func(d): d.reference.wing_area.erase("unit"), "missing 'unit'")
	_rejects("negative mass", func(d): d.inventory[3].mass.value = -0.1, "outside")
	_rejects("position not a 3-vector", func(d): d.inventory[0].position.value = [0.1, 0.2], "3 numbers")
	_rejects("area inconsistent with span × chord", func(d): d.reference.wing_area.value = 0.6, "differs from wing_area")
	_rejects("unstable pitch (Cma > 0)", func(d): d.aero.coefficients.Cma.value = 0.4, "Cma")
	_rejects("reversed elevator (Cmde > 0)", func(d): d.aero.coefficients.Cmde.value = 0.8, "Cmde")
	_rejects("missing coefficient", func(d): d.aero.coefficients.erase("Cnr"), "Cnr")
	_rejects("total mass implausible (kg/g mix-up)", func(d): d.inventory[0].mass.value = 4.9, "plausible range")
	_rejects("missing controls section", func(d): d.erase("controls"), "controls: missing")
	_rejects("throw in radians", func(d): d.controls.max_throw.rudder.unit = "rad", "unit 'rad'")
	_rejects("missing elevator throw", func(d): d.controls.max_throw.erase("elevator"), "controls.max_throw.elevator")
	_rejects("implausible throw", func(d): d.controls.max_throw.aileron.value = 90.0, "outside")
	_rejects("servo time in milliseconds", func(d): d.controls.servo_full_throw_time.unit = "ms", "unit 'ms'")
	_rejects("unbalanced build", func(d): d.inventory.pop_back(), "balance")
	_rejects("rudder moment multiplied tenfold", func(d): d.aero.coefficients.Cndr.value *= 10, "vertical surface force/arm")
	_rejects("missing local surfaces", func(d): d.aero.erase("surfaces"), "surfaces")
	_rejects("reversed tail blend", func(d): d.aero.surfaces.tail_stall_end.value = 11, "strictly ordered")
	_rejects("tail source missing", func(d): d.aero.surfaces.vertical.area.source = "", "empty source")
	_rejects("reference wrong type", func(d): d.reference = [], "expected an object")
	_rejects("inventory wrong type", func(d): d.inventory = {}, "expected an array")
	_rejects("aero wrong type", func(d): d.aero = [], "expected an object")
	_rejects("tail wrong type", func(d): d.aero.surfaces.horizontal = [], "expected an object")
	_rejects("hull NaN", func(d): d.crash_hull.value[0][0] = NAN, "finite point")

	# Landing gear (E1): three spring-damper contacts, the wheels no longer in the crash hull, stiffness by the tick rule.
	var gear: Dictionary = m.landing_gear
	_check("landing gear: 3 contacts; the hull keeps 8 points without the wheels", gear.get("contacts", []).size() == 3 and m.crash_hull.size() == 8 * 3, str(gear))
	var eq: Dictionary = Geometry.DATA.equipment
	var mains_ok := true
	for i in 2:
		var p: PackedFloat64Array = gear.contacts[i].position
		mains_ok = mains_ok and absf(absf(p[1]) - eq.main_track / 2.0) < 1e-9 and absf(p[2] - (-eq.wheel_y + eq.main_wheel_diameter / 2.0)) < 1e-9
	var nose: PackedFloat64Array = gear.contacts[2].position
	_check("gear track and wheel bottoms match the visual model's equipment table", mains_ok and absf(nose[2] - (-eq.wheel_y + eq.nose_wheel_diameter / 2.0)) < 1e-4, str(gear.contacts))
	_check("mains aft of the CG, nose ahead (a tricycle stands on its wheels)", gear.contacts[0].position[0] < 0.0 and gear.contacts[2].position[0] > 0.0)
	_check("heave rule ω·dt < 0.1 at 240 Hz, not absurdly soft", gear.heave_omega / 240.0 < 0.1 and gear.heave_omega > 15.0, "ω %.1f rad/s" % gear.heave_omega)
	_check("static sag 1–3 cm", gear.static_sag > 0.01 and gear.static_sag < 0.03, "%.4f m" % gear.static_sag)
	var no_gear := _raw()
	no_gear.erase("landing_gear")
	var r_no_gear := AD.validate_and_derive(no_gear)
	_check("without a landing_gear section the data still loads (gear is optional; wheels crash as in D9d)", r_no_gear.ok and r_no_gear.model.landing_gear.is_empty(), str(r_no_gear.errors))
	_rejects("gear too stiff for the tick", func(d): for c in d.landing_gear.contacts: c.stiffness.value *= 50, "ω·dt")
	_rejects("CG outside the wheelbase", func(d): for c in d.landing_gear.contacts: c.position.value[0] -= 0.2, "cannot stand")
	_rejects("all wheels on one side", func(d): for c in d.landing_gear.contacts: c.position.value[1] += 0.5, "cannot stand")
	_check_ground_support(r.model.cg_le)
	_rejects("gear stiffness in lbf/in", func(d): d.landing_gear.contacts[0].stiffness.unit = "lbf/in", "unit 'lbf/in'")
	_rejects("negative damping", func(d): d.landing_gear.contacts[1].damping.value = -5, "outside")
	_rejects("overdamped gear (a shock absorber, not a wire leg)", func(d): d.landing_gear.contacts[0].damping.value = 500, "ratio")
	_rejects("two wheels only", func(d): d.landing_gear.contacts.pop_back(), "fewer than 3")
	_rejects("gear travel missing", func(d): d.landing_gear.contacts[2].erase("max_compression"), "max_compression")
	_rejects("unnamed contact", func(d): d.landing_gear.contacts[0].erase("name"), "missing name")
	# E2: tyre friction is required with the gear; steering is optional per contact.
	_check("E2 tyre data derived: C_rr 0.04, μ 0.8, tan 6°, nose steers 20°, mains fixed", absf(gear.rolling_resistance - 0.04) < 1e-12 and absf(gear.side_friction - 0.8) < 1e-12
		and absf(gear.tan_peak_slip - tan(deg_to_rad(6.0))) < 1e-12 and absf(gear.contacts[2].max_steering - deg_to_rad(20.0)) < 1e-12 and gear.contacts[0].max_steering == 0.0, str(gear))
	_rejects("gear without tyre friction (it would slide forever)", func(d): d.landing_gear.erase("side_friction"), "side_friction")
	_rejects("side force too stiff for the tick (peak slip 2°)", func(d): d.landing_gear.peak_slip_angle.value = 2.0, "λ·dt")
	_rejects("steering in radians", func(d): d.landing_gear.contacts[2].max_steering.unit = "rad", "unit 'rad'")
	_rejects("steering beyond 45°", func(d): d.landing_gear.contacts[2].max_steering.value = 60.0, "outside")
	_rejects("rolling resistance of a brake (0.5)", func(d): d.landing_gear.rolling_resistance.value = 0.5, "outside")
	_rejects("prop table numeric strings", func(d): d.propulsion.propeller.ct_table.value[0] = ["0", "0.1"], "finite numbers")
	_rejects("prop table empty source", func(d): d.propulsion.propeller.cp_table.source = "", "empty source")
	_check("data fingerprint is available for traces", m.data_sha256.length() == 64)
	var bad := AD.validate_and_derive({ format = "nope" })
	_check("rejects garbage", not bad.ok)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## D1-R3: the CG must project inside the resting facet of the contacts, not merely inside their bounding box.
func _check_ground_support(stik_cg: PackedFloat64Array) -> void:
	# The audit's probe (physics B3): inside both coordinate ranges, outside the support triangle.
	_rejects("CG inside the gear bounding box but outside the support triangle (audit B3)", func(d):
		var xy := [[0.0, -0.18], [1.0, 0.18], [1.0, 0.0]]
		for i in 3:
			d.landing_gear.contacts[i].position.value[0] = xy[i][0]
			d.landing_gear.contacts[i].position.value[1] = xy[i][1], "cannot stand")
	_rejects("collinear contacts", func(d): for c in d.landing_gear.contacts: c.position.value[1] = 0.0, "no support plane")
	# Margin against an independent side view: symmetric gear rests on the line from the main axle to the third wheel.
	var p51_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/p51d_mustang_120.json"))
	var p51 := AD.validate_and_derive(p51_raw)
	_check("P-51 data loads with its taildragger gear", p51.ok, str(p51.errors))
	for case in [["Stik (tricycle)", _raw(), stik_cg], ["P-51 (taildragger)", p51_raw, p51.model.cg_le if p51.ok else PackedFloat64Array([0, 0, 0])]]:
		var pts := _points(case[1])
		var cg: PackedFloat64Array = case[2]
		var support := AD.ground_support(pts, cg)
		var main: PackedFloat64Array = pts[0]
		var third: PackedFloat64Array = pts[2]
		var dx := third[0] - main[0]
		var dz := third[2] - main[2]
		var length := sqrt(dx * dx + dz * dz)
		var side_margin := ((cg[0] - main[0]) * dx + (cg[2] - main[2]) * dz) / length
		var pitch := absf(atan2(dz, absf(dx)))
		_check("%s stands; margin to the main axle %.4f m equals the side-view value %.4f m" % [case[0], support.margin, side_margin],
			support.supported and absf(support.margin - side_margin) < 1e-9 and absf(support.tilt - pitch) < 1e-9, str(support))
	var p51_pts := _points(p51_raw)
	var nose_heavy: PackedFloat64Array = p51.model.cg_le.duplicate() if p51.ok else PackedFloat64Array([0, 0, 0])
	nose_heavy[0] -= 0.30 # CG ahead of the mains at the three-point attitude: it noses over
	_check("taildragger with the CG projected ahead of its mains does not stand", not AD.ground_support(p51_pts, nose_heavy).supported)
	# A coplanar square with the CG on both diagonals: a per-triangle test would see a zero margin.
	var square := [PackedFloat64Array([-0.2, -0.2, -0.3]), PackedFloat64Array([-0.2, 0.2, -0.3]),
		PackedFloat64Array([0.2, -0.2, -0.3]), PackedFloat64Array([0.2, 0.2, -0.3])]
	var centred := AD.ground_support(square, PackedFloat64Array([0.0, 0.0, 0.0]))
	_check("square gear, CG at the centre: margin is the half width 0.2 m (whole facet, not one triangle)",
		centred.supported and absf(centred.margin - 0.2) < 1e-12 and centred.facet.size() == 4, str(centred))
	var off := AD.ground_support(square, PackedFloat64Array([0.25, 0.0, 0.0]))
	_check("square gear, CG 5 cm beyond an edge: margin -0.05 m", not off.supported and absf(off.margin + 0.05) < 1e-12, str(off))
	var hanging := AD.ground_support(square, PackedFloat64Array([0.0, 0.0, -0.5]))
	_check("CG below the wheel plane is not supported", not hanging.supported, str(hanging))


func _points(raw: Dictionary) -> Array:
	var pts := []
	for c in raw.landing_gear.contacts:
		pts.append(PackedFloat64Array(c.position.value))
	return pts
