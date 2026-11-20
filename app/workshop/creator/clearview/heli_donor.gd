extends RefCounted
## Import closeout: a converted ClearView helicopter (modelType 0) test flies on the validated X-Cell .60
## reference helicopter physics as a labelled donor. Only the appearance is imported: no ClearView flight
## value is read, and the flown mass, rotors and skids are the donor's.
##
## Placement: the ClearView render frame (metres, nose -X, up +Y). The ClearView origin (its CG reference)
## sits on the donor's CG horizontally; vertically the model's lowest point sits on the donor's skid
## contact plane, so a landed model touches the ground. A model whose main rotor radius differs from the
## donor's by more than MAX_SIZE_RATIO is shown scaled to the donor rotor, and the flight label says so.
const R := preload("res://workshop/creator/result.gd")
const Setup := preload("res://workshop/creator/clearview/setup.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

const DONOR_ID := "xcell-60-research"
const OFFER := "Fly as a helicopter (X-Cell .60 donor)"
const OFFER_HINT := "Flies with the X-Cell .60 reference helicopter physics; this model's appearance only."
const CONFIRM_TITLE := "Fly with donor helicopter physics?"
const CONFIRM := "This model flies with the X-Cell .60 reference helicopter physics; only its appearance is used. It is not the ClearView flight model, and no ClearView flight setting is read."
const CONFIRM_PLACEMENT := "Its ClearView origin is placed on the donor's centre of gravity and its lowest point on the donor's skids. A model whose main rotor is more than 1.5 times larger or smaller than the donor's is shown scaled to the donor rotor."
const ACCEPT := "Fly as a helicopter"
const LABEL := "X-Cell .60 reference physics · %s appearance only"
const LABEL_SCALED := "X-Cell .60 reference physics · %s appearance only, shown at %s %% of its size"
const UNAVAILABLE := "This helicopter model could not be shown for flight."
const MAX_SIZE_RATIO := 1.5
## A model shown more than 20 times larger or smaller than it is, or with a rotor under 1 mm, is a
## degenerate or mis-scaled source rather than a helicopter: it is refused, never shown absurdly.
const MAX_SHOWN_SCALE := 20.0
const MIN_MODEL_RADIUS_M := 0.001
## Shaft speed (rad/s) above which ClearView's spinning-disc parts replace its blades (about 570 rpm).
const DISC_OMEGA_RAD_S := 60.0
## ClearView rotor part prefixes (lower case): [disc, blades] per rotor.
const MAIN_PARTS := ["rotordisk", "rotorblades"]
const TAIL_PARTS := ["taildisk", "tailblades"]


## Accepts any value (flight payloads arrive untyped): only an admitted ClearView helicopter source passes.
static func is_helicopter(source: Variant) -> bool:
	return source is InspectedSource and Setup.is_helicopter(source)


## Flight visual in the dictionary shape helicopter_main reads ({root, cg_model_m, ...}) or a refusal.
## `rotor_radius_m` is the donor main rotor radius; `skid_depth_m` the donor skid contact depth below its CG.
static func build(source: InspectedSource, rotor_radius_m: float, skid_depth_m: float) -> Dictionary:
	if not is_helicopter(source) or not is_finite(rotor_radius_m) or rotor_radius_m <= 0.0 \
			or not is_finite(skid_depth_m) or skid_depth_m < 0.0:
		return R.fail(R.BUILD_INVALID, UNAVAILABLE, "source", "import")
	var placement := {nose_axis = Setup.NOSE_AXIS, up_axis = Setup.UP_AXIS, unit_scale = 1.0, datum = [0.0, 0.0, 0.0]}
	var built: Dictionary = VisualBuilder.build_flight(source, placement)
	if built.is_empty():
		return R.fail(R.BUILD_INVALID, UNAVAILABLE, "source", "import")
	var root: Node3D = built.root
	var model := root.get_node_or_null(NodePath(VisualBuilder.MODEL_NAME)) as Node3D
	var measured := measure(root)
	if model == null or measured.is_empty():
		root.free()
		return R.fail(R.BUILD_INVALID, UNAVAILABLE, "source", "import")
	var scale := 1.0
	var model_radius: float = measured.rotor_radius_m
	if not is_finite(model_radius) or model_radius < MIN_MODEL_RADIUS_M:
		root.free()
		return R.fail(R.BUILD_INVALID, UNAVAILABLE, "source", "import")
	var ratio := rotor_radius_m / model_radius
	if ratio > MAX_SIZE_RATIO or ratio < 1.0 / MAX_SIZE_RATIO:
		scale = ratio
	if scale > MAX_SHOWN_SCALE or scale < 1.0 / MAX_SHOWN_SCALE:
		root.free()
		return R.fail(R.BUILD_INVALID, UNAVAILABLE, "source", "import")
	# The datum is the origin, so scaling the model node equals placement unit_scale = scale.
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO) * model.transform
	var lowest: float = float(measured.lowest_m) * scale
	return R.ok({
		"root": root, "propeller": built.propeller, "has_propeller": false,
		"cg_model_m": Vector3(0.0, lowest + skid_depth_m, 0.0),
		"creator_scale": scale, "model_rotor_radius_m": model_radius * scale,
		"rotor_parts": rotor_parts(root), "creator_source_sha256": source.sha256(),
		"visual_family": "clearview-helicopter-donor",
	})


