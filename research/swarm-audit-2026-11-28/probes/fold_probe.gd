extends SceneTree

const Scene := preload("res://main.gd")
const Session := preload("res://sim/flight_session.gd")
const Geometry := preload("res://aircraft/f4u_corsair_geometry.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const Inputs := preload("res://input/commands.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rows := []
	var field: Dictionary = FieldLoader.load_from().field
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var obstacles: Dictionary = Landscapes.collision_world("club_field", field, {})
	if not obstacles.ok:
		printerr("Ground fixture refused ", obstacles)
		quit(1)
		return
	for render_first in [false, true]:
		var main := Scene.new()
		var session := Session.new()
		var id := "f4u-corsair-250"
		session.start_choice = Session.START_RUNWAY
		session.input_enabled = true
		session.read_raw = Inputs.neutral_raw
		session.soft_hull_contacts = true
		session.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
		session.set_field(field)
		session.set_lake_context(lake)
		session.set_collision_world(obstacles.world)
		session.crash_auto_restart = false
		session.reset()
		main.session = session
		main._airplane = {"folds": Geometry.DATA.folds}
		for i in 240:
			if main._stopped_on_wheels(): break
			session._physics_process(1.0 / 240.0)
			session.sim.step()
		var stopped := bool(main._stopped_on_wheels())
		var at_tick := int(session.sim.tick)
		session.commands.throttle = 1.0
		main._toggle_wing_fold()
		var immediate_hold := session.throttle_holds.has("wing_fold")
		if render_first:
			main._advance_wing_fold(1.0 / 60.0)
		session._physics_process(1.0 / 240.0)
		var pending_input := float(session.sim.inputs[3])
		session.sim.step()
		var accepted_tick := int(session.sim.tick)
		var end_input := float(session.sim.inputs[3])
		main._advance_wing_fold(1.0 / 60.0)
		session._physics_process(1.0 / 240.0)
		rows.append({"render_before_first_tick": render_first, "stopped": stopped,
			"at_tick": at_tick, "accepted_tick": accepted_tick, "target":main._wing_fold_target,
			"held_immediately":immediate_hold, "first_input": pending_input,
			"accepted_input":end_input, "next_input":float(session.sim.inputs[3]), "fault":session.sim.fault_reason})
		main.session = null
		session.free()
		main.free()
	print("FOLD_OBSERVATION ", JSON.stringify(rows))
	var ok: bool = rows[0].stopped and rows[1].stopped and rows[0].target == 1.0 and rows[1].target == 1.0 \
		and rows[0].first_input == 1.0 and rows[1].first_input == 0.0 and rows[0].next_input == 0.0 \
		and rows[0].accepted_tick == rows[0].at_tick + 1 and rows[1].accepted_tick == rows[1].at_tick + 1 \
		and rows[0].fault == "" and rows[1].fault == ""
	if ok: print("CORSAIR_FOLD_CADENCE_CONFIRMED")
	quit(0 if ok else 1)
