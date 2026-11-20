# Direct component probe for d736ee8a. No accepted simulator tick is claimed.
# Run by copying unchanged into the Godot project as a scratch test and invoking --headless --script.
# The scenery case uses one synthetic hull point and a box containing the CG; it is NOT a complete
# physically valid airplane configuration. Its independent oracle is clearance of that point.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Hull := preload("res://physics/hull_contact.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const World := preload("res://scenery/collision_world.gd")
const DT: float = 1.0 / 240.0
const SPEED: float = 250.0 / 3.0
const MASS: float = 2.0
var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
var identity_att := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
var count: int = 0
var failures: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	count += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		failures += 1

func state(north: float, down: float, q: PackedFloat64Array, velocity_ned: PackedFloat64Array,
		rates: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(north, 0.0, down), M.q_rotate(M.q_conj(q), velocity_ned), q, rates)

func flat_probe() -> void:
	print("CASE flat plane: direct HullContact, single point, no wheels/prop/lake/track/scenery")
	print("PARAM dt=%.12f speed=%.12f m/s distance=%.12f m mass=%.3f inertia=%s" % [DT, SPEED, SPEED * DT, MASS, str(inertia)])
	var hull := PackedFloat64Array([0.0, 1.0, 0.0])
	var prepared: Dictionary = Hull.prepare(hull, MASS, inertia)
	check("flat test contact geometry prepared", not prepared.is_empty(), "point=" + str(hull))
	if prepared.is_empty():
		return
	var rates := M.v3(0.0, 0.0, 0.0)
	var level_vel := M.v3(SPEED, 0.0, 0.0)
	var clear_a := state(0.0, -0.001, identity_att, level_vel, rates)
	var clear_b := state(SPEED * DT, -0.001, identity_att, level_vel, rates)
	var clear_loads: PackedFloat64Array = Hull.loads(clear_b, prepared)
	var clear_records: Array = Hull.contacts(clear_a, clear_b, prepared)
	var clear_terminal: Dictionary = Hull.terminal(clear_a, clear_b, prepared)
	print("OBS flat_clear a_point=%s b_point=%s normal=[0, 0, -1] normal_speed=0 loads=%s records=%s terminal=%s" % [str(M.v3(0.0, 1.0, -0.001)), str(M.v3(SPEED * DT, 1.0, -0.001)), str(clear_loads), str(clear_records), str(clear_terminal)])
	check("300 km/h one-point 1 mm clear: no soft loads", clear_loads.is_empty())
	check("300 km/h one-point 1 mm clear: no contact/terminal", clear_records.is_empty() and int(clear_terminal.index) < 0)
	var tan_a := state(0.0, 0.0, identity_att, level_vel, rates)
	var tan_b := state(SPEED * DT, 0.0, identity_att, level_vel, rates)
	var tan_loads: PackedFloat64Array = Hull.loads(tan_b, prepared)
	var tan_records: Array = Hull.contacts(tan_a, tan_b, prepared)
	var tan_terminal: Dictionary = Hull.terminal(tan_a, tan_b, prepared)
	print("OBS flat_tangent a_point=%s b_point=%s normal=[0, 0, -1] normal_speed=0 loads=%s records=%s terminal=%s" % [str(M.v3(0.0, 1.0, 0.0)), str(M.v3(SPEED * DT, 1.0, 0.0)), str(tan_loads), str(tan_records), str(tan_terminal)])
	check("soft zero-depth tangent: no loads", tan_loads.is_empty())
	check("soft zero-depth tangent: no contact/terminal", tan_records.is_empty() and int(tan_terminal.index) < 0)
	# Move down 1.1 mm over 1/240 s, consistent with 0.264 m/s normal approach.
	var brush_vel := M.v3(SPEED, 0.0, 0.264)
	var brush_a := state(0.0, -0.001, identity_att, brush_vel, rates)
	var brush_b := state(SPEED * DT, 0.0001, identity_att, brush_vel, rates)
	var brush_loads: PackedFloat64Array = Hull.loads(brush_b, prepared)
	var brush_records: Array = Hull.contacts(brush_a, brush_b, prepared)
	var brush_terminal: Dictionary = Hull.terminal(brush_a, brush_b, prepared)
	# r=(0,1,0), up normal=(0,0,-1), diagonal I=(1,1,1), mass=2.
	var independent_meff: float = 1.0 / (1.0 / MASS + 1.0)
	var independent_specific: float = 0.5 * independent_meff * 0.264 * 0.264 / MASS
	var entry_fraction: float = 0.001 / 0.0011
	print("OBS flat_brush a_point=[0,1,-0.001] b_point=%s normal=[0,0,-1] approach=0.264 m/s entry_fraction=%.12f entry_seconds=%.12f independent_effective_mass=%.12f independent_specific_J_per_kg=%.12f" % [str(M.v3(SPEED * DT, 1.0, 0.0001)), entry_fraction, entry_fraction * DT, independent_meff, independent_specific])
	print("OBS flat_brush loads=%s records=%s terminal=%s" % [str(brush_loads), str(brush_records), str(brush_terminal)])
	check("penetrating tip has one contact record", brush_records.size() == 1)
	check("penetrating tip has upward force and opposing friction", brush_loads.size() == 6 and brush_loads[2] < 0.0 and brush_loads[0] < 0.0)
	check("specified light brush is below configured terminal threshold", independent_specific < Hull.terminal_energy(prepared) and int(brush_terminal.index) < 0)
	if brush_records.size() == 1:
		var observed: Dictionary = brush_records[0]
		check("brush normal and slide speeds match prescribed motion", absf(float(observed.normal_speed_mps) - 0.264) < 1e-10 and absf(float(observed.slide_speed_mps) - SPEED) < 1e-10)

