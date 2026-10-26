## GP-11 independent potentials, passivity and same-kernel rebound/drop fixtures.
extends SceneTree
const C := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-local-envelope/normal_compliance.gd")
const Sim := preload("res://sim/simulation.gd")
const VM := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _raw() -> Dictionary:
	var numbers := {stiffness = 1000.0, compression_damping = 3.0, rebound_damping = 8.0,
		damping_onset = 0.002, stroke = 0.02, stop_stiffness = 3000.0,
		stop_scale = 0.01, stop_exponent = 3.0, stop_damping = 5.0}
	var raw := {format = C.FORMAT}
	for key: String in numbers:
		raw[key] = {value = numbers[key], unit = C.SPECS[key][0], kind = "derived",
			source = "analytical test fixture; not aircraft calibration"}
	return raw

func _initialize() -> void:
	_algebra()
	_envelopes_and_validation()
	_kernel_drops()
	print("%d normal-compliance checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _algebra() -> void:
	var raw := _raw()
	var law := C.prepare(raw)
	_check("provenance-bearing compliance prepares", law.ok)
	if not law.ok: return
	var x := C.evaluate(law, 0.03, 0.4)
	_check("cubic stop force known answer", absf(x.elastic_force_n - 60.0) < 1e-12)
	_check("integrated cubic stop potential known answer", absf(x.potential_j - 0.525) < 1e-14)
	_check("compression damper plus engaged stop", absf(x.normal_load_n - 63.2) < 1e-12)
	_check("actual compression loss", absf(x.dissipation_w - 1.28) < 1e-12)
	_check("tangent spring stiffness", absf(x.elastic_tangent_npm - 10000.0) < 1e-10)
	var rebound := C.evaluate(law, 0.03, -0.4)
	_check("rebound damping is independent", absf(rebound.normal_load_n - 54.8) < 1e-12)
	_check("rebound loses energy while returning spring energy", rebound.dissipation_w > 0.0 and rebound.normal_load_n > 0.0)
	var before := var_to_bytes(law)
	raw.stiffness.value = 9999.0
	_check("prepared values and provenance are detached", before == var_to_bytes(law))
	for p: int in [1, 2, 3]:
		raw = _raw()
		raw.stop_exponent.value = float(p)
		law = C.prepare(raw)
		var worst := 0.0
		var passive := true
		for displacement: float in [0.0003, 0.007, 0.019, 0.021, 0.027, 0.035]:
			var h := 1e-7
			var numerical: float = (C.evaluate(law, displacement + h, 0.0).potential_j \
				- C.evaluate(law, displacement - h, 0.0).potential_j) / (2.0 * h)
			var elastic: float = C.evaluate(law, displacement, 0.0).elastic_force_n
			worst = maxf(worst, absf(numerical - elastic) / maxf(1.0, absf(elastic)))
			for speed: float in [-10.0, -0.4, -0.01, 0.0, 0.01, 0.4, 10.0]:
				var sample := C.evaluate(law, displacement, speed)
				var work_residual: float = -sample.normal_load_n * speed + elastic * speed + sample.dissipation_w
				passive = passive and sample.normal_load_n >= 0.0 and sample.dissipation_w >= 0.0 and absf(work_residual) < 1e-10
		_check("independent potential derivative p=%d" % p, worst < 2e-9, str(worst))
		_check("normal work closes and stays passive p=%d" % p, passive)
		var onset := C.evaluate(law, 1e-12, 2.0)
		_check("contact reaction tends continuously to zero p=%d" % p, onset.normal_load_n < 1e-7)
		var left := C.evaluate(law, 0.02 - 1e-10, 0.7)
		var right := C.evaluate(law, 0.02 + 1e-10, 0.7)
		_check("bottom-stop force and potential continuous p=%d" % p,
			absf(right.normal_load_n - left.normal_load_n) < 1e-5 and absf(right.potential_j - left.potential_j) < 1e-8)
	raw = _raw()
	raw.damping_onset.value = 0.0
	law = C.prepare(raw)
	var clipped := C.evaluate(law, 0.001, -2.0)
	_check("rebound clipping never attracts", clipped.clipped and clipped.normal_load_n == 0.0)
	_check("clipped loss is 2 W, not c*v^2=32 W", clipped.dissipation_w == 2.0)
	var separate := C.evaluate(law, -0.001, 200.0)
	_check("airborne query gives zero force energy and damping", separate.ok and separate.normal_load_n == 0.0 \
		and separate.potential_j == 0.0 and separate.damping_nsm == 0.0)

func _envelopes_and_validation() -> void:
	var raw := _raw()
	var law := C.prepare(raw)
	var envelope := C.bounds(law, 0.04, 3.0)
	var valid := true
	for i in 101:
		var displacement := 0.04 * i / 100.0
		for speed: float in [-3.0, -0.5, 0.0, 0.5, 3.0]:
			var sample := C.evaluate(law, displacement, speed)
			valid = valid and absf(sample.load_position_derivative_npm) <= envelope.position_derivative_bound_npm \
				and sample.load_rate_derivative_nsm <= envelope.rate_derivative_bound_nsm
	_check("declared envelope bounds both force derivatives across branches", valid)
	var bound := C.scalar_substeps(law, 0.04, 3.0, 2.0, 1.0 / 240.0, 64)
	_check("admitted scalar step meets stiffness and damping margins", bound.ok \
		and bound.angular_frequency_bound / (240.0 * bound.substeps) <= 0.1 \
		and bound.damping_rate_bound / (240.0 * bound.substeps) <= 0.25)
	var untouched := var_to_bytes(law)
	_check("excessive stiffness budget refuses instead of softening", not C.scalar_substeps(law, 0.04, 3.0, 1e-9, 1.0, 16).ok \
		and var_to_bytes(law) == untouched)
	_check("negative effective mass rejected", not C.scalar_substeps(law, 0.04, 3.0, -1.0, 0.01).ok)
	var ideal := _raw()
	ideal.damping_onset.value = 0.0
	var ideal_law := C.prepare(ideal)
	_check("ideal discontinuous damping is not falsely given a smooth integration bound", ideal_law.ok \
		and not C.bounds(ideal_law, 0.04, 3.0).continuous_onset \
		and not C.scalar_substeps(ideal_law, 0.04, 3.0, 2.0, 1.0 / 240.0).ok)
	_check("nonfinite rate rejected", not C.evaluate(law, 0.01, NAN).ok)
	_check("invalid displacement envelope rejected", not C.bounds(law, -1.0, 1.0).ok)
	for key: String in C.SPECS:
		var malformed := _raw()
		malformed[key].source = ""
		_check("missing provenance rejected: " + key, not C.prepare(malformed).ok)
	var malformed := _raw()
	malformed.stop_exponent.value = 1.5
	_check("unsupported noninteger stop exponent rejected", not C.prepare(malformed).ok)
	malformed = _raw()
	malformed.stop_scale.value = 0.0
	_check("zero stop scale rejected", not C.prepare(malformed).ok)
	malformed = _raw()
	malformed.stiffness.unit = "N"
	_check("wrong stiffness dimension rejected", not C.prepare(malformed).ok)
	malformed = _raw()
	malformed.bounce_multiplier = 2.0
	_check("undeclared bounce parameter rejected", not C.prepare(malformed).ok)

func _drop(law: Dictionary, mass: float, rate: int, speed: float, gravity := 0.0, duration_s := 0.5, initial_compression := 0.0) -> Dictionary:
	Engine.physics_ticks_per_second = rate
	var sim := Sim.new()
	sim.mass = mass
	sim.gravity = gravity
	sim.continuous = PackedFloat64Array([0.0])
	var model := VM.new()
	model.continuous_size = 1
	model.identity = {law = C.LAW, fixture = "scalar-effective-normal-compliance"}
	model.stage = func(body: PackedFloat64Array, _values: PackedFloat64Array, _t: float) -> Dictionary:
		var contact := C.evaluate(law, body[2], body[5])
		return {loads = PackedFloat64Array([0.0, 0.0, -contact.normal_load_n, 0.0, 0.0, 0.0]),
			derivative = PackedFloat64Array([contact.dissipation_w]), rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])}
	# Same law and same time grid across each mass pair; only m changes.
	model.substeps = func(_body: PackedFloat64Array, _values: PackedFloat64Array, _t: float) -> int: return 8
	var initial := RB.make_state(M.v3(0.0, 0.0, initial_compression), M.v3(0.0, 0.0, speed), M.q_from_euler(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	var installed := sim.set_model(model) and sim.reset(initial)
	if not installed:
		printerr("drop reset failed: ", sim.fault_reason)
		sim.free()
		return {ok = false, error = INF, peak = 0.0, speed = NAN, loss = 0.0, monotone = false, repeats = false}
	var energy0: float = 0.5 * mass * speed * speed - mass * gravity * initial_compression + C.evaluate(law, initial_compression, speed).potential_j
	var maximum_error := 0.0
	var peak := 0.0
	var monotone := true
	var last_loss := 0.0
	for _tick in int(rate * duration_s):
		sim.step()
		var sample := C.evaluate(law, sim.state[2], sim.state[5])
		var total: float = 0.5 * mass * sim.state[5] * sim.state[5] - mass * gravity * sim.state[2] + sample.potential_j + sim.continuous[0]
		maximum_error = maxf(maximum_error, absf(total - energy0))
		peak = maxf(peak, sim.state[2])
		monotone = monotone and sim.continuous[0] >= last_loss - 1e-15
		last_loss = sim.continuous[0]
	var checkpoint := sim.checkpoint()
	for _tick in 5: sim.step()
	var end_state := var_to_bytes(sim.state)
	var end_local := var_to_bytes(sim.continuous)
	var restored := sim.restore_checkpoint(checkpoint)
	for _tick in 5: sim.step()
	var result := {ok = installed and sim.fault_reason.is_empty(), error = maximum_error,
		peak = peak, compression = sim.state[2], speed = sim.state[5], loss = sim.continuous[0], monotone = monotone,
		repeats = restored and end_state == var_to_bytes(sim.state) and end_local == var_to_bytes(sim.continuous)}
	sim.free()
	return result

func _kernel_drops() -> void:
	var original_rate := Engine.physics_ticks_per_second
	var raw := _raw()
	raw.compression_damping.value = 0.0
	raw.rebound_damping.value = 0.0
	raw.stop_damping.value = 0.0
	raw.stop_stiffness.value = 0.0
	var linear := C.prepare(raw)
	for mass: float in [2.0, 4.0]:
		var previous_error := INF
		for rate: int in [120, 240, 480]:
			var r := _drop(linear, mass, rate, 1.0)
			_check("elastic drop same-kernel completes %.1f/%d" % [mass, rate], r.ok)
			_check("elastic rebound approaches analytic speed %.1f/%d" % [mass, rate], absf(r.speed + 1.0) < 2e-5, str(r))
			_check("analytic peak compression %.1f/%d" % [mass, rate], absf(r.peak - sqrt(mass / 1000.0)) < 2e-4)
			_check("elastic refinement improves work error %.1f/%d" % [mass, rate], r.error < previous_error and r.error < 2e-5, str(r.error))
			_check("checkpoint repeats drop and work bytes %.1f/%d" % [mass, rate], r.repeats and r.loss == 0.0)
			previous_error = r.error
			print("GP11 elastic mass=", mass, " rate=", rate, " error_J=", r.error, " peak_m=", r.peak)
	var nonlinear := C.prepare(_raw())
	var light := _drop(nonlinear, 2.0, 480, 1.0)
	var heavy := _drop(nonlinear, 4.0, 480, 1.0)
	_check("same gear with greater mass compresses further", light.ok and heavy.ok and heavy.peak > light.peak)
	_check("progressive stop reduces peak versus same linear gear", light.peak < sqrt(2.0 / 1000.0) and heavy.peak < sqrt(4.0 / 1000.0))
	_check("damped heavy and light drops naturally rebound", light.speed < 0.0 and heavy.speed < 0.0)
	_check("normal loss ledger closes with finite compliance", light.error < 2e-5 and heavy.error < 2e-5, str([light, heavy]))
	_check("damping work is positive and monotone", light.loss > 0.0 and heavy.loss > 0.0 and light.monotone and heavy.monotone)
	var phase_worst_previous := INF
	for rate: int in [120, 240, 480]:
		var phase_worst := 0.0
		for phase: float in [0.0, 0.23, 0.5, 0.81]:
			var shifted := _drop(linear, 2.0, rate, 1.0, 0.0, 0.5, -phase / rate)
			phase_worst = maxf(phase_worst, shifted.error)
		_check("contact-onset phase envelope refines at %d Hz" % rate, phase_worst < phase_worst_previous and phase_worst < 5e-5, str(phase_worst))
		phase_worst_previous = phase_worst
	raw = _raw()
	raw.compression_damping.value = 60.0
	raw.rebound_damping.value = 60.0
	raw.stop_stiffness.value = 0.0
	raw.stop_damping.value = 0.0
	var static_law := C.prepare(raw)
	for mass: float in [2.0, 4.0]:
		var settled := _drop(static_law, mass, 240, 0.0, 9.80665, 3.0)
		_check("same-gear static sag equals mg/k for %.1f kg" % mass, settled.ok and absf(settled.compression - mass * 9.80665 / 1000.0) < 1e-7, str(settled))
		_check("static equilibrium rests without velocity clamp for %.1f kg" % mass, absf(settled.speed) < 1e-7)
		_check("gravity and damper work close for %.1f kg" % mass, settled.error < 2e-5 and settled.monotone)
	Engine.physics_ticks_per_second = original_rate
