# Elevator investigation, script 2b: elevator step responses through the real FlightSession loop (servos, rpm,
# downwash lag, RK4 at 240 Hz) for the four aircraft, with in-memory variants: forced regimes, or the candidate
# repair (the E0a2 free-tail law via an injected downwash_gradient). Writes one CSV per run into OUT.
# Read-only for app/: variants edit loaded data in memory only.
# Run (repo root): $(app/get-godot.sh) --headless --path app --script "$PWD/research/flight-dynamics/elevator-repair/elev_steps.gd" -- [--only=name] [--tag=x] [--variants=prod,local,oracle_linear,freetail] [--hz=480] [--out=/abs/dir/]
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const AD := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")

## Output directory for the per-run CSVs (override with --out=/abs/dir/).
const DEFAULT_OUT := "/tmp/openrc-elevator-steps/"
const AIRCRAFT := {
	"ugly": ["res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60"],
	"extra": ["res://data/aircraft/gp_extra_300s_60.json", "gp-extra-300s-60"],
	"p51": ["res://data/aircraft/p51d_mustang_120.json", "p51d-mustang-120"],
	"avanti": ["res://data/aircraft/sebart_avanti_s_a200.json", "sebart-avanti-s-a200-p100rx"],
}
## dε/dα at the tail from each generator's own derivation table (research/<aircraft>/derivation.md); the Stik already
## declares its value in the data. Used only by the "freetail" variant.
const DEPS := { "extra": 0.4734, "p51": 0.4391, "avanti": 0.5088 }
const RHO := 1.225
const ALTITUDE := 300.0
const T_STEP := 0.5
const T_RELEASE := 2.0
const T_END := 5.0
## Pitch command amplitudes (+ = stick back, nose up).
const AMPLITUDES := [0.25, 0.5, 1.0, -0.5, -1.0]
const DEFAULT_VARIANTS := ["prod", "local", "oracle_linear"]

var _tag := ""
var _out := DEFAULT_OUT


func _initialize() -> void:
	var only: String = ""
	var variants: Array = DEFAULT_VARIANTS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--variants="):
			variants = Array(arg.trim_prefix("--variants=").split(","))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--hz="):
			Engine.physics_ticks_per_second = int(arg.trim_prefix("--hz="))
			print("physics ticks per second: %d" % Engine.physics_ticks_per_second)
	DirAccess.make_dir_recursive_absolute(_out)
	for name in AIRCRAFT:
		if not only.is_empty() and name != only:
			continue
		var session := FlightSession.new()
		session.setup(AIRCRAFT[name][0], AIRCRAFT[name][1])
		root.add_child(session)
		session.input_enabled = false
		if not session.aircraft.get("ok", false):
			print("%s: aircraft not ok: %s" % [name, session.aircraft.get("errors", [])])
			continue
		var original: Dictionary = session.aircraft
		var v0: float = session.aircraft.model.start_speed
		for variant in variants:
			if variant == "freetail":
				if not DEPS.has(name):
					continue
				var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AIRCRAFT[name][0]))
				raw.aero.surfaces.horizontal.downwash_gradient = { value = DEPS[name], unit = "1", kind = "estimated",
					source = "investigation variant: the generator's own d(eps)/d(alpha)" }
				var data: Dictionary = AD.validate_and_derive(raw)
				if not data.ok:
					print("%s freetail: derive failed: %s" % [name, data.errors])
					continue
				session.expected_aircraft_id = ""
				if not session._apply(data):
					print("%s freetail: apply failed" % name)
					continue
				var tail: Dictionary = session.aircraft.model.surfaces.horizontal
				print("%s freetail: free_slope %.3f elevator_tau %.3f downwash_per_cl %.3f lag length %.3f" % [name, tail.free_slope, tail.elevator_tau, tail.downwash_per_cl, tail.downwash_lag_length])
			else:
				_apply_variant(session.aircraft.model, original.model, variant)
			for speed in [v0, 1.4 * v0]:
				for amp in AMPLITUDES:
					if variant != "prod" and speed != v0 and absf(amp) != 1.0 and absf(amp) != 0.25:
						continue # keep the matrix small: variants at the start speed, plus ±1 and +0.25 at 1.4 V
					_run(session, name, variant, speed, amp, 0.0)
			if variant == "prod":
				_run(session, name, variant, v0, 0.5, -1.0) # throttle cut with the pull
				_run(session, name, variant, v0, 0.0, 0.0) # hands off: trim integrity
			if variant == "freetail":
				session.expected_aircraft_id = ""
				session._apply(original)
		root.remove_child(session)
		session.free()
	quit(0)


