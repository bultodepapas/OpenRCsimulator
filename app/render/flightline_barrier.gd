## L10c: one low, open flightline cue; estimated visual layout, not a restraint or safety standard.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const POST_WIDTH_M: float = 0.08
const POST_DEPTH_M: float = 0.08
const FOOT_HEIGHT_M: float = 0.02
const CAP_HEIGHT_M: float = 0.02
const SLAT_HEIGHT_M: float = 0.05
const SLAT_DEPTH_M: float = 0.06
const FIRST_SLAT_CENTRE_M: float = 0.225
const TOP_SLAT_MARGIN_M: float = 0.06
const MAX_BAY_SPAN_M: float = 2.4
const SLAT_COUNT: int = 4
const STEEL: Color = Color("#969b99")
const ORANGE: Color = Color("#c87740")
const FOOTING: Color = Color("#8e9186")


## Shared local post centres for the barrier mesh and per-post contact shadows.
## The array contains the west-to-gap and gap-to-east banks as separate ordered runs.
static func post_positions(cue: Dictionary) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var width: float = float(cue.get("width", 0.0))
	var gap_width: float = float(cue.get("gap_width", 0.0))
	if not is_finite(width) or not is_finite(gap_width) or width <= gap_width + POST_WIDTH_M:
		return result
	var outer_centre: float = width * 0.5 - POST_WIDTH_M * 0.5
	var inner_centre: float = gap_width * 0.5 + POST_WIDTH_M * 0.5
	var bay_span: float = outer_centre - inner_centre
	if bay_span <= 0.0:
		return result
	var bay_count: int = maxi(1, int(ceil(bay_span / MAX_BAY_SPAN_M)))
	for bank: int in 2:
		for index: int in range(bay_count + 1):
			var amount: float = float(index) / float(bay_count)
			var east_offset: float
			if bank == 0:
				east_offset = lerpf(-outer_centre, -inner_centre, amount)
			else:
				east_offset = lerpf(inner_centre, outer_centre, amount)
			result.append(Vector3(east_offset, 0.0, 0.0))
	return result


static func build(cue: Dictionary) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = str(cue.id)
	root.position = Frames.ned_to_render([cue.north, cue.east, 0.0])
	root.set_process(false)
	var kit: RefCounted = MeshKit.new()
	var positions: PackedVector3Array = post_positions(cue)
	var posts_per_bank: int = positions.size() / 2
	var bay_count: int = posts_per_bank - 1
	var height: float = float(cue.height)
	var cap_base_y: float = height - CAP_HEIGHT_M
	var post_body_height: float = height - FOOT_HEIGHT_M - CAP_HEIGHT_M
	for position: Vector3 in positions:
		kit.block(Vector3(POST_WIDTH_M, FOOT_HEIGHT_M, POST_DEPTH_M), Vector3(position.x, 0.0, 0.0), FOOTING)
		kit.block(Vector3(POST_WIDTH_M, post_body_height, POST_DEPTH_M), Vector3(position.x, FOOT_HEIGHT_M, 0.0), STEEL)
		kit.block(Vector3(POST_WIDTH_M, CAP_HEIGHT_M, POST_DEPTH_M), Vector3(position.x, cap_base_y, 0.0), STEEL.lightened(0.08))
	for bank: int in 2:
		var bank_start: int = bank * posts_per_bank
		for bay: int in bay_count:
			var left: Vector3 = positions[bank_start + bay]
			var right: Vector3 = positions[bank_start + bay + 1]
			var span: float = absf(right.x - left.x)
			var centre_east: float = (right.x + left.x) * 0.5
			for slat: int in SLAT_COUNT:
				var fraction: float = float(slat) / float(SLAT_COUNT - 1)
				var centre_y: float = lerpf(FIRST_SLAT_CENTRE_M, height - TOP_SLAT_MARGIN_M, fraction)
				kit.block(
					Vector3(span, SLAT_HEIGHT_M, SLAT_DEPTH_M),
					Vector3(centre_east, centre_y - SLAT_HEIGHT_M * 0.5, 0.0),
					ORANGE
				)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Barrier"
	mesh_instance.mesh = kit.to_mesh(material)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.set_process(false)
	root.add_child(mesh_instance)
	return root
