extends SceneTree
## Focused contract tests for the sustained-flight fixture.

const Commands := preload("res://input/commands.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const FixedWingContactObserver := preload("res://statistics/fixed_wing_adapter.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Math3D := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	var path: String = get_script().resource_path.get_base_dir().path_join("sustained_input.gd")
	var adapter: Script = load(path)
	if adapter == null:
		printerr("cannot load sustained input adapter: ", path)
		quit(1)
		return
	var target := {roll = 0.5, pitch = -0.3, yaw = 0.2, throttle = 0.6}
	var sample: Dictionary = adapter.keyboard_sample(target, 0.5, 1.0 / 240.0)
	_check("valid packet accepted", sample.ok)
	_check("stick targets preserved", sample.raw.roll == 0.5 and sample.raw.pitch == -0.3 and sample.raw.yaw == 0.2)
	_check("large throttle move saturates at keyboard rate", sample.raw.throttle == 1.0)
	var current := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.5}
	var applied: Dictionary = Commands.step_commands(current, sample.raw, 1.0 / 240.0)
	_check("ordinary keyboard limits surfaces", absf(applied.roll - 4.0 / 240.0) < 1e-12)
	_check("ordinary keyboard limits throttle", absf(applied.throttle - (0.5 + 0.5 / 240.0)) < 1e-12)
	target.throttle = 0.501
	sample = adapter.keyboard_sample(target, 0.5, 1.0 / 240.0)
	applied = Commands.step_commands(current, sample.raw, 1.0 / 240.0)
	_check("nearby absolute throttle reaches target", absf(applied.throttle - 0.501) < 1e-12)
	target.throttle = 0.0
	sample = adapter.keyboard_sample(target, 0.5, 1.0 / 240.0)
	_check("large throttle reduction is bounded", sample.ok and sample.raw.throttle == -1.0)
	_check("zero tick refused", not adapter.keyboard_sample(target, 0.5, 0.0).ok)
	_check("nonfinite throttle refused", not adapter.keyboard_sample(target, NAN, 1.0 / 240.0).ok)
	target.roll = NAN
	_check("nonfinite pilot demand refused", not adapter.keyboard_sample(target, 0.5, 1.0 / 240.0).ok)
	target.roll = 1.01
	_check("out-of-range pilot demand refused", not adapter.keyboard_sample(target, 0.5, 1.0 / 240.0).ok)
	target.erase("yaw")
	_check("missing pilot demand refused", not adapter.keyboard_sample(target, 0.5, 1.0 / 240.0).ok)
	_test_wheel_contact_parity()
	_test_focus_readiness()
	print("sustained fixture contract: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: ", label)


func _test_focus_readiness() -> void:
	var path: String = get_script().resource_path.get_base_dir().path_join("sustained_flight.gd")
	var host: Script = load(path)
	_check("focus readiness host loads", host != null)
	if host == null: return
	var gate: Node = host.FocusReadiness.new()
	gate.begin(1_000_000)
	_check("unfocused cannot start", gate.observe(1_000_000, false, true) == 0)
	_check("focused starts interval", gate.observe(1_100_000, true, true) == 0)
	_check("499999 microseconds insufficient", gate.observe(1_599_999, true, true) == 0)
	_check("500000 microseconds succeeds", gate.observe(1_600_000, true, true) == 1)
	gate.begin(2_000_000)
	_check("second interval starts", gate.observe(2_100_000, true, true) == 0)
	gate.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check("transient window focus loss resets", gate.observe(2_400_000, true, true) == 0)
	_check("reset requires full duration", gate.observe(2_899_999, true, true) == 0)
	_check("reset interval can complete", gate.observe(2_900_000, true, true) == 1)
	gate.begin(3_000_000)
	_check("third interval starts", gate.observe(3_100_000, true, true) == 0)
	gate.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("transient application loss resets", gate.observe(3_400_000, true, true) == 0)
	_check("hidden window resets", gate.observe(3_700_000, true, false) == 0)
	_check("visible again starts new interval", gate.observe(3_800_000, true, true) == 0)
	_check("visibility reset can complete", gate.observe(4_300_000, true, true) == 1)
	gate.begin(10_000_000)
	_check("before deadline can wait", gate.observe(14_999_999, false, false) == 0)
	_check("deadline fails closed", gate.observe(15_000_000, false, false) == -1)
	gate.begin(20_000_000)
	_check("boundary interval starts", gate.observe(24_500_000, true, true) == 0)
	_check("interval completed exactly at deadline succeeds", gate.observe(25_000_000, true, true) == 1)
	_check("late completion fails", gate.observe(25_000_001, true, true) == -1)
	gate.free()


func _test_wheel_contact_parity() -> void:
	# Evaluate detached state copies only; neither simulation ticks nor live state
	# are edited. Compare each wheel's actual >0 contact classification across
	# the existing fast bound and the ordinary per-wheel ground/lake query.
	var field := FieldLoader.load_from()
	var lake := LakeLoader.load_from()
	_check("Club field and lake load", field.ok and lake.ok)
	if not field.ok or not lake.ok: return
	var session: Node = FlightSession.new()
	session.setup("res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60")
	var installed: bool = session.is_flyable() and session.set_field(field.field) and session.set_lake_context(lake.lake)
	_check("contact comparison session installs", installed)
	if not installed:
		session.free()
		return
	session.reset()
	var observer := FixedWingContactObserver.new()
	observer.session = session
	var any_contact := false
	var any_clear := false
	var cases := 0
	for place: Array in [[60.0, -40.0], [110.0, 125.0], [110.0, 170.0]]:
		for altitude: float in [30.0, 2.0, 0.7, 0.3, 0.0, -0.5, -5.0]:
			for bank: float in [0.0, 0.5, -0.5]:
				var state: PackedFloat64Array = session.sim.state.duplicate()
				state[0] = place[0]
				state[1] = place[1]
				state[2] = -altitude
				var attitude: PackedFloat64Array = Math3D.q_from_euler(0.3, 0.1, bank)
				for axis in 4: state[6 + axis] = attitude[axis]
				var full: PackedFloat64Array = session.gear_compressions(state)
				var bounded: PackedFloat64Array = observer._compressions(state)
				var same := full.size() == bounded.size() and not full.is_empty()
				for i in mini(full.size(), bounded.size()):
					if not is_finite(full[i]) or not is_finite(bounded[i]) or (full[i] > 0.0) != (bounded[i] > 0.0): same = false
					any_contact = any_contact or full[i] > 0.0
					any_clear = any_clear or full[i] <= 0.0
				_check("wheel contact flags at %s, %.2f m, bank %.2f" % [str(place), altitude, bank], same)
				cases += 1
	_check("terrain/lake comparison includes contact and clearance", cases == 63 and any_contact and any_clear)
	session.free()
