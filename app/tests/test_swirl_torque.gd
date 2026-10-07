# E0b6: torque-based strength and nominal core-regularized angular-momentum audit.
# The cylinder is a diagnostic assumption, not a measured wake or a coupled balance.
extends SceneTree
const AD = preload("res://physics/aircraft_data.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const S = preload("res://physics/slipstream.gd")
const Prop = preload("res://physics/propulsion.gd")
var checks: int = 0
var failed: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("%s %s" % ["ok" if ok else "FAIL", label])

func _initialize() -> void:
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var loaded: Dictionary = AD.validate_and_derive(raw)
	check("provenanced swirl fixture accepted", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var model: Dictionary = loaded.model
	var prop: Dictionary = model.propulsion
	var rho: float = 1.225
	for speed: float in [0.0, 5.0, 15.0, 25.0]:
		var velocity: PackedFloat64Array = PackedFloat64Array([speed, 0.0, 0.0])
		var tq: PackedFloat64Array = Prop.thrust_torque(velocity, prop.max_rpm, prop, rho)
		var wake: Dictionary = S.wake(velocity, tq[0], tq[1], prop, rho)
		var negative: Dictionary = S.wake(velocity, tq[0], -tq[1], prop, rho)
		var doubled: Dictionary = S.wake(velocity, tq[0], 2.0*tq[1], prop, rho)
		var scaled: Dictionary = S.wake(velocity, 2.0*tq[0], 2.0*tq[1], prop, 2.0*rho)
		check("signed strength linear in shaft torque at %.0f m/s" % speed,
			wake.swirl > 0.0 and negative.swirl == -wake.swirl and doubled.swirl == 2.0*wake.swirl)
		check("density similarity at fixed Ct/Cp and rpm at %.0f m/s" % speed,
			wake.swirl == scaled.swirl and wake.dv == scaled.dv and wake.rs == scaled.rs)
		var kw: float = wake.dv/wake.w
		var disc_mass: float = rho*PI*pow(prop.diameter/2.0, 2)*(wake.u+wake.w)
		var nominal_flux: float = sampled_flux(wake, prop, model, rho, wake.vs)
		var core_fraction: float = 1.0-pow(wake.core/wake.rs, 2)/2.0
		var expected: float = tq[1]*prop.slipstream.swirl_factor*kw/2.0*core_fraction
		check("nominal far-wake flux includes solid core deficit at %.0f m/s" % speed,
			absf(nominal_flux-expected) < 2e-6*absf(expected))
		check("ideal contracted cylinder preserves disc mass at %.0f m/s" % speed,
			absf(rho*PI*wake.rs*wake.rs*wake.vs-disc_mass) < 1e-12)
		var local_flux: float = sampled_flux(wake, prop, model, rho, wake.u+wake.dv)
		check("attenuated local speed further changes diagnostic flux at %.0f m/s" % speed,
			absf(local_flux/nominal_flux-(wake.u+wake.dv)/wake.vs) < 1e-12)
	# The 1 m/s divisor is a numerical floor, not measured mass flow. Verify its finite, continuous join.
	var left: Dictionary = S.wake(PackedFloat64Array([1.0-1e-8,0,0]), 0.0, 1.0, prop, rho)
	var right: Dictionary = S.wake(PackedFloat64Array([1.0+1e-8,0,0]), 0.0, 1.0, prop, rho)
	check("swirl speed-floor join is continuous", absf(left.swirl-right.swirl) < 1e-6)
	check("zero torque gives exactly zero strength", S.wake(PackedFloat64Array([0,0,0]), 10.0, 0.0, prop, rho).swirl == 0.0)
	print("E0b6 torque: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

# Sample the runtime immersion velocity around a thin probe at radius r. No production strength formula
# is repeated here; integrate rho*U*r*v_theta over concentric annuli and compare to the closed-form audit.
func sampled_flux(wake: Dictionary, prop: Dictionary, model: Dictionary, rho: float, axial_speed: float) -> float:
	var probe_prop: Dictionary = prop.duplicate(true)
	probe_prop.slipstream.erase("edge_fraction")
	var piece: Dictionary = {surface = "vertical", area = 1e-10, span = 1e-9,
		span_dir = PackedFloat64Array([0,0,1]), chords = PackedFloat64Array([0.1,0.1])}
	var total: float = 0.0
	var dr: float = wake.rs/2048.0
	for index: int in 2048:
		var radius: float = (index+0.5)*dr
		piece.root = PackedFloat64Array([1.0,radius,0.0])
		var point: Dictionary = S.immersion(piece, wake, PackedFloat64Array([0,0,0]),
			probe_prop, PackedFloat64Array([0,0,0]), 0.0, model)
		total += rho*axial_speed*radius*point.swirl[2]*TAU*radius*dr
	return total
