## AUD-15: recorded powertrain identity, RPM bands, observer reset and pause behavior.
extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Powertrain = preload("res://audio/powertrain_audio.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	var airplanes: Array = Catalog.airplane_flyable_entries()
	_check("catalog has eight fixed-wing configurations", airplanes.size() == 8, str(airplanes.size()))
	for entry: Dictionary in airplanes:
		var id := str(entry.id)
		var profile: Dictionary = Powertrain.profile_for(id, {})
		_check("profile preserves aircraft identity: " + id, str(profile.get("id", "")) == id)
		_check("profile has usable RPM reference: " + id,
			float(profile.get("max_rpm", 0.0)) > 0.0 and int(profile.get("blades", 0)) >= 2)
	_check("P-51 maps to gasoline bank", Powertrain.profile_for("p51d-mustang-120", {}).family == "gasoline")
	_check("Avanti maps to turbine bank", Powertrain.profile_for("sebart-avanti-s-a200-p100rx", {"kind": "turbine"}).family == "turbine")
	_check("Timber maps to electric bank", Powertrain.profile_for("turbo-lumber-evolution", {"kind": "electric_prop"}).family == "electric")
	_check("X-Cell maps to rotor bank", Powertrain.profile_for("xcell-60-research", {}).family == "rotor")

	var bands := Powertrain.band_weights(sqrt(6000.0 * 12000.0), PackedFloat64Array([6000.0, 12000.0]))
	_check("adjacent RPM layers use an equal-power midpoint",
		bands.size() == 2 and absf(bands[0] * bands[0] + bands[1] * bands[1] - 1.0) < 1e-9,
		str(bands))
	_check("distance law is bounded at the source", is_equal_approx(Powertrain.distance_gain(0.0), 8.0 / 3.0))
	_check("distance law reaches silence at its far bound", Powertrain.distance_gain(1500.0) == 0.0)

	# Attach one deterministic looping test layer so behavior is exercised without a particular
	# licensed recording manifest or a live aircraft scene.
	var rig := Powertrain.new()
	rig.profile = {id = "test-rig", family = "gasoline", max_rpm = 12000.0, trim_db = 0.0}
	root.add_child(rig)
	var pcm := PackedByteArray()
	for _i: int in 1024:
		pcm.append(0)
		pcm.append(0)
	var source := AudioStreamWAV.new()
	source.format = AudioStreamWAV.FORMAT_16_BITS
	source.mix_rate = 48000
	source.data = pcm
	var player := AudioStreamPlayer3D.new()
	player.stream = Powertrain.guarded_loop(source)
	rig.add_child(player)
	rig.players.append(player)
	rig.layers.append({rpm = 6000.0, gain = 1.0})
	rig.levels.resize(1)
	var stopped := {rpm = 0.0, max_rpm = 12000.0, running = false, throttle = 0.0, load = 0.0,
		source = Vector3.ZERO, listener = Vector3.ZERO, paused = false}
	rig.update_sound(stopped, 1.0 / 60.0)
	_check("initial stopped snapshot stays silent", rig.last_targets.get("running", true) == false and rig.levels[0] == 0.0)
	var running := stopped.duplicate(true)
	running.rpm = 7200.0
	running.running = true
	running.throttle = 0.6
	running.load = 0.5
	# Starting from an already accepted running snapshot creates only the ordinary smoothed bank level.
	rig.reset_observer()
	rig.update_sound(running, 1.0 / 60.0)
	_check("initial already-running snapshot follows accepted RPM without a fabricated start edge",
		float(rig.last_targets.get("accepted_rpm", -1.0)) == 7200.0 and rig.last_targets.get("running", false)
		and rig.levels[0] >= 0.0 and rig.levels[0] < float(rig.last_targets.get("level", 1.0)))
	var paused := running.duplicate(true)
	paused.paused = true
	rig.update_sound(paused, 1.0 / 60.0, 0.0)
	_check("paused zero-gain snapshot freezes the stream", player.stream_paused and player.volume_db <= -90.0,
		"paused=%s volume_db=%s" % [player.stream_paused, player.volume_db])
	rig.reset_observer()
	_check("reset stops and silences every layer", not player.playing and rig.levels[0] == 0.0 and player.volume_db <= -90.0)

	print("AUD-15 powertrain checks: %d, failed: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
