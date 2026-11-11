## BL-09: RC blimp visual adapter. Loads one skin GLB and poses its articulated nodes only from accepted physical
## state: vector angles, fin deflections and propeller shaft phase. Rendering never feeds back into physics.
## Bindings (node names and local rotation axes) come from the generated `presentation` block of the airship data.
## BL-19c: optional Workshop presentation (paint, markings, aircraft lights) binds lazily; build()/pose() callers that
## never call it load and allocate nothing extra.
extends RefCounted

const Frames := preload("res://render/frames.gd")
const Catalog := preload("res://vehicles/airship/airship_catalog.gd")
const PRESENTATION_PATH := "res://vehicles/airship/airship_presentation.gd"
const CUSTOMIZATION_PATH := "res://render/aircraft_customization.gd"
const WORLD_PATH := "res://render/world/world.gd"
const RIG_PATH := "res://render/lighting/aircraft_lighting_rig_3d.gd"
const LIGHTS_PATH := "res://render/world/aircraft_lights.gd"

const VECTOR_KEYS := ["vector_port", "vector_starboard", "vector_stern"]
const FIN_KEYS := ["fin_dorsal", "fin_port", "fin_starboard"]
const ROTOR_KEYS := ["rotor_port", "rotor_starboard", "rotor_stern_axial", "rotor_stern_lateral"]
## Visual shaft speed at full normalized motor speed (rev/s); motion blur is not simulated.
const FULL_SPEED_REV_S := 120.0

var root: Node3D
var model: Node3D
var error := ""
var active_skin := ""
## Builder-compatible presentation dictionary (see AirshipPresentation.instance); empty until bound.
var customization: Dictionary = {}
var _bindings := {}
var _phase := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _discs: Array[MeshInstance3D] = []
var _world: Script
var _lights: Script
var _light_state: RefCounted
var _light_context: Dictionary = {}
var _light_rig: Node3D
var _night_kit: Node3D
var _light_clock := 0.0
var _light_configured := false
var _rig_mode := ""
var _rig_gain := -1.0


static func skins(_presentation: Dictionary = {}) -> Array:
	return Catalog.skins()


func build(presentation: Dictionary, skin_id: String) -> bool:
	var chosen: Dictionary = {}
	for skin: Dictionary in skins(presentation):
		if skin.id == skin_id:
			chosen = skin
	if chosen.is_empty():
		error = "Unknown blimp skin: " + skin_id
		return false
	var scene := load(str(chosen.model)) as PackedScene
	if scene == null:
		error = "Blimp model is unavailable: " + str(chosen.model)
		return false
	active_skin = skin_id
	root = Node3D.new()
	root.name = "Airship"
	model = scene.instantiate() as Node3D
	if model == null:
		error = "Blimp model did not instantiate"
		return false
	model.name = "Model"
	root.add_child(model)
	var bindings: Dictionary = presentation.get("bindings", {})
	for key: String in VECTOR_KEYS + FIN_KEYS + ROTOR_KEYS:
		var binding: Variant = bindings.get(key)
		if typeof(binding) != TYPE_DICTIONARY:
			error = "Blimp binding missing: " + key
			return false
		var node := model.find_child(str(binding.node), true, false) as Node3D
		var axis_raw: Array = binding.get("local_axis", [])
		if node == null or axis_raw.size() != 3:
			error = "Blimp model node missing: " + str(binding.node)
			return false
		var axis := Vector3(axis_raw[0], axis_raw[1], axis_raw[2])
		if absf(axis.length() - 1.0) > 1e-3:
			error = "Blimp binding axis is not a unit vector: " + key
			return false
		_bindings[key] = {node = node, rest = node.transform, axis = axis.normalized(), sign = float(binding.get("sign", 1.0))}
	for key: String in ROTOR_KEYS:
		_discs.append(_make_disc(_bindings[key], presentation.get("disc_radius", {}).get(key, 0.09)))
	return true


