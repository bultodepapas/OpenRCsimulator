extends SceneTree

const AirfieldLighting := preload("res://render/landscape_upgrade/airfield_lighting.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Exposure := preload("res://render/world/exposure.gd")

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("LU-03 lighting: " + label + (": " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	var field_result := FieldLoader.load_from()
	_check("default field loads", field_result.ok, "; ".join(field_result.errors))
	var scenery_result := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field_result.field)
	_check("default scenery validates", scenery_result.ok, "; ".join(scenery_result.errors))
	var lights_result := FieldLights.load_from()
	_check("existing field light positions validate", lights_result.ok, "; ".join(lights_result.errors))
	if not field_result.ok or not scenery_result.ok or not lights_result.ok:
		quit(1)
		return

	var field_lights := FieldLights.build(lights_result.lights)
	var helper: Variant = AirfieldLighting.build(field_result.field, lights_result.lights, scenery_result.scenery)
	_check("helper creates runway fixture hardware", helper.get_node_or_null("RunwayFixtureHardware") is MeshInstance3D)
	_check("four mast heads and windsock receive hardware", helper.get_meta("fixture_hardware").flood_housings == 5)
	_check("all current stake locations receive posts", helper.get_meta("fixture_hardware").marker_posts == 19,
		str(helper.get_meta("fixture_hardware").marker_posts))
	var spill := helper.get_node_or_null("RunwayEdgeGroundSpill") as MultiMeshInstance3D
	_check("low edge scatter uses one twelve-instance batch and no direct lights",
		spill != null and spill.multimesh.instance_count == 12
		and int(helper.get_meta("ground_spill_instances", 0)) == 12)
	var spill_material := spill.multimesh.mesh.material as ShaderMaterial if spill != null else null
	var pavilion: Node = helper.find_child("PavilionLighting_*", true, false)
	_check("pavilion is matched by validated placement", pavilion != null)
	if pavilion != null:
		_check("six actual pavilion windows are represented", pavilion.get_meta("window_count") == 6)
		_check("one mullion is added inside each pane", pavilion.get_meta("mullion_count") == 6)
		_check("window insert remains shallow", is_equal_approx(float(pavilion.get_meta("shallow_window_depth_m")), 0.16))
		_check("window inserts use prefab glass-centre elevations",
			pavilion.get_meta("window_centers_y_m") == [1.575, 1.575, 1.65, 1.65, 1.55, 1.55])
		var panes := pavilion.get_node("PavilionWarmWindowsAndLamps") as MultiMeshInstance3D
		_check("six warm panes and two wall lamps share one draw", panes.multimesh.instance_count == 8)
		var window_shader := panes.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		_check("warm panes cap output with the shared live exposure", window_shader.shader.code.contains("world_exposure"))
	var omnis: Array = helper.find_children("*", "OmniLight3D", true, false)
	var spots: Array = helper.find_children("*", "SpotLight3D", true, false)
	_check("exactly two veranda pool lights", omnis.size() == 2, str(omnis.size()))
	_check("helper never duplicates existing flood spots", spots.is_empty())
	var existing_spots := field_lights.find_children("*", "SpotLight3D", true, false)
	_check("existing FieldLights remains the only five-spot source", existing_spots.size() == 5)
	var original_spot_energies: Array[float] = []
	for spot: SpotLight3D in existing_spots:
		original_spot_energies.append(spot.light_energy)

	var day_env := Atmosphere.environment()
	helper.bind_environment(day_env, field_lights)
	_check("fixed FW sun keeps existing lights root visible", field_lights.visible)
	_check("day has no local pools", is_zero_approx(float(helper.get_meta("night_factor"))))
	_check("day has no marker ground scatter", spill_material != null
		and is_zero_approx(float(spill_material.get_shader_parameter("night_factor"))) and not spill.visible)
	for spot: SpotLight3D in existing_spots:
		_check("day flood energy is zero: " + spot.name, is_zero_approx(spot.light_energy))
	var flood_sprite := field_lights.get_node("flood_west_lamp") as MeshInstance3D
	var flood_material := flood_sprite.mesh.surface_get_material(0) as ShaderMaterial
	_check("day marker sprites are dimmed without hiding fixture geometry", is_zero_approx(float(flood_material.get_shader_parameter("radiance"))))
	var sky_shader := day_env.sky.sky_material as ShaderMaterial
	sky_shader.set_shader_parameter("sun_disc", 0.0)
	sky_shader.set_shader_parameter("disc_dir", Vector3(0.0, sin(deg_to_rad(-0.5)), -cos(deg_to_rad(-0.5))))
	helper.call("_update_from_environment")
	_check("sun-disc fade uses a continuous solar-elevation transition",
		float(helper.get_meta("night_factor")) > 0.45 and float(helper.get_meta("night_factor")) < 0.55,
		str(helper.get_meta("night_factor")))
	sky_shader.set_shader_parameter("disc_cloud_occlusion", true)
	sky_shader.set_shader_parameter("disc_dir", Vector3(0.0, sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0))))
	helper.call("_update_from_environment")
	_check("cloud-disc direction keeps the actual sun above the horizon", is_zero_approx(float(helper.get_meta("night_factor"))))
	# Repeated sky polls must still observe explicit snapshots, exposure and material replacement.
	helper.call("_update_from_environment")
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	helper.call("_update_from_environment")
	_check("unchanged sky supersedes a direct night snapshot", is_zero_approx(float(helper.get_meta("night_factor"))))
	sky_shader.set_shader_parameter("disc_dir", Vector3.DOWN)
	helper.call("_update_from_environment")
	var uncapped_energy: float = omnis[0].light_energy
	day_env.tonemap_exposure = 10000.0
	helper.call("_update_from_environment")
	_check("unchanged night direction observes changed exposure",
		omnis[0].light_energy < uncapped_energy and omnis[0].light_energy <= 0.0000121)
	day_env.tonemap_exposure = 1.0
	var replacement := sky_shader.duplicate() as ShaderMaterial
	replacement.set_shader_parameter("disc_dir", Vector3.UP)
	day_env.sky.sky_material = replacement
	helper.call("_update_from_environment")
	_check("replacement sky material updates the light state", is_zero_approx(float(helper.get_meta("night_factor"))))
	day_env.sky.sky_material = sky_shader
	sky_shader.set_shader_parameter("disc_dir", Vector3.UP)
	helper.bind_environment(day_env, field_lights)
	_check("rebinding an unchanged environment initializes the fixtures",
		existing_spots.all(func(s: SpotLight3D) -> bool: return is_zero_approx(s.light_energy)))
	_check("manual on accepts an explicit daylight override", helper.set_activation("on")
		and is_equal_approx(float(helper.get_meta("night_factor")), 1.0)
		and existing_spots.all(func(s: SpotLight3D) -> bool: return s.light_energy > 0.0))
	_check("manual on also enables bounded batched ground scatter",
		is_equal_approx(float(spill_material.get_shader_parameter("night_factor")), 1.0)
		and float(spill_material.get_shader_parameter("display_cap")) <= 0.05 and spill.visible)
	_check("manual off extinguishes lights while retaining their fixtures", helper.set_activation("off")
		and is_zero_approx(float(helper.get_meta("night_factor")))
		and existing_spots.all(func(s: SpotLight3D) -> bool: return is_zero_approx(s.light_energy))
		and helper.get_node_or_null("RunwayFixtureHardware") != null)
	_check("manual off removes the ground scatter", is_zero_approx(float(spill_material.get_shader_parameter("night_factor")))
		and not spill.visible)
	_check("invalid activation is rejected without changing the switch", not helper.set_activation("invalid")
		and str(helper.get_meta("field_activation")) == "off")
	_check("auto restores daylight gating", helper.set_activation("auto")
		and is_zero_approx(float(helper.get_meta("night_factor"))))

	helper.apply_lighting({"sun_elevation_deg": -0.5})
	var transition := float(helper.get_meta("night_factor"))
	_check("dusk changes continuously through the transition", transition > 0.45 and transition < 0.55, str(transition))
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("night reaches full local lighting", is_equal_approx(float(helper.get_meta("night_factor")), 1.0))
	_check("manual off overrides full night", helper.set_activation("off")
		and is_zero_approx(float(helper.get_meta("night_factor"))))
	_check("auto restores full night", helper.set_activation("auto")
		and is_equal_approx(float(helper.get_meta("night_factor")), 1.0))
	_check("two veranda pools brighten at night", omnis.all(func(node: OmniLight3D) -> bool: return node.light_energy > 0.0))
	var spots_restore := true
	for i in existing_spots.size():
		spots_restore = spots_restore and absf((existing_spots[i] as SpotLight3D).light_energy - original_spot_energies[i]) < 1e-6
	_check("night restores the five original spot energies before high-exposure capping", spots_restore)
	day_env.tonemap_exposure = 10000.0
	Exposure.set_value(10000.0)
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("night pool energy is capped against the live exposure",
		omnis.all(func(node: OmniLight3D) -> bool: return node.light_energy > 0.0 and node.light_energy <= 0.0000121))
	var spots_capped := true
	var runway_spots_visible := true
	for spot: SpotLight3D in existing_spots:
		var cap := 800.0 if spot.name.begins_with("flood_") else 0.6
		var expected_cap_energy := minf(original_spot_energies[existing_spots.find(spot)], cap / 10000.0)
		spots_capped = spots_capped and spot.light_energy > 0.0 and absf(spot.light_energy - expected_cap_energy) < 1e-8
		if spot.name.begins_with("flood_"):
			runway_spots_visible = runway_spots_visible and spot.light_energy >= 0.0799
	_check("all five existing spot contributions use their high-exposure caps", spots_capped)
	_check("runway flood spots retain the 800-unit inverse-square display budget", runway_spots_visible)
	helper.apply_lighting({"sun_elevation_deg": -0.5})
	var spot_transition := true
	var spot_factor := float(helper.get_meta("night_factor"))
	for i in existing_spots.size():
		var spot: SpotLight3D = existing_spots[i]
		var cap := 800.0 if spot.name.begins_with("flood_") else 0.6
		var expected := minf(original_spot_energies[i], cap / 10000.0) * spot_factor
		spot_transition = spot_transition and absf(spot.light_energy - expected) < 1e-8
	_check("existing spot energy fades continuously under high exposure", spot_transition)
	_check("existing sprites restore their original radiance", float(flood_material.get_shader_parameter("radiance")) > 0.0)
	helper.apply_lighting({"sun_disc": 0.0, "sun_dir": Vector3.UP})
	_check("moon as dominant world light still means night", is_equal_approx(float(helper.get_meta("night_factor")), 1.0))
	helper.apply_lighting({"sun_disc": 0.0,
		"disc_dir": Vector3(0.0, sin(deg_to_rad(-0.5)), -cos(deg_to_rad(-0.5)))})
	_check("sun-disc fade snapshot still transitions continuously from the solar direction",
		float(helper.get_meta("night_factor")) > 0.45 and float(helper.get_meta("night_factor")) < 0.55)
	helper.apply_lighting({"disc_cloud_occlusion": true, "disc_dir": Vector3(0.0, sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0)))})
	_check("cloud-occluded path follows the solar-disc direction", is_zero_approx(float(helper.get_meta("night_factor"))))
	day_env.tonemap_exposure = 0.6
	Exposure.set_value(0.6)
	helper.bind_environment(day_env, field_lights, 1000.0)
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("static SDR snapshots accept a bounded local-light gain", is_equal_approx(float(helper.get_meta("sdr_local_gain")), 1000.0))
	var sdr_spots_bounded := true
	for i in existing_spots.size():
		var spot: SpotLight3D = existing_spots[i]
		var cap := 800.0 if spot.name.begins_with("flood_") else 0.6
		var expected := minf(original_spot_energies[i] * 1000.0, cap / 0.6)
		sdr_spots_bounded = sdr_spots_bounded and absf(spot.light_energy - expected) < 5e-6
	_check("SDR gain cannot exceed the runway and auxiliary output caps", sdr_spots_bounded)
	_check("SDR gain keeps veranda pools within their live-exposure cap",
		omnis.all(func(node: OmniLight3D) -> bool: return node.light_energy > 0.0 and node.light_energy <= 0.200001))
	var sdr_sprite_bounded := float(flood_material.get_shader_parameter("radiance")) > 0.0
	for surface in flood_sprite.mesh.get_surface_count():
		var material := flood_sprite.mesh.surface_get_material(surface) as ShaderMaterial
		if material != null and material.get_shader_parameter("display_cap") != null:
			var respects_cap := float(material.get_shader_parameter("radiance")) <= float(material.get_shader_parameter("display_cap")) / 0.6 + 1e-6
			sdr_sprite_bounded = sdr_sprite_bounded and respects_cap
	_check("sprite SDR gain respects its existing shader display cap", sdr_sprite_bounded)

	var preserved: Array = lights_result.lights.get("fixtures", [])
	_check("runway edge positions remain in the existing data", preserved.filter(func(f: Dictionary) -> bool: return f.id == "runway_edge_stakes")[0].points.size() == 12)
	_check("threshold positions remain in the existing data", preserved.filter(func(f: Dictionary) -> bool: return f.id == "threshold_stakes")[0].points.size() == 6)
	_check("no added real spots or markers alter fixture counts", field_lights.get_meta("spots") == 5)
	helper.apply_lighting({"sun_elevation_deg": -8.0})
	_check("off profile accepted", helper.set_profile("off"))
	_check("off profile extinguishes every field spot", existing_spots.all(func(s: SpotLight3D) -> bool: return is_zero_approx(s.light_energy)))
	var club_color: Color = (existing_spots[0] as SpotLight3D).light_color
	_check("airfield profile accepted", helper.set_profile("airfield"))
	_check("airfield uses a visibly cooler flood tint", not (existing_spots[0] as SpotLight3D).light_color.is_equal_approx(club_color))
	_check("airfield restores every spot", existing_spots.all(func(s: SpotLight3D) -> bool: return s.light_energy > 0.0))
	_check("unknown profile rejected", not helper.set_profile("invalid"))
	_check("all downloaded head instances exist", helper.find_children("*_housing", "Node3D", false, false).size() == 5)
	var scenery_off_helper := AirfieldLighting.build(field_result.field, lights_result.lights, {})
	_check("fixture hardware remains when clubhouse scenery is disabled",
		scenery_off_helper.get_node_or_null("RunwayFixtureHardware") is MeshInstance3D)
	_check("clubhouse pools and window inserts require a validated pavilion placement",
		scenery_off_helper.find_children("*", "OmniLight3D", true, false).is_empty()
		and scenery_off_helper.find_child("PavilionLighting_*", true, false) == null)
	print("%d checks, %d failed" % [_checks, _failures])
	scenery_off_helper.free()
	helper.free()
	field_lights.free()
	quit(1 if _failures > 0 else 0)
