# Presentation adapter for the HX-700 main and tail rotors. All values are
# telemetry inputs; this node never writes to simulation state.
extends Node3D
class_name HeliRotorVisual

const HeliRotorBlur := preload("res://render/rotor/heli_rotor_blur.gd")
const MODEL_BUILDER := preload("res://aircraft/hx700_model.gd")

var airplane: Dictionary = {}
var telemetry: Dictionary = {}
var _main_mount: Node3D
var _main_tilt: Node3D
var _main_pivot: Node3D
var _main_rest := Basis.IDENTITY
var _tail_mount: Node3D
var _tail_pivot: Node3D
var _tail_rest := Basis.IDENTITY
var _main_spin_sign := -1.0
var _tail_spin_sign := -1.0
var _main_blur: Node3D
var _tail_blur: Node3D
var _legacy_main_phase := 0.0
var _legacy_tail_phase := 0.0


## Attach after the aircraft root has been added to its flight scene.
static func attach(model: Dictionary, parent: Node) -> HeliRotorVisual:
	if model.is_empty() or not (model.get("root") is Node3D) or parent == null:
		return null
	var visual := HeliRotorVisual.new()
	visual.name = "HelicopterRotorVisual"
	visual.airplane = model
	visual._main_mount = model.get("main_rotor_mount") as Node3D
	visual._main_tilt = model.get("main_rotor_tilt") as Node3D
	visual._main_pivot = model.get("main_rotor_pivot") as Node3D
	visual._main_rest = model.get("main_rotor_rest", Basis.IDENTITY)
	visual._tail_mount = model.get("tail_rotor") as Node3D
	visual._tail_pivot = model.get("tail_rotor_pivot") as Node3D
	visual._tail_rest = model.get("tail_rotor_rest", Basis.IDENTITY)
	visual._main_spin_sign = float(model.get("main_visual_spin_sign", -1.0))
	visual._tail_spin_sign = float(model.get("tail_visual_spin_sign", -1.0))
	if visual._main_mount == null or visual._main_tilt == null or visual._main_pivot == null \
			or visual._tail_mount == null or visual._tail_pivot == null:
		return null
	parent.add_child(visual)
	var root: Node3D = model.root
	visual._main_blur = HeliRotorBlur.attach(visual._main_mount, root, visual)
	visual._tail_blur = HeliRotorBlur.attach(visual._tail_mount, root, visual)
	return visual


## Consume shaft-speed telemetry and absolute shaft phases in radians. Axis direction
## signs are applied from the builder adapter; a1, b1 and collective are radians.
## The source model has no blade-feather hinge, so collective remains telemetry only.
## The legacy two-argument call still consumes a delta time; production
## presentation supplies both accepted-tick absolute phases.
func update(heli_state: Dictionary, main_phase_rad: float, tail_phase_rad: Variant = null) -> void:
	telemetry["omega_rad_s"] = _finite(heli_state.get("omega_rad_s", 0.0))
	telemetry["tail_omega_rad_s"] = _finite(heli_state.get("tail_omega_rad_s", 0.0))
	telemetry["a1"] = _finite(heli_state.get("a1", 0.0))
	telemetry["b1"] = _finite(heli_state.get("b1", 0.0))
	telemetry["collective"] = _finite(heli_state.get("collective", 0.0))
	var main_shaft_phase := _finite(main_phase_rad)
	var tail_shaft_phase := _finite(tail_phase_rad) if tail_phase_rad != null else 0.0
	if tail_phase_rad == null:
		var dt := maxf(main_shaft_phase, 0.0)
		_legacy_main_phase = fposmod(_legacy_main_phase + float(telemetry.omega_rad_s) * dt, TAU)
		_legacy_tail_phase = fposmod(_legacy_tail_phase + float(telemetry.tail_omega_rad_s) * dt, TAU)
		main_shaft_phase = _legacy_main_phase
		tail_shaft_phase = _legacy_tail_phase
	var main_phase := main_shaft_phase * _main_spin_sign
	var tail_phase := tail_shaft_phase * _tail_spin_sign
	_main_pivot.basis = Basis(Vector3(0.0, 0.0, 1.0), fposmod(main_phase, TAU)) * _main_rest
	_tail_pivot.basis = Basis(Vector3(0.0, 0.0, 1.0), fposmod(tail_phase, TAU)) * _tail_rest
	_main_tilt.basis = _cyclic_tilt(float(telemetry.a1), float(telemetry.b1))
	if _main_blur != null:
		(_main_blur as HeliRotorBlur).update(_rpm(float(telemetry.omega_rad_s)))
	if _tail_blur != null:
		(_tail_blur as HeliRotorBlur).update(_rpm(float(telemetry.tail_omega_rad_s)))
	if airplane.get("root") is Node3D:
		(airplane.root as Node3D).set_meta("heli_collective", float(telemetry.collective))


static func _rpm(omega_rad_s: float) -> float:
	return omega_rad_s * 60.0 / TAU


static func _finite(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0.0
	return float(value)


static func _cyclic_tilt(a1: float, b1: float) -> Basis:
	# Match MainRotor's first-harmonic shaft normal exactly in body/model coordinates.
	# The supplied mesh shaft is model +Y, and the frame conjugation applies this body
	# rotation to that visual axis at the presentation boundary.
	var normal_body := Vector3(sin(b1), cos(a1) * cos(b1), sin(a1)).normalized()
	var cross := Vector3.UP.cross(normal_body)
	var dot := clampf(Vector3.UP.dot(normal_body), -1.0, 1.0)
	var body_tilt := Basis.IDENTITY
	if cross.length_squared() > 1e-16:
		body_tilt = Basis(Quaternion(cross.normalized(), acos(dot)))
	elif dot < 0.0:
		body_tilt = Basis(Vector3.RIGHT, PI)
	return MODEL_BUILDER.GLTF_TO_MODEL.inverse() * body_tilt * MODEL_BUILDER.GLTF_TO_MODEL
