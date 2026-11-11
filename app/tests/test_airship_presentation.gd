## BL-19c: the RC blimp as a Workshop presentation family (paint, markings, lighting, preview).
extends SceneTree

const Catalog := preload("res://vehicles/airship/airship_catalog.gd")
const AirshipPresentation := preload("res://vehicles/airship/airship_presentation.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Lighting := preload("res://render/lighting/lighting_profile.gd")
const PreviewScript := preload("res://ui/workshop_preview.gd")

const REST := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const DAY := {"local_seconds": 12.0 * 3600.0, "sun_elevation_deg": 40.0}
const NIGHT := {"local_seconds": 21.0 * 3600.0, "sun_elevation_deg": -12.0}

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	_test_describe()
	_test_builds_and_paint()
	_test_expected_presentation()
	await _test_lighting()
	await _test_preview()
	print("airship presentation: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_describe() -> void:
	var described := AirshipPresentation.describe()
	_check("default describe validates", bool(described.ok) and described.skin_id == Catalog.DEFAULT_SKIN, str(described.get("errors")))
	if not described.ok:
		return
	var bindings: Dictionary = described.bindings
	_check("companion passes the shared customization validator",
		Customization.validate_bindings(bindings, Catalog.VISUAL_FAMILY, str(described.model_manifest_sha256)).ok)
	_check("slot hash agrees with the Workshop hash helper", Presentation.bindings_sha256(bindings) == described.slots_sha256)
	_check("no smoke outlets are offered", (bindings.smoke_slots as Array).is_empty())
	var again := AirshipPresentation.describe(Catalog.DEFAULT_SKIN)
	_check("model and slot identities are stable", again.model_manifest_sha256 == described.model_manifest_sha256
		and again.slots_sha256 == described.slots_sha256)
	var hashes := {}
	for skin: String in Catalog.SKIN_IDS:
		var each := AirshipPresentation.describe(skin)
		_check("describe validates skin " + skin, bool(each.ok), str(each.get("errors")))
		if each.ok:
			hashes[str(each.model_manifest_sha256)] = true
			var ids: Array = []
			for slot: Dictionary in each.bindings.paint_slots:
				ids.append(str(slot.id))
			_check("skin %s offers envelope, fins, rudders and gondola" % skin,
				ids.has("envelope") and ids.has("fins") and ids.has("rudders") and ids.has("gondola"), str(ids))
	_check("each skin has its own model identity", hashes.size() == Catalog.SKIN_IDS.size())
	_check("unknown skin is refused", not AirshipPresentation.describe("no-such-skin").ok)
	var anchors: Array = []
	for row: Dictionary in bindings.lighting_layout.anchors:
		anchors.append(str(row.id))
	for wanted: String in ["nav_left", "nav_right", "nav_tail", "strobe_left", "strobe_right", "strobe_dorsal", "strobe_ventral", "landing"]:
		_check("lighting anchor " + wanted, anchors.has(wanted))
	# GLB pins in the authored source copy the exporter's generated manifest.
	var manifest_path := ProjectSettings.globalize_path("res://").path_join("../assets/aircraft/rc-blimp-5m/source-manifest.json")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(AirshipPresentation.SOURCE_PATH))
	var pins_match := manifest is Dictionary and source is Dictionary
	if pins_match:
		for record: Dictionary in source.skins:
			pins_match = pins_match and str(record.asset.sha256) == str(manifest.skins[str(record.id)].glb.sha256)
	_check("GLB pins match the exporter manifest", pins_match)
	var profile := _painted_profile(bindings)
	var checked := Presentation.validate(profile, bindings)
	_check("painted profile validates through workshop/presentation.gd", bool(checked.ok) and bool(checked.available), str(checked.get("errors")))
	var record := Presentation.identity_record(checked.get("profile", {}), bindings)
	_check("identity record pins the blimp companion", not record.is_empty()
		and record.binding.visual_family == Catalog.VISUAL_FAMILY and record.binding.slots_sha256 == described.slots_sha256)


func _painted_profile(bindings: Dictionary) -> Dictionary:
	var profile := Presentation.defaults(bindings)
	var colors := ["#FF0000FF", "#00FF00FF", "#0000FFFF", "#FFFF00FF", "#FF00FFFF", "#00FFFFFF"]
	var index := 0
	for slot: Dictionary in bindings.paint_slots:
		profile.paint.append({"slot": str(slot.id), "color": colors[index % colors.size()], "pattern": "solid", "accent": "none"})
		index += 1
	profile.markings.append({"slot": "registration", "text": "OPENRC 1", "color": "#202020FF"})
	return profile


func _test_builds_and_paint() -> void:
	for skin: String in Catalog.SKIN_IDS:
		var built := AirplaneBuilder.build(Catalog.STOCK_ID, NAN, {}, "" if skin == Catalog.DEFAULT_SKIN else skin)
		_check("AirplaneBuilder builds skin " + skin, not built.is_empty() and built.get("root") is Node3D)
		if built.is_empty():
			continue
		var blimp: Node3D = built.root
		_check("builder dict carries the presentation identity (%s)" % skin, built.aircraft_id == Catalog.STOCK_ID
			and built.visual_family == Catalog.VISUAL_FAMILY and built.livery_id == skin
			and built.customization_slots_sha256 == built.customization_bindings.slots_sha256)
		_check("blimp publishes lighting metas (%s)" % skin, blimp.has_meta("lighting_layout") and blimp.has_meta("lighting_skin_bindings")
			and blimp.get_meta("aircraft_id") == Catalog.STOCK_ID and blimp.get_meta("airship_visual") != null)
		var checked := Presentation.validate(_painted_profile(built.customization_bindings), built.customization_bindings)
		var applied := Customization.apply(built, checked.get("profile", {}))
		_check("paint and markings apply (%s)" % skin, bool(applied.ok) and int(applied.get("marking_count", 0)) == 2, str(applied.get("errors")))
		var painted := true
		var index := 0
		for slot: Dictionary in built.customization_bindings.paint_slots:
			var expected := Color(["#FF0000FF", "#00FF00FF", "#0000FFFF", "#FFFF00FF", "#FF00FFFF", "#00FFFFFF"][index % 6])
			index += 1
			for target: Dictionary in slot.targets:
				var mesh := blimp.get_node(NodePath(str(target.node_path))) as MeshInstance3D
				var material := mesh.get_surface_override_material(int(target.surface)) as StandardMaterial3D
				painted = painted and material != null and material.albedo_color.is_equal_approx(expected)
		_check("every paint slot recolors its target surfaces (%s)" % skin, painted)
		var restored := Customization.apply(built, {})
		var envelope_mesh := blimp.get_node("Model/airship/airship_mesh") as MeshInstance3D
		var stock_target: Dictionary = built.customization_bindings.paint_slots.filter(func(slot: Dictionary) -> bool: return slot.id == "envelope")[0].targets[0]
		var stock := envelope_mesh.get_surface_override_material(int(stock_target.surface)) as StandardMaterial3D
		var source := envelope_mesh.mesh.surface_get_material(int(stock_target.surface)) as StandardMaterial3D
		_check("empty profile restores the stock finish (%s)" % skin, bool(restored.ok) and stock.albedo_color.is_equal_approx(source.albedo_color))
		blimp.free()
	_check("custom paint kits are refused", AirplaneBuilder.build(Catalog.STOCK_ID, NAN, {}, "custom:abc").is_empty())


func _test_expected_presentation() -> void:
	var described := AirshipPresentation.describe()
	var matching := AirplaneBuilder.build(Catalog.STOCK_ID, NAN, {"visual_family": Catalog.VISUAL_FAMILY,
		"model_manifest_sha256": described.model_manifest_sha256})
	_check("matching expected presentation builds", not matching.is_empty())
	if not matching.is_empty():
		matching.root.free()
	var stale := AirplaneBuilder.build(Catalog.STOCK_ID, NAN, {"visual_family": Catalog.VISUAL_FAMILY,
		"model_manifest_sha256": "0".repeat(64)})
	_check("stale expected presentation is refused", stale.is_empty())


func _test_lighting() -> void:
	var built := AirplaneBuilder.build(Catalog.STOCK_ID)
	var blimp: Node3D = built.root
	var stage := Node3D.new()
	get_root().add_child(stage)
	stage.add_child(blimp)
	await process_frame
	var visual: RefCounted = blimp.get_meta("airship_visual")
	var configured: Dictionary = visual.configure_lighting(Lighting.defaults(), {})
	visual.update_lighting(0.016, 1.0, DAY)
	_check("inherit lighting configures", bool(configured.ok), str(configured.get("errors")))
	_check("daylight inherit allocates no lights", blimp.get_node_or_null("NightKit") == null)
	visual.update_lighting(0.016, 2.0, NIGHT)
	var kit := blimp.get_node_or_null("NightKit") as Node3D
	_check("night fits the kit", kit != null and kit.visible and visual.light_state().active_mode == "all")
	if kit != null:
		var layout: Dictionary = blimp.get_meta("lighting_layout")
		var at_anchors := true
		for row: Dictionary in layout.anchors:
			var lamp_name := "landing_lamp" if row.id == "landing" else str(row.id)
			var lamp := kit.get_node_or_null(lamp_name) as Node3D
			var host := blimp.get_node(NodePath(str(row.node_path))) as Node3D
			var expected: Vector3 = (blimp.global_transform.affine_inverse() * host.global_transform) * Vector3(row.position_m[0], row.position_m[1], row.position_m[2])
			at_anchors = at_anchors and lamp != null and lamp.position.distance_to(expected) < 1e-4
		_check("every lamp sits at its authored anchor", at_anchors)
		_check("authored strips replace wing fitting", kit.get_node_or_null("strip_belly") != null and kit.get_node_or_null("strip_top_left") != null)
		var tail := kit.get_node("nav_tail") as Node3D
		var rest := tail.position
		var continuous := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.0, 0.0])
		visual.pose(PackedFloat64Array(REST), continuous, 0.016)
		var rudder := blimp.get_node("Model/airship/rudder_dorsal_hinge") as Node3D
		var followed: Vector3 = (blimp.global_transform.affine_inverse() * rudder.global_transform) * Vector3(0.0, 0.3345, -0.02)
		_check("tail light follows the deflected dorsal rudder", tail.position.distance_to(rest) > 0.002
			and tail.position.distance_to(followed) < 1e-4, "moved %.4f m" % tail.position.distance_to(rest))
		# Workshop virtual size: the activity scales visual.model; lamps and markings must follow it.
		visual.model.scale = Vector3.ONE * 1.5
		visual.pose(PackedFloat64Array(REST), continuous, 0.016)
		var nav := kit.get_node("nav_left") as Node3D
		_check("lamps follow the Workshop model scale", nav.position.distance_to(Vector3(-0.47757, 0.0, -1.2) * 1.5) < 1e-4, str(nav.position))
		var painted := Presentation.validate(_painted_profile(built.customization_bindings), built.customization_bindings)
		var marked: Dictionary = visual.apply_presentation(painted.get("profile", {}))
		var label := blimp.find_child("AircraftRegistration", true, false) as Label3D
		_check("visual.apply_presentation installs scaled markings", bool(marked.ok) and label != null
			and visual.model.is_ancestor_of(label), str(marked.get("errors")))
		visual.model.scale = Vector3.ONE
		_check("light selection OFF hides the kit", visual.set_light_mode("off") and not kit.visible)
	var rig_profile := Lighting.preset("classic_rc")
	configured = visual.configure_lighting(rig_profile, {"rig_parent": stage, "luminous_layers": 1 << 19})
	visual.update_lighting(0.016, 3.0, NIGHT)
	_check("preset lighting builds an RGB rig", bool(configured.ok) and stage.get_node_or_null("AirshipLightingRig") != null, str(configured.get("errors")))
	var rig := stage.get_node_or_null("AirshipLightingRig")
	if rig != null:
		var report: Dictionary = rig.capability_report()
		_check("rig reports live zones for the blimp", not (report.get("zones", []) as Array).is_empty(), str(report))
	visual.dispose_lighting()
	stage.queue_free()
	await process_frame
	# A preset on a fresh blimp reuses the authored compact kit (no whole-mesh fitting).
	var fresh := AirplaneBuilder.build(Catalog.STOCK_ID)
	var fresh_stage := Node3D.new()
	get_root().add_child(fresh_stage)
	fresh_stage.add_child(fresh.root)
	var fresh_visual: RefCounted = fresh.root.get_meta("airship_visual")
	var started := Time.get_ticks_usec()
	var fresh_result: Dictionary = fresh_visual.configure_lighting(Lighting.preset("classic_rc"), {"rig_parent": fresh_stage})
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	fresh_visual.update_lighting(0.016, 1.0, NIGHT)
	var fresh_kit := fresh.root.get_node_or_null("NightKit") as Node3D
	_check("preset on a fresh blimp builds its kit at the anchors", bool(fresh_result.ok) and fresh_kit != null
		and fresh_kit.get_node("strobe_dorsal").position.distance_to(Vector3(0.0, 0.505, -0.31)) < 1e-4, str(fresh_result.get("errors")))
	print("preset lighting configure: %.1f ms" % elapsed_ms)
	fresh_visual.dispose_lighting()
	fresh_stage.queue_free()
	await process_frame
	# Disabled lighting on a fresh blimp never fits lights.
	var dark := AirplaneBuilder.build(Catalog.STOCK_ID)
	var dark_stage := Node3D.new()
	get_root().add_child(dark_stage)
	dark_stage.add_child(dark.root)
	var dark_visual: RefCounted = dark.root.get_meta("airship_visual")
	var disabled := Lighting.defaults()
	disabled.selection = "disabled"
	var dark_result: Dictionary = dark_visual.configure_lighting(disabled, {"rig_parent": dark_stage})
	dark_visual.update_lighting(0.016, 1.0, NIGHT)
	_check("disabled lighting allocates no lights", bool(dark_result.ok) and dark.root.get_node_or_null("NightKit") == null, str(dark_result.get("errors")))
	# BL-19g: hosts that light the root themselves (the Workshop preview) get the fit-free authored kit, dark and once.
	var hook: Variant = dark.root.get_meta("prepare_light_kit") if dark.root.has_meta("prepare_light_kit") else null
	var prepared: Node3D = (hook as Callable).call() if hook is Callable else null
	var fitted_layout: Dictionary = prepared.get_meta("geometry_layout", {}) if prepared != null else {}
	_check("prepare_light_kit attaches a dark fit-free kit", prepared != null and not prepared.visible
		and (fitted_layout.get("belly", PackedVector3Array([Vector3.ONE])) as PackedVector3Array).is_empty()
		and prepared.get_node_or_null("nav_left") != null)
	_check("prepare_light_kit is idempotent", hook is Callable and (hook as Callable).call() == prepared
		and dark.root.find_children("NightKit", "", false, false).size() == 1)
	dark_visual.dispose_lighting()
	dark_stage.queue_free()
	await process_frame


