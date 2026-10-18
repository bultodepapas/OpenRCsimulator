extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const Conditions = preload("res://render/world/conditions.gd")
const Ephemeris = preload("res://render/world/ephemeris.gd")
const SkyState = preload("res://render/world/sky_state.gd")
const FieldLights = preload("res://render/world/field_lights.gd")
const Clock = preload("res://render/shader_clock.gd")
const Exposure = preload("res://render/world/exposure.gd")

func same(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))

func _initialize() -> void:
	Clock.register()
	var base: String = get_script().resource_path.get_base_dir()
	var reference: GDScript = load(base.path_join("world_reference.gd"))
	var candidate: GDScript = load("res://render/world/world.gd")
	var loaded := FieldLights.load_from()
	assert(loaded.ok)
	var when: Dictionary = Conditions.resolve(PackedStringArray(["--time_of_day=night"])).when
	var night := SkyState.state(Ephemeris.sky(when))
	var targets: Array[Vector3] = [Vector3(0, 10, 0), Vector3(12, 3, -30), Vector3(0, 120, -300), Vector3(NAN, 0, 0), Vector3(INF, 0, 0)]
	var failures: Array = []
	var checked := 0
	var transitions := 0
	var had_env := OS.has_environment("OPENRC_LANDSCAPE_UPGRADE")
	var saved_env := OS.get_environment("OPENRC_LANDSCAPE_UPGRADE")
	for selector in ["on", "off"]:
		OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", selector)
		for script in [reference, candidate]:
			script._lights = loaded.lights
			script._ground_light = 20.0
		for profile in ["club", "airfield", "off"]:
			reference._night_profile = profile
			candidate._night_profile = profile
			for elevation in [-4.001, -4.0, -3.999, 0.0, 2.999, 3.0, 3.001, 45.0]:
				Atmosphere.state = night.duplicate()
				Atmosphere.state.sun_elevation_deg = elevation
				for target in targets:
					for share in [-1.0, 0.0, 0.5, 1.0, 2.0, NAN, INF]:
						checked += 1
						if not same(reference.view_exposure(target, share), candidate.view_exposure(target, share)):
							failures.append({selector = selector, profile = profile, elevation = elevation, target = str(target), share = str(share)})
		var a := Environment.new()
		var b := Environment.new()
		a.tonemap_exposure = 0.6
		b.tonemap_exposure = 0.6
		reference._adapt_clock = -1.0
		candidate._adapt_clock = -1.0
		for index in 180:
			Atmosphere.state = night.duplicate()
			Atmosphere.state.sun_elevation_deg = 5.0 - float(index % 100) * 0.1
			var profile := "off" if index % 17 == 0 else "club"
			reference._night_profile = profile
			candidate._night_profile = profile
			# Repeated clocks exercise pause; modulo crossing exercises rewind, then a large jump.
			var clock_s := float((index / 2) % 60) * 0.1 + (20.0 if index >= 160 else 0.0)
			var target := targets[index % 3]
			var share := float(index % 11) / 10.0
			var x: float = reference.adapt(a, target, clock_s, share)
			var reference_push := Exposure.last
			var y: float = candidate.adapt(b, target, clock_s, share)
			transitions += 1
			if x != y or reference_push != Exposure.last or reference._adapt_log != candidate._adapt_log:
				failures.append({selector = selector, transition = index})
	if had_env: OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", saved_env)
	else: OS.unset_environment("OPENRC_LANDSCAPE_UPGRADE")
	var report := {point_cases = checked, transition_cases = transitions, failures = failures, reference_sha256 = FileAccess.get_sha256(reference.resource_path), candidate_sha256 = FileAccess.get_sha256(candidate.resource_path)}
	FileAccess.open(base.path_join("transitions.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("Exposure boundary/input cases: ", checked, "; adaptation transitions: ", transitions, "; failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