## A faint translucent disc appears only at speed; at rest the real blades are visible.
func _make_disc(binding: Dictionary, radius: float) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.002
	mesh.radial_segments = 32
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.87, 0.9, 0.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var node: Node3D = binding.node
	var rest: Transform3D = binding.rest
	# Cylinder axis is local +Y; align it with the spin axis expressed in the rotor's parent frame.
	var spin: Vector3 = (rest.basis * Vector3(binding.axis)).normalized()
	var helper := Vector3.UP if absf(spin.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := spin.cross(helper).normalized()
	disc.transform = Transform3D(Basis(x, spin, x.cross(spin)), rest.origin)
	node.get_parent().add_child(disc)
	return disc


## body: 13-value accepted (or interpolated) state; continuous: motor speeds, vector/fin angles (CTRL sign).
func pose(body: PackedFloat64Array, continuous: PackedFloat64Array, frame_dt: float) -> void:
	if root == null:
		return
	root.transform = Transform3D(Frames.quat_to_render(body.slice(6, 10)), Frames.ned_to_render([body[0], body[1], body[2]]))
	for i in 3:
		_turn(VECTOR_KEYS[i], continuous[4 + i])
		_turn(FIN_KEYS[i], continuous[7 + i])
	for i in 4:
		var n := continuous[i]
		_phase[i] = fposmod(_phase[i] + TAU * FULL_SPEED_REV_S * n * frame_dt, TAU)
		_turn(ROTOR_KEYS[i], _phase[i])
		var material := _discs[i].material_override as StandardMaterial3D
		material.albedo_color.a = clampf((absf(n) - 0.25) * 0.35, 0.0, 0.22)
	_follow_lights()


func _turn(key: String, angle: float) -> void:
	var binding: Dictionary = _bindings[key]
	var node: Node3D = binding.node
	var rest: Transform3D = binding.rest
	node.transform = Transform3D(rest.basis * Basis(binding.axis, angle * float(binding.sign)), rest.origin)


## BL-19c: bind the shared Workshop presentation companion to this built visual. Returns {ok, errors}; idempotent.
func bind_presentation() -> Dictionary:
	if not customization.is_empty():
		return {"ok": true, "errors": PackedStringArray()}
	if root == null:
		return {"ok": false, "errors": PackedStringArray(["blimp visual is not built"])}
	var bound: Dictionary = load(PRESENTATION_PATH).instance(self, active_skin)
	if not bool(bound.get("ok", false)):
		return {"ok": false, "errors": bound.get("errors", PackedStringArray())}
	bound.erase("ok")
	bound.erase("errors")
	customization = bound
	# Hosts that light this root themselves (the Workshop preview) call this first, so the shared rig reuses the
	# fit-free kit instead of slicing the whole 220k-triangle hull (about 0.3 s). Nothing is allocated until then.
	root.set_meta("prepare_light_kit", prepare_light_kit)
	return {"ok": true, "errors": PackedStringArray()}


## Paint and markings through the shared AircraftCustomization.apply. An empty profile restores the stock finish.
## The profile is a canonical Workshop presentation profile bound to this skin (workshop/presentation.gd).
func apply_presentation(profile: Dictionary) -> Dictionary:
	var bound := bind_presentation()
	if not bool(bound.ok):
		return bound
	var applied: Dictionary = load(CUSTOMIZATION_PATH).apply(customization, profile)
	return {"ok": bool(applied.get("ok", false)), "errors": applied.get("errors", PackedStringArray())}


## Aircraft lights, mirroring the fixed-wing flight (main.gd). `profile` is a lighting profile (lighting_profile.gd);
## "inherit" (the default) uses the night kit at the authored anchors, fitted lazily only when the time of day turns
## the lights on, so daylight and OFF allocate no lights. "preset"/"custom" build an AircraftLightingRig3D; "disabled"
## keeps everything dark. Context keys (all optional):
##   lighting_config: Dictionary - the session's time-of-day config (World.aircraft_local_seconds), default legacy;
##   lighting_snapshot: Dictionary - the World lighting snapshot (World.aircraft_sun_elevation), default {};
##   rig_parent: Node - parent of the RGB rig node (default: the root's parent, else the root);
##   luminous_layers: int - render layer bits OR-ed onto luminous nodes (main.gd uses Magnifier.LAYER), default 0;
##   mode: String - initial light selection "auto" (default), "all", "nav" or "off".
## Returns {ok, errors, warnings}; callers may ignore it. Call update_lighting() every rendered frame afterwards.
func configure_lighting(profile: Dictionary, context: Dictionary = {}) -> Dictionary:
	dispose_lighting()
	var bound := bind_presentation()
	if not bool(bound.ok):
		return {"ok": false, "errors": bound.errors, "warnings": []}
	_world = load(WORLD_PATH)
	_lights = _world.AircraftLights
	_light_state = _world.AircraftLightState.new()
	if not _light_state.set_mode(str(context.get("mode", "auto"))):
		return {"ok": false, "errors": PackedStringArray(["unknown light selection: " + str(context.get("mode"))]), "warnings": []}
	_light_context = context.duplicate()
	_light_clock = 0.0
	var warnings: Array = []
	if str(profile.get("selection", "inherit")) not in ["inherit", "disabled"]:
		_attach_kit() # the rig reuses this kit instead of fitting the whole mesh
	if str(profile.get("selection", "inherit")) != "inherit":
		_light_rig = load(RIG_PATH).new()
		_light_rig.name = "AirshipLightingRig"
		var parent: Node = context.get("rig_parent") if context.get("rig_parent") is Node else root.get_parent()
		(parent if parent != null else root).add_child(_light_rig)
		var result: Dictionary = _light_rig.configure(root, profile)
		if not bool(result.get("ok", false)):
			dispose_lighting()
			return {"ok": false, "errors": result.get("errors", []), "warnings": result.get("warnings", [])}
		warnings = result.get("warnings", [])
		_night_kit = _light_rig.get_kit()
		var layers := int(context.get("luminous_layers", 0))
		if layers != 0:
			for luminous: VisualInstance3D in _light_rig.luminous_nodes():
				luminous.layers |= layers
	_light_configured = true
	update_lighting(0.0, 0.0)
	return {"ok": true, "errors": PackedStringArray(), "warnings": warnings}


## Per rendered frame, after pose(). clock_s is the displayed presentation clock (sim time, as main.gd uses); NAN
## advances an internal clock by delta. Telemetry is forwarded to the rig (throttle, speed_mps, airspeed, roll_rate,
## pitch_rate, maneuver, distance_m, effects_allowed); optional overrides: exposure (default World.Exposure.last),
## local_seconds and sun_elevation_deg (default from the configured context through World).
func update_lighting(delta: float, clock_s: float = NAN, telemetry: Dictionary = {}) -> void:
	if not _light_configured or root == null:
		return
	_light_clock = clock_s if is_finite(clock_s) else _light_clock + maxf(delta, 0.0)
	var local_seconds := float(telemetry.get("local_seconds", _world.aircraft_local_seconds(_light_context.get("lighting_config", {}), _light_clock)))
	var elevation := float(telemetry.get("sun_elevation_deg", _world.aircraft_sun_elevation(_light_context.get("lighting_snapshot", {}))))
	_light_state.update(local_seconds, 1.0 if elevation < _world.NIGHT_KIT_BELOW_SUN_DEG else 0.0)
	_apply_light_mode()
	# Anchors first: the rig's effects read their positions, and a kit lit this frame skipped earlier follow passes.
	_follow_lights()
	if is_instance_valid(_light_rig):
		var forwarded := telemetry.duplicate()
		forwarded["lighting_priority"] = 100
		if not forwarded.has("exposure"):
			forwarded["exposure"] = _world.Exposure.last
		_light_rig.advance(_light_clock, forwarded)


## Light selection, as the fixed-wing keyboard/menu adapters use it: "auto", "all", "nav" or "off".
func set_light_mode(mode: String) -> bool:
	if _light_state == null or not _light_state.set_mode(mode):
		return false
	_apply_light_mode()
	return true


## {selection, active_mode, gain}, or empty before configure_lighting().
func light_state() -> Dictionary:
	if _light_state == null:
		return {}
	return {"selection": _light_state.selection, "active_mode": _light_state.active_mode, "gain": _light_state.gain}


## A flight reset: AUTO selection and restarted light patterns.
func reset_lighting() -> void:
	if _light_state != null:
		_light_state.reset()
	if is_instance_valid(_light_rig):
		_light_rig.reset()
	_light_clock = 0.0
	_apply_light_mode()


## Frees the RGB rig (restoring imported materials). A fitted night kit stays on the root and is freed with it.
func dispose_lighting() -> void:
	if is_instance_valid(_light_rig):
		_light_rig.dispose()
		if _light_rig.is_inside_tree():
			_light_rig.queue_free()
		else:
			_light_rig.free()
	_light_rig = null
	_light_configured = false
	_rig_mode = ""
	_rig_gain = -1.0


func _apply_light_mode() -> void:
	if _light_state == null or root == null:
		return
	var mode: String = _light_state.active_mode
	var gain: float = _light_state.gain
	if is_instance_valid(_light_rig):
		if mode != _rig_mode or gain != _rig_gain:
			_light_rig.set_mode(mode, gain)
			_rig_mode = mode
			_rig_gain = gain
		return
	if not is_instance_valid(_night_kit) and mode != "off":
		_attach_kit()
	if is_instance_valid(_night_kit) and str(_night_kit.get_meta("mode", "")) != mode:
		_lights.set_mode(_night_kit, mode)
	_lights.set_emission_mode(_lights.prepare_emission(root), mode, gain)


## Lights mounted on moving parts (the dorsal rudder's tail light) follow the posed hinges. A dark kit is skipped;
## lighting it up (_apply_light_mode) precedes the follow pass of the same frame.
func _follow_lights() -> void:
	if is_instance_valid(_night_kit) and _night_kit.visible:
		_lights.update_dynamic(_night_kit, root, 1.0)


## The dark, fit-free authored kit (root meta "prepare_light_kit"); idempotent. Returns the NightKit.
func prepare_light_kit() -> Node3D:
	if root == null:
		return null
	_attach_kit()
	return _night_kit


## Every lamp and strip is authored, so the kit needs no geometric fitting: the generic fit slices the whole
## 220k-triangle mesh (about 0.3 s) only to produce fallbacks the authored layout replaces. Bounds stay measured
## (mesh AABBs only, at the current model scale) for the lighting effects' projected-size budget. A new kit is dark.
func _attach_kit() -> void:
	if _lights == null:
		_lights = load(LIGHTS_PATH)
	_night_kit = root.get_node_or_null("NightKit") as Node3D
	if not is_instance_valid(_night_kit):
		var empty := PackedVector3Array()
		var tip := {"centre": Vector3.ZERO, "trailing": Vector3.ZERO, "leading_z": 0.0}
		var layout := {"bounds": _lights.bounds(root).all, "skins": {"lower": {"left": empty, "right": empty},
			"upper": {"left": empty, "right": empty}}, "left": tip, "right": tip, "belly": empty, "landing": Vector3.ZERO}
		_night_kit = _lights.attach(root, layout)
		_lights.set_mode(_night_kit, "off")
	var layers := int(_light_context.get("luminous_layers", 0))
	if layers != 0 and is_instance_valid(_night_kit):
		for luminous: Node in _night_kit.find_children("*", "VisualInstance3D", true, false):
			(luminous as VisualInstance3D).layers |= layers
