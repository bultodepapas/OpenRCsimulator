extends SceneTree

const Flight = preload("res://sim/flight_session.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Glow = preload("res://physics/glow/flight.gd")
const Log = preload("res://sim/flight_log.gd")
const Reader = preload("res://tools/flight_log_cli.gd")
var checks := 0
var failures := 0
var report := {}
var path := "/workspace/scratch/b3c27b2e84ee/extra300_audit/round2/dynamics/fuel-transitions.orfl"

func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks += 1
	if not ok: failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, str(detail)])

func max_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size(): return INF
	var result := 0.0
	for i in a.size(): result = maxf(result, absf(a[i] - b[i]))
	return result

func parallel(r: PackedFloat64Array) -> PackedFloat64Array:
	var x: float = r[0]
	var y: float = r[1]
	var z: float = r[2]
	return PackedFloat64Array([y*y+z*z,x*x+z*z,x*x+y*y,-x*y,-x*z,-y*z])

# Independent one-box fixed-datum formula, with reference wet CG as origin.
func mass_oracle(model: Dictionary, fuel: float) -> Dictionary:
	var install: Dictionary = model.propulsion.glow
	var dm: float = fuel - float(install.reference_fuel_kg)
	var mass: float = float(model.mass_kg) + dm
	var r: PackedFloat64Array = install.tank_position
	var size: PackedFloat64Array = install.tank_size
	var cg: PackedFloat64Array = M.scale(r, dm / mass)
	var box: PackedFloat64Array = parallel(r)
	box[0] += (size[1]*size[1] + size[2]*size[2])/12.0
	box[1] += (size[0]*size[0] + size[2]*size[2])/12.0
	box[2] += (size[0]*size[0] + size[1]*size[1])/12.0
	var p: PackedFloat64Array = parallel(cg)
	var inertia: PackedFloat64Array = model.inertia.duplicate()
	for i in 6: inertia[i] += dm * box[i] - mass * p[i]
	return {mass = mass, cg = cg, inertia = inertia}

