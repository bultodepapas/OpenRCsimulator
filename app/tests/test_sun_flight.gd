# SUN-05b (docs/plans/sun.md): the sun optics inside the real flight scene (main.gd), not the capture harness.
#   - the glare node is built with the world, after Main in the process order (World.update runs first each frame),
#     and its afterimage canvas layer sits under every interface layer;
#   - the pilot's eye looking at the sun bleaches it on simulation time; looking away leaves the patch on screen;
#   - a held clock (pause) holds the patch; chase/orbit/close-up are lenses (no patch drawn); back in the pilot view
#     the eye still carries it; a restart rests the eye;
#   - --sun-glare=off keeps the node but draws and bleaches nothing.
# Run: godot --headless --path . --script res://tests/test_sun_flight.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const SunOptics := preload("res://render/sun/sun_optics.gd")

class TestFlight extends "res://main.gd":
	var options: Dictionary = {}
	func _user_args() -> Dictionary:
		return options

var _checks := 0
var _failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


## One 60 Hz frame of flight: four 240 Hz ticks unless the clock is held, Main's frame (World.update), the glare's.
func _frame(flight: Node, glare: Node, advance := true) -> void:
	if advance:
		for i in 4:
			flight.session.sim.step()
	flight._process(1.0 / 60.0)
	glare._process(0.0)


func _frames(flight: Node, glare: Node, count: int, advance := true) -> void:
	for i in count:
		_frame(flight, glare, advance)


func _run() -> void:
	var flight: TestFlight = TestFlight.new()
	flight.options = {"soundscape": "off", "crash-effects": "off", "smoke": "off"}
	root.add_child(flight)
	await process_frame
	var glare: Node = flight.find_child("SunGlare", true, false)
	check("the flight world carries the sun optics", glare != null)
	if glare == null:
		_finish(flight)
		return
	check("processed after Main, so it sees this frame's World.update", flight.is_ancestor_of(glare))
	var layer: CanvasLayer = glare.get_node_or_null("Afterimage")
	var lowest_ui := 1 << 30
	for node: Node in root.find_children("*", "CanvasLayer", true, false):
		if node != layer:
			lowest_ui = mini(lowest_ui, (node as CanvasLayer).layer)
	check("afterimage layer under every interface layer", layer != null and layer.layer < lowest_ui,
		"%s vs %d" % [str(layer.layer if layer != null else null), lowest_ui])

	# The pilot's eye on the calibrated sun (landscape-review look, an eye view), then 1 s of flight time.
	var rig: RefCounted = flight._rig
	var sun_az := float(Spec.ATMOSPHERE.sun_azimuth_deg)
	var sun_el := float(Spec.ATMOSPHERE.sun_elevation_deg)
	rig.look = Vector2(sun_az, sun_el)
	var clock_before: float = flight.session.sim.time()
	_frames(flight, glare, 60)
	check("simulation time advanced", flight.session.sim.time() > clock_before + 0.9)
	check("the pilot view is an eye", str(glare.get_meta("optics", "")) == "eye")
	var looked := float(glare.get_meta("afterimage", 0.0))
	check("a second on the sun bleaches the eye", looked > 0.9, str(looked))
	check("the veil is drawn", glare.visible and float(glare.get_meta("strength", 0.0)) > 1.0)

	# Look 40° away: the sun leaves the frame, the patch stays where it was on screen.
	rig.look = Vector2(sun_az + 40.0, sun_el)
	_frames(flight, glare, 10)
	check("the patch remains after looking away", layer.visible and float(glare.get_meta("afterimage", 0.0)) > 0.8)

	# A held clock (the pause) holds it exactly.
	var held := float(glare.get_meta("afterimage", 0.0))
	_frames(flight, glare, 30, false)
	check("a held clock holds the patch", float(glare.get_meta("afterimage", 0.0)) == held)

	# Chase is a lens: no patch drawn there; the eye keeps recovering on simulation time.
	rig.look = Vector2(NAN, NAN)
	rig.set_view("chase")
	_frames(flight, glare, 5)
	check("chase is a lens", str(glare.get_meta("optics", "")) == "lens" and not layer.visible)
	var in_chase := float(glare.get_meta("afterimage", 0.0))
	check("the eye recovers while the chase view shows", in_chase < held, "%f vs %f" % [in_chase, held])
	rig.set_view("pilot")
	_frames(flight, glare, 1)
	check("back in the pilot view the eye is an eye again", str(glare.get_meta("optics", "")) == "eye")

	# A restart rewinds the simulation clock: the eye starts rested.
	flight._request_restart()
	_frames(flight, glare, 3)
	check("a restart rests the eye", float(glare.get_meta("afterimage", 0.0)) == 0.0 and not layer.visible,
		str(glare.get_meta("afterimage", 0.0)))

	# --sun-glare=off: the node stays (one code path), draws and bleaches nothing.
	glare.intensity = 0.0
	rig.look = Vector2(sun_az, sun_el)
	_frames(flight, glare, 60)
	check("strength 0: no veil", not glare.visible)
	check("strength 0: no bleaching", float(glare.get_meta("afterimage", 0.0)) == 0.0 and not layer.visible)
	_finish(flight)


func _finish(flight: Node) -> void:
	flight.queue_free()
	await process_frame
	print("SUN flight: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
