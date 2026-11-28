extends SceneTree
## NK-6s: GlowAudioState.vibration (native numbers, GDScript dictionary) equals GlowFlight.Vibration.evaluate bit for
## bit, read-only flag included: random crank phases (any sign and size), speeds (0 to beyond redline), zero and
## nonzero angular acceleration and firing fractions, for every stock glow geometry; invalid inputs and an unchecked
## geometry return evaluate's own answer. Skips (passes) without the verified native library.

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flight := preload("res://sim/flight_session.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const GlowAudioState := preload("res://audio/glow_audio_state.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _same(a: Dictionary, b: Dictionary) -> bool:
	return var_to_bytes(a) == var_to_bytes(b) and a.is_read_only() == b.is_read_only()


func _run() -> void:
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or GlowAudioState._vibration_kernel() == null:
		print("NK6S_SKIP native library unavailable")
		quit(0)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 6065
	var geometries := 0
	var samples := 0
	var mismatched := 0
	for id: String in ["gp-extra-300s-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]:
		var s: Node = Flight.new()
		s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
		if not s.aircraft.get("ok", false) or not s.glow_is_active():
			s.free()
			continue
		var prepared: Dictionary = GlowFlight.Vibration.prepare(s.aircraft.model.propulsion.glow.profile)
		s.free()
		if not prepared.get("ok", false):
			continue
		geometries += 1
		for i in 5000:
			var phase: float = rng.randf_range(-200.0, 200.0) if i % 3 else rng.randf_range(0.0, TAU)
			var omega: float = [0.0, rng.randf_range(0.0, 3000.0), rng.randf_range(0.0, 20.0)][i % 3]
			var alpha: float = 0.0 if i % 2 else rng.randf_range(-500.0, 500.0)
			var firing: float = [0.0, 1.0, rng.randf()][i % 3]
			samples += 1
			if not _same(GlowAudioState.vibration(prepared, phase, omega, alpha, firing),
					GlowFlight.Vibration.evaluate(prepared, phase, omega, alpha, firing)):
				mismatched += 1
		for bad: Array in [[NAN, 100.0, 0.0, 1.0], [1.0, -1.0, 0.0, 1.0], [1.0, 100.0, 0.0, 1.5], [INF, 1.0, 0.0, 0.5]]:
			samples += 1
			if not _same(GlowAudioState.vibration(prepared, bad[0], bad[1], bad[2], bad[3]),
					GlowFlight.Vibration.evaluate(prepared, bad[0], bad[1], bad[2], bad[3])):
				mismatched += 1
	_check("native vibration equals evaluate (%d samples, %d geometries)" % [samples, geometries],
		mismatched == 0 and geometries >= 3, str(mismatched))
	var unchecked := {ok = true, errors = PackedStringArray(), prepared = {family = "glow_2t"}}
	_check("an unchecked geometry returns evaluate's answer", _same(GlowAudioState.vibration(unchecked, 1.0, 100.0, 0.0, 1.0),
		GlowFlight.Vibration.evaluate(unchecked, 1.0, 100.0, 0.0, 1.0)))
	print("native glow vibration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
