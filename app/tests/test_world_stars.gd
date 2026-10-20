# FW-24: the star field stands where the ephemeris says: Sirius at its computed azimuth and elevation, Polaris at the
# latitude's height; colours follow B−V; the build is complete and deterministic.
# Run: godot --headless --path . --script res://tests/test_world_stars.gd
extends SceneTree

const Ephemeris := preload("res://render/world/ephemeris.gd")
const Conditions := preload("res://render/world/conditions.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const Stars := preload("res://render/world/stars.gd")
const CacheShaderClock := preload("res://render/shader_clock.gd")
const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Azimuth (from north, clockwise) and elevation in degrees of a render-axes direction.
func _az_el(d: Vector3) -> Vector2:
	var north := -d.z
	var east := d.x
	return Vector2(fposmod(rad_to_deg(atan2(east, north)), 360.0), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))


func _initialize() -> void:
	CacheShaderClock.register()
	var c := Conditions.resolve(PackedStringArray(["--time_of_day=night_dark"]))
	var sky := Ephemeris.sky(c.when)
	var basis := Stars.equatorial_basis(sky.lst_deg, c.when.latitude_deg)
	_check("basis orthonormal", basis.is_equal_approx(basis.orthonormalized()) and absf(basis.determinant() - 1.0) < 1e-5, str(basis))

	# Sirius (RA 101.287°, Dec −16.716°) and Vega (279.234°, +38.784°) against Ephemeris.horizontal at the same instant.
	for star: Array in [["Sirius", 101.287, -16.716], ["Vega", 279.234, 38.784], ["Altair", 297.696, 8.868]]:
		var want := Ephemeris.horizontal(star[1], star[2], c.when.latitude_deg, c.when.longitude_deg, sky.jd)
		var got := _az_el(basis * Stars.equatorial(star[1], star[2]))
		var daz := absf(fposmod(got.x - want.azimuth_deg + 180.0, 360.0) - 180.0) * cos(deg_to_rad(want.elevation_deg))
		_check("%s placed by the ephemeris" % star[0], daz < 0.01 and absf(got.y - want.elevation_deg) < 0.01,
			"got %s want az %.3f el %.3f" % [got, want.azimuth_deg, want.elevation_deg])
	var polaris := _az_el(basis * Stars.equatorial(37.95, 89.264))
	_check("Polaris north at the latitude's height", absf(polaris.y - c.when.latitude_deg) < 1.0 and (polaris.x < 2.0 or polaris.x > 358.0), str(polaris))
	var vega := _az_el(basis * Stars.equatorial(279.234, 38.784))
	_check("Vega high on a June midnight at 40° N", vega.y > 60.0, str(vega))

	var blue := Stars.colour(-0.3)
	var red := Stars.colour(1.6)
	_check("hot star bluish, cool star reddish", blue.b > blue.r and red.r > red.b, "%s %s" % [blue, red])
	_check("colours normalised to a white peak", is_equal_approx(maxf(maxf(red.r, red.g), red.b), 1.0))

	var stars := Stars.placements(SkyState.state(sky), c.when.latitude_deg)
	_check("brightest star is Sirius", (stars[0].dir as Vector3).is_equal_approx(basis * Stars.equatorial(101.287, -16.716)), str(stars[0].dir))
	_check("Sirius flux 10^(0.4·1.46)", absf(stars[0].flux - pow(10.0, 0.584)) < 1e-6)
	_check("faintest kept star is V ≤ 6.0", stars[-1].flux >= pow(10.0, -2.4) - 1e-9)
	var field := Stars.build(SkyState.state(sky), c.when.latitude_deg)
	var mmi: MultiMeshInstance3D = field.get_node("StarField")
	_check("all 5,080 stars built in one MultiMesh", stars.size() == 5080 and mmi.multimesh.instance_count == 5080 and field.get_meta("stars") == 5080)
	_check("deterministic", str(Stars.placements(SkyState.state(sky), c.when.latitude_deg)[4000]) == str(stars[4000]))
	field.free()
	var seeded_classic := SkyConfig.defaults()
	seeded_classic.seed = 99
	_check("classic star mask accepts selected seed", Atmosphere.configure_appearance(seeded_classic))
	var seeded_stars := Stars.build(SkyState.state(sky), c.when.latitude_deg, Atmosphere.cloud_state_snapshot())
	var seeded_field := seeded_stars.get_node("StarField") as MultiMeshInstance3D
	var seeded_quad := seeded_field.multimesh.mesh as QuadMesh
	var seeded_material := seeded_quad.material as ShaderMaterial
	_check("classic star mask uses non-default seed", int(seeded_material.get_shader_parameter("cloud_seed")) == 99)
	seeded_stars.free()
	_check("classic default seed restores star mask", Atmosphere.configure_appearance(SkyConfig.defaults()))
	var default_stars := Stars.build(SkyState.state(sky), c.when.latitude_deg, Atmosphere.cloud_state_snapshot())
	var default_field := default_stars.get_node("StarField") as MultiMeshInstance3D
	var default_quad := default_field.multimesh.mesh as QuadMesh
	var default_material := default_quad.material as ShaderMaterial
	_check("classic star mask keeps calibrated seed 1253", int(default_material.get_shader_parameter("cloud_seed")) == 1253)
	default_stars.free()
	var electrical := SkyConfig.for_preset("electrical_storm")
	_check("electrical cloud appearance configures for star occlusion", Atmosphere.configure_appearance(electrical))
	var storm_stars := Stars.build(SkyState.state(sky), c.when.latitude_deg, Atmosphere.cloud_state_snapshot())
	var storm_field := storm_stars.get_node("StarField") as MultiMeshInstance3D
	var storm_quad := storm_field.multimesh.mesh as QuadMesh
	var storm_material := storm_quad.material as ShaderMaterial
	_check("electrical stars sample the layered cloud mask",
		bool(storm_material.get_shader_parameter("layered_appearance"))
		and int(storm_material.get_shader_parameter("appearance_layer_count")) == 3)
	var storm_parameters: PackedVector4Array = storm_material.get_shader_parameter("appearance_layer_parameters")
	_check("star cloud decks sort by physical altitude",
		storm_parameters[0].x < storm_parameters[1].x and storm_parameters[1].x < storm_parameters[2].x)
	var retained_environment := Environment.new()
	retained_environment.set_meta("fw_star_field", weakref(storm_stars))
	_check("clear appearance configures before refreshing retained stars", Atmosphere.configure_appearance(SkyConfig.for_preset("clear")))
	World.refresh_star_cloud_appearance(retained_environment)
	_check("paused preset refresh updates the retained star material",
		int(storm_material.get_shader_parameter("appearance_layer_count")) == 0
		and float(storm_material.get_shader_parameter("appearance_cloud_density")) == 0.0)
	storm_stars.free()
	_test_cached_catalogue()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _test_cached_catalogue() -> void:
	var data_path := "user://stars_cache_regression_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	if FileAccess.file_exists(data_path):
		_check("cache test refuses an existing user file", false, data_path)
		return
	var api := _star_cache_api(data_path)
	if api == null:
		return
	var state := {lst_deg = 137.25}
	var clouds := {profile_id = "classic", seed = 1253, offset = Vector2.ZERO}
	var first_text := _star_cache_text(101287)
	if not _star_cache_write(data_path, first_text):
		_check("owned JSON writes", false, data_path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
		return
	_check("owned JSON writes", true)
	var first_rows: Array = api.rows()
	var first: Array = api.placements(state, 4.7)
	var repeat: Array = api.placements(state, 4.7)
	_check("unchanged source repeats placements", first == repeat)
	var expected: Dictionary = first[0].duplicate(true)
	first[0].dir = Vector3.ZERO
	first[0].colour = Color.BLACK
	first[0].flux = -1.0
	first_rows[0][0] = -1
	var fresh_rows: Array = api.rows()
	var fresh: Array = api.placements(state, 4.7)
	_check("row mutation is detached", fresh_rows[0][0] == 101287)
	_check("placement and dictionary mutation are detached", fresh[0] == expected)
	_check("owned catalogue can be removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path)) == OK)
	var missing: Array = api.placements(state, 4.7)
	_check("missing catalogue never returns cached stars", missing.is_empty())
	if not _star_cache_write(data_path, first_text):
		_check("catalogue recovers after missing file", false)
		return
	_check("catalogue recovers after missing file", api.placements(state, 4.7)[0] == expected)
	var turned: Array = api.placements({lst_deg = 151.0}, 4.7)
	_check("basis still follows current sky state", turned[0].dir != expected.dir)
	var changed_text := _star_cache_text(101288)
	_check("same-length source fixture", changed_text.length() == first_text.length())
	if not _star_cache_write(data_path, changed_text):
		_check("same-length source rewrite", false)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
		return
	_check("same-length source rewrite", true)
	var changed_rows: Array = api.rows()
	var changed: Array = api.placements(state, 4.7)
	_check("public rows see same-length edit", changed_rows[0][0] == 101288)
	_check("content key refreshes prepared catalogue", changed[0].dir != expected.dir)
	var empty_text := JSON.stringify({"format": "openrc-stars v1", "rows": []})
	if not _star_cache_write(data_path, empty_text):
		_check("valid empty source writes", false)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
		return
	_check("valid empty source writes", true)
	var empty_rows: Array = api.rows()
	var empty: Array = api.placements(state, 4.7)
	var empty_tree: Node3D = api.build(state, 4.7, clouds) as Node3D
	_check("valid empty catalogue clears placements", empty_rows.is_empty() and empty.is_empty())
	_check("empty build has no stale star field", empty_tree.get_node_or_null("StarField") == null)
	if not _star_cache_write(data_path, changed_text):
		_check("catalogue recovers after empty source", false)
		empty_tree.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path))
		return
	_check("catalogue recovers after empty source", true)
	var recovered: Array = api.placements(state, 4.7)
	_check("recovered catalogue is current", recovered.size() == 1 and recovered[0].dir == changed[0].dir)
	var tree_a: Node3D = api.build(state, 4.7, clouds) as Node3D
	var tree_b: Node3D = api.build(state, 4.7, clouds) as Node3D
	var field_a := tree_a.get_node_or_null("StarField") as MultiMeshInstance3D
	var field_b := tree_b.get_node_or_null("StarField") as MultiMeshInstance3D
	_check("builds create independent trees", tree_a.get_instance_id() != tree_b.get_instance_id())
	if field_a != null and field_b != null:
		var quad_a := field_a.multimesh.mesh as QuadMesh
		var quad_b := field_b.multimesh.mesh as QuadMesh
		_check("builds own independent MultiMeshes", field_a.multimesh.get_instance_id() != field_b.multimesh.get_instance_id())
		_check("builds own independent meshes", quad_a.get_instance_id() != quad_b.get_instance_id())
		_check("builds own independent materials", quad_a.material.get_instance_id() != quad_b.material.get_instance_id())
	else:
		_check("both fresh builds contain a star field", false)
	empty_tree.free()
	tree_a.free()
	tree_b.free()
	_check("test removes only its owned JSON", DirAccess.remove_absolute(ProjectSettings.globalize_path(data_path)) == OK)


func _star_cache_text(ra_milli: int) -> String:
	return JSON.stringify({"format": "openrc-stars v1", "rows": [[ra_milli, -16716, 146, 65]]})


func _star_cache_write(path: String, source: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(source)
	file.close()
	return FileAccess.get_file_as_string(path) == source


func _star_cache_api(data_path: String) -> GDScript:
	var candidate_path := "res://render/world/stars.gd"
	var source := FileAccess.get_file_as_string(candidate_path)
	var old_path := 'const DATA_PATH := "res://data/sky/stars.json"'
	if source.is_empty() or not source.contains(old_path):
		_check("candidate source has expected data path", false, candidate_path)
		return null
	source = source.replace(old_path, 'const DATA_PATH := "' + data_path + '"')
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	_check("in-memory candidate parses", err == OK, error_string(err))
	return script if err == OK else null
