## A36 R7-F02: an admitted electric motor must be resolved by the fixed 240 Hz step. The stock quad's shaft decay rate
## is h*lambda = 0.197 at its declared maximum speed; a custom 0.001 ohm motor (h*lambda = 11.76) passed the strict
## loader and then failed its first arming tick. Flight admission now refuses it with the reason, before any flight exists.
extends SceneTree

const Data := preload("res://physics/multirotor_data.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Session := preload("res://sim/multirotor/session.gd")

const STOCK := "res://data/multirotors/openrc-fpv5-x1.json"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _prepared(raw: Dictionary) -> Dictionary:
	var admitted: Dictionary = Data.load_document(raw, "a36-r7-motor")
	if not admitted.ok:
		return {}
	var prepared: Dictionary = Data.prepare(admitted.data, admitted.sha256)
	return prepared.get("prepared", {}) if prepared.get("ok", false) else {}


func _run() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STOCK))
	var stock := _prepared(raw)
	check("stock quad admits and prepares", not stock.is_empty())
	if stock.is_empty():
		_finish()
		return
	var stock_ratio: float = Plant.electric_motor_step_ratio(stock)
	# Independent: h*(1/(R Kv^2) + 2 kQ Omega_max)/J with the stock powertrain and rotor law.
	var pt: Dictionary = raw.powertrain
	var law: Dictionary = raw.rotor_law
	var expected: float = (1.0 / (float(pt.resistance.value) * float(pt.kv.value) * float(pt.kv.value))
		+ 2.0 * float(law.torque_coefficient.value) * float(law.max_speed.value)) / 7.0e-6 / 240.0
	check("stock motor step ratio matches the independent formula (0.197)", absf(stock_ratio - expected) < 1.0e-9
		and absf(stock_ratio - 0.19725726592520587) < 1.0e-6, stock_ratio)
	var created: Dictionary = Plant.create(stock, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	check("stock plant is created", created.ok, created.get("errors", []))
	var custom_raw: Dictionary = raw.duplicate(true)
	custom_raw.powertrain.resistance.value = 0.001
	custom_raw.powertrain.resistance.kind = "estimated"
	custom_raw.powertrain.resistance.source = "estimated: A36 R7-F02 synthetic low-resistance motor; not a real motor"
	var custom := _prepared(custom_raw)
	check("the R7 custom motor still passes the strict loader", not custom.is_empty())
	if not custom.is_empty():
		var ratio: float = Plant.electric_motor_step_ratio(custom)
		check("the custom motor's step ratio at maximum speed is 11.85 (11.76 at hover)", absf(ratio - 11.8513) < 0.001, ratio)
		var reason: String = Plant.motor_step_error(custom)
		check("flight admission refuses the unresolved motor with its reason", reason.contains("too fast for the 240 Hz step"),
			reason)
		check("the stock motor is admitted", Plant.motor_step_error(stock).is_empty())
		# The real session route: the custom file is refused before a flight exists; the stock file prepares.
		var dir := "user://a36-r7-motor"
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir + "/custom-motor.json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(custom_raw, "  "))
		file.close()
		var session: Node = Session.new()
		root.add_child(session)
		var custom_ok: bool = session.prepare({}, {data_path = path})
		check("the session refuses the custom motor file before any flight", not custom_ok
			and str(session.load_error).contains("too fast for the 240 Hz step"), session.load_error)
		var stock_ok: bool = session.prepare({}, {})
		check("the same session then prepares the stock quad", stock_ok, session.load_error)
		session.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish()


func _finish() -> void:
	print("multirotor motor step: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
