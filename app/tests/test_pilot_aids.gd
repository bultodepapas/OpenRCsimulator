# D7: pilot aids. Auto-zoom keeps the airplane readable; the shadow sits under it and narrows when banked; the grass
# texture is deterministic; the HUD statistics; [F5] hot reload of the aircraft data (good and broken files).
# Run: godot --headless --path . --script res://tests/test_pilot_aids.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const Shadow := preload("res://render/shadow.gd")
const Ground := preload("res://render/ground.gd")
const Hud := preload("res://render/hud.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const SPAN := 1.524
const H := 720.0
const TMP := "user://test_reload_aircraft.json"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	# Auto-zoom: projected span ≥ 30 px from 20 to 150 m; without it ≈ 12 px at 100 m.
	var worst := 1e9
	for d in range(20, 151, 5):
		worst = minf(worst, PilotCamera.projected_px(SPAN, d, PilotCamera.auto_fov(SPAN, d, H), H))
	_check("auto-zoom: span ≥ 30 px from 20 to 150 m", worst >= 30.0 - 1e-9, "worst %.2f px" % worst)
	var fixed := PilotCamera.projected_px(SPAN, 100.0, Spec.CAMERA.fov_deg, H)
	_check("fixed 50° FOV: ≈ 12 px at 100 m (the problem auto-zoom solves)", absf(fixed - 11.8) < 0.1, "%.2f px" % fixed)
	_check("auto-zoom never widens beyond the base FOV (close airplane)", PilotCamera.auto_fov(SPAN, 5.0, H) == Spec.CAMERA.fov_deg)
	_check("auto-zoom stops at the minimum FOV (very far)", PilotCamera.auto_fov(SPAN, 5000.0, H) == Spec.AUTO_ZOOM.min_fov_deg)

	# Shadow footprint: under the airplane, on the ground; banked 90° → no span; nose down 90° → no length.
	var pos := Vector3(10.0, 30.0, -60.0)
	var t := Shadow.footprint(Basis.IDENTITY, pos, SPAN, 1.3)
	_check("shadow on the ground under the airplane", absf(t.origin.y - Spec.SHADOW.height) < 1e-6 and absf(t.origin.x - 10.0) < 1e-6 and absf(t.origin.z + 60.0 - (0.5 - Shadow.WING_CENTER_V) * 1.3) < 1e-6, str(t.origin))
	_check("level: full span and length", absf(t.basis.x.length() - SPAN) < 1e-6 and absf(t.basis.z.length() - 1.3) < 1e-6)
	var banked := Shadow.footprint(Basis(Vector3(0, 0, -1), PI / 2.0), pos, SPAN, 1.3)
	_check("knife edge: the span shadow vanishes", banked.basis.x.length() < 1e-6, str(banked.basis.x))
	var dive := Shadow.footprint(Basis(Vector3(1, 0, 0), -PI / 2.0), pos, SPAN, 1.3)
	_check("vertical dive: the length shadow vanishes", dive.basis.z.length() < 1e-6, str(dive.basis.z))
	# L3: projected along the sun (45° up, from the south-west), a level airplane's shadow lies (h − shadow height) /
	# tan 45° away from the point below it, on the side away from the sun.
	var Atmosphere := load("res://render/atmosphere.gd")
	var s: Vector3 = Atmosphere.sun_direction()
	var sun_t := Shadow.footprint(Basis.IDENTITY, pos, SPAN, 1.3, s)
	var vert := Shadow.footprint(Basis.IDENTITY, pos, SPAN, 1.3)
	var shift := sun_t.origin - vert.origin
	var expect := Vector3(-s.x, 0.0, -s.z).normalized() * (pos.y - Spec.SHADOW.height) / tan(deg_to_rad(45.0))
	_check("sun shadow: offset (h − 0.05)/tan 45° away from the sun", shift.distance_to(expect) < 1e-4 and absf(sun_t.origin.y - Spec.SHADOW.height) < 1e-6, "%s vs %s" % [shift, expect])
	_check("sun shadow of a level airplane keeps its span and length", absf(sun_t.basis.x.length() - SPAN) < 1e-5 and absf(sun_t.basis.z.length() - 1.3) < 1e-5)
	_check("shadow fades with height but never vanishes", Shadow.alpha(0.0) == Spec.SHADOW.alpha_low and Shadow.alpha(1000.0) == Spec.SHADOW.alpha_high and Shadow.alpha(40.0) < Shadow.alpha(5.0))
	var sil := Shadow.silhouette()
	_check("silhouette: wing solid, outside clear", sil.get_pixel(10, 43).a > 0.9 and sil.get_pixel(10, 120).a < 0.05, "%s %s" % [sil.get_pixel(10, 43), sil.get_pixel(10, 120)])

	# The built model's extent (the shadow's size) matches the airplane.
	var a := AirplaneBuilder.build()
	var ext := Shadow.model_extent(a.root)
	a.root.free()
	_check("model extent: span 1.52 m, length 1.1–1.5 m", absf(ext.x - SPAN) < 0.03 and ext.y > 1.1 and ext.y < 1.5, str(ext))

	# Grass: deterministic (captures stay byte-identical), mipmapped, around the grass colour.
	var g1 := Ground.grass_image()
	var g2 := Ground.grass_image()
	_check("grass texture is deterministic", g1.get_data() == g2.get_data())
	_check("grass texture has mipmaps", g1.has_mipmaps())
	var mean := 0.0
	for j in range(0, 256, 4):
		for i in range(0, 256, 4):
			mean += g1.get_pixel(i, j).g
	mean /= 64.0 * 64.0
	_check("grass brightness centred on the grass colour", absf(mean - Spec.GRASS.g) < 0.03, "%.3f vs %.3f" % [mean, Spec.GRASS.g])

	# HUD numbers.
	var times := PackedFloat64Array()
	for i in 100:
		times.append(1.0 / 60.0 if i < 95 else 0.05)
	_check("p95 of 95 frames at 16.7 ms and 5 at 50 ms = 16.7 ms", absf(Hud.p95(times) - 1.0 / 60.0) < 1e-12)
	times.append(0.05)
	_check("one more slow frame tips the p95 to 50 ms", Hud.p95(times) == 0.05)
	_check("flight line", Hud.flight_line(15.0, 30.0, 3.71, 0.28) == "airspeed  15.0 m/s   altitude  30.0 m   AoA  +3.7°   throttle  28%", Hud.flight_line(15.0, 30.0, 3.71, 0.28))

	# Hot reload: more drag → the re-trimmed airplane needs more throttle; broken data keeps the old aircraft.
	var session := FlightSession.new()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scenarios.AIRCRAFT))
	_write(raw)
	session.setup(TMP)
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var throttle0: float = session.start.throttle
	raw.aero.coefficients.CD0.value = 0.06
	_write(raw)
	var msg := session.reload()
	_check("reload: CD0 0.0434 → 0.06 needs more throttle", session.start.ok and session.start.throttle > throttle0 + 0.02 and "reloaded" in msg, "%s (%.3f → %.3f)" % [msg, throttle0, session.start.throttle])
	_check("reload restarts the flight at the new trim", session.sim.tick == 0 and session.commands.throttle == session.start.throttle)
	var throttle1: float = session.start.throttle
	raw.aero.coefficients.Cma.value = 0.4 # unstable: the loader refuses it
	_write(raw)
	msg = session.reload()
	_check("reload of broken data: refused, old aircraft keeps flying", "failed" in msg and "Cma" in msg and session.aircraft.ok and session.start.throttle == throttle1, msg)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _write(raw: Dictionary) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw, "  "))
	f.close()
