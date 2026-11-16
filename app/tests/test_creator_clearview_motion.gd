extends SceneTree
## AC-CV-03/04: known geometry, explicit mapping, real bound preview and manual selection.
const Motion := preload("res://workshop/creator/clearview/motion.gd")
const Ac3d := preload("res://workshop/creator/clearview/ac3d.gd")
const Params := preload("res://workshop/creator/clearview/params.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Parts := preload("res://workshop/creator/visual_parts.gd")
const Builder := preload("res://workshop/creator/visual_builder.gd")
const PanelParts := preload("res://ui/aircraft_creator_parts.gd")
const Fixture := preload("res://tests/test_creator_clearview_readers.gd")
const R := preload("res://workshop/creator/result.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")

class OptionalRigRefusal extends Converter:
	func _admit(label: String) -> Dictionary:
		if _gltf.nodes.size() > _scene.nodes.size():
			return R.fail(R.SOURCE_UNSUPPORTED,"Injected optional rig refusal.","source","import")
		return super._admit(label)
var checks := 0
var failures := 0

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ",label)

func _initialize() -> void:
	await process_frame
	_frames()
	await _conversion()
	print("ClearView motion: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _frames() -> void:
	var scene := Ac3d.read(_body().to_ascii_buffer())
	var params := Params.read(_params().to_ascii_buffer())
	check("asymmetric fixture parses", scene.ok and params.ok)
	if not scene.ok or not params.ok:
		return
	var result := Motion.inspect(scene.value,params.value)
	check("four-point frame recognized with nonzero origin and texture", result.ok and result.value.frames.size() == 1)
	if not result.ok:
		printerr(result)
		return
	var frame: Dictionary = result.value.frames[0]
	check("origin is a vertex, not loc or a fixed index", frame.origin_vertex == 1 and frame.origin == [0.4,0.5,0.6])
	check("axes use Y shortest, X middle, Z longest", frame.lengths == [2.0,1.0,3.0])
	# Parent is +90deg about Z, then marker +5deg about Y; loc and vertex both contribute.
	var expected_origin := Vector3(3.0,4.0,5.0) + Basis(Vector3.FORWARD,-PI/2.0) * (Vector3(0.1,0.2,0.3) + Basis(Vector3.UP,deg_to_rad(5.0))*Vector3(0.4,0.5,0.6))
	check("world origin composes all ancestors", _near(Vector3(frame.world_origin[0],frame.world_origin[1],frame.world_origin[2]),expected_origin))
	var permuted: Dictionary = scene.value.duplicate(true)
	var node: Dictionary = permuted.nodes[frame.node]
	var vertices: Array = node.vertices.duplicate(true)
	node.vertices = [vertices[1],vertices[3],vertices[0],vertices[2]]
	for surface: Dictionary in node.surfaces:
		for ref: Dictionary in surface.refs:
			ref.vertex = [2,0,3,1][ref.vertex]
	var reordered := Motion.inspect(permuted,params.value)
	check("vertex order cannot change frame semantics", reordered.ok and reordered.value.frames[0].origin_vertex == 0 and reordered.value.frames[0].axes == frame.axes)
	for change: String in ["equal","skew","mirror","children","data","flags"]:
		var broken: Dictionary = scene.value.duplicate(true)
		var marker: Dictionary = broken.nodes[frame.node]
		match change:
			"equal": marker.vertices[3] = [1.4,0.5,0.6]
			"skew": marker.vertices[3] = [2.4,0.6,0.6]
			"mirror": marker.vertices[2] = [0.4,0.5,-2.4]
			"children": marker.children = [2]
			"data": marker.has_data = true
			"flags": marker.surfaces[0].flags = 0x20
		check("reserved ambiguous marker refused: " + change,not Motion.inspect(broken,params.value).ok)
	var almost: Dictionary = scene.value.duplicate(true)
	almost.nodes[frame.node].vertices[3][1] += 0.0008
	check("rounded near-orthogonal frame tolerated", Motion.inspect(almost,params.value).ok)
	for name: String in [".XYZObject",".Control.XYZObject","Control..XYZObject","Control..Part.XYZObject"]:
		var unnamed: Dictionary = scene.value.duplicate(true)
		unnamed.nodes[frame.node].name = name
		check("coordinate marker needs a qualified nonempty group",not Motion.inspect(unnamed,params.value).ok)
	var exact: Variant = Motion.exact(frame.original)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(exact))
	var decoded := PackedByteArray()
	decoded = str(roundtrip.vertices[0][0].f64le).hex_decode()
	check("source coordinate bits survive JSON", decoded.decode_double(0) == float(frame.original.vertices[0][0]))
	check("frame scan is cancellable", not Motion.inspect(scene.value,params.value,func() -> bool: return true).ok)
	var gltf := _scene_graph(scene.value)
	var before := gltf.duplicate(true)
	var broken: Dictionary = result.value.duplicate(true)
	broken.world[4][3] += 1.0 # last child fails the independently retained neutral-pose contract
	var rejected := Motion.prepare(gltf,scene.value,broken)
	check("last-child mismatch leaves all graph nodes untouched",rejected.ok and rejected.value.prepared.is_empty() and gltf == before)
	gltf = _scene_graph(scene.value)
	while gltf.nodes.size() < 512:
		gltf.nodes.append({name = "unused"})
	var limited := Motion.prepare(gltf,scene.value,result.value)
	check("wrapper node budget leaves the model static",limited.ok and limited.value.prepared.is_empty() and limited.value.unresolved[0].reason == "node_limit")
	check("preparation is cancellable",not Motion.prepare(_scene_graph(scene.value),scene.value,result.value,func() -> bool: return true).ok)
	for hostile: Variant in [null,false,2.0,[],"x",{format = "openrc-creator-part-hint-v1",axis = "w"},{format = "openrc-creator-part-hint-v1",axis = "x",extra = true}]:
		check("untrusted axis hint has a closed schema",Parts._axis_hint({extras = {openrc_creator_part = hostile}}).is_empty())

func _conversion() -> void:
	var converted := _convert(_body(),_params())
	check("explicit mapping converts through source admission",converted.ok)
	if not converted.ok:
		printerr(converted)
		return
	var source: RefCounted = converted.value.source
	var motion: Dictionary = converted.value.receipt.coordinate_frames
	check("marker triangles and missing marker texture are not rendered",source.triangle_count() == 3)
	check("typed target renderGroupName resolves to one assembled pivot",motion.prepared.size() == 1 and motion.prepared[0].children == [3,4] and motion.prepared[0].source_axis == "z")
	if motion.prepared.is_empty():
		printerr(motion.unresolved)
		return
	var pivot: int = motion.prepared[0].node
	var graph := Parts.graph(source)
	check("source object indices remain stable and frame node has no mesh",graph.ok and graph.value.mesh[5] == -1 and graph.value.names[3] == "Control.surface")
	var listed := Parts.list_parts(source)
	var aggregate := {}
	for part: Dictionary in listed.value:
		if part.node == pivot:
			aggregate = part
	check("pivot group is selectable with aggregate bounds", not aggregate.is_empty() and aggregate.triangles == 2 and aggregate.bounds_min[0] <= aggregate.bounds_max[0])
	var suggested := Parts.suggest_binding(source,{},pivot,"rudder")
	check("unplaced manual selection prefers declared hinge X",suggested.ok and suggested.value.axis == "x")
	var square := _convert(_body().replace("rot 0.9961946980917455 0 0.08715574274765817 0 1 0 -0.08715574274765817 0 0.9961946980917455","rot 1 0 0 0 1 0 0 0 1"),_params())
	var placed := {nose_axis = "+z",up_axis = "+y",unit_scale = 1.0,datum = [0.0,0.0,0.0]}
	var perpendicular := Parts.suggest_binding(square.value.source,placed,int(square.value.receipt.coordinate_frames.prepared[0].node),"aileron_left")
	check("declared X survives an exactly perpendicular role axis",perpendicular.ok and perpendicular.value.axis == "x" and perpendicular.value.sign == 1)
	var bindings := Parts.empty_bindings()
	bindings.controls.rudder = [{node = pivot,axis = "x",sign = 1}]
	var reopened := Importer.inspect_bytes(source.source_bytes(),"saved.glb")
	check("saved source reopens with provenance notes",reopened.ok and Converter.source_notes(reopened.value).size() == Converter.source_notes(source).size())
	var static_view := Builder.build_preview(source)
	var moving_view := Builder.build_preview(reopened.value,{},bindings)
	check("real bound preview maps appended group and children",static_view.ok and moving_view.ok)
	if static_view.ok and moving_view.ok:
		var a: Node3D = static_view.value.root
		var b: Node3D = moving_view.value.root
		var static_part := a.find_child("Control_surface",true,false) as Node3D
		var moving_part := b.find_child("Control_surface",true,false) as Node3D
		# Godot sanitizes AC3D dots in glTF node names; resolve by matching label if needed.
		if static_part == null:
			static_part = _find_part(a,"Control")
		if moving_part == null:
			moving_part = _find_part(b,"Control")
		check("moving mesh found", static_part != null and moving_part != null)
		if static_part != null and moving_part != null:
			var before := Builder.relative(a,static_part)*Vector3(0.2,0.3,0.1)
			var original := Vector3(3,4,5)+Basis(Vector3(0,0,1),PI/2.0)*(Vector3(2,-1,0.5)+Vector3(0.2,0.3,0.1))
			check("neutral pose matches original AC3D transforms independently",_near(before,original))
			check("wrapper leaves neutral mesh world pose intact",_near(before,Builder.relative(b,moving_part)*Vector3(0.2,0.3,0.1)))
			var parent := Basis(Vector3(0,0,1),PI/2.0)
			var marker := Basis(Vector3.UP,deg_to_rad(5.0))
			var origin := Vector3(3,4,5) + parent*(Vector3(0.1,0.2,0.3)+marker*Vector3(0.4,0.5,0.6))
			var axis := (parent*marker*Vector3(0,0,1)).normalized()
			for angle: float in [-30.0,30.0,0.0]:
				Builder.apply_surfaces(moving_view.value,{rudder = angle})
				var expected := origin + Basis(axis,deg_to_rad(angle))*(before-origin)
				check("actual deflection follows independent global hinge line: " + str(angle),_near(Builder.relative(b,moving_part)*Vector3(0.2,0.3,0.1),expected))
		a.free()
		b.free()
	elif static_view.ok:
		static_view.value.root.free()
	elif moving_view.ok:
		moving_view.value.root.free()
	var panel := PanelParts.new()
	root.add_child(panel)
	var authored := Authoring.new()
	authored.set_source(source)
	authored.set_bindings(bindings)
	var restored := Authoring.new()
	var restored_result := restored.restore(JSON.parse_string(JSON.stringify(authored.snapshot())),reopened.value)
	check("wrapper binding survives authoring snapshot and restore",restored_result.ok and restored.bindings() == bindings)
	panel.show_model(reopened.value,{},restored.bindings())
	check("reopened group remains selected",panel._collect().controls.rudder[0].node == pivot)
	var row: Dictionary = panel._rows["aileron_left/0"]
	var picker: OptionButton = row.part
	panel._select_part(picker,pivot)
	panel._on_part_selected(picker.selected,"aileron_left/0")
	check("actual picker selects prepared X", panel._collect().controls.aileron_left[0].axis == "x")
	panel._select_part(picker,2)
	panel._on_part_selected(picker.selected,"aileron_left/0")
	restored.set_bindings(panel._collect())
	check("editing another row preserves the reopened group binding",Parts.validate_bindings(source,restored.bindings()).ok and restored.bindings().controls.rudder == bindings.controls.rudder)
	for role: String in Parts.CONTROL_ROLES:
		var two := Parts.empty_bindings()
		two.controls[role] = [{node = 3,axis = "z",sign = -1},{node = 4,axis = "y",sign = 1}]
		panel.show_model(source,{},two)
		check("valid second role slot survives: " + role,Parts.validate_bindings(source,two).ok and panel._collect() == two)
	panel.queue_free()
	await process_frame
	for params: String in [_params().replace("renderGroupName Control","renderGroupName Missing"),_params().replace("controlledAxisName z","controlledAxisName z\ncontrolledAxisName x"),_params().replace("liftsurface","receiver"),_params().replace("controlledPartMovement rotate","controlledPartMovement rotate\ncontrolledPartMovement move")]:
		var unresolved := _convert(_body(),params)
		check("ambiguous servo stays static with visible warning",unresolved.ok and unresolved.value.receipt.coordinate_frames.prepared.is_empty() and not unresolved.value.receipt.coordinate_frames.unresolved.is_empty() and unresolved.diagnostics.any(func(d: Dictionary) -> bool: return d.severity == "warning"))
	for params: String in [_params().replace("modelServos main","modelServos main other")+_servo("other"),_params().replace("modelServos main\n",""),_params().replace("modelServos main","modelServos main\nmodelServos other")]:
		var unresolved := _convert(_body(),params)
		check("active servo roster is mandatory and unambiguous",unresolved.ok and unresolved.value.receipt.coordinate_frames.prepared.is_empty() and not unresolved.value.receipt.coordinate_frames.unresolved.is_empty())
	var orphan := _convert(_body(),_params()+_servo("orphan"))
	check("unused servo cannot invalidate the active hinge",orphan.ok and orphan.value.receipt.coordinate_frames.prepared.size() == 1 and orphan.value.receipt.coordinate_frames.unresolved[0].reason == "unlisted_servo_section")
	var throttle_params := _params().replace("modelServos main","modelServos main throttle")+_servo("throttle").replace("controlledPartType liftsurface","controlledPartType none").replace("controlledPartName Logical","controlledPartName none")
	for movement: String in ["rotate","input"]:
		var throttle := _convert(_body(),throttle_params.replace("#begin servo.throttle\ncontrolledAxisName z\ncontrolledPartMovement rotate","#begin servo.throttle\ncontrolledAxisName z\ncontrolledPartMovement "+movement))
		check("ordinary throttle needs no visual hinge warning",throttle.ok and throttle.value.receipt.coordinate_frames.prepared.size() == 1 and throttle.value.receipt.coordinate_frames.unresolved.is_empty())
	var foreign := _convert(_body().replace("Control.link","Other.link"),_params())
	# Direct siblings with another prefix stay outside the selected group, hence still safe.
	check("other prefix is not swept into the hinge", foreign.ok and foreign.value.receipt.coordinate_frames.prepared[0].children == [3])
	var v5 := _convert(_body(),"verNumber 5\nmodelType 1\nmodelName body.ac\n")
	check("v5 retains exact frames without assumed servo axis",v5.ok and v5.value.receipt.coordinate_frames.frames.size() == 1 and v5.value.receipt.coordinate_frames.prepared.is_empty())
	var far_body := _body().replace("loc 0.1 0.2 0.3","loc 100000000 0 0").replace("rot 0.9961946980917455 0 0.08715574274765817 0 1 0 -0.08715574274765817 0 0.9961946980917455","rot 1 0 0 0 1 0 0 0 1").replace("0.4 1.5 0.6\n0.4 0.5 0.6\n0.4 0.5 3.6\n2.4 0.5 0.6","0 1 0\n0 0 0\n0 0 3\n2 0 0")
	var far := _convert(far_body,_params())
	if not far.ok or not far.value.receipt.coordinate_frames.prepared.is_empty() or far.value.receipt.coordinate_frames.unresolved[0].reason != "render_precision":
		printerr("Far hinge outcome: ",far.value.receipt.coordinate_frames.unresolved if far.ok else far)
	check("float32 cancellation leaves optional hinge static",far.ok and far.value.receipt.coordinate_frames.prepared.is_empty() and far.value.receipt.coordinate_frames.unresolved[0].reason == "render_precision")
	if far.ok:
		var preview := Builder.build_preview(far.value.source)
		check("far hinge cannot move the static render pose",preview.ok and _near(Builder.relative(preview.value.root,_find_part(preview.value.root,"Control"))*Vector3(0.2,0.3,0.1),Vector3(3,4,5)+Basis(Vector3(0,0,1),PI/2.0)*(Vector3(2,-1,0.5)+Vector3(0.2,0.3,0.1))))
		if preview.ok:
			preview.value.root.free()
	var package := _package(_body(),_params())
	var fallback := OptionalRigRefusal.new()
	fallback._package = package.value
	fallback._model = package.value.model("Plane")
	fallback._scene = Ac3d.read(_body().to_ascii_buffer()).value
	var static_fallback := fallback._convert()
	check("optional rig admission failure preserves complete static import",static_fallback.ok and static_fallback.value.receipt.coordinate_frames.prepared.is_empty() and static_fallback.value.receipt.coordinate_frames.unresolved[0].reason == "rig_admission" and static_fallback.value.source.triangle_count() == 3 and Parts.graph(static_fallback.value.source).value.count == 6)
	var examples: Array = []
	for reason: String in ["missing_render_group","unlisted_servo_section","foreign_render_descendant","render_precision","rig_admission"]:
		examples.append({group = "Control",reason = reason})
	var details := Converter._motion_notes({format = Motion.FORMAT,frames = [],prepared = [],unresolved = examples})
	check("unprepared mappings have named actionable explanations",details.size() == 6 and details[1].arguments == ["Control"])
	var unsafe := Converter._motion_notes({format = Motion.FORMAT,frames = [],prepared = [],unresolved = [{group = "line\nbreak",reason = "render_precision"},{group = "Control",reason = "arbitrary source error text"},false]})
	check("saved receipt cannot supply error messages or control characters",unsafe.size() == 1)
	for locale: String in ["es","pt_BR","de","fr","it","ru","ja","zh_Hans"]:
		TranslationServer.set_locale(locale)
		for diagnostic: Dictionary in converted.diagnostics + details:
			check("conversion explanation translated in " + locale,TranslationServer.translate(diagnostic.message) != diagnostic.message)
		for slot: Array in PanelParts.SLOTS:
			check("moving part caption translated in " + locale,TranslationServer.translate(slot[2]) != slot[2] or (locale == "de" and slot[2] == "Propeller"))
	TranslationServer.set_locale("en")

static func _find_part(node: Node, prefix: String) -> Node3D:
	for child: Node in node.get_children():
		if child is MeshInstance3D and str(child.name).begins_with(prefix):
			return child as Node3D
		var found := _find_part(child,prefix)
		if found != null:
			return found
	return null

static func _convert(body: String, params: String) -> Dictionary:
	var package := _package(body,params)
	return Converter.convert(package.value,"Plane") if package.ok else package

static func _package(body: String, params: String) -> Dictionary:
	return Package.inspect_bytes(Fixture._zip_bytes([["Plane/params.txt",params.to_ascii_buffer()],["Plane/data/body.ac",body.to_ascii_buffer()]]))

static func _scene_graph(scene: Dictionary) -> Dictionary:
	var nodes: Array = []
	for node: Dictionary in scene.nodes:
		var output := {name = node.name,children = node.children.duplicate(),matrix = Motion.matrix(Motion.local(node))}
		if not node.surfaces.is_empty() and not str(node.name).ends_with(".XYZObject"):
			output.mesh = 0
		nodes.append(output)
	return {scenes = [{nodes = scene.roots.duplicate()}],nodes = nodes}

static func _servo(name: String) -> String:
	return "#begin servo."+name+"\ncontrolledAxisName z\ncontrolledPartMovement rotate\ncontrolledPartName Logical\ncontrolledPartType liftsurface\n#end servo."+name+"\n"

static func _params() -> String:
	return "#begin params\nverNumber 6\nmodelType 1\nmodelName body.ac\nmodelServos main\n#end params\n#begin liftsurface.Logical\nrenderGroupName Control\n#end liftsurface.Logical\n"+_servo("main")

static func _body() -> String:
	var material := "AC3Db\nMATERIAL \"m\" rgb 1 1 1 amb 0.2 0.2 0.2 emis 0 0 0 spec 0.5 0.5 0.5 shi 10 trans 0\n"
	var triangle := "numvert 3\n0 0 0\n1 0 0\n0 1 1\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n"
	return material+"OBJECT world\nkids 1\nOBJECT group\nname \"parent\"\nrot 0 -1 0 1 0 0 0 0 1\nloc 3 4 5\nkids 4\nOBJECT poly\nname \"Body\"\n"+triangle+"OBJECT poly\nname \"Control.surface\"\nloc 2 -1 0.5\n"+triangle+"OBJECT poly\nname \"Control.link\"\nloc 2 -2 0.5\n"+triangle+"OBJECT poly\nname \"Control.XYZObject\"\nloc 0.1 0.2 0.3\nrot 0.9961946980917455 0 0.08715574274765817 0 1 0 -0.08715574274765817 0 0.9961946980917455\ntexture \"missing.gif\"\nnumvert 4\n0.4 1.5 0.6\n0.4 0.5 0.6\n0.4 0.5 3.6\n2.4 0.5 0.6\nnumsurf 2\nSURF 0x30\nmat 0\nrefs 3\n1 0 0\n0 0 0\n3 0 0\nSURF 0x30\nmat 0\nrefs 3\n1 0 0\n3 0 0\n2 0 0\nkids 0\n"

static func _near(a: Vector3,b: Vector3) -> bool:
	return a.distance_to(b) < 0.00002
