# BL-19d: Home -> Workshop -> RC blimp stock build -> size and travel edits -> Test fly in the airship activity
# (frozen variant, scaled model, Workshop menu) -> Return to Workshop with the same draft.
extends SceneTree

const AppRoot = preload("res://app_root.gd")
const UiDriver = preload("res://tests/ui_driver.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("ok   " + description)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var ui: RefCounted = UiDriver.new(self)
	var app := AppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = "user://test_airship_workshop_flow_settings.cfg"
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	root.add_child(app)
	await _frames(2)
	app.open_workshop()
	await _frames(3)
	var workshop: Node = app.screens.top()
	check(app.screens.is_top("workshop") and workshop != null, "Workshop opens from Home")
	if workshop == null:
		await ui.close_app(app)
		quit(1)
		return
	workshop.recovery_enabled = false
	check(workshop._load_catalog_aircraft("rc-blimp-5m", false), "the blimp loads as a stock build")
	await _frames(2)
	var caps: Dictionary = workshop._capabilities
	check(caps.get("vehicle") == "airship" and workshop._compiled.get("ok", false), "airship capabilities and a valid stock compile")
	check(workshop._mass_policy_selector.disabled, "mass policy is not offered for a buoyant build")
	workshop._apply_scale(5.0)
	check(is_equal_approx(float(workshop._recipe.scale), 2.0), "size clamps to the blimp's 2.0 maximum (%s)" % str(workshop._recipe.scale))
	workshop._apply_scale(0.6)
	await _frames(1)
	var summary: Dictionary = workshop._compiled.get("summary", {})
	check(workshop._compiled.ok and is_equal_approx(float(summary.get("envelope_length_m", 0.0)), 3.0), "60 % size compiles a 3 m envelope")
	check(str(workshop._scale_readout.text).contains("envelope"), "size readout reports the envelope length: " + str(workshop._scale_readout.text))
	check(str(workshop._summary_label.text).contains("Envelope length") or str(workshop._summary_label.text).contains("envelope"),
		"summary lists the blimp metrics")
	# Appearance and Lighting: every blimp paint slot, the registration marking and a lighting preset.
	var bindings: Dictionary = load("res://workshop/airship_family.gd").customization().get("bindings", {})
	var profile: Dictionary = load("res://workshop/presentation.gd").defaults(bindings)
	for slot: Dictionary in bindings.get("paint_slots", []):
		profile.paint.append({"slot": str(slot.id), "color": "#D02020FF", "pattern": "solid", "accent": "none"})
	profile.markings.append({"slot": "registration", "text": "OPENRC 7", "color": "#202020FF"})
	profile.lighting = load("res://render/lighting/lighting_profile.gd").preset("night_radian")
	workshop._presentation = profile
	workshop.trial_start_choice = "airborne"
	workshop._request_trial()
	await _frames(6)
	var activity: Node = app.ground_vehicle
	check(activity != null and activity.name == "AirshipActivity" and app.flight == null, "Test fly starts the airship activity")
	if activity == null:
		print(workshop._status_label.text)
		await ui.close_app(app)
		quit(1)
		return
	check(str(activity.startup_error).is_empty(), "trial activity starts: " + str(activity.startup_error))
	check(not activity.workshop_trial.is_empty() and is_equal_approx(float(activity.session.data.envelope.length), 3.0),
		"the activity flies the frozen 3 m variant")
	check(activity.visual.model.scale.is_equal_approx(Vector3.ONE * 0.6), "the model is drawn at the build size")
	var envelope_slot: Dictionary = bindings.paint_slots.filter(func(s: Dictionary) -> bool: return s.id == "envelope")[0]
	var target: Dictionary = envelope_slot.targets[0]
	var mesh := activity.visual.root.get_node(NodePath(str(target.node_path))) as MeshInstance3D
	var painted := mesh.get_surface_override_material(int(target.surface)) as StandardMaterial3D if mesh != null else null
	check(painted != null and painted.albedo_color.is_equal_approx(Color("#D02020FF")), "the trial flies the Workshop paint")
	check(activity.get_node_or_null("AirshipLightingRig") != null, "the trial flies the Workshop lighting preset")
	check(is_instance_valid(activity._mechanical), "servo sound follows the actuators")
	check(activity.hud.home_button.text == "Return to Workshop" and (activity.hud.choices.skin as OptionButton).disabled,
		"the trial menu returns to the Workshop and pins the default skin")
	activity.scripted_sticks = func(_tick: int) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	activity.handle_action("resume")
	for i in 20:
		await physics_frame
	check(activity.session.sim.tick > 0 and activity.session.crash.is_empty(), "the trial flies")
	activity.handle_action("home")
	await _frames(10)
	check(app.ground_vehicle == null and app.screens.is_top("workshop"), "Return to Workshop restores the editor")
	var back: Node = app.screens.top()
	check(back == workshop and is_equal_approx(float(back._recipe.scale), 0.6) and not back._trial_pending,
		"the same draft is kept after the trial")
	await ui.close_app(app)
	print("Airship Workshop flow: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
