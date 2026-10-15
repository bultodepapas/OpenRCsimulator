# P51-25: lateral modes (Dutch roll, spiral, roll subsidence) of the linearized aircraft at several level-flight speeds,
# from FlightModes.analyze. Research only. Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/modes_probe.gd [-- --data=res://...]
extends SceneTree
const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
func _initialize() -> void:
	var path := "res://data/aircraft/p51d_mustang_120.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="): path = arg.trim_prefix("--data=")
	var model: Dictionary = AircraftData.load_file(path).model
	for v in [22.0, 28.6, 35.0, 45.0]:
		var m := FlightModes.analyze(model, v)
		if not m.ok:
			print("V %.1f: %s" % [v, m.message]); continue
		var dr: Dictionary = m.dutch_roll
		var period := 1.0 / float(dr.f_hz)
		var cycles_half := log(2.0) / (2.0 * PI * float(dr.zeta) / sqrt(1.0 - float(dr.zeta) * float(dr.zeta)))
		print("V %.1f: dutch roll %.3f Hz period %.2f s zeta %.3f cycles-to-half %.2f; spiral tau %.1f s; roll tau %.3f s" % [v, dr.f_hz, period, dr.zeta, cycles_half, m.spiral_tau, m.roll_tau])
	quit(0)
