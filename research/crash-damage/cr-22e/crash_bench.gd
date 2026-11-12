## CR-22e crash/ground-contact frame bench. Run through run.py (rendered 1920x1080, OpenGL).
## Flags: --reference (synchronous archive/valuation, no crash-frame deferral), --sync-valuation,
## --hide-effects, --hide-wreck, --no-ui; scenarios: hard (dive into turf), slide (belly slide).
extends SceneTree
## Crash/ground-contact frame-cost bench: main.tscn, rendered, per-frame split into
## physics (all _physics_process), process (all _process) and the remainder (render + engine).
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")

class Stamp extends Node:
	var bench
	var first := true
	func _process(_d: float) -> void:
		if first: bench.p_begin = Time.get_ticks_usec()
		else: bench.p_end = Time.get_ticks_usec()
	func _physics_process(_d: float) -> void:
		if first: bench.ph_begin = Time.get_ticks_usec()
		else:
			bench.ph_sum += Time.get_ticks_usec() - bench.ph_begin
			bench.ph_ticks += 1

var flight: Node3D
var out := ""
var scenario := "hard"
var p_begin := 0
var p_end := 0
var ph_begin := 0
var ph_sum := 0
var ph_ticks := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	_run.call_deferred()

func _stamps() -> void:
	var a := Stamp.new(); a.bench = self; a.first = true
	a.process_priority = -100000; a.process_physics_priority = -100000
	var b := Stamp.new(); b.bench = self; b.first = false
	b.process_priority = 100000; b.process_physics_priority = 100000
	root.add_child(a); root.add_child(b)

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	_stamps()
	var load_clock := Time.get_ticks_usec()
	flight = load("res://main.tscn").instantiate()
	root.add_child(flight)
	flight.session.input_enabled = false
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	var setup_us := Time.get_ticks_usec() - load_clock
	await RenderingServer.frame_post_draw
	var uargs := OS.get_cmdline_user_args()
	if uargs.has("--no-ui"): root.canvas_cull_mask = 0
	if uargs.has("--hide-effects"): flight._crash_director.effects.hide()
	if uargs.has("--hide-wreck"): flight._crash_director.wreck.hide()
	if uargs.has("--no-accident"): flight._accident_report.hide()
	var reference := uargs.has("--reference")
	if uargs.has("--sync-valuation") and flight._accident_incident != null:
		flight._accident_incident.async_valuation = false
	if reference and flight._accident_incident != null:
		flight._accident_incident.async_archive = false
		flight._accident_incident.async_valuation = false
	var results: Array = []
	for run in 2:
		for i in 120: await process_frame
		var state: PackedFloat64Array = flight.session.sim.state.duplicate()
		var att: PackedFloat64Array
		var v_ned: PackedFloat64Array
		if scenario == "hard":
			att = M.q_from_euler(0.2, -0.95, 0.55)
			v_ned = PackedFloat64Array([12.0, 0.0, 25.0])
		else: # belly slide: shallow, slow, nearly level arrival
			att = M.q_from_euler(0.0, 0.02, 0.0)
			v_ned = PackedFloat64Array([14.0, 0.0, 1.2])
		for i in 4: state[RB.ATT + i] = att[i]
		state[RB.POS] = -25.0
		state[RB.POS + 1] = -15.0
		var deepest := -INF
		var hull: PackedFloat64Array = flight.session.aircraft.model.crash_hull
		for i in range(0, hull.size(), 3):
			deepest = maxf(deepest, M.q_rotate(att, hull.slice(i, i + 3))[2])
		var lead := 5.0 if scenario == "hard" else 0.6
		state[RB.POS + 2] = -deepest - lead
		var velocity := M.q_rotate(M.q_conj(att), v_ned)
		for i in 3:
			state[RB.VEL + i] = velocity[i]
			state[RB.RATE + i] = 0.0
		flight.session.sim.state = state.duplicate()
		flight.session.sim.previous = flight.session.sim.state.duplicate()
		var inputs: PackedFloat64Array = flight.session.sim.inputs.duplicate()
		for k in mini(4, inputs.size()): inputs[k] = 0.0
		flight.session.sim.inputs = inputs
		for i in 30: await process_frame
		flight.session.sim.set_paused(false)
		flight.session.set_physics_process(true)
		flight.session.sim.set_physics_process(true)
		var frames: Array = []
		var tick_costs: Array = []
		var impact_frame := -1
		var stamp := Time.get_ticks_usec()
		var tick0: int = flight.session.sim.tick
		var n := 240 if scenario == "hard" else 600
		for i in n:
			ph_sum = 0; ph_ticks = 0
			await process_frame
			if reference: flight._accident_crash_deferred = true
			var now := Time.get_ticks_usec()
			# process_frame fires before Node._process; the p_* of the previous frame are complete now.
			frames.append([snappedf((now - stamp) / 1000.0, 0.01), ph_ticks, snappedf(ph_sum / 1000.0, 0.01),
				snappedf((p_end - p_begin) / 1000.0, 0.01), flight.session.sim.tick - tick0])
			if impact_frame < 0 and not flight.session.crash.is_empty():
				impact_frame = i
			if scenario == "slide" and i >= 20 and i < 60 and flight._accident_incident != null:
				var s0 := Time.get_ticks_usec()
				var snap: Dictionary = flight.session.contact_events()
				var s1 := Time.get_ticks_usec()
				flight._accident_incident.observe(snap, flight._accident_bindings, false, false)
				var s2 := Time.get_ticks_usec()
				flight._observe_accident_settlement()
				var s3 := Time.get_ticks_usec()
				tick_costs.append([s1 - s0, s2 - s1, s3 - s2, (snap.get("events", []) as Array).size()])
			stamp = Time.get_ticks_usec()
		var director: Node = flight._crash_director
		var econ := {}
		var inc: RefCounted = flight._accident_incident
		if inc != null:
			econ.revision = inc._revision
			econ.report_bytes = JSON.stringify(inc.report).length()
			var rec_us: Array = []
			var enc_us: Array = []
			var wr_us: Array = []
			for k in 3:
				var t0 := Time.get_ticks_usec(); inc._recalculate(); rec_us.append(Time.get_ticks_usec() - t0)
				t0 = Time.get_ticks_usec(); inc.ReportArchive.encode(inc.report); enc_us.append(Time.get_ticks_usec() - t0)
				t0 = Time.get_ticks_usec(); inc._write_archive(); wr_us.append(Time.get_ticks_usec() - t0)
			econ.recalc_us = rec_us; econ.encode_us = enc_us; econ.write_us = wr_us
			var t1 := Time.get_ticks_usec(); inc._purchase_options_key = ""; inc._purchase_options(); econ.purchase_options_us = Time.get_ticks_usec() - t1
			t1 = Time.get_ticks_usec(); inc.Calculator.calculate(inc.dossier, inc._assessment); econ.calculator_us = Time.get_ticks_usec() - t1
			var CT = inc.CostTransaction
			var micro := {}
			var ctx: Dictionary = inc.cost_transaction_context()
			var items := {
				safe_dossier = func(): CT._safe_tree(inc.dossier),
				safe_recipe = func(): CT._safe_tree(inc._recipe_book),
				safe_book = func(): CT._safe_tree(inc._package_book),
				safe_policy = func(): CT._safe_tree(inc._labor_policy),
				safe_assessment = func(): CT._safe_tree(inc._assessment),
				digest_book = func(): CT.digest(inc._package_book),
				digest_policy = func(): CT.digest(inc._labor_policy),
				context = func(): inc.cost_transaction_context(),
				prepare_auto = func(): inc._prepare_purchase(inc._costing_mode, ""),
				package_candidates = func(): CT.package_candidates(inc._package_book, inc.dossier, inc._assessment),
				apply_game = func(): inc._apply_game_assessment(),
				report_dup = func(): inc.report.duplicate(true),
				emit = func(): inc.assessment_changed.emit(inc.report.duplicate(true), inc.terminal),
			}
			for name: String in items:
				var best := 1 << 40
				for k in 3:
					var t2 := Time.get_ticks_usec(); items[name].call(); best = mini(best, Time.get_ticks_usec() - t2)
				micro[name] = best
			micro.packages = inc._package_book.get("packages", []).size()
			micro.dossier_bytes = JSON.stringify(inc.dossier).length()
			micro.recipe_bytes = JSON.stringify(inc._recipe_book).length()
			econ.micro = micro
		results.append({tick_costs = tick_costs, econ = econ, run = run, aircraft = flight.aircraft_id, scenario = scenario, impact_frame = impact_frame,
			impact_us = director.impact_usec, frames = frames, class_level = director.report.get("class", -1),
			crashed = not flight.session.crash.is_empty(), height = -flight.session.sim.state[RB.POS + 2],
			step_usec = flight.session.sim.step_usec, setup_us = setup_us,
			warmup = director.stats().get("shader_warmup", {})})
		flight.session.reset()
		flight.session.set_physics_process(false)
		flight.session.sim.set_physics_process(false)
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify({adapter = RenderingServer.get_video_adapter_name(), results = results}))
	flight.free()
	await process_frame
	quit()
