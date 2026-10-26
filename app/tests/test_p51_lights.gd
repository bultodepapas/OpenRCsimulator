# P51-V13: the FW-35 night kit on the P-51D shines from the model's own lenses. Wing-tip lights sit just outboard of
# the red/green lenses, the tail light rides on the rudder, and the landing lamp lowers with the left gear leg and works
# only with the gear down and locked (P-51D: the light is in the left wheel well). Driven from a real session through
# the ground-gear observer. Aircraft without anchors keep the bounds-derived kit exactly.
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Kit := preload("res://render/world/aircraft_lights.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const P51 := preload("res://aircraft/p51d_model.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const GroundGear := preload("res://render/ground_gear.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _local(node: Node3D, model: Node3D) -> Transform3D:
	return model.global_transform.affine_inverse() * node.global_transform


func _lit(kit: Node3D, name: String) -> bool:
	return kit.visible and (kit.get_node(name) as Node3D).visible


func _run() -> void:
	ShaderClock.register()
	Engine.physics_ticks_per_second = 240
	var plane: Dictionary = Builder.build(Builder.P51_ID)
	_check("the P-51 model builds (manifest current)", not plane.is_empty())
	if plane.is_empty():
		_finish()
		return
	var model: Node3D = plane.root
	root.add_child(model)
	var anchors: Dictionary = model.get_meta("light_anchors", {})
	_check("the P-51 publishes anchors for both tip lights, the tail light and the landing lamp",
		["nav_left", "nav_right", "nav_tail", "landing"].all(func(k: String) -> bool: return anchors.has(k)), str(anchors.keys()))
	var kit := Kit.attach(model)

	# 1. Tip lights shine from just outside the modelled lenses (a sprite inside the lens sphere would be hidden by it).
	var r := float(P51.D.details.nav_lights.radius)
	var tips_ok := true
	var detail := ""
	for side in ["left", "right"]:
		var lens: Vector3 = _local(model.get_node("nav_light_" + side), model).origin
		var light: Vector3 = (kit.get_node("nav_" + side) as Node3D).position
		var d := lens.distance_to(light)
		tips_ok = tips_ok and d > r and d < r + 0.005 and signf(light.x) == (-1.0 if side == "left" else 1.0) and absf(light.x) > absf(lens.x)
		detail += "%s %.4f m from the lens; " % [side, d]
	_check("tip lights sit just outboard of their red/green lenses", tips_ok, detail)

	# 2. The tail light follows the rudder.
	var rudder: Node3D = plane.hinges.rudder
	var lens_node: Node3D = rudder.get_node("tail_light")
	var follow_ok := true
	var worst := 0.0
	for angle in [0.0, 0.45, -0.45]:
		rudder.rotation.y = angle
		Kit.update_dynamic(kit, model, 1.0)
		var gap := _local(lens_node, model).origin.distance_to((kit.get_node("nav_tail") as Node3D).position)
		worst = maxf(worst, absf(gap - 0.011))
	rudder.rotation.y = 0.0
	Kit.update_dynamic(kit, model, 1.0)
	follow_ok = worst < 1e-5
	_check("the tail light keeps 11 mm behind its lens as the rudder swings ±26°", follow_ok, "worst %s m" % String.num_scientific(worst))

	# 3. Landing lamp: on its lens with the gear down, off and stowed with the leg otherwise, independent of the mode.
	var lamp_lens: Node3D = model.find_child("landing_lamp_left", true, false)
	var beam: Node3D = kit.get_node("landing_light")
	var face_gap := _local(lamp_lens, model).origin.distance_to(beam.position)
	_check("landing light is the lamp lens's face on the left gear leg", lamp_lens != null and face_gap < 0.006 and beam.position.x < 0.0
		and String(beam.get_meta("crash_follow", "")).contains("landing_lamp_left"), "%.4f m, host %s" % [face_gap, beam.get_meta("crash_follow", "")])
	P51.set_gear(plane, 0.0)
	Kit.update_dynamic(kit, model, 0.0)
	var stowed_ok := not _lit(kit, "landing_light") and not _lit(kit, "landing_lamp") and _lit(kit, "nav_left")
	var stowed_gap := _local(lamp_lens, model).origin.distance_to(beam.position)
	_check("gear up: landing light off and stowed with the leg, navigation lights on", stowed_ok and stowed_gap < 0.006, "gap %.4f m" % stowed_gap)
	P51.set_gear(plane, 0.999)
	Kit.update_dynamic(kit, model, 0.999)
	_check("gear in transit (0.999): landing light still off", not _lit(kit, "landing_light"))
	Kit.set_mode(kit, "all")
	_check("selecting ALL does not override the gear gate", not _lit(kit, "landing_light") and _lit(kit, "strip_left"))
	P51.set_gear(plane, 1.0)
	Kit.update_dynamic(kit, model, 1.0)
	_check("gear down and locked: landing light and lamp on", _lit(kit, "landing_light") and _lit(kit, "landing_lamp"))
	Kit.set_mode(kit, "nav")
	_check("NAV mode still turns the landing light off with the gear down", not _lit(kit, "landing_light") and _lit(kit, "nav_tail"))
	Kit.set_mode(kit, "all")
	var aim := (beam as Node3D).basis * Vector3(0, 0, -1)
	_check("the landing beam aims forward and slightly down", aim.z < -0.99 and aim.y < 0.0, str(aim))
	model.queue_free()

	# 4. Through the session: an airborne start is gear up (lamp dark); lowering the gear lights it once locked down.
	var flight: Dictionary = Builder.build(Builder.P51_ID)
	root.add_child(flight.root)
	var flight_kit := Kit.attach(flight.root)
	var session := FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = true
	var observer := GroundGear.attach(flight, session)
	observer._process(0.0)
	var dark_up := not _lit(flight_kit, "landing_light")
	session.set_gear_down(true)
	var dt: float = session.sim.dt()
	var lit_early := false
	for i in roundi(3.9 / dt):
		session._physics_process(dt)
		session.sim.step()
		observer._process(dt)
		lit_early = lit_early or _lit(flight_kit, "landing_light")
	for i in roundi(0.3 / dt):
		session._physics_process(dt)
		session.sim.step()
	observer._process(dt)
	_check("session: dark with the gear up and through the 4 s extension, lit once down and locked", dark_up and not lit_early
		and session.gear_state().status == "down" and _lit(flight_kit, "landing_light"), "%s" % session.gear_state())
	session.queue_free()
	flight.root.queue_free()

	# 5. Aircraft without anchors keep the bounds-derived kit: no dynamic lights, no gates.
	var stik: Dictionary = Builder.build(Builder.STIK_ID)
	# Stik now ships creator navigation mounts. Exercise absence on this disposable instance,
	# without changing its geometry, source metadata or the shipped customization contract.
	for metadata_key: String in ["light_anchors", "lighting_layout"]:
		if stik.root.has_meta(metadata_key):
			stik.root.remove_meta(metadata_key)
	root.add_child(stik.root)
	var stik_kit := Kit.attach(stik.root)
	var plain := not stik_kit.has_meta("dynamic")
	for child in stik_kit.get_children():
		plain = plain and not child.has_meta("follow") and not child.has_meta("gear_gated")
	Kit.update_dynamic(stik_kit, stik.root, 0.0)
	_check("an aircraft without anchors has no following or gated lights, and gear state never changes its kit", plain and _lit(stik_kit, "landing_light"))
	stik.root.queue_free()
	_finish()


func _finish() -> void:
	print("P51-V13 lights: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
