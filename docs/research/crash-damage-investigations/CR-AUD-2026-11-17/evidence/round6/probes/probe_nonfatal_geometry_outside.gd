# Outside-CG synthetic one-point scenery fixture for main d736ee8a.
# Direct first_hit component call only: no accepted tick, stock-aircraft trajectory, complete
# aircraft surface, mesh clearance, or calibrated material behavior is established.
# The whole nlerp interval has an analytic point-clearance bound, not only sampled poses.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const World := preload("res://scenery/collision_world.gd")
const DT: float = 1.0 / 240.0
const SPEED: float = 250.0 / 3.0
const MASS: float = 2.0
const R_Z: float = 0.1
var inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
var checks: int = 0
var failures: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		failures += 1

func vertical_arm(angle: float) -> float:
	# Rotated D coordinate of body point (0,1,0.1) at pure roll angle.
	return sin(angle) + R_Z * cos(angle)

func state(north: float, down: float, q: PackedFloat64Array, velocity_ned: PackedFloat64Array,
		rates: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(north, 0.0, down), M.q_rotate(M.q_conj(q), velocity_ned), q, rates)

func box_world() -> Dictionary:
	# Box top D=0, bottom D=2; north/east extents ±5 m.
	var proxies: Array[Dictionary] = []
	World._add_box_at_down(proxies, "outside-cg:top", "test_obstacle", "body", "soft_foliage_impulse",
		0.0, 0.0, 1.0, 10.0, 2.0, 10.0, 0.0)
	return {format = World.FORMAT, identity = "outside-cg-padded-fixture", cell_size_m = World.CELL_SIZE_M,
		proxies = proxies, bins = World._build_bins(proxies)}

func fixture(world: Dictionary, angle0: float, angle1: float, start_clear: float,
		end_clear: float) -> Dictionary:
	var q0: PackedFloat64Array = M.q_from_euler(0.0, 0.0, angle0)
	var q1: PackedFloat64Array = M.q_from_euler(0.0, 0.0, angle1)
	var d0: float = -start_clear - vertical_arm(angle0)
	var d1: float = -end_clear - vertical_arm(angle1)
	var velocity_ned := M.v3(SPEED, 0.0, (d1 - d0) / DT)
	var rates := M.v3((angle1 - angle0) / DT, 0.0, 0.0)
	var a := state(0.0, d0, q0, velocity_ned, rates)
	var b := state(SPEED * DT, d1, q1, velocity_ned, rates)
	var event: Variant = Collision.first_hit(a, b, PackedFloat64Array([0.0, 1.0, R_Z]), world, 1, MASS, inertia)
	return {event = event, a = a, b = b, d0 = d0, d1 = d1, velocity_ned = velocity_ned, rates = rates}

func print_event(label: String, result: Dictionary) -> void:
	var event: Variant = result.event
	if event == null:
		print("OBS %s event=null cg_down_start=%.12f cg_down_end=%.12f" % [label, result.d0, result.d1])
		return
	print("OBS %s fraction=%.12f seconds=%.12f point=%s normal=%s point_velocity=%s normal_speed_mps=%.12f effective_mass_kg=%.12f energy_j=%.12f terminal=%s status=%s uninflated_top_clearance_m=%.12f" % [label, float(event.time_fraction), float(event.time_fraction) * DT, str(event.point_ned), str(event.normal_ned), str(event.velocity_ned), float(event.normal_speed_mps), float(event.effective_mass_kg), float(event.impact_energy_j), str(event.terminal), str(event.response_status), -float(event.point_ned[2])])

