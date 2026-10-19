extends SceneTree
const Sample := preload("res://sim/fuel_sample.gd")
const Flight := preload("res://sim/flight_session.gd")
var checks := 0
var failed := 0
func check(label: String, accepted: bool) -> void:
	checks += 1
	if not accepted: failed += 1
	print(("ok " if accepted else "FAIL ") + label)
func _initialize() -> void:
	var properties := {ok = true, mass_kg = 3.0, cg_body_m = PackedFloat64Array([0.01, -0.02, 0.03]),
		inertia = PackedFloat64Array([1.0, 2.0, 3.0, 0.0, 0.0, 0.0]),
		inverse = PackedFloat64Array([1.0, 0.5, 1.0/3.0, 0.0, 0.0, 0.0])}
	var tanks: Array = [
		{id="left", fuel="water_fixture", family="fixture", density_kg_m3=1000.0, capacity_kg=0.4,
			unusable_kg=0.01, reserve_kg=0.05, reserve_estimated=false},
		{id="right", fuel="oil_fixture", family="fixture", density_kg_m3=800.0, capacity_kg=0.8,
			unusable_kg=0.02, reserve_kg=0.1, reserve_estimated=true}]
	var amounts := {left=0.2, right=0.4}
	var sample: Dictionary = Sample.build(properties, tanks, amounts, 240, 1.0, true)
	check("mass sample carries exact accepted tick and time", sample.ok and sample.tick == 240 and sample.time_s == 1.0)
	check("different blend densities are converted per store", is_equal_approx(sample.volume_ml, 700.0))
	check("volume fill and weighted reserve use capacities", is_equal_approx(sample.fill_fraction, 0.5) and is_equal_approx(sample.reserve_fraction, 0.125))
	check("unusable residue remains onboard and is excluded from usable fuel", is_equal_approx(sample.fuel_remaining_kg, 0.6) and is_equal_approx(sample.fuel_usable_kg, 0.57))
	check("estimated reserve provenance is explicit", sample.reserve_estimated and sample.reserve_basis == "estimated reserve")
	var with_line: Array = tanks.duplicate(true)
	with_line.append({id="line", kind="feed_line", fuel="water_fixture", family="fixture",
		density_kg_m3=1000.0, capacity_kg=0.002, unusable_kg=0.0, reserve_kg=0.0, reserve_estimated=false})
	var dry_line: Dictionary = Sample.build(properties, with_line, {left=0.2,right=0.4,line=0.0},0,0.0,true)
	check("an empty delivery line cannot mislabel healthy main tanks as low fuel", dry_line.ok and not dry_line.low_fuel and dry_line.stores[2].kind == "feed_line")
	var reserve_main: Dictionary = Sample.build(properties, with_line, {left=0.04,right=0.4,line=0.002},0,0.0,true)
	check("main reserve still warns with a primed line", reserve_main.ok and reserve_main.low_fuel)
	sample.cg_body_m[0] = 123.0
	sample.stores[0].remaining_kg = 123.0
	check("observation is detached from owner and store definitions", properties.cg_body_m[0] == 0.01 and amounts.left == 0.2)
	check("constant-mass aircraft does not invent fuel state", not Sample.build(properties, [], {}, 0, 0.0, false).finite_fuel)
	for amount: float in [-0.1, 0.41, NAN, INF]:
		check("invalid resource amount refused %s" % amount, not Sample.build(properties,tanks,{left=amount,right=0.4},0,0.0,true).ok)
	check("missing store refused", not Sample.build(properties,tanks,{left=0.2},0,0.0,true).ok)
	check("unrecognized store refused", not Sample.build(properties,tanks,{left=0.2,right=0.4,extra=0.1},0,0.0,true).ok)
	var bad: Dictionary = properties.duplicate(true)
	bad.cg_body_m[0] = NAN
	check("nonfinite CG refused", not Sample.build(bad,tanks,amounts,0,0.0,true).ok)
	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.setup("res://data/aircraft/stik_glow_61fx_2t.json")
	var full: Dictionary = flight.mass_properties()
	check("live full tank reports capacity volume", full.ok and is_equal_approx(full.volume_ml,350.0) and full.fill_fraction == 1.0)
	var saved: PackedByteArray = var_to_bytes(flight.sim.checkpoint())
	for i in 3: flight.mass_properties()
	check("mass queries cannot advance or mutate physics", saved == var_to_bytes(flight.sim.checkpoint()))
	flight.sim.step()
	var next: Dictionary = flight.mass_properties()
	check("sample clock matches committed tick", next.tick == flight.sim.tick and next.time_s == flight.sim.time() and next.volume_ml < full.volume_ml)
	flight.free()
	print("FUEL sample: %d checks, %d failed" % [checks,failed])
	quit(1 if failed else 0)
