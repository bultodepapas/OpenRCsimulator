# B5: rate limiter, throttle, and surface signs on the real airplane nodes.
# Run: godot --headless --path . --script res://tests/test_controls.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const Commands := preload("res://input/commands.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _raw(overrides: Dictionary) -> Dictionary:
	var r := Commands.neutral_raw()
	r.merge(overrides, true)
	return r


## Trailing edge relative to the hinge, in model axes, using the real node transforms.
func _trailing_edge(c: Dictionary, surface_name: String) -> Vector3:
	var a := AirplaneBuilder.build()
	AirplaneBuilder.apply_surfaces(a, Commands.hinge_rotations(c))
	var depth := 0.0
	for s in Spec.SURFACES:
		if s.name == surface_name:
			depth = s.size.z
	var hinge: Node3D = a.hinges[surface_name]
	var mesh: Node3D = hinge.get_child(0)
	var te: Vector3 = hinge.transform.basis * (mesh.transform * Vector3(0, 0, depth / 2.0))
	a.root.free()
	return te


func _initialize() -> void:
	# Rate limiter
	_check("0.5 after 0.125 s", absf(Commands.rate_limit(0.0, 1.0, 4.0, 0.125) - 0.5) < 1e-12)
	var v := 0.0
	for i in 100:
		v = Commands.rate_limit(v, 1.0, 4.0, 1.0 / 60.0)
	_check("reaches target exactly", v == 1.0, str(v))
	_check("no overshoot", Commands.rate_limit(0.99, 1.0, 4.0, 1.0) == 1.0)
	var c := Commands.neutral_commands()
	c.roll = 1.0
	c = Commands.step_commands(c, _raw({}), 0.25)
	_check("re-centers", absf(c.roll) < 1e-12, str(c.roll))

	# Throttle
	_check("throttle holds", Commands.step_commands(Commands.neutral_commands(), _raw({}), 10.0).throttle == 0.5)
	_check("throttle clamps high", Commands.step_commands(Commands.neutral_commands(), _raw({ throttle = 1.0 }), 10.0).throttle == 1.0)
	_check("throttle clamps low", Commands.step_commands(Commands.neutral_commands(), _raw({ throttle = -1.0 }), 10.0).throttle == 0.0)

	# Surface signs on the real nodes
	for s in Spec.SURFACES:
		var te := _trailing_edge(Commands.neutral_commands(), s.name)
		_check("neutral %s straight aft" % s.name, absf(te.x) < 1e-6 and absf(te.y) < 1e-6, str(te))
	var full := Commands.neutral_commands()
	full.roll = 1.0
	full.pitch = 1.0
	full.yaw = 1.0
	var r := _trailing_edge(full, "aileron_right")
	var l := _trailing_edge(full, "aileron_left")
	_check("roll right: right aileron TE up", r.y > 0, str(r))
	_check("roll right: left aileron TE down", l.y < 0, str(l))
	_check("aileron 20 deg", absf(rad_to_deg(atan2(r.y, r.z)) - 20.0) < 1e-4)
	_check("pitch up: elevator TE up", _trailing_edge(full, "elevator").y > 0)
	var rud := _trailing_edge(full, "rudder")
	_check("yaw right: rudder TE +x", rud.x > 0, str(rud))
	_check("rudder 25 deg", absf(rad_to_deg(atan2(rud.x, rud.z)) - 25.0) < 1e-4)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
