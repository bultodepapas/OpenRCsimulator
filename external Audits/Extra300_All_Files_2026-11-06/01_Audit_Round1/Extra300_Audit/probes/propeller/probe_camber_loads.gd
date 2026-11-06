extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const P := preload("res://physics/propulsion.gd")
const G := preload("res://physics/glow/propeller.gd")
const M := preload("res://physics/math3d.gd")
var failures: int = 0
var checks: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label)

func flat(rows: Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for row: Array in rows:
		result.append(float(row[0]))
		result.append(float(row[1]))
	return result

func norm(v: PackedFloat64Array) -> float:
	return sqrt(M.dot(v, v))

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Expected -- <camber_tables.json> <output.json>")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var loaded: Dictionary = AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
	check("stock Extra model validates", loaded.get("ok", false))
	if not loaded.get("ok", false):
		quit(1)
		return
	var stock: Dictionary = loaded.model.propulsion
	var candidate: Dictionary = stock.duplicate(true)
	candidate.normal_force = flat(data.normal_force)
	candidate.pfactor_moment = flat(data.pfactor_moment)
	var axis: PackedFloat64Array = P.axis(stock)
	var vertical: PackedFloat64Array = M.cross(axis, M.v3(0.0, 1.0, 0.0))
	vertical = M.scale(vertical, 1.0 / norm(vertical))
	var horizontal: PackedFloat64Array = M.cross(vertical, axis)
	var rho: float = 1.225
	var rpm: float = 12000.0
	var angle: float = deg_to_rad(10.0)
	var rows: Array = []
	for advance: float in [0.3, 0.5, 0.7, 0.8]:
		var along: float = advance * rpm / 60.0 * float(stock.diameter)
		var gp: Dictionary = G.evaluate(rpm, along, rho, stock.glow.propeller)
		check("installed annular propeller valid at J %.2f" % advance, gp.get("ok", false))
		var python_row: Dictionary = {}
		for entry: Dictionary in data.rows:
			if absf(float(entry.J) - advance) < 1e-12:
				python_row = entry
		check("Python and production installed thrust agree J %.2f" % advance,
			absf(float(gp.thrust_n) - float(python_row.thrust_installed_n)) < 1e-10)
		for transverse: PackedFloat64Array in [vertical, horizontal]:
			var label: String = "vertical" if transverse == vertical else "horizontal"
			var velocity: PackedFloat64Array = M.add(M.scale(axis, along), M.scale(transverse, along * tan(angle)))
			var stock_nf: PackedFloat64Array = P.normal_force(velocity, rpm, stock, rho)
			var new_nf: PackedFloat64Array = P.normal_force(velocity, rpm, candidate, rho)
			var stock_pf: PackedFloat64Array = P.pfactor_moment(velocity, rpm, stock, rho)
			var new_pf: PackedFloat64Array = P.pfactor_moment(velocity, rpm, candidate, rho)
			var stock_tq: PackedFloat64Array = P.thrust_torque(velocity, rpm, stock, rho)
			var new_tq: PackedFloat64Array = P.thrust_torque(velocity, rpm, candidate, rho)
			var stock_loads: PackedFloat64Array = P.loads(velocity, rpm, stock, rho)
			var new_loads: PackedFloat64Array = P.loads(velocity, rpm, candidate, rho)
			check("shaft thrust and torque bit-identical J %.2f %s" % [advance, label], stock_tq.to_byte_array() == new_tq.to_byte_array())
			var normal_scale: float = rho * pow(rpm / 60.0, 2.0) * pow(float(stock.diameter), 4.0) * sin(angle)
			var moment_scale: float = normal_scale * float(stock.diameter)
			check("independent normal-force magnitude J %.2f %s" % [advance, label],
				absf(norm(stock_nf) - float(python_row.Cn_stock) * normal_scale) < 1e-12
				and absf(norm(new_nf) - float(python_row.Cn_consistent) * normal_scale) < 1e-12)
			check("independent P-factor magnitude J %.2f %s" % [advance, label],
				absf(norm(stock_pf) - float(python_row.Cm_stock) * moment_scale) < 1e-12
				and absf(norm(new_pf) - float(python_row.Cm_consistent) * moment_scale) < 1e-12)
			check("both crossflow effects oppose transverse flow J %.2f %s" % [advance, label],
				M.dot(new_nf, transverse) < 0.0 and M.dot(new_pf, transverse) < 0.0)
			var delta_wrench: Array = []
			for k: int in 6:
				delta_wrench.append(new_loads[k] - stock_loads[k])
			rows.append({"J": advance, "rpm": rpm, "rho_kg_m3": rho, "disc_angle_deg": 10.0,
				"direction": label, "velocity_body_mps": Array(velocity), "shaft_thrust_n": stock_tq[0],
				"shaft_torque_nm": stock_tq[1], "normal_stock_n": norm(stock_nf), "normal_consistent_n": norm(new_nf),
				"pfactor_stock_nm": norm(stock_pf), "pfactor_consistent_nm": norm(new_pf),
				"stock_wrench": Array(stock_loads), "consistent_wrench": Array(new_loads), "delta_wrench": delta_wrench})
		var aligned: PackedFloat64Array = M.scale(axis, along)
		check("axis-aligned control has negligible crossflow J %.2f" % advance,
			norm(P.normal_force(aligned, rpm, candidate, rho)) < 1e-12
			and norm(P.pfactor_moment(aligned, rpm, candidate, rho)) < 1e-12)
	check("zero RPM control has no crossflow terms",
		norm(P.normal_force(M.v3(30.0, 1.0, 4.0), 0.0, candidate, rho)) == 0.0
		and norm(P.pfactor_moment(M.v3(30.0, 1.0, 4.0), 0.0, candidate, rho)) == 0.0)
	var report: Dictionary = {"source_revision": data.source_revision, "engine": Engine.get_version_info(),
		"checks": checks, "failures": failures, "rows": rows,
		"scope": "Production Propulsion loads using only in-memory alternative generator tables. No aircraft source changed; no physical flight calibration asserted."}
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("CAMBER LOAD PROBE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
