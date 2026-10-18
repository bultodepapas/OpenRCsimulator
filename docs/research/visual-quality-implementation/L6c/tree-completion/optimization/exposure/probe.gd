extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const Conditions = preload("res://render/world/conditions.gd")
const Ephemeris = preload("res://render/world/ephemeris.gd")
const SkyState = preload("res://render/world/sky_state.gd")
const FieldLights = preload("res://render/world/field_lights.gd")
const Clock = preload("res://render/shader_clock.gd")

func _initialize() -> void:
	Clock.register()
	var base: String = get_script().resource_path.get_base_dir()
	var reference: GDScript = load(base.path_join("world_reference.gd"))
	var candidate: GDScript = load(base.path_join("world_candidate.gd"))
	var loaded := FieldLights.load_from()
	assert(loaded.ok)
	var targets: Array[Vector3] = [Vector3(0, 10, 0), Vector3(12, 3, -30), Vector3(0, 120, -300), Vector3(50, 0, 20)]
	for script in [reference, candidate]:
		script._lights = loaded.lights
		script._ground_light = FieldLights.illuminance_point(loaded.lights, Vector3(0, 0.5, 0))
	var rows: Array = []
	var matches := 0
	var mismatches := 0
	var original_env := OS.get_environment("OPENRC_LANDSCAPE_UPGRADE")
	var had_env := OS.has_environment("OPENRC_LANDSCAPE_UPGRADE")
	for selector in ["on", "off"]:
		OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", selector)
		for preset in ["noon", "golden_hour", "sunset", "blue_hour", "night", "legacy"]:
			var conditions := Conditions.resolve(PackedStringArray(["--time_of_day=" + preset])) if preset != "legacy" else {}
			Atmosphere.state = SkyState.state(Ephemeris.sky(conditions.when)) if preset != "legacy" else {}
			for profile in ["club", "airfield", "off"]:
				reference._night_profile = profile
				candidate._night_profile = profile
				for target in targets:
					for share in [-1.0, 0.0, 0.5, 1.0, 2.0]:
						if reference.view_exposure(target, share) == candidate.view_exposure(target, share): matches += 1
						else: mismatches += 1
			reference._night_profile = "club"
			candidate._night_profile = "club"
			var timings: Array = []
			for pair in 7:
				var row := {}
				for side in (["reference", "candidate"] if pair % 2 == 0 else ["candidate", "reference"]):
					var script: GDScript = reference if side == "reference" else candidate
					var sum := 0.0
					var start := Time.get_ticks_usec()
					for index in 2000:
						sum += script.view_exposure(targets[index % targets.size()], float(index % 11) / 10.0)
					row[side] = {usec = Time.get_ticks_usec() - start, checksum = sum}
				timings.append(row)
			rows.append({selector = selector, preset = preset, timings = timings})
	if had_env: OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", original_env)
	else: OS.unset_environment("OPENRC_LANDSCAPE_UPGRADE")
	var report := {matches = matches, mismatches = mismatches, rows = rows, source_reference = FileAccess.get_sha256(reference.resource_path), source_candidate = FileAccess.get_sha256(candidate.resource_path)}
	FileAccess.open(base.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("Exposure parity: ", matches, "; mismatches: ", mismatches)
	quit(0 if mismatches == 0 else 1)
