## FW-82: appearance edits and native visual restore do not perturb the physical session.
extends SceneTree
const Main := preload("res://main.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyCheckpoint := preload("res://app_state/sky_checkpoint.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Conditions := preload("res://render/world/conditions.gd")
const Weather := preload("res://physics/wind_config.gd")
var failures := 0
var checks := 0

func check(label: String, valid: bool) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Conditions.session_preset = "day"
	var flight := Main.new()
	flight.user_args = PackedStringArray(["--soundscape=off"])
	flight.interactive_start = true
	flight.weather_config = Weather.GENTLE_PRACTICE.duplicate(true)
	flight.weather_config.from_deg = 360.0 # canonical north wind, with a live turbulence RNG to preserve
	root.add_child(flight)
	flight.set_process(false)
	if not flight.startup_error.is_empty() or flight.session == null:
		printerr("Sky test startup: " + flight.startup_error)
		quit(1)
		return
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.recorder.detach()
	for tick: int in 24:
		flight.session.sim.step()
	flight.session.sim.set_paused(true)
	var old: Dictionary = flight.checkpoint()
	check("classic keeps existing envelope", old.get("format") == "openrc-visual-checkpoint v1")
	var physics: PackedByteArray = var_to_bytes(flight.session.checkpoint())
	var light: Dictionary = flight.lighting_config.duplicate(true)
	for entry: Dictionary in SkyConfig.presets():
		var result: Dictionary = flight.apply_sky_config(SkyConfig.for_preset(entry.id))
		check("apply " + entry.id, result.ok)
		check("physical bytes unchanged for " + entry.id, physics == var_to_bytes(flight.session.checkpoint()))
		check("time selection unchanged for " + entry.id, flight.lighting_config == light)
	var saved: Dictionary = flight.checkpoint()
	check("new appearance emits sky envelope", saved.get("format") == SkyCheckpoint.FORMAT)
	check("snapshot is detached", saved.config == flight.sky_config and saved.edits.size() == 8)
	check("follow wind is bound to accepted noncalm weather", saved.transport.mean_wind_ned == [-1.5, 0.0, 0.0] \
		and saved.transport.layers[0].velocity_cells_s[1] < 0.0)
	var bad: Dictionary = saved.duplicate(true)
	bad.config.seed += 1
	var before: Dictionary = _observed(flight)
	check("tampered config is rejected without mutation", not flight.restore_checkpoint(bad).ok and _observed(flight) == before)
	bad = saved.duplicate(true)
	bad.profile.renderer.cloud_density = -0.5
	bad.payload_sha256 = SkyCheckpoint._digest(bad)
	check("retuned profile is rejected without mutation", not flight.restore_checkpoint(bad).ok and _observed(flight) == before)
	bad = saved.duplicate(true)
	bad.edits.back().tick = flight.session.sim.tick + 1
	bad.payload_sha256 = SkyCheckpoint._digest(bad)
	check("future edit is rejected without mutation", not flight.restore_checkpoint(bad).ok and _observed(flight) == before)
	bad = saved.duplicate(true)
	bad.transport.mean_wind_ned = [0.0, 0.0, 0.0]
	bad.payload_sha256 = SkyCheckpoint._digest(bad)
	check("mismatched physical wind is rejected without mutation", not flight.restore_checkpoint(bad).ok and _observed(flight) == before)
	check("different selection applies", flight.apply_sky_config(SkyConfig.for_preset("clear")).ok)
	var restored: Dictionary = flight.restore_checkpoint(bytes_to_var(var_to_bytes(saved)))
	check("valid visual restore succeeds", restored.ok)
	check("restores selected storm", flight.sky_config == saved.config)
	check("restores exact cloud transport", Atmosphere.cloud_transport_checkpoint() == saved.transport)
	check("restores physical bytes", var_to_bytes(flight.session.checkpoint()) == physics)
	check("restores ordered visual edit history", flight.checkpoint().edits == saved.edits)
	var sky_context: Dictionary = JSON.parse_string(flight._trace_meta().sky_context)
	# JSON numbers decode as floats; native checkpoint types remain strict and separate.
	check("trace freezes profile and config", sky_context.profile == JSON.parse_string(JSON.stringify(saved.profile, "", true, true)) \
		and sky_context.config == JSON.parse_string(JSON.stringify(saved.config, "", true, true)))
	check("old checkpoint still restores", flight.restore_checkpoint(old).ok)
	check("old checkpoint explicitly selects classic", flight.sky_config == SkyConfig.defaults() and flight._sky_edits.is_empty())
	flight.session.sim.set_paused(false)
	before = _observed(flight)
	check("running flight refuses visual edit", not flight.apply_sky_config(SkyConfig.for_preset("clear")).ok and _observed(flight) == before)
	root.remove_child(flight)
	flight.free()
	print("sky checkpoint checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _observed(flight: Node) -> Dictionary:
	return {physics = var_to_bytes(flight.session.checkpoint()), config = flight.sky_config.duplicate(true),
		transport = Atmosphere.cloud_transport_checkpoint(), light = flight.lighting_config.duplicate(true),
		edits = flight._sky_edits.duplicate(true)}
