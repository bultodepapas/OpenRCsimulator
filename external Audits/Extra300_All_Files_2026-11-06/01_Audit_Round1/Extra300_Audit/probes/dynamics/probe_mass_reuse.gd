extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Flight = preload("res://physics/glow/flight.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var s = Session.new()
	s.input_enabled = false
	s.soft_hull_contacts = true
	s.setup("res://data/aircraft/gp_extra_300s_60.json", "gp-extra-300s-60")
	if not s.is_flyable():
		printerr("Extra setup failed: ",s.start_error)
		quit(1)
		return
	var p: Dictionary = s.aircraft.model.propulsion.glow
	if p.has("feed_line") or p.has("fuel_feed"):
		printerr("Extra is not the expected simple tank")
		quit(1)
		return
	var cap: float = p.capacity_fuel_kg
	var floor_mass: float = p.unusable_fuel_kg
	var samples: PackedFloat64Array = PackedFloat64Array([-0.000001, -0.0, 0.0, floor_mass - 1e-12, floor_mass, floor_mass + 1e-12, float(p.reference_fuel_kg), cap, cap + 0.000001])
	for i in 1001:
		samples.append(cap * float(i) / 1000.0)
	var mismatch: int = 0
	for amount: float in samples:
		var values: PackedFloat64Array = s.sim.continuous.duplicate()
		values[1] = amount
		values[Flight.LINE_FUEL_INDEX] = 0.0
		var stage: Dictionary = Flight._stage_mass_context(s, values)
		var direct: Dictionary = Flight.properties(s, amount, 0.0)
		if not stage.get("ok",false) or not direct.get("ok",false) or var_to_bytes(stage.properties) != var_to_bytes(direct):
			mismatch += 1
			print("MISMATCH ", amount, " ",stage," ",direct)
	for amount: float in [NAN,INF,-INF]:
		var values: PackedFloat64Array = s.sim.continuous.duplicate()
		values[1] = amount
		var a: Dictionary = Flight._stage_mass_context(s,values)
		var b: Dictionary = Flight.properties(s,amount,0.0)
		if a.get("ok", false) or b.get("ok", false):
			mismatch += 1
			print("NONFINITE_MISMATCH ",amount," ",a," ",b)
	print("MASS_EQUALITY samples=",samples.size()," nonfinite=3 mismatches=",mismatch," cap=",cap," floor=",floor_mass," reference=",p.reference_fuel_kg)
	print("MASS_REUSE_PROBE ","PASS" if mismatch == 0 else "FAIL")
	s.free()
	quit(0 if mismatch == 0 else 1)