## Edits the model in place. "prod": restore. "local": the local strip/tail model everywhere.
## "oracle_linear": the attached empirical model everywhere, no stall (the textbook linear model).
func _apply_variant(model: Dictionary, pristine: Dictionary, variant: String) -> void:
	model.surfaces.attached_limit = pristine.surfaces.attached_limit
	model.surfaces.tail_local_limit = pristine.surfaces.tail_local_limit
	model.surfaces.tail_stall_end = pristine.surfaces.tail_stall_end
	for key in ["a1", "a2", "n1", "n2"]:
		model.envelope[key] = pristine.envelope[key]
	match variant:
		"local":
			model.surfaces.attached_limit = -1e9
		"oracle_linear":
			model.surfaces.attached_limit = 1e8
			model.surfaces.tail_local_limit = 2e8
			model.surfaces.tail_stall_end = 3e8
			model.envelope.a1 = 2e8
			model.envelope.a2 = 3e8
			model.envelope.n1 = 2e8
			model.envelope.n2 = 3e8


func _run(session: Node, name: String, variant: String, speed: float, amp: float, throttle_delta: float) -> void:
	var t: Dictionary = session.trim_at(speed, "level")
	if not t.ok:
		print("%s %s V %.1f: trim failed: %s" % [name, variant, speed, t.message])
		return
	session.set_start_altitude(ALTITUDE)
	session.reset()
	var sim: Node = session.sim
	var model: Dictionary = session.aircraft.model
	var mass: float = model.mass_kg
	var throw_el: float = model.controls.throw_deg.elevator
	var lag: int = session.downwash_index()
	var label := "%s_%s%s_V%02.0f_a%+.2f%s" % [name, variant, _tag, speed, amp, "_cut" if throttle_delta < 0.0 else ""]
	var f := FileAccess.open(_out + label + ".csv", FileAccess.WRITE)
	f.store_line("t,cmd,servo,elev_deg,V,alpha_deg,beta_deg,theta_deg,phi_deg,psi_deg,p_dps,q_dps,r_dps,nz,blend,My_aero,My_prop,My_other,My_gyro,My_total,Mx_total,Mz_total,alt,lag_cl,rpm,crashed")
	var crashed := 0
	var n := roundi(T_END / sim.dt())
	for i in n:
		var time: float = sim.time()
		var pitch: float = amp if time >= T_STEP and time < T_RELEASE else 0.0
		var thr: float = clampf(session.start.throttle + (throttle_delta if time >= T_STEP else 0.0), 0.0, 1.0)
		session.commands = { roll = 0.0, pitch = pitch, yaw = 0.0, throttle = thr }
		sim.inputs = session._inputs()
		# Diagnostics at the committed state before the step (the k1 evaluation of this tick).
		var s: PackedFloat64Array = sim.state
		var a: PackedFloat64Array = sim.aux
		var air: Dictionary = Air.compute(s, PackedFloat64Array([0, 0, 0]), RHO)
		var d: Dictionary = session._deflections(a)
		var lag_cl: float = a[lag] if lag >= 0 else NAN
		var blend: float = Aero.local_flow_weight(s, air, d, model)
		var aero: PackedFloat64Array = Aero.loads(s, air, d, model, RHO, lag_cl)
		var prop: PackedFloat64Array = Propulsion.loads(air.v_air, a[0], model.propulsion, RHO)
		var total: PackedFloat64Array = sim.last_loads
		var h: PackedFloat64Array = Dynamics.rotor_momentum(model, a[0])
		var w0: float = s[RB.RATE]
		var w2: float = s[RB.RATE + 2]
		var gyro_y: float = -(w2 * h[0] - w0 * h[2])
		var e := M.q_to_euler(s.slice(RB.ATT, RB.ATT + 4))
		var nz: float = -total[2] / (mass * 9.80665)
		f.store_line("%.5f,%.3f,%.4f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f,%s,%.0f,%d" % [
			time, pitch + session.trims.pitch, a[2], a[2] * throw_el, air.V, rad_to_deg(air.alpha), rad_to_deg(air.beta),
			rad_to_deg(e[1]), rad_to_deg(e[2]), rad_to_deg(e[0]),
			rad_to_deg(s[RB.RATE]), rad_to_deg(s[RB.RATE + 1]), rad_to_deg(s[RB.RATE + 2]), nz, blend,
			aero[4], prop[4], total[4] - aero[4] - prop[4], gyro_y, total[4] + gyro_y, total[3], total[5],
			-s[RB.POS + 2], str(lag_cl), a[0], crashed])
		if crashed == 1 or not sim.fault_reason.is_empty():
			break
		sim.step()
		if not session.crash.is_empty():
			crashed = 1
	f.close()
	print("%s: trim α %.2f° δe %.2f° thr %.2f; ran %d ticks%s%s" % [label, rad_to_deg(t.alpha), rad_to_deg(t.elevator), t.throttle, sim.tick,
		" CRASH" if crashed == 1 else "", (" FAULT " + sim.fault_reason) if not sim.fault_reason.is_empty() else ""])