func box_world() -> Dictionary:
	# Wide box top D=0, bottom D=2; north/east extents ±5 m.
	var proxies: Array[Dictionary] = []
	World._add_box_at_down(proxies, "synthetic-top", "test_obstacle", "body", "soft_foliage_impulse", 0.0, 0.0, 1.0, 10.0, 2.0, 10.0, 0.0)
	return {format = World.FORMAT, identity = "synthetic-pad-fixture", cell_size_m = World.CELL_SIZE_M,
		proxies = proxies, bins = World._build_bins(proxies)}

func scenery_hit(world: Dictionary, angle0: float, angle1: float, start_clear: float,
		end_clear: float) -> Variant:
	var half_angle: float = deg_to_rad(0.9995)
	var q0: PackedFloat64Array = M.q_from_euler(0.0, 0.0, angle0)
	var q1: PackedFloat64Array = M.q_from_euler(0.0, 0.0, angle1)
	var d0: float = cos(half_angle) - start_clear
	var d1: float = cos(half_angle) - end_clear
	var velocity_ned := M.v3(SPEED, 0.0, (d1 - d0) / DT)
	var rates := M.v3((angle1 - angle0) / DT, 0.0, 0.0)
	var a := state(0.0, d0, q0, velocity_ned, rates)
	var b := state(SPEED * DT, d1, q1, velocity_ned, rates)
	return Collision.first_hit(a, b, PackedFloat64Array([0.0, -1.0, 0.0]), world, 1, MASS, inertia)

func print_scenery_event(label: String, event: Variant) -> void:
	if event == null:
		print("OBS %s event=null" % label)
		return
	print("OBS %s fraction=%.12f seconds=%.12f point=%s normal=%s point_velocity=%s normal_speed_mps=%.12f effective_mass_kg=%.12f energy_j=%.12f terminal=%s status=%s uninflated_box_top_clearance_m=%.12f" % [label, float(event.time_fraction), float(event.time_fraction) * DT, str(event.point_ned), str(event.normal_ned), str(event.velocity_ned), float(event.normal_speed_mps), float(event.effective_mass_kg), float(event.impact_energy_j), str(event.terminal), str(event.response_status), -float(event.point_ned[2])])

func scenery_probe() -> void:
	print("CASE scenery padding: synthetic one-point fixture ONLY; the CG is INSIDE the box. No accepted flight claim.")
	var world: Dictionary = box_world()
	check("synthetic box and bins prepared", world.proxies.size() == 1 and not world.bins.is_empty())
	var half_angle: float = deg_to_rad(0.9995)
	var a0: float = PI / 2.0 - half_angle
	var a1: float = PI / 2.0 + half_angle
	var d0: float = cos(half_angle) - 0.000300
	var d1: float = cos(half_angle) - 0.000050
	var pad: float = 1.0 - cos(half_angle) + 1e-9
	var predicted_fraction: float = (0.000300 - pad) / 0.000250
	# q varies monotonically between a0 and a1, so sin(roll)>=cos(half_angle).
	# Thus point down <= −0.000300 + 0.000250*f <= −0.000050 m throughout.
	print("PARAM start_cg_down=%.12f end_cg_down=%.12f start_clearance_m=0.000300 end_clearance_m=0.000050 roll_deg=[89.0005,90.9995] rate_radps=%.12f CG_downspeed_mps=%.12f" % [d0, d1, (a1 - a0) / DT, (d1 - d0) / DT])
	print("ORACLE uninflated-point clearance >=0.000050 m for entire monotone nlerp interval; padding_m=%.12f chord_entry_fraction=%.12f" % [pad, predicted_fraction])
	check("fixture explicitly has CG inside box", d0 > 0.0 and d1 < 2.0)
	var far: Variant = scenery_hit(world, a0, a1, 0.001300, 0.001050)
	print_scenery_event("scenery_rotating_far_clear", far)
	check("rotating farther-clear control has no event", far == null)
	var straight: Variant = scenery_hit(world, a0, a0, 0.000300, 0.000050)
	print_scenery_event("scenery_unrotated_clear", straight)
	check("unrotated clear control has no event", straight == null)
	var real: Variant = scenery_hit(world, a0, a1, 0.000300, -0.000050)
	print_scenery_event("scenery_true_point_penetration_control", real)
	check("real point penetration admits a scenery event", real != null)
	var event: Variant = scenery_hit(world, a0, a1, 0.000300, 0.000050)
	print_scenery_event("scenery_rotating_clear_test", event)
	if event != null:
		check("reported event point is independently clear of box top", float(event.point_ned[2]) < -0.000050 + 1e-10, "clearance_m=%.12f" % -float(event.point_ned[2]))
		check("reported approach passes soft minimum speed", float(event.normal_speed_mps) >= Collision.MIN_RESPONSE_NORMAL_SPEED_MPS)
		check("reported time matches inflated chord entry", absf(float(event.time_fraction) - predicted_fraction) < 1e-7)
	# Desired outcome, intentionally not a characterization assertion. A failure with the
	# corroborating clear-point and control checks is evidence only for this component case.
	check("desired: clear rotating point causes no uninflated-box contact", event == null)

func _initialize() -> void:
	flat_probe()
	scenery_probe()
	print("SUMMARY component checks=%d desired_failures_or_fixture_errors=%d" % [count, failures])
	quit(1 if failures > 0 else 0)