func _initialize() -> void:
	print("CASE outside-CG rotating scenery sweep: direct first_hit; one synthetic point and no full aircraft")
	var world: Dictionary = box_world()
	check("synthetic box and bins prepared", world.proxies.size() == 1 and not world.bins.is_empty())
	var alpha: float = deg_to_rad(0.9995)
	var t: float = tan(alpha / 2.0)
	var radius: float = sqrt(1.0 + R_Z * R_Z)
	var pad: float = radius * (1.0 - cos(alpha)) + 1.0e-9
	var predicted_fraction: float = (0.000300 - pad) / 0.000250
	# For u=2f−1, the shortest-nlerp pure roll is phi=2 atan(u*t).
	# Let g(phi)=sin(phi)+R_Z*cos(phi). The vertical rotated-point deviation
	# from the linear chord between g(-alpha) and g(alpha) is exactly
	# 2*t^2*(1-u^2)*(R_Z+u*t) / ((1+u^2*t^2)*(1+t^2)).
	# Since |u|<=1, its value is <= the conservative bound below. With the
	# CG's linear interpolation, the endpoint point clearances 300→50 µm
	# imply every pose's clearance is >=50 µm minus this deviation bound.
	var deviation_upper: float = 2.0 * t * t * (R_Z + t) / (1.0 + t * t)
	var whole_interval_min_clearance: float = 0.000050 - deviation_upper
	print("PARAM dt=%.12f speed_n=%.12f body_point=[0,1,0.1] roll_deg=[-0.9995,+0.9995] radius=%.12f" % [DT, SPEED, radius])
	print("ORACLE t=%.12f max_chord_vertical_deviation_m=%.12f minimum_whole_interval_clearance_m=%.12f rotational_padding_m=%.12f predicted_padded_entry_fraction=%.12f" % [t, deviation_upper, whole_interval_min_clearance, pad, predicted_fraction])
	check("analytic bound proves the entire true point path clear", whole_interval_min_clearance > 0.0)
	var far: Dictionary = fixture(world, -alpha, alpha, 0.001300, 0.001050)
	print_event("rotating_far_clear", far)
	check("rotating far-clear control has no event", far.event == null)
	var straight: Dictionary = fixture(world, -alpha, -alpha, 0.000300, 0.000050)
	print_event("unrotated_clear", straight)
	check("unrotated close-clear control has no event", straight.event == null)
	var real: Dictionary = fixture(world, -alpha, alpha, 0.000300, -0.000050)
	print_event("true_point_penetration_control", real)
	var real_endpoint_down: float = float(real.d1) + vertical_arm(alpha)
	check("penetrating control finishes physically inside the box", real_endpoint_down > 0.0, "endpoint_down_m=%.12f" % real_endpoint_down)
	check("real point penetration admits a scenery event", real.event != null)
	var target: Dictionary = fixture(world, -alpha, alpha, 0.000300, 0.000050)
	print_event("rotating_clear_test", target)
	print("PARAM cg_down_start=%.12f cg_down_end=%.12f cg_velocity_ned=%s body_rate=%s" % [float(target.d0), float(target.d1), str(target.velocity_ned), str(target.rates)])
	# CG down is an affine interpolation and both endpoints lie above D=0.
	check("CG is outside box for entire interval", float(target.d0) < 0.0 and float(target.d1) < 0.0)
	var event: Variant = target.event
	if event != null:
		var f: float = float(event.time_fraction)
		var u: float = 2.0 * f - 1.0
		var phi: float = 2.0 * atan(u * t)
		var predicted_point_down: float = (1.0 - f) * float(target.d0) + f * float(target.d1) + vertical_arm(phi)
		var omega: float = 2.0 * alpha / DT
		var cg_down_speed: float = (float(target.d1) - float(target.d0)) / DT
		# Source interpolates endpoint body velocities, then rotates v_body + omega×r.
		# This independent expression reproduces that specific velocity convention;
		# it is not asserted to be the exact derivative of the nlerp pose.
		var body_y: float = (1.0 - f) * cg_down_speed * sin(-alpha) + f * cg_down_speed * sin(alpha)
		var body_z: float = cg_down_speed * cos(alpha)
		var expected_normal_speed: float = sin(phi) * (body_y - omega * R_Z) + cos(phi) * (body_z + omega)
		print("ORACLE event_fraction=%.12f phi_rad=%.12f predicted_true_point_down_m=%.12f independently_predicted_approach_mps=%.12f" % [f, phi, predicted_point_down, expected_normal_speed])
		check("reported point matches independent actual-pose point", absf(float(event.point_ned[2]) - predicted_point_down) < 1e-9)
		check("reported event point respects all-interval clear bound", -float(event.point_ned[2]) >= whole_interval_min_clearance - 1e-9)
		check("reported normal velocity matches body interpolation oracle", absf(float(event.normal_speed_mps) - expected_normal_speed) < 1e-8)
		check("event passes nonterminal normal-speed admission floor", float(event.normal_speed_mps) >= Collision.MIN_RESPONSE_NORMAL_SPEED_MPS and not event.terminal)
		check("event time matches padded chord entry", absf(f - predicted_fraction) < 1e-7)
	# Desired behavior assertion: if this fails with the controls and oracle above,
	# evidence is bounded to an uninflated synthetic proxy/one-point component call.
	check("desired: clear rotating point produces no uninflated-box contact", event == null)
	print("SUMMARY outside-CG component checks=%d desired_failures_or_fixture_errors=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
