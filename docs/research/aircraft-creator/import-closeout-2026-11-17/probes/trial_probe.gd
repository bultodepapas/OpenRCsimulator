extends SceneTree
## Exercise the actual v4 authoring/trial path; do not patch production modules.
const AuthoringFixture := preload("res://tests/creator_authoring_fixture.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Trial := preload("res://workshop/creator/trial.gd")
const Session := preload("res://sim/flight_session.gd")
const ServoFlight := preload("res://sim/servo_interval_flight.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")

func _initialize() -> void:
	var source: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(),"ordinary.glb")
	if not source.ok:
		_fail("source",source)
		return
	var doc: RefCounted = AuthoringFixture.populated(source.value)
	if not doc.set_servo_integration(Definition.ServoLaw.LAW):
		_fail("servo selection",{})
		return
	var compiled: Dictionary = doc.compile()
	if not compiled.ok:
		_fail("compile",compiled)
		return
	var trial: Dictionary = Trial.freeze({creator_candidate = compiled.value, creator_source = doc.source(), creator_placement = doc.placement(), creator_name = "Audit v4"})
	if not trial.ok:
		_fail("freeze",trial)
		return
	var field: Dictionary = FieldLoader.load_from()
	if not field.ok:
		_fail("field",field)
		return
	var result: Dictionary = Trial.check_start(trial,field.field,Weather.defaults(),Session.START_AIRBORNE)
	var session := Session.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.crash_auto_restart = false
	session.start_choice = Session.START_AIRBORNE
	session.setup_stage_backend("gdscript_reference")
	session.setup("",trial.data.model.id,trial.data)
	var before: Dictionary = ServoFlight.admission(session,trial.data.model)
	session.soft_hull_contacts = true
	var after: Dictionary = ServoFlight.admission(session,trial.data.model)
	var report := {base_commit = "2a3cf04dbbdaf486b9c9c8e983463d828f90c64a", compiled = compiled.ok, frozen = trial.ok,
		check_start = result, explicit_reference_session = {aircraft_ok = session.aircraft.get("ok",false),before_soft_contacts = before,after_soft_contacts = after},
		scope = "Public trial/session boundaries only; not a full Main or exported-build journey."}
	session.free()
	print("AUDIT_TRIAL_JSON: ",JSON.stringify(report,"",true,true))
	print("AUDIT_TRIAL_COMPLETE")
	quit(0)

func _fail(stage: String, result: Dictionary) -> void:
	printerr("AUDIT_PROBE_SETUP_FAILED ",stage," ",JSON.stringify(result))
	quit(2)
