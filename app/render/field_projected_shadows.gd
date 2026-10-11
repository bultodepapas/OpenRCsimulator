## VQ-04a-F1: cached geometry shadows for flight cues and nearby static scenery.
## Uses the same projection as the aircraft, without changing scenery ownership.
extends Node

const Projected = preload("res://render/projected_shadow.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const MAX_SCENERY_RANGE := 100.0 # artistic near-field budget, metres from pilot
const MAX_MAPS := 16
const MAX_TARGET_PIXELS := 8 * 1024 * 1024 # <=64 MiB nominal RGBA8 + 32-bit depth
const OPACITY := 0.40 # artistic direct-light reduction, before time-of-day strength

var projectors: Array[Node] = []
var snapshot: Dictionary = {}
var target_pixels := 0
var _light_signature: Array = []


static func attach(field_node: Node3D, field: Dictionary, lighting: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--field-shadows=off"):
		return # explicit evidence/recovery route keeps the legacy contact shadows
	var manager := new()
	manager.name = "ProjectedFieldShadows"
	field_node.add_child(manager)
	manager.snapshot = lighting.duplicate(true)
	var cues_complete := true
	for cue: Dictionary in field.get("flight_cues", []):
		var model := field_node.get_node_or_null(NodePath(str(cue.id))) as Node3D
		if model == null or not manager.add_caster(model):
			cues_complete = false
	# Legacy cues share one mesh. Keep the complete old set if any new cue fails,
	# avoiding both missing contacts and overlapping old/new receivers.
	if not cues_complete:
		for projector in manager.projectors:
			projector.free()
		manager.projectors.clear()
		manager.target_pixels = 0
	var contacts := field_node.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if contacts != null and not manager.projectors.is_empty():
		contacts.visible = false
	var scenery := field_node.get_node_or_null("Scenery") as Node3D
	if scenery != null:
		var pilot := Vector2(float(field.pilot.east), -float(field.pilot.north))
		for node in scenery.get_children():
			if not node is MeshInstance3D or not str(node.name).begins_with("cell_"):
				continue
			var box: AABB = node.mesh.get_aabb()
			var centre := box.get_center()
			if box.size.y < 0.08 or Vector2(centre.x, centre.z).distance_to(pilot) > MAX_SCENERY_RANGE:
				continue
			if manager.add_caster(node):
				var old := scenery.get_node_or_null(NodePath(str(node.name).replace("cell_", "shadows_"))) as MeshInstance3D
				if old != null:
					old.visible = false
	if manager.projectors.is_empty():
		manager.free()
		return
	manager.apply(lighting)


static func apply_lighting(field_node: Node3D, lighting: Dictionary) -> void:
	var manager := field_node.get_node_or_null("ProjectedFieldShadows")
	if manager != null:
		manager.apply(lighting)


func add_caster(model: Node3D) -> bool:
	if projectors.size() >= MAX_MAPS:
		return false
	var shape := Projected.collect(model, 0.04)
	if shape.is_empty():
		return false
	var longest := maxf(shape.bounds.size.x, shape.bounds.size.z)
	# At most 1024² per static batch, without an MSAA depth/color target. Small cues
	# use 256². This preserves the narrow fence slats within the bounded memory cap.
	var resolution := 256 if longest < 8.0 else (512 if longest < 20.0 else 1024)
	if target_pixels + resolution * resolution > MAX_TARGET_PIXELS:
		return false
	var projector := Projected.new()
	projector.name = "Caster_" + str(model.name)
	add_child(projector)
	projector.setup(model, shape, resolution, Viewport.MSAA_DISABLED)
	projector.set_meta("soft_height", maxf(shape.bounds.size.y * 0.5, 0.0))
	projectors.append(projector)
	target_pixels += resolution * resolution
	return true


func _ready() -> void:
	# Field and Home are assembled outside the tree; now every source has its final
	# global transform. No new animation clock.
	apply(snapshot)


func _process(_delta: float) -> void:
	# FW flowing time changes its shared visual state; read it, never advance it.
	var signature := [Atmosphere.shadow_direction(), Atmosphere.light_energy()]
	if signature != _light_signature:
		apply(snapshot)


func apply(lighting: Dictionary) -> void:
	snapshot = lighting.duplicate(true)
	var direction := Atmosphere.shadow_direction(lighting)
	var strength: float = Atmosphere.shadow_strength(lighting)
	var flowing := lighting.is_empty() and not Atmosphere.state.is_empty()
	set_process(flowing)
	if flowing:
		strength *= clampf(Atmosphere.light_energy() / float(Atmosphere.Spec.ATMOSPHERE.sun_energy), 0.0, 1.0)
	_light_signature = [direction, Atmosphere.light_energy(lighting)]
	for projector in projectors:
		projector.refresh(float(projector.get_meta("soft_height")), direction,
			OPACITY * strength, strength > 0.0)
