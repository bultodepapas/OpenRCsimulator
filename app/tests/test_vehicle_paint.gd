## Stock paints of the HX-700 and the RC cars (render/vehicle_paint.gd, data/vehicle_paints.json): every binding
## resolves, paint never mutates the shared imported materials, repainting stays one copy deep, the HX-700 carbon fix
## is always on, and the Monster Car 2 neon follows a painted colour.
extends SceneTree

const VehiclePaint := preload("res://render/vehicle_paint.gd")
const HX700 := preload("res://aircraft/hx700_model.gd")
const Articulated := preload("res://aircraft/hx700_articulated_model.gd")
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
	_check_inspection_layer()
	_check_suspension()
	_check_cars()
	_check_stik_cyberpunk()
	_check_stik_gear()
	_check_jet_livery()
	_check_sabre_livery()
	_check_stik_metal()
	_check_stik_blackbird()
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
				for field: String in ["albedo_texture", "emission_texture", "normal_texture", "roughness_texture", "metallic_texture"]:
					if group[material_name].has(field) and group[material_name][field] != null:  # null removes the map
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


func _check_stik_metal() -> void:
	var family := "jensen-das-ugly-stik-60"
	var ids := [family, "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "stik-glow-61fx-2t", "stik-electric-6s"]
	var previous := SceneDetail._preference
	var forced := not OS.get_environment("OPENRC_SCENE_DETAIL").is_empty()
	for argument: String in OS.get_cmdline_user_args():
		forced = forced or argument.begins_with("--scene_detail=")
	if not forced: SceneDetail.set_preference("medium")
	for id: String in ids:
		var offered := false
		for choice: Dictionary in AirplaneBuilder.livery_choices(id):
			offered = offered or choice.id == "silver_ace"
		check(id + " offers SILVER ACE", offered)
		var built: Dictionary = AirplaneBuilder.build(id, NAN, {}, "silver_ace")
		check(id + " builds SILVER ACE", not built.is_empty())
		if built.is_empty(): continue
		var finishes := _materials_named(built.root, "classic-covering-v4")
		check(id + " has a single shared metal finish per instance", finishes.size() == 1)
		if finishes.size() == 1:
			var finish: StandardMaterial3D = finishes[0]
			check(id + " binds metal and paint boundaries at full multiplier", finish.metallic == 1.0
				and finish.metallic_texture != null and finish.metallic_texture.resource_path.ends_with("silver_ace_metallic.png")
				and finish.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE)
			check(id + " keeps the metal finish nonemissive and UV-mapped", not finish.emission_enabled
				and not finish.clearcoat_enabled and not finish.uv1_triplanar)
			if VehiclePaint.detail_enabled():
				check(id + " uses rivet normals and varying raw-metal finish", finish.normal_enabled
					and finish.normal_texture.resource_path.ends_with("silver_ace_normal.png") and is_equal_approx(finish.normal_scale, 0.85)
					and finish.roughness_texture.resource_path.ends_with("silver_ace_roughness.png"))
			else:
				check(id + " omits replacement detail at forced Low", not finish.normal_enabled
					and finish.normal_texture == null and finish.roughness_texture == null)
		var gaps := _materials_named(built.root, "classic-covering-gap-v1")
		check(id + " keeps hinge slots dark and nonreflective", not gaps.is_empty()
			and gaps[0].albedo_texture.resource_path.ends_with("silver_ace_albedo.png")
			and gaps[0].albedo_color.get_luminance() < 0.11 and gaps[0].roughness == 1.0
			and gaps[0].metallic == 0.0 and not gaps[0].normal_enabled)
		var ventral := _materials_named(built.root, "skin:b00e28ff")
		check(id + " finishes the solid ventral fin in aluminium", not ventral.is_empty() and ventral[0].metallic == 1.0)
		built.root.free()
	# Repainting must reset to the immutable stock resource, including emission and normals.
	var plain: Dictionary = AirplaneBuilder.build(family)
	var factory: StandardMaterial3D = _materials_named(plain.root, "classic-covering-v4")[0]
	var stock_image := factory.albedo_texture
	var stock_normal := factory.normal_texture
	var fuselage := plain.root.get_node("fuselage") as MeshInstance3D
	var stock_mesh := fuselage.mesh
	VehiclePaint.apply(plain.root, family, "neon_ronin")
	VehiclePaint.apply(plain.root, family, "silver_ace")
	var metal: StandardMaterial3D = _materials_named(plain.root, "classic-covering-v4")[0]
	check("changing neon to metal removes emission without editing geometry", not metal.emission_enabled and fuselage.mesh == stock_mesh)
	VehiclePaint.apply(plain.root, family)
	check("factory film and its normals survive repainting", _materials_named(plain.root, "classic-covering-v4")[0] == factory
		and factory.albedo_texture == stock_image and factory.normal_texture == stock_normal and factory.metallic_texture == null)
	if not forced or not VehiclePaint.detail_enabled():
		if not forced: SceneDetail.set_preference("low")
		VehiclePaint.apply(plain.root, family, "silver_ace")
		var low: StandardMaterial3D = _materials_named(plain.root, "classic-covering-v4")[0]
		check("Low retains the metal/paint mask and skips replacement detail", low.metallic_texture != null
			and low.roughness_texture == null and low.normal_texture == null and not low.normal_enabled
			and is_equal_approx(low.roughness, VehiclePaint._detail_means()["res://assets/vehicle-paints/ugly-stik/silver_ace_roughness.png"]))
		VehiclePaint.apply(plain.root, family, "neon_ronin")
		check("Low neon still retains the stock film normals", _materials_named(plain.root, "classic-covering-v4")[0].normal_texture == stock_normal)
	plain.root.free()
	SceneDetail.set_preference(previous)
	var mask := Image.load_from_file("res://assets/vehicle-paints/ugly-stik/silver_ace_metallic.png")
	check("painted bands are dielectric while unpainted panels are metallic", mask.get_pixel(40, 40).r > 0.99
		and mask.get_pixel(250, 150).r < 0.01)


func _check_stik_blackbird() -> void:
	var ids := ["jensen-das-ugly-stik-60", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "stik-glow-61fx-2t", "stik-electric-6s"]
	for id: String in ids:
		check(id + " resolves BLACKBIRD", AirplaneBuilder.resolve_livery(id, "blackbird") == "blackbird")
		var built: Dictionary = AirplaneBuilder.build(id, NAN, {}, "blackbird")
		check(id + " builds BLACKBIRD", not built.is_empty())
		if built.is_empty(): continue
		var finishes := _materials_named(built.root, "classic-covering-v4")
		check(id + " has one thermal coating finish", finishes.size() == 1)
		if finishes.size() == 1:
			var finish: StandardMaterial3D = finishes[0]
			check(id + " uses its own charcoal coating and exposure mask", finish.albedo_texture.resource_path.ends_with("blackbird_albedo.png")
				and finish.metallic_texture != null and finish.metallic_texture.resource_path.ends_with("blackbird_metallic.png"))
			check(id + " has no glow or lacquer", not finish.emission_enabled and not finish.clearcoat_enabled)
			if VehiclePaint.detail_enabled():
				check(id + " uses thermal panel normals and coating roughness", finish.normal_enabled
					and finish.normal_texture.resource_path.ends_with("blackbird_normal.png")
					and finish.roughness_texture.resource_path.ends_with("blackbird_roughness.png"))
		var ventral := _materials_named(built.root, "skin:b00e28ff")
		check(id + " keeps the ventral fin charcoal and matte", not ventral.is_empty()
			and ventral[0].albedo_color.is_equal_approx(Color("202226")) and ventral[0].metallic == 0.0)
		# Repaint after neon to catch inherited glow or stale maps on an existing instance.
		VehiclePaint.apply(built.root, id, "neon_ronin")
		VehiclePaint.apply(built.root, id, "blackbird")
		check(id + " removes neon emission when repainted BLACKBIRD", not _materials_named(built.root, "classic-covering-v4")[0].emission_enabled)
		built.root.free()
	var mask := Image.load_from_file("res://assets/vehicle-paints/ugly-stik/blackbird_metallic.png")
	check("BLACKBIRD coating is dielectric over the panels", mask.get_pixel(40, 40).r < 0.01
		and mask.get_pixel(600, 100).r < 0.01)
	var previous := SceneDetail._preference
	var forced := not OS.get_environment("OPENRC_SCENE_DETAIL").is_empty()
	for argument: String in OS.get_cmdline_user_args():
		forced = forced or argument.begins_with("--scene_detail=")
	if not forced: SceneDetail.set_preference("low")
	if not VehiclePaint.detail_enabled():
		var built: Dictionary = AirplaneBuilder.build(ids[0], NAN, {}, "blackbird")
		var sample: StandardMaterial3D = _materials_named(built.root, "classic-covering-v4")[0]
		check("Low BLACKBIRD omits panel detail and retains coating identity", sample.roughness_texture == null
			and sample.normal_texture == null and not sample.normal_enabled and sample.metallic_texture != null
			and is_equal_approx(sample.roughness, VehiclePaint._detail_means()["res://assets/vehicle-paints/ugly-stik/blackbird_roughness.png"]))
		built.root.free()
	SceneDetail.set_preference(previous)


func _check_stik_cyberpunk() -> void:
	var ids := ["jensen-das-ugly-stik-60", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "stik-glow-61fx-2t", "stik-electric-6s"]
	for id: String in ids:
		var offered := false
		for choice: Dictionary in AirplaneBuilder.livery_choices(id):
			offered = offered or choice.id == "neon_ronin"
		check(id + " offers NEON RONIN", offered)
		var plain: Dictionary = AirplaneBuilder.build(id)
		var painted: Dictionary = AirplaneBuilder.build(id, NAN, {}, "neon_ronin")
		check(id + " builds both paints", not plain.is_empty() and not painted.is_empty())
		if plain.is_empty() or painted.is_empty():
			if not plain.is_empty(): plain.root.free()
			if not painted.is_empty(): painted.root.free()
			continue
		var original := _materials_named(plain.root, "classic-covering-v4")
		var finish := _materials_named(painted.root, "classic-covering-v4")
		check(id + " applies the actual atlas to instance-owned film", original.size() == 1 and finish.size() == 1
			and finish[0] != original[0] and finish[0].albedo_texture != original[0].albedo_texture
			and finish[0].albedo_texture.resource_path.ends_with("neon_ronin_albedo.png"))
		if original.size() == 1 and finish.size() == 1:
			check(id + " preserves film normals with selective luminous traces", finish[0].normal_texture == original[0].normal_texture
				and finish[0].normal_scale == original[0].normal_scale and finish[0].emission_enabled
				and finish[0].emission_operator == BaseMaterial3D.EMISSION_OP_ADD and finish[0].emission == Color.BLACK
				and finish[0].emission_texture.resource_path.ends_with("neon_ronin_emission.png"))
			check(id + " keeps factory paint unmodified", not original[0].emission_enabled
				and not original[0].has_meta(VehiclePaint.ORIGIN_META))
		for mesh: MeshInstance3D in plain.root.find_children("*", "MeshInstance3D", true, false):
			# Anonymous Godot node names contain a process-wide counter. Pair by
			# hierarchy position and check authored names separately.
			var route: Array[int] = []
			var ancestor: Node = mesh
			while ancestor != plain.root:
				route.push_front(ancestor.get_index())
				ancestor = ancestor.get_parent()
			var paired: Node = painted.root
			for child_index in route:
				paired = paired.get_child(child_index) if paired != null and child_index < paired.get_child_count() else null
			var other := paired as MeshInstance3D
			check(id + " retains mesh and hinge paths: " + str(mesh.name), other != null
				and (str(mesh.name).begins_with("@") or other.name == mesh.name)
				and other.transform == mesh.transform and other.mesh.get_surface_count() == mesh.mesh.get_surface_count())
			if other == null: continue
			for surface in mesh.mesh.get_surface_count():
				check(id + " retains paint geometry: " + str(mesh.name), other.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					== mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
		var gaps := _materials_named(painted.root, "classic-covering-gap-v1")
		var ventral := _materials_named(painted.root, "skin:b00e28ff")
		check(id + " recolours the solid ventral fin", not ventral.is_empty()
			and ventral[0].albedo_color.is_equal_approx(Color("16e5f4")))
		check(id + " hinge slots use the matching dark atlas", not gaps.is_empty()
			and gaps[0].albedo_texture.resource_path.ends_with("neon_ronin_albedo.png")
			and gaps[0].albedo_color.get_luminance() < 0.11 and not gaps[0].emission_enabled)
		plain.root.free()
		painted.root.free()


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


func _node_material(root: Node, node_name: String, material_name: String) -> StandardMaterial3D:
	var node := root.find_child(node_name, true, false) as MeshInstance3D
	if node == null:
		return null
	for surface in node.mesh.get_surface_count():
		var active := node.get_active_material(surface) as StandardMaterial3D
		if active != null and active.resource_name == material_name:
			return active
	return null


func _check_inspection_layer() -> void:
	var preview: Dictionary = Articulated.load_preview()
	check("the articulated HX-700 loads with its paint", preview.ok)
	if not preview.ok:
		return
	var root_node: Node3D = preview.root
	var fixed_real := _node_material(root_node, "Plato_Exterior", "Aluminio_Anodizado_Azul")
	var link_real := _node_material(root_node, "Bieleta_Cabeza_A_Terminal_Plato", "Plastico_Negro")
	var servo_link_real := _node_material(root_node, "Varilla_Servo_Trasera_Terminal_Plato", "Plastico_Negro")
	check("real finish: every ball link shares one black nylon copy", link_real != null and link_real == servo_link_real)
	VehiclePaint.apply(root_node, "hx-700", "", ["inspection"])
	var fixed := _node_material(root_node, "Plato_Exterior", "Aluminio_Anodizado_Azul")
	var rotating := _node_material(root_node, "Plato_Interior", "Aluminio_Grafito")
	var pitch_link := _node_material(root_node, "Bieleta_Cabeza_A_Terminal_Plato", "Plastico_Negro")
	var servo_link := _node_material(root_node, "Varilla_Servo_Trasera_Terminal_Plato", "Plastico_Negro")
	var servo_arm := _node_material(root_node, "Brazo_Servo_Trasero", "Aluminio_Anodizado_Negro")
	var screws := _node_material(root_node, "Brazo_Servo_Trasero", "Acero_Hueco_Hexagonal")
	check("inspection code: fixed swashplate red, rotating swashplate blue", fixed != null and rotating != null
		and fixed.albedo_color.r > 0.6 and fixed.albedo_color.b < 0.3 and rotating.albedo_color.b > 0.8 and rotating.albedo_color.r < 0.3)
	check("inspection code: pitch links and servo links differ, servo arms orange", pitch_link != null and servo_link != null
		and servo_arm != null and pitch_link != servo_link and pitch_link.albedo_color.g > 0.6 and servo_arm.albedo_color.r > 0.9)
	check("inspection code keeps real hardware: screws stay black oxide", screws != null and screws.albedo_color.get_luminance() < 0.2)
	check("inspection code keeps the brushed-metal detail of the anodised parts", fixed != null
		and (fixed.roughness_texture != null or not VehiclePaint.detail_enabled()))
	VehiclePaint.apply(root_node, "hx-700")
	var fixed_off := _node_material(root_node, "Plato_Exterior", "Aluminio_Anodizado_Azul")
	var link_off := _node_material(root_node, "Bieleta_Cabeza_A_Terminal_Plato", "Plastico_Negro")
	check("switching the code off restores the real finish", fixed_off != null and link_off != null
		and fixed_off.albedo_color.is_equal_approx(fixed_real.albedo_color) and link_off.albedo_color.is_equal_approx(link_real.albedo_color))
	# A layer on a material the base leaves alone: switching it off must return the imported material itself.
	var layers: Dictionary = VehiclePaint._vehicles()["hx-700"]["layers"]
	layers["test_only"] = {"materials": {"Nylon_Tuerca": {"albedo": "#ff00ff"}}}
	var grip := root_node.find_child("Portapalas_A", true, false) as MeshInstance3D
	var nut_surface := -1
	for surface in grip.mesh.get_surface_count():
		if grip.mesh.surface_get_material(surface).resource_name == "Nylon_Tuerca":
			nut_surface = surface
	VehiclePaint.apply(root_node, "hx-700", "", ["test_only"])
	var painted_nut := grip.get_surface_override_material(nut_surface) if nut_surface >= 0 else null
	VehiclePaint.apply(root_node, "hx-700")
	check("a switched-off layer returns untouched surfaces to their imported material", nut_surface >= 0
		and painted_nut != null and grip.get_surface_override_material(nut_surface) == null)
	layers.erase("test_only")
	root_node.free()


func _check_suspension() -> void:
	var plain: Dictionary = Mt8Model.build()
	var shaft := _node_material(plain.root, "FL_ShockA_Shaft", "MT8_Chrome")
	var body := _node_material(plain.root, "FL_ShockA_Body", "MT8_Alu_Teal")
	var chassis := _node_material(plain.root, "Chassis", "MT8_Alu_Teal")
	var spring := _node_material(plain.root, "FL_ShockA_Spring", "MT8_Spring_Yellow")
	var arm := _node_material(plain.root, "FL_ArmLower", "MT8_Plastic_Black")
	check("MT8 shock shafts are TiN gold", shaft != null and shaft.albedo_color.r > 0.75 and shaft.albedo_color.b < 0.55 and shaft.metallic > 0.9)
	check("MT8 shock bodies are machined apart from the teal chassis", body != null and chassis != null and body != chassis
		and body.albedo_color.get_luminance() > chassis.albedo_color.get_luminance() + 0.2)
	check("MT8 springs are powder-coated and keep their colour", spring != null and spring.clearcoat_enabled
		and spring.albedo_color.r > 0.8 and spring.albedo_color.b < 0.3)
	check("MT8 arms are glass-filled nylon, not chassis black", arm != null and arm.roughness > 0.55
		and arm != _node_material(plain.root, "Chassis", "MT8_Plastic_Black"))
	plain.root.free()
	var glacier: Dictionary = Mt8Model.build("azul_glaciar")
	var caps := _node_material(glacier.root, "FL_ShockA_Body", "MT8_Alu_Raw")
	var glacier_spring := _node_material(glacier.root, "FL_ShockA_Spring", "MT8_Spring_Yellow")
	check("an MT8 skin brings its own shock caps and spring colour, keeping the coating", caps != null and glacier_spring != null
		and caps.albedo_color.b > 0.7 and glacier_spring.albedo_color.get_luminance() > 0.9 and glacier_spring.clearcoat_enabled)
	glacier.root.free()
	var monster: Dictionary = MonsterCar2Model.build()
	var rod := _node_material(monster.root, "Amort_Del_Izq_Vastago_Malla", "Cromo")
	var exhaust := _node_material(monster.root, "Escape_Sintonizado", "Cromo")
	var stop := _node_material(monster.root, "Amort_Del_Izq_Tope", "Uretano_Tope")
	check("Monster Car 2 shock rods are TiN gold while the exhaust stays chrome", rod != null and exhaust != null
		and rod.albedo_color.b < 0.55 and exhaust.albedo_color.b > 0.8)
	check("Monster Car 2 bump stops are red urethane", stop != null and stop.albedo_color.r > 0.5 and stop.albedo_color.g < 0.25)
	monster.root.free()


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


func _check_stik_gear() -> void:
	for stik_id: String in ["jensen-das-ugly-stik-60", "stik-electric-6s"]:
		var stik: Dictionary = AirplaneBuilder.build(stik_id)
		if stik.is_empty():
			check("%s builds" % stik_id, false)
			continue
		var tyre := _node_material(stik.root, "gear_left", "rubber:202124ff")
		var hub := _node_material(stik.root, "gear_left", "aluminum:858d91ff")
		var strap := _node_material(stik.root, "main_gear_structure", "aluminum:a3aaadff")
		var wire := _node_material(stik.root, "nose_gear_strut", "steel:c0c3c3ff")
		check("%s tyres are anthracite rubber, not pure black" % stik_id, tyre != null
			and tyre.albedo_color.get_luminance() > 0.1 and tyre.roughness > 0.8)
		check("%s hubs are brushed aluminium apart from the engine case" % stik_id, hub != null
			and hub.albedo_color.get_luminance() > 0.6 and hub.has_meta(VehiclePaint.ORIGIN_META))
		check("%s gear strap and piano-wire nose leg have their own finishes" % stik_id, strap != null and wire != null
			and strap.metallic > 0.85 and wire.albedo_color.get_luminance() < 0.7)
		stik.root.free()


func _check_jet_livery() -> void:
	var jet_id := "sebart-avanti-s-a200-p100rx"
	var choices: Array = AirplaneBuilder.livery_choices(jet_id)
	var ids: Array = choices.map(func(choice: Dictionary) -> String: return str(choice.id))
	check("the jet lists its delivered paint first, then Verde Neón Carbono", ids.size() >= 2 and ids[0] == ""
		and ids.has("verde_neon_carbono"), str(ids))
	check("the jet livery resolves; a stale id is the default", AirplaneBuilder.resolve_livery(jet_id, "verde_neon_carbono") == "verde_neon_carbono"
		and AirplaneBuilder.resolve_livery(jet_id, "retired") == "")
	var jet: Dictionary = AirplaneBuilder.build(jet_id, NAN, {}, "verde_neon_carbono")
	check("the jet builds with Verde Neón Carbono", not jet.is_empty())
	if jet.is_empty():
		return
	var fuselage := _materials_named(jet.root, "paint_fuselage")
	var doors := _materials_named(jet.root, "paint_doors_ala")
	var canopy := _materials_named(jet.root, "canopy_glass")
	check("the livery replaces the paint and its glow maps", fuselage.size() == 1
		and fuselage[0].albedo_texture.resource_path.contains("verde_neon_carbono_fuselage")
		and fuselage[0].emission_texture.resource_path.contains("verde_neon_carbono_fuselage_emission") and fuselage[0].clearcoat_enabled)
	check("the wing doors get their own texture (the stock doors overlap the wing's leading edge)", doors.size() == 1
		and doors[0].albedo_texture.resource_path.contains("verde_neon_carbono_doors"))
	check("the canopy is F-22-style reflective gold, mostly opaque but not solid", canopy.size() == 1
		and canopy[0].albedo_color.r > canopy[0].albedo_color.b + 0.3 and canopy[0].metallic > 0.8
		and canopy[0].albedo_color.a < 0.95 and canopy[0].transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	var tub := _materials_named(jet.root, "cockpit_tub_grey")
	check("the cockpit behind the gold canopy is dark and neutral", tub.size() >= 1 and tub[0].albedo_color.get_luminance() < 0.2)
	jet.root.free()
	var plain: Dictionary = AirplaneBuilder.build(jet_id)
	var stock := _materials_named(plain.root, "paint_fuselage")
	check("the delivered jet paint is untouched without the livery", stock.size() == 1
		and not stock[0].albedo_texture.resource_path.contains("vehicle-paints"))
	plain.root.free()


func _check_sabre_livery() -> void:
	var jet_id := "sebart-avanti-s-a200-p100rx"
	var ids: Array = AirplaneBuilder.livery_choices(jet_id).map(func(choice: Dictionary) -> String: return str(choice.id))
	check("the jet lists Sabre Plata", ids.has("sabre_plata") and ids[0] == "", str(ids))
	var jet: Dictionary = AirplaneBuilder.build(jet_id, NAN, {}, "sabre_plata")
	check("the jet builds with Sabre Plata", not jet.is_empty())
	if jet.is_empty():
		return
	var detail := VehiclePaint.detail_enabled()
	for part: String in ["fuselage", "wing", "doors", "stab", "fin"]:
		var material_name := "paint_doors_ala" if part == "doors" else "paint_" + part
		var finish := _materials_named(jet.root, material_name)
		check("Sabre Plata %s: natural-metal maps, metal/paint mask and no stock glow" % part, finish.size() == 1
			and finish[0].albedo_texture.resource_path.ends_with("sabre_plata_%s.jpg" % part)
			and finish[0].metallic_texture != null and finish[0].metallic_texture.resource_path.ends_with("sabre_plata_%s_metallic.png" % part)
			and finish[0].metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
			and not finish[0].emission_enabled and finish[0].emission_texture == null
			and (finish[0].normal_texture != null) == detail and (finish[0].roughness_texture != null) == detail)
	var trim := _materials_named(jet.root, "paint_trim_carbono")
	check("a null albedo texture drops the stock carbon pattern for plain metal", trim.size() >= 1
		and trim[0].albedo_texture == null and trim[0].metallic > 0.4 and not trim[0].emission_enabled)
	var canopy := _materials_named(jet.root, "canopy_glass")
	check("the Sabre canopy is clear glass", canopy.size() == 1 and canopy[0].metallic < 0.1
		and canopy[0].albedo_color.a < 0.5)
	jet.root.free()
	var plain: Dictionary = AirplaneBuilder.build(jet_id)
	var stock_trim := _materials_named(plain.root, "paint_trim_carbono")
	check("the delivered carbon trim keeps its texture without the livery", stock_trim.size() >= 1
		and stock_trim[0].albedo_texture != null and stock_trim[0].emission_enabled)
	plain.root.free()
