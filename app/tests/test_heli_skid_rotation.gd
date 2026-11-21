## A36 R8-F01: skid admission must bound the contact rotation modes, not only the mass-normalized vertical ones. Widening
## the stock X-Cell's skids to +/-0.5 m kept the translational ratios unchanged but put the roll contact mode at
## h*lambda = -4.4 (RK4 gain 7.69 per tick instead of decay). Stock and HX-700 data remain admitted.
extends SceneTree

const Data := preload("res://physics/rotorcraft_data.gd")

const XCELL := "res://data/aircraft/xcell_60_research.json"
const HX700 := "res://data/aircraft/hx700_electric_3d_experimental.json"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _widened(half_width: float) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(XCELL))
	var points: Dictionary = raw.skids.points_body_frd_m
	var values: Array = points.value
	for i in range(1, values.size(), 3):
		values[i] = half_width * signf(float(values[i]))
	points.kind = "estimated"
	points.source = "A36 R8-F01 synthetic widened skid geometry; not measured hardware"
	return raw


func _run() -> void:
	for path: String in [XCELL, HX700]:
		var loaded: Dictionary = Data.load_file(path)
		check("%s is still admitted" % path.get_file(), loaded.ok, loaded.get("errors", []))
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(XCELL))
	var stock_points: Array = stock.skids.points_body_frd_m.value
	# Independent stock roll ratios: lever^2 = y^2 + z^2 = 0.0858^2 + 0.1098^2, J_x = 0.18, k = 10000, c = 190.
	var arm := pow(absf(float(stock_points[1])), 2) + pow(absf(float(stock_points[2])), 2)
	var roll_damping := 4.0 * 190.0 * arm / (0.18 * 240.0)
	check("stock roll damping ratio stays inside the limit (0.342)", roll_damping < 1.0 and absf(roll_damping - 0.3417) < 0.01,
		roll_damping)
	for half_width: float in [0.5, 1.0]:
		var refused: Dictionary = Data.validate(_widened(half_width))
		check("+/-%.1f m skids are refused for contact rotation stiffness" % half_width, not refused.ok
			and str(refused.get("errors", [])).contains("contact rotation"), refused.get("errors", []))
	var narrow: Dictionary = Data.validate(_widened(absf(float(stock_points[1]))))
	check("the same edit at the stock half-width is admitted", narrow.ok, narrow.get("errors", []))
	print("heli skid rotation: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
