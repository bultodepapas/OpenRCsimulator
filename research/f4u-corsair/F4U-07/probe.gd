extends SceneTree
## F4U-07: headless production-loader and trim probe for the staged Corsair data (not in the catalog).
## godot --headless --path app --audio-driver Dummy --script <repo>/research/f4u-corsair/F4U-07/probe.gd [-- <json>]
const AircraftData := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
const G := 9.80665
var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://").path_join("../research/f4u-corsair/F4U-07/f4u_corsair_1_5.json").simplify_path()
	var loaded: Dictionary = AircraftData.load_file(path)
	_check("staged v2 file passes production validation", loaded.get("ok", false), "; ".join(loaded.get("errors", PackedStringArray())))
	if not loaded.get("ok", false):
		print("F4U-07 probe: %d checks, %d failed" % [checks, failures])
		quit(1)
		return
	var model: Dictionary = loaded.model
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check("loader keeps identity, span and flight mass", model.id == "f4u-corsair-1-5" and absf(float(model.reference.b) - 2.5) < 1e-9
		and absf(float(model.mass_kg) - 18.5) < 1e-6, "%s, %.3f m, %.4f kg" % [model.id, model.reference.b, model.mass_kg])
	var throws: Dictionary = model.controls.throw_rad
	var v_start := float(raw.start.level_speed.value)
	var cl_max := float(raw.aero.envelope.CL_max.value)
	var v_stall := sqrt(2.0 * float(model.mass_kg) * G / (1.225 * float(model.reference.S) * cl_max))
	for speed: float in [1.3 * v_stall, v_start, 30.0, 38.0]:
		var t: Dictionary = Trim.solve("level", speed, model, G, throws)
		var ok: bool = t.get("ok", false)
		var detail := "alpha %.2f deg, elevator %.2f of %.1f deg, throttle %.3f, rpm %.0f" % [rad_to_deg(float(t.get("alpha", NAN))),
			rad_to_deg(float(t.get("elevator", NAN))), rad_to_deg(float(throws.elevator)), float(t.get("throttle", NAN)), float(t.get("rpm", NAN))]
		_check("level trim at %.1f m/s inside the control envelope" % speed, ok and absf(float(t.elevator)) < 0.9 * float(throws.elevator)
			and float(t.throttle) >= 0.0 and float(t.throttle) <= 1.0, detail)
	var glide: Dictionary = Trim.solve("glide", 1.4 * v_stall, model, G, throws)
	_check("power-off glide trim at 1.4 Vs", glide.get("ok", false), "gamma %.2f deg, elevator %.2f deg" % [rad_to_deg(float(glide.get("gamma", NAN))), rad_to_deg(float(glide.get("elevator", NAN)))])
	# Flare authority: the power-off glide near the stall must trim inside the elevator throw. Closer than about
	# 1.08 Vs the steady solve enters the stall blend and stops converging, which is not an authority limit.
	for factor: float in [1.15, 1.10]:
		var flare: Dictionary = Trim.solve("glide", factor * v_stall, model, G, throws)
		_check("power-off flare trim at %.2f Vs inside the elevator throw" % factor, flare.get("ok", false)
			and absf(float(flare.elevator)) < float(throws.elevator), "alpha %.2f deg, elevator %.2f of %.1f deg" % [rad_to_deg(float(flare.get("alpha", NAN))),
			rad_to_deg(float(flare.get("elevator", NAN))), rad_to_deg(float(throws.elevator))])
	print("F4U-07 probe: %d checks, %d failed (1-g stall %.1f m/s, start %.0f m/s)" % [checks, failures, v_stall, v_start])
	quit(1 if failures else 0)