func momentum(s: PackedFloat64Array, prop: Dictionary, props: Dictionary, rpm: float) -> Dictionary:
	var w: PackedFloat64Array = s.slice(RB.RATE,RB.RATE+3)
	var v: PackedFloat64Array = s.slice(RB.VEL,RB.VEL+3)
	var vc: PackedFloat64Array = M.add(v, M.cross(w,props.cg_body_m))
	return {p = M.scale(vc,props.mass_kg), h = M.add(RB.inertia_mul(props.inertia,w),
		M.scale(prop.axis,float(prop.rotor_inertia)*rpm*TAU/60.0))}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.physics_ticks_per_second = 240
	var f = Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup("res://data/aircraft/gp_extra_300s_60.json","gp-extra-300s-60")
	check("stock Extra prepared",f.is_flyable(),f.start_error)
	if not f.is_flyable(): quit(1); return
	var install: Dictionary = f.aircraft.model.propulsion.glow
	check("one fixed tank, no feed line",not install.has("feed_line"))
	var rows: Array = []
	for fill: float in [1.0,0.75,0.5,0.25]:
		check("selection accepted %.2f" % fill,f.set_fuel_start_fill(fill))
		f.reset()
		var actual: Dictionary = f.mass_properties()
		var oracle: Dictionary = mass_oracle(f.aircraft.model,float(f.sim.continuous[1]))
		var fuel: float = f.sim.continuous[1]
		var fuelerr: float = absf(fuel - fill*float(install.capacity_fuel_kg))
		var merr: float = absf(actual.mass_kg - oracle.mass)
		var cerr: float = max_diff(actual.cg_body_m,oracle.cg)
		var ierr: float = max_diff(actual.inertia,oracle.inertia)
		check("reset mass formula %.2f" % fill,f.is_flyable() and actual.ok and fuelerr < 1e-15 and merr < 1e-12 and cerr < 1e-12 and ierr < 1e-12,
			{fuel=fuel,mass=actual.mass_kg,cg=actual.cg_body_m,fuel_error=fuelerr,mass_error=merr,cg_max_error=cerr,inertia_max_error=ierr})
		rows.append({fill=fill,fuel_kg=fuel,mass_kg=actual.mass_kg,cg=Array(actual.cg_body_m),fuel_error=fuelerr,mass_error=merr,cg_error=cerr,inertia_error=ierr})
	report.fills = rows
	var field: Dictionary = FieldLoader.load_from()
	check("field installed",field.ok and f.set_field(field.field))
	f.start_choice = Flight.START_RUNWAY
	f.reset()
	check("selected-fill runway starts stopped",f.is_flyable() and f.sim.tick==0 and f.sim.continuous[0]==0.0 and not f.engine_running and not f.glow_state().running, f.start_error)
	var old_state: PackedFloat64Array = f.sim.state.duplicate()
	var old_fuel: float = f.sim.continuous[1]
	var old_rpm: float = f.sim.continuous[0]
	var prime: float = install.settings.starter_prime_kg
	var started: bool = f.glow_start()
	var sample: Dictionary = f.mass_properties()
	var before_hypothetical: Dictionary = momentum(old_state,f.aircraft.model.propulsion,sample,old_rpm)
	var after: Dictionary = momentum(f.sim.state,f.aircraft.model.propulsion,sample,f.sim.continuous[0])
	var pe: float = M.norm(M.sub(before_hypothetical.p,after.p))
	var he: float = M.norm(M.sub(before_hypothetical.h,after.h))
	check("starter consumes prime and starts",started and f.propulsion_source_running() and absf((old_fuel-f.sim.continuous[1])-prime)<1e-15 and f.sim.continuous[0]==install.settings.minimum_start_rpm,
		{old_fuel=old_fuel,new_fuel=f.sim.continuous[1],prime=prime,rpm=f.sim.continuous[0],linear_residual=pe,angular_residual=he})
	check("starter impulse preserves post-prime linear and angular momentum",pe<1e-12 and he<1e-12)
	report.starter = {fuel_before_kg=old_fuel,fuel_after_kg=f.sim.continuous[1],prime_kg=prime,rpm=f.sim.continuous[0],linear_residual=pe,angular_residual=he}
	# Record actual F6/F7 method interventions and replay the exact affected arrays.
	DirAccess.remove_absolute(path)
	var logger = Log.new(f)
	check("log starts",logger.start(path)==OK)
	for tick in 16:
		if tick==4: check("F6 cut accepted",f.glow_cut())
		if tick==8: check("F7 restart accepted",f.glow_start())
		f.sim.step()
		if not f.sim.fault_reason.is_empty(): break
	check("16 ticks complete",f.sim.tick==16 and f.sim.fault_reason.is_empty(),f.sim.fault_reason)
	check("log closes",logger.stop()==OK)
	var read: Dictionary = Reader.inspect(path)
	check("log inspection accepts",read.get("ok",false),read.get("error",""))
	var replay_count := 0
	var mismatches := 0
	var interventions: Array = []
	if read.get("ok",false):
		var prepared: Dictionary = Reader.prepare_replay(read.header)
		check("log replay prepares",prepared.get("ok",false),prepared.get("message",""))
		if prepared.get("ok",false):
			var observer = Log.new(prepared.flight)
			var stream = FileAccess.open(path,FileAccess.READ)
			stream.seek(8)
			Log.read_packet(stream)
			var first := true
			while stream.get_position()<stream.get_length():
				var block: Dictionary = Log.read_packet(stream).value
				if block.kind=="footer": break
				for row: Dictionary in block.rows:
					if first: first=false; continue
					if not row.intervention.is_empty(): interventions.append({tick=row.tick,keys=row.intervention.keys()})
					for key in row.intervention: prepared.flight.sim.set(key,row.intervention[key].duplicate())
					prepared.flight.sim.inputs=row.inputs.duplicate()
					prepared.flight.sim.step()
					replay_count += 1
					if not Reader.disagreement(row,observer._sample({})).is_empty(): mismatches += 1
			stream.close()
			prepared.flight.free()
	check("cut and restart replay exact",replay_count==16 and mismatches==0 and interventions.size()==2,{ticks=replay_count,mismatches=mismatches,interventions=interventions})
	report.log = {ticks=replay_count,mismatches=mismatches,interventions=interventions}
	f.reset()
	check("runway reset refuels and stops",f.is_flyable() and f.sim.continuous[0]==0.0 and not f.engine_running and absf(f.sim.continuous[1] - 0.25*install.capacity_fuel_kg)<1e-15)
	report.checks = checks
	report.failures = failures
	var output = FileAccess.open("/workspace/scratch/b3c27b2e84ee/extra300_audit/round2/dynamics/fuel-transition-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ",true,true)); output.close()
	f.free()
	print("FUEL-TRANSITION-PROBE %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
