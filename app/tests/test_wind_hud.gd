# Wind telemetry: horizontal ground speed, undefined horizontal bearing, and localization.
extends SceneTree
const Main = preload("res://main.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	TranslationServer.set_locale("en")
	var main: Main = Main.new()
	var state: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, -30.0, 3.0, 4.0, 12.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var text: String = main._weather_hud_line(state, M.v3(0.0, 0.0, -2.0))
	check("GS is horizontal 5, not 3D speed 13", text.contains("ground speed 5.0 m/s"))
	check("updraft has no horizontal bearing", text.contains("from --") and text.contains("up +2.0 m/s"))
	check("zero wind has no bearing", main._weather_hud_line(state, M.v3(0.0, 0.0, 0.0)).contains("from --"))
	for fixture: Array in [[M.v3(-3.0, 0.0, 0.0), "000°"], [M.v3(0.0, -3.0, 0.0), "090°"], [M.v3(3.0, 0.0, 0.0), "180°"], [M.v3(0.0, 3.0, 0.0), "270°"]]:
		check("meteorological cardinal " + fixture[1], main._weather_hud_line(state, fixture[0]).contains("from " + fixture[1]))
	# Pitch the aircraft: use world vertical, not body u/v, to project ground speed.
	var q: PackedFloat64Array = M.q_from_euler(0.0, PI / 2.0, 0.0)
	for index: int in 4:
		state[RB.ATT + index] = q[index]
	state[RB.VEL] = 12.0
	state[RB.VEL + 1] = 4.0
	state[RB.VEL + 2] = 3.0
	check("GS projection follows attitude", main._weather_hud_line(state, M.v3(0.0, 3.0, 0.0)).contains("ground speed 5.0 m/s"))
	TranslationServer.set_locale("es")
	check("Spanish wind telemetry is localized", main._weather_hud_line(state, M.v3(0.0, 3.0, 0.0)).begins_with("vel. suelo"))
	main.free()
	print("wind HUD: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