func _test_preview() -> void:
	get_root().size = Vector2i(1280, 720)
	var preview := PreviewScript.new() as Control
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(preview)
	for _index in 3:
		await process_frame
	preview.set_aircraft(Catalog.STOCK_ID, 1.0)
	for _index in 3:
		await process_frame
	var model_root := preview.get("_airplane_root") as Node3D
	var bounds: AABB = preview.get("_model_bounds")
	_check("Workshop preview displays the blimp", is_instance_valid(model_root) and bounds.size.z > 4.9 and bounds.size.z < 5.4,
		str(bounds))
	_check("daylight inherit preview allocates no blimp lights", model_root.get_node_or_null("NightKit") == null)
	var described := AirshipPresentation.describe()
	var profile := _painted_profile(described.bindings)
	profile.lighting = Lighting.preset("classic_rc")
	var checked := Presentation.validate(profile, described.bindings)
	preview.set_presentation(checked.get("profile", {}))
	preview.set_preview_night(true)
	for _index in 3:
		await process_frame
	var report: Dictionary = preview.get_lighting_capability_report()
	_check("preview lighting is available for the blimp", str(report.get("state", "")) != "unavailable", str(report))
	# BL-19g: the preview lights the prepared fit-free kit (no whole-hull fit) and switches it on despite its dark start.
	var kit := model_root.get_node_or_null("NightKit") as Node3D
	var layout: Dictionary = kit.get_meta("geometry_layout", {}) if kit != null else {}
	_check("preview preset reuses the fit-free blimp kit, lit", kit != null and kit.visible and str(kit.get_meta("mode", "")) != "off"
		and (layout.get("belly", PackedVector3Array([Vector3.ONE])) as PackedVector3Array).is_empty(), str(kit.get_meta("mode", "")) if kit else "no kit")
	preview.queue_free()
	for _index in 2:
		await process_frame