## {rotor_radius_m (0 when no main rotor part is named), lowest_m} of a built visual, in model metres.
static func measure(root: Node3D) -> Dictionary:
	var lowest := INF
	var rotor := AABB()
	var has_rotor := false
	var whole := AABB()
	var has_mesh := false
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box: AABB = VisualBuilder.relative(root, mesh) * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
		whole = box if not has_mesh else whole.merge(box)
		has_mesh = true
		if _family(root, mesh, MAIN_PARTS) >= 0:
			rotor = box if not has_rotor else rotor.merge(box)
			has_rotor = true
	if not is_finite(lowest):
		return {}
	# Without a named rotor, half the model's horizontal length stands in for the rotor radius
	# (a helicopter's rotor diameter is close to its fuselage length).
	return {rotor_radius_m = 0.5 * maxf(rotor.size.x, rotor.size.z) if has_rotor else 0.5 * maxf(whole.size.x, whole.size.z),
		lowest_m = lowest, named_rotor = has_rotor}


## {main: [discs, blades], tail: [discs, blades]}: the top-most named ClearView rotor parts.
static func rotor_parts(root: Node3D) -> Dictionary:
	var parts := {main = [[], []], tail = [[], []]}
	for node: Node in root.find_children("*", "Node3D", true, false):
		for key: String in ["main", "tail"]:
			var prefixes: Array = MAIN_PARTS if key == "main" else TAIL_PARTS
			var kind := _kind(str(node.name), prefixes)
			if kind >= 0 and _family(root, node.get_parent(), prefixes) < 0:
				parts[key][kind].append(node)
	return parts


## ClearView shows a rotor's disc parts while it turns and its blades while it is slow. Presentation only:
## a rotor without both disc and blade parts keeps its source look.
static func show_rotors(parts: Dictionary, main_omega_rad_s: float, tail_omega_rad_s: float) -> void:
	for key: String in ["main", "tail"]:
		var groups: Array = parts.get(key, [[], []])
		if (groups[0] as Array).is_empty() or (groups[1] as Array).is_empty():
			continue
		var omega := main_omega_rad_s if key == "main" else tail_omega_rad_s
		var spinning := is_finite(omega) and absf(omega) > DISC_OMEGA_RAD_S
		for index: int in 2:
			for part: Variant in groups[index]:
				if is_instance_valid(part):
					(part as Node3D).visible = spinning == (index == 0)


static func _kind(name: String, prefixes: Array) -> int:
	var lowered := name.to_lower()
	for index: int in prefixes.size():
		if lowered.begins_with(str(prefixes[index])):
			return index
	return -1


## The part kind of `node` or its nearest named ancestor below `root`, or -1.
static func _family(root: Node, node: Node, prefixes: Array) -> int:
	var current := node
	while current != null and current != root:
		var kind := _kind(str(current.name), prefixes)
		if kind >= 0:
			return kind
		current = current.get_parent()
	return -1
