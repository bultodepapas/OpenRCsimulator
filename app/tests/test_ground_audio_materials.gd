extends SceneTree
const Model := preload("res://audio/ground_audio_model.gd")
const EnvironmentModel := preload("res://sim/environment.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const Session := preload("res://sim/flight_session.gd")
const Lake := preload("res://data/lake_loader.gd")
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func field() -> Dictionary:
	return {"id": "material-test", "surfaces": [
		{"id": "runway", "type": "runway", "center_north": 0.0, "center_east": 0.0,
			"width_north_south": 8.0, "length_east_west": 20.0},
		{"id": "mown", "type": "mown", "center_north": 0.0, "center_east": 0.0,
			"width_north_south": 30.0, "length_east_west": 30.0}]}

func _initialize() -> void:
	var table := Surfaces.load_table()
	var built := Surfaces.build(table.table, field())
	var env := EnvironmentModel.new()
	env.surfaces = built.rects
	check("real registry installs", env.install_ground_registry(built.regions))
	var zero := PackedFloat64Array([0, 0, 0])
	for entry: Array in [[0.0, "maintained_turf"], [11.0, "mown_grass"], [30.0, "long_grass"]]:
		var result := Model.surface_observation(env, PackedFloat64Array([0, entry[0], 0]), zero, 0.0)
		check("authored material " + str(entry[1]), result.material_id == entry[1]
			and result.surface == "grass" and result.material_resolved and not result.surface_audio_fallback)
	var flat := EnvironmentModel.new()
	var plain := Model.surface_observation(flat, zero, zero, 0.0)
	check("explicit historical flat fixture is pavement", plain.material_id == "dry_pavement"
		and plain.surface == "hard" and not plain.surface_audio_fallback)
	for entry: Array in [["asphalt", "hard"], ["concrete", "hard"], ["gravel", "gravel"], ["future_material", "hard"]]:
		var regions: Array = built.regions.duplicate(true)
		regions[0].material_id = entry[0]
		check("custom registry installs " + str(entry[0]), env.install_ground_registry(regions))
		var result := Model.surface_observation(env, zero, zero, 0.0)
		check("same runway usage follows material " + str(entry[0]), result.surface == entry[1]
			and result.material_id == entry[0] and result.material_resolved
			and result.surface_audio_fallback == (entry[0] == "future_material"))
	env.surfaces[4] += 0.01
	var stale := Model.surface_observation(env, zero, zero, 0.0)
	check("changed raw table cannot retain stale material", stale.material_id == "unspecified"
		and stale.surface_audio_fallback and not stale.material_resolved)
	var unavailable := Model.surface_observation(null, zero, zero, 0.0)
	check("missing provider has explicit safe fallback", unavailable.surface == "hard" and unavailable.surface_audio_fallback)
	env.road = func(_north: float, _east: float) -> Dictionary: return {}
	check("unsupported road does not fabricate grass", Model.surface_observation(env, zero, zero, 0.0).surface_audio_fallback)
	env.road = Callable()
	var lake := Lake.load_from(Lake.DEFAULT_PATH)
	check("lake fixture loads", lake.ok)
	if lake.ok:
		env.lake = lake.lake
		var bed := Model.surface_observation(env, PackedFloat64Array([110, 125, 0]), zero, 0.0)
		check("unmeasured lake bed cannot borrow field material", bed.material_id == "unspecified" and bed.surface_audio_fallback)
	var session := Session.new()
	session.input_enabled = false
	session.setup()
	var installed_field := field()
	for region: Dictionary in installed_field.surfaces:
		region.center_north = session.sim.state[0]
		region.center_east = session.sim.state[1]
	check("actual Session installs field", session.set_field(installed_field))
	var checkpoint := var_to_bytes(session.checkpoint())
	check("actual Session checkpoint available", not session.checkpoint().is_empty())
	var contacts := Model.snapshot_contacts(session, {"surfaces": []})
	check("actual contact snapshot contains wheels", not contacts.is_empty())
	check("field argument cannot override installed material", contacts.all(func(c: Dictionary) -> bool:
		return c.material_id == "maintained_turf" and c.surface == "grass" and not c.surface_audio_fallback))
	check("material queries preserve full Session checkpoint", var_to_bytes(session.checkpoint()) == checkpoint)
	session.free()
	print("Ground audio materials: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
