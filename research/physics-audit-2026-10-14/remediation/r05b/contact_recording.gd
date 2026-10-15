## R05B explicit test scenario: unchanged catalog Glow with 25% fuel at a lamp contact.
## This is a software contact fixture, not a piloted flight or a physical validation.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const World := preload("res://scenery/collision_world.gd")
const RB := preload("res://physics/rigid_body.gd")
var destination := ""
var probe := "foremost"

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): destination = argument.trim_prefix("--out=")
		if argument.begins_with("--probe="): probe = argument.trim_prefix("--probe=")
	call_deferred("run")

func run() -> void:
	if destination.is_empty() or DirAccess.dir_exists_absolute(destination) or probe not in ["foremost", "rightmost"]:
		fail("fresh --out directory required")
		return
	var f := Flight.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup("res://data/aircraft/stik_glow_55ax_2t.json")
	if not f.is_flyable():
		f.free()
		fail("fixture aircraft did not load")
		return
	var hull: PackedFloat64Array = f.aircraft.model.crash_hull
	var foremost := 0
	for index in range(3, hull.size(), 3):
		var axis: int = 0 if probe == "foremost" else 1
		if hull[index + axis] > hull[foremost + axis]: foremost = index
	var world: Dictionary = World.build(
		{pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []}, {groups = []},
		{fixtures = [{id = "r05_lamp", type = "flood", north = 5.0, east = hull[foremost + 1], height = 8.0}]})
	if not world.ok or not f.set_collision_world(world.world) or not f.glow_cut():
		f.free()
		fail("fixture environment or source cut failed")
		return
	var initial: PackedFloat64Array = f.sim.state.duplicate()
	initial[0] = 5.0 - 0.07 - hull[foremost] - 0.01
	initial[1] = 0.0
	initial[2] = -4.0
	initial[3] = 8.0
	initial[4] = 0.0
	initial[5] = 0.0
	for i in 4: initial[RB.ATT + i] = 1.0 if i == 0 else 0.0
	for i in 3: initial[RB.RATE + i] = 0.0
	f.sim.continuous[1] = 0.25 * f.aircraft.model.propulsion.glow.initial_fuel_kg
	f.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	if not f.sim.reset(initial) or f.checkpoint().is_empty():
		f.free()
		fail("fixture initial boundary refused")
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var recorder := Log.new(f)
	if recorder.start(destination.path_join("contact.orfl")) != OK:
		f.free()
		fail("recording failed")
		return
	recorder.mark("R05B: 25% fuel; actual catalog hull; 8 m/s lamp approach; source cut, spinning propeller")
	var initial_boundary: Dictionary = f.checkpoint()
	var contacts: Array = []
	var valid := true
	for tick in 60:
		f.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		f.sim.step()
		if not f.sim.fault_reason.is_empty() or f.sim.tick != tick + 1:
			valid = false
			break
		var event = f.last_scenery_event()
		if event != null:
			contacts.append({tick = f.sim.tick, fraction = event.time_fraction, mass_effective_kg = event.effective_mass_kg,
				energy_j = event.impact_energy_j, dissipated_j = event.dissipated_energy_j,
				terminal = event.terminal, response = event.response_status})
		if not f.crash.is_empty():
			valid = false
			break
	var finish: Error = recorder.stop("Completed 60-tick contact fixture" if valid else "Rejected contact fixture")
	var report: Dictionary = {ok = valid and finish == OK and not contacts.is_empty(), ticks = f.sim.tick, probe = probe,
		fault = f.sim.fault_reason, complete = valid and finish == OK, contacts = contacts,
		initial_body = Array(initial_boundary.simulation.state), initial_aux = Array(initial_boundary.simulation.aux),
		initial_continuous = Array(initial_boundary.simulation.continuous), initial_inputs = Array(initial_boundary.simulation.inputs),
		final_body = Array(f.sim.state), final_continuous = Array(f.sim.continuous),
		solver_sha256 = Log.solver_identity(), aircraft_identity = f.aircraft.input_identity,
		purpose = "Software fixture only; identical body, internal state and post-conditioning input tape across laws."}
	var file := FileAccess.open(destination.path_join("scenario.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", false, true) + "\n")
	file.close()
	f.free()
	print(JSON.stringify({ok = report.ok, ticks = report.ticks, contacts = contacts, fault = report.fault}))
	quit(0 if report.ok else 1)

func fail(message: String) -> void:
	printerr(message)
	quit(1)
