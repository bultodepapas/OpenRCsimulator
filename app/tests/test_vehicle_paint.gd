## Stock paints of the HX-700 and the RC cars (render/vehicle_paint.gd, data/vehicle_paints.json): every binding
## resolves, paint never mutates the shared imported materials, repainting stays one copy deep, the HX-700 carbon fix
## is always on, and the Monster Car 2 neon follows a painted colour.
extends SceneTree

const VehiclePaint := preload("res://render/vehicle_paint.gd")
const HX700 := preload("res://aircraft/hx700_model.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Mt8Model := preload("res://vehicles/ground/mt8_model.gd")
const MonsterCar2Model := preload("res://vehicles/ground/monster_car_2_model.gd")
const MonsterCar2Lights := preload("res://vehicles/ground/monster_car_2_lights.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const HELI := "xcell-60-research"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s %s" % [label, detail])


func _run() -> void:
	_check_data()
	_check_helicopter()
	_check_cars()
	print("Vehicle paint: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VehiclePaint.DATA_PATH))
	check("the paint registry parses", parsed is Dictionary and parsed.get("format") == VehiclePaint.FORMAT)
	for family: String in parsed.vehicles:
		var entry: Dictionary = parsed.vehicles[family]
		var ids := {}
		for skin: Dictionary in entry.skins:
			check("%s skin id is a valid livery key: %s" % [family, skin.id], preload("res://aircraft/model_manifest.gd").is_livery_id(skin.id))
			check("%s skin id is unique: %s" % [family, skin.id], not ids.has(skin.id))
			ids[skin.id] = true
		var groups: Array = [entry.base]
		for skin: Dictionary in entry.skins:
			groups.append(skin.materials)
		for group: Dictionary in groups:
			for material_name: String in group:
				for field: String in ["albedo_texture", "emission_texture"]:
					if group[material_name].has(field):
						check("texture exists: " + str(group[material_name][field]), ResourceLoader.exists(str(group[material_name][field])))
	check("unknown vehicles and skins fall back", VehiclePaint.choices("ugly-stik-60").is_empty()
		and VehiclePaint.resolve("mt8-bisonte", "nope") == "" and not VehiclePaint.contains("mt8-bisonte", "nope"))


func _materials_named(root: Node, material_name: String) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var active := mesh.get_active_material(surface) as StandardMaterial3D
			if active != null and active.resource_name == material_name and not out.has(active):
				out.append(active)
	return out


func _shared_material(root: Node, material_name: String) -> StandardMaterial3D:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var shared := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if shared != null and shared.resource_name == material_name:
				return shared
	return null


func _check_helicopter() -> void:
	var plain: Dictionary = HX700.build()
	var carbon := _materials_named(plain.root, "Fibra_de_Carbono")
	var shared := _shared_material(plain.root, "Fibra_de_Carbono")
	check("the HX-700 carbon fibre is restored on every build", carbon.size() == 1 and carbon[0].albedo_texture != null
		and carbon[0].albedo_texture.resource_path.contains("carbon_twill") and carbon[0].uv1_triplanar)
	check("carbon detail maps are drawn above Low scene detail", carbon.size() == 1 and carbon[0].normal_enabled
		and carbon[0].normal_texture != null and carbon[0].roughness_texture != null
		and carbon[0].texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
	var blade := _materials_named(plain.root, "Pala_Carbono")
	check("blades stay dark so the rotor blur keeps a carbon colour", blade.size() == 1
		and blade[0].albedo_color.get_luminance() < 0.3 and blade[0].clearcoat_enabled)
	check("the shared imported carbon material is untouched", shared != null and shared.albedo_texture == null
		and shared.albedo_color.is_equal_approx(Color.WHITE))
	var factory_canopy := _materials_named(plain.root, "Pintura_Carenado")
	check("the Original canopy keeps the author's roughness mask", factory_canopy.size() == 1
		and factory_canopy[0].roughness_texture != null and not factory_canopy[0].has_meta(VehiclePaint.ORIGIN_META))
	plain.root.free()
	# --scene_detail / OPENRC_SCENE_DETAIL outrank the saved preference; only force Low when neither is set.
	var forced: bool = OS.get_environment("OPENRC_SCENE_DETAIL") != ""
	for argument: String in OS.get_cmdline_user_args():
		forced = forced or argument.begins_with("--scene_detail=")
	if not forced:
		var previous: String = SceneDetail._preference
		SceneDetail.set_preference("low")
		var modest: Dictionary = HX700.build()
		var modest_carbon := _materials_named(modest.root, "Fibra_de_Carbono")
		var modest_blade := _materials_named(modest.root, "Pala_Carbono")
		check("Low scene detail skips the detail maps but keeps the carbon colour", modest_carbon.size() == 1
			and modest_carbon[0].normal_texture == null and modest_carbon[0].roughness_texture == null
			and modest_carbon[0].albedo_texture != null)
		check("Low keeps the sheen: blades use multiplier x map mean, without triplanar", modest_blade.size() == 1
			and modest_blade[0].roughness < 0.3 and not modest_blade[0].uv1_triplanar, str(modest_blade[0].roughness if modest_blade.size() == 1 else -1.0))
		modest.root.free()
		SceneDetail.set_preference(previous)
	var choices: Array = VehiclePaint.choices(HELI)
	var painted: Dictionary = AirplaneBuilder.build(HELI, NAN, {}, str(choices[1].id))
	check("a stock HX-700 paint builds through AirplaneBuilder", not painted.is_empty()
		and str(painted.root.get_meta("vehicle_paint", "")) == str(choices[1].id))
	if painted.is_empty():
		return
	var canopy := _materials_named(painted.root, "Pintura_Carenado")
	var blades := _materials_named(painted.root, "Pala_Carbono")
	check("the canopy carries the skin texture", canopy.size() == 1 and canopy[0].albedo_texture != null
		and canopy[0].albedo_texture.resource_path.contains("vehicle-paints"))
	check("repainting stays one copy deep", blades.size() == 1
		and not (blades[0].get_meta(VehiclePaint.ORIGIN_META) as Material).has_meta(VehiclePaint.ORIGIN_META))
	painted.root.free()
	check("a stale HX-700 paint resolves to the default", AirplaneBuilder.resolve_livery(HELI, "nope") == "")


func _check_cars() -> void:
	for skin: Dictionary in VehiclePaint.choices("mt8-bisonte"):
		var built: Dictionary = Mt8Model.build(str(skin.id))
		check("MT8 builds with paint %s" % skin.id, built.ok and built.skin == str(skin.id))
		if built.ok:
			built.root.free()
	var green: Dictionary = MonsterCar2Model.build()
	var blue_id := str(VehiclePaint.choices("monster-car-2")[1].id)
	var blue: Dictionary = MonsterCar2Model.build(blue_id)
	check("Monster Car 2 builds with its default and a stock paint", green.ok and blue.ok and blue.skin == blue_id)
	if not green.ok or not blue.ok:
		return
	var livery := _materials_named(blue.root, "Pintura_Livery")
	check("the painted livery swaps the colour and emission maps", livery.size() == 1
		and livery[0].albedo_texture.resource_path.contains("vehicle-paints")
		and livery[0].emission_texture.resource_path.contains("vehicle-paints"))
	root.add_child(green.root) # the lights place their spots from global transforms
	root.add_child(blue.root)
	var lights_green := MonsterCar2Lights.new()
	var lights_blue := MonsterCar2Lights.new()
	check("both cars prepare their lights", lights_green.prepare(green) and lights_blue.prepare(blue))
	var wash_green: SpotLight3D = lights_green.get("_underglow")
	var wash_blue: SpotLight3D = lights_blue.get("_underglow")
	check("the default neon keeps its authored green", wash_green.light_color.is_equal_approx(MonsterCar2Lights.NEON))
	check("a painted neon recolours the ground wash", not wash_blue.light_color.is_equal_approx(MonsterCar2Lights.NEON)
		and wash_blue.light_color.b > wash_blue.light_color.g)
	green.root.free()
	blue.root.free()
