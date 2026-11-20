## SA-08: the planar moving-vehicle shadow for activities without the fixed-wing flight's own cue (helicopter,
## RC car, quad, blimp), so a Projected selection still gives every vehicle a shadow.
## It draws only while projected cues are on and native maps are off (Projected, or a renderer without native
## shadows). In Auto/Native these vehicles already cast native shadows; doubling them would widen the unresolved
## overlapping-route question (SA-02). Presentation only: it reads the drawn pose and never writes it back.
## Geometry is collected on first activation, not when the cue is constructed.
extends Node3D

const Shadow = preload("res://render/shadow.gd")
const Projected = preload("res://render/projected_shadow.gd")
const ShadowSettings = preload("res://render/shadow_settings.gd")
const Atmosphere = preload("res://render/atmosphere.gd")

var carrier: MeshInstance3D
var vehicle: Node3D
## The activity's lighting snapshot ({} in legacy/flowing time, which reads the shared flow state).
var lighting: Dictionary = {}
## Render x, z -> terrain y (NAN when unknown); invalid keeps the historical flat field.
var ground_height := Callable()
var _bound: Node3D = null
var _extent := Vector2.ZERO


## `rotors` (pivots whose blades the activity's rotor blur shows only while slow) contribute only their blades, and
## only while the blur shows them (SA-19, ProjectedShadow.tag_rotor): parked rotors cast, spinning ones never freeze.
static func attach(parent: Node3D, vehicle_root: Node3D, lighting_snapshot: Dictionary,
		ground: Callable = Callable(), rotors: Array = []) -> Node3D:
	var cue := new()
	cue.name = "VehicleShadowCue"
	cue.lighting = lighting_snapshot
	cue.ground_height = ground
	# Runs after the activity has drawn this frame's vehicle pose (default priority 0).
	cue.process_priority = 100
	parent.add_child(cue)
	cue.carrier = Shadow.create(cue)
	cue.carrier.visible = false
	cue.set_vehicle(vehicle_root, rotors)
	return cue


## The helicopter's rotors: the main rotor sits under a `propeller` wrapper, the tail rotor does not.
static func helicopter_rotors(helicopter: Dictionary) -> Array:
	return [helicopter.get("main_rotor_pivot"), helicopter.get("tail_rotor_pivot")]


static func active() -> bool:
	return ShadowSettings.projected_enabled() and not ShadowSettings.native_enabled()


## A replaced vehicle visual (skin change, restart) rebinds on the next active frame.
func set_vehicle(vehicle_root: Node3D, rotors: Array = []) -> void:
	vehicle = vehicle_root
	for node: Variant in rotors:
		if node is Node3D and is_instance_valid(node):
			Projected.tag_rotor(node as Node3D)
	_bound = null


func _process(_delta: float) -> void:
	var drawn := active() and is_instance_valid(vehicle) and vehicle.is_visible_in_tree()
	if not drawn:
		if carrier.visible:
			carrier.visible = false
		return
	if _bound != vehicle:
		_extent = Shadow.model_extent(vehicle)
		Shadow.bind_model(carrier, vehicle)
		_bound = vehicle
	var pose := vehicle.global_transform
	var cue := ShadowSettings.aircraft_cue()
	var strength := Shadow.cue_strength("auto", Atmosphere.shadow_strength(lighting))
	var direction := Atmosphere.shadow_direction(lighting)
	carrier.visible = cue != "off" and strength > 0.0
	# Terrain queries only for a cue that will draw.
	var receiving := Shadow.receiving_ground(pose.origin, Vector3.UP if cue == "vertical" else direction,
		ground_height if carrier.visible else Callable(), maxf(_extent.x, _extent.y))
	Shadow.update(carrier, pose.basis, pose.origin, _extent.x, _extent.y, direction, strength * float(receiving.fit),
		"auto", float(receiving.y))
