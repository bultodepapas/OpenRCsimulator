# D5: the placeholder engine sound — pitch follows rpm, no clicks between blocks, bounded amplitude.
# Run: godot --headless --path . --script res://tests/test_engine_sound.gd
extends SceneTree

const Sound := preload("res://render/engine_sound.gd")
const FlightAudio := preload("res://audio/flight_audio.gd")
# Counts are FlightAudio helper outputs; Avanti's 2 is the fallback for its turbine path.
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const EXPECTED_AIRCRAFT_BLADE_COUNTS := {
	"jensen-das-ugly-stik-60": 2,
	"stik-glow-61fx-2t": 2,
	"stik-glow-55ax-2t": 2,
	"stik-glow-fs64v-4t": 2,
	"gp-extra-300s-60": 2,
	"p51d-mustang-120": 4,
	"f4u-corsair-250": 3,
	"sebart-avanti-s-a200-p100rx": 2,
	"turbo-lumber-evolution": 3,
	"skywalker-x8": 2, # X8-09: APC 12x6E(P) two-blade pusher
}

class LegacySessionStub extends Node:
	var engine_running: bool = true


class AcceptedSourceStub extends Node:
	var engine_running: bool = true
	var accepted_running: bool = false

	func propulsion_source_running() -> bool:
		return accepted_running


class AtmosphereSessionStub extends Node:
	var temperature_k: float = 288.15

	func atmosphere_configuration() -> Dictionary:
		return {"temperature_k": temperature_k}


class FlightStub extends Node3D:
	var session: AtmosphereSessionStub

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Goertzel: signal power at one frequency.
func _power(x: PackedFloat32Array, freq: float, rate: float) -> float:
	var w := TAU * freq / rate
	var coeff := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s0 := v + coeff * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


func _initialize() -> void:
	var rate := Sound.MIX_RATE
	_check("firing frequency = rpm / 60", Sound.firing_frequency(6000.0) == 100.0 and Sound.firing_frequency(-5.0) == 0.0)
	var timber_motor: Dictionary = {
		"kind": "electric_prop",
		"motor": {"kv_rpm_per_volt": 800.0},
		"battery": {"kind": "fixed_voltage", "voltage_v": 14.8},
		"max_rpm": 12000.0,
	}
	_check("fixed-bus electric audio reference is Kv × voltage", Sound.reference_rpm(timber_motor) == 11840.0,
		str(Sound.reference_rpm(timber_motor)))
	var ocv_motor: Dictionary = {
		"kind": "electric_prop",
		"motor": {"kv_rpm_per_volt": 800.0},
		"battery": {"kind": "ocv_resistance"},
		"max_rpm": 13440.0,
	}
	_check("OCV electric fixture keeps its normalized reference RPM", Sound.reference_rpm(ocv_motor) == 13440.0)
	_check("electric data without a reference does not use the combustion fallback",
		Sound.reference_rpm({"kind": "electric_prop"}) == 0.0)
	var airplane_ids := Array(Catalog.airplane_flyable_ids())
	var expected_airplane_ids := EXPECTED_AIRCRAFT_BLADE_COUNTS.keys()
	airplane_ids.sort()
	expected_airplane_ids.sort()
	_check("explicit propeller blade-count expectations cover exactly the flyable airplane catalog",
		airplane_ids == expected_airplane_ids,
		"catalog=%s expected=%s" % [str(airplane_ids), str(expected_airplane_ids)])
	for aircraft_id: String in EXPECTED_AIRCRAFT_BLADE_COUNTS:
		var expected_blades: int = int(EXPECTED_AIRCRAFT_BLADE_COUNTS[aircraft_id])
		var check_label := "FlightAudio helper returns %d for %s" % [expected_blades, aircraft_id]
		if aircraft_id == "sebart-avanti-s-a200-p100rx":
			check_label = "Avanti turbine audio helper returns fallback blade count %d" % expected_blades
		_check(check_label, FlightAudio.propeller_blade_count(aircraft_id) == expected_blades,
			"actual=%d" % FlightAudio.propeller_blade_count(aircraft_id))
	var audio_adapter: Node = FlightAudio.new()
	var flight_stub := FlightStub.new()
	flight_stub.session = AtmosphereSessionStub.new()
	audio_adapter.set("flight", flight_stub)
	for temperature_k: float in [216.65, 288.15, 308.15]:
		flight_stub.session.temperature_k = temperature_k
		var expected_sound_speed: float = sqrt(1.4 * 287.05 * temperature_k)
		_check("sound speed follows accepted atmosphere temperature %.2f K" % temperature_k,
			is_equal_approx(float(audio_adapter.call("sound_speed_mps")), expected_sound_speed))
	audio_adapter.free()
	flight_stub.session.free()
	flight_stub.free()
	var accepted_source := AcceptedSourceStub.new()
	_check("accepted stopped source silences audio while ignition remains on",
		FlightAudio.propulsion_source_running(accepted_source) == false and accepted_source.engine_running)
	accepted_source.accepted_running = true
	_check("accepted active source restores audio",
		FlightAudio.propulsion_source_running(accepted_source) and accepted_source.engine_running)
	var legacy_session := LegacySessionStub.new()
	_check("audio compatibility falls back to engine_running without source API",
		FlightAudio.propulsion_source_running(legacy_session))
	accepted_source.free()
	legacy_session.free()

	# The buzz has its fundamental at rpm/60, not in between harmonics.
	for rpm in [2800.0, 5139.0, 11149.0]:
		var f := Sound.firing_frequency(rpm)
		var x: PackedFloat32Array = Sound.synthesize(0.0, f, 0.5, 8192)[0]
		var at_f := _power(x, f, rate)
		var off := _power(x, 1.5 * f, rate)
		_check("%d rpm: energy at %.1f Hz ≫ at 1.5×" % [rpm, f], at_f > 100.0 * off, "%s vs %s" % [String.num_scientific(at_f), String.num_scientific(off)])

	# Doubling rpm doubles the pitch.
	var lo: PackedFloat32Array = Sound.synthesize(0.0, 50.0, 0.5, 8192)[0]
	var hi: PackedFloat32Array = Sound.synthesize(0.0, 100.0, 0.5, 8192)[0]
	_check("2× rpm → the fundamental moves to 2× frequency", _power(hi, 100.0, rate) > 50.0 * _power(hi, 50.0, rate) and _power(lo, 50.0, rate) > 50.0 * _power(hi, 50.0, rate))

	# Phase-continuous: two blocks equal one long block (no clicks at block joins).
	var whole: PackedFloat32Array = Sound.synthesize(0.0, 137.0, 0.5, 2000)[0]
	var first := Sound.synthesize(0.0, 137.0, 0.5, 1200)
	var second: PackedFloat32Array = Sound.synthesize(first[1], 137.0, 0.5, 800)[0]
	var joined: PackedFloat32Array = first[0]
	joined.append_array(second)
	var worst := 0.0
	for i in 2000:
		worst = maxf(worst, absf(joined[i] - whole[i]))
	_check("blocks join without a click", worst < 1e-5, String.num_scientific(worst))

	# Never louder than requested.
	var peak := 0.0
	for v in Sound.synthesize(0.3, 186.0, 0.6, 22050)[0]:
		peak = maxf(peak, absf(v))
	_check("|sample| <= amp", peak <= 0.6 + 1e-6, str(peak))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
