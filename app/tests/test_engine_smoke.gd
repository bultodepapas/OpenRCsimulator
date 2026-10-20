extends SceneTree

const Smoke := preload("res://render/smoke/exhaust.gd")
const Builder := preload("res://render/airplane.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	var airplane := Builder.build()
	var anchor: Dictionary = airplane.exhausts[0]
	check("one validated Stik mouth", airplane.exhausts.size() == 1 and Smoke.valid_anchor(anchor))
	var e: Dictionary = Geometry.DATA.equipment
	var z: float = (float(e.firewall_z) + float(e.prop_z)) * 0.5
	check("mouth matches hollow mesh endpoint", anchor.position.is_equal_approx(Vector3(0.064, e.shaft_y - 0.018, z + 0.041)))
	var direction := Vector3(0.008, -0.009, 0.011).normalized()
	check("gas exits hollow outlet axis", anchor.direction.is_equal_approx(direction))
	for id in [Builder.EXTRA_ID, Builder.AVANTI_ID, Builder.TIMBER_ID]:
		var model := Builder.build(id)
		check(id + " has no guessed RC outlet", model.exhausts.is_empty())
		model.root.free()
	# P51-V12: the P-51 publishes its kit installation's canister outlet (CARF manual; location estimated at the radiator exit).
	var p51 := Builder.build(Builder.P51_ID)
	check("P-51 declares one estimated canister outlet with a pump", p51.exhausts.size() == 1 and Smoke.valid_anchor(p51.exhausts[0]) and p51.exhausts[0].pump)
	p51.root.free()
	var bad := anchor.duplicate()
	bad.position = Vector3(NAN, 0, 0)
	check("invalid mouth refused", not Smoke.valid_anchor(bad))
	bad = anchor.duplicate()
	bad.direction = Vector3.ZERO
	check("degenerate direction refused", not Smoke.valid_anchor(bad))
	for kind in ["electric_prop", "turbine", "gasoline_prop", ""]:
		check(kind + " stays clear", Smoke.operating_levels(kind, 8000, 2000, 12000, 1, 1).exhaust == 0.0)
	check("stopped glow engine stays clear", Smoke.operating_levels("glow_prop", 0, 2000, 12000, 1, 1).exhaust == 0.0)
	check("disabled/crashed engine stays clear", Smoke.operating_levels("glow_prop", 8000, 2000, 12000, 1, 1, false).pump == 0.0)
	check("nonfinite speed stays clear", Smoke.operating_levels("glow_prop", NAN, 2000, 12000, 1, 1).exhaust == 0.0)
	var idle := Smoke.operating_levels("glow_prop", 2000, 2000, 12000, 0, 1)
	var cruise := Smoke.operating_levels("glow_prop", 7000, 2000, 12000, 0.5, 1)
	check("idle oil mist without pump", idle.exhaust > 0.0 and idle.pump == 0.0)
	check("cruise responds to RPM and warm-load gate", cruise.exhaust > idle.exhaust and cruise.pump == 1.0)
	check("pump OFF is immediate", Smoke.operating_levels("glow_prop", 7000, 2000, 12000, 0.5, 0).pump == 0.0)
	var smoke := Smoke.new()
	root.add_child(smoke)
	check("configure native effect", smoke.configure(anchor))
	var count := smoke.get_child_count()
	check("world coordinates, manual clock, fixed seed", not smoke.pump.local_coords and smoke.pump.speed_scale == 0.0 and smoke.pump.use_fixed_seed)
	for attitude in [Basis.IDENTITY, Basis(Vector3.RIGHT, PI), Basis(Vector3.FORWARD, PI / 2.0), Basis(Vector3.UP, PI / 2.0)]:
		var pose := Transform3D(attitude, Vector3(8, 5, -12))
		smoke.reset()
		smoke.advance(0, pose, "glow_prop", 7000, 2000, 12000, 0.5, Vector3(3, 0, 0), 1)
		smoke.advance(1.0 / 30.0, pose, "glow_prop", 7000, 2000, 12000, 0.5, Vector3(3, 0, 0), 1)
		var mat := smoke.pump.process_material as ShaderMaterial
		check("outlet follows rendered attitude", (mat.get_shader_parameter("segment_end") as Vector3).is_equal_approx(pose * anchor.position))
		check("gas direction follows attitude", (mat.get_shader_parameter("direction_end") as Vector3).is_equal_approx(attitude * direction))
		check("old and new puffs receive shared wind", mat.get_shader_parameter("wind_velocity") == Vector3(3, 0, 0))
		var elapsed := smoke.presented_s
		smoke.advance(elapsed, pose, "glow_prop", 7000, 2000, 12000, 0.5, Vector3.ZERO, 0)
		check("equal clock cannot advance particle age", smoke.presented_s == elapsed and smoke.last_interval_s == 1.0 / 30.0)
		var pump_mat := smoke.pump.process_material as ShaderMaterial
		var birth_segment_end: Vector3 = pump_mat.get_shader_parameter("segment_end")
		var birth_carrier: Vector3 = pump_mat.get_shader_parameter("carrier_velocity")
		var residual_pose := pose.translated(Vector3(0.5, 0.25, -0.75))
		smoke.advance(elapsed + 0.01, residual_pose, "glow_prop", 7000, 2000, 12000, 0.5, Vector3(4, 1, -2), 0)
		check("pump off stops births without restart", not smoke.pump.emitting and smoke.pump.get_meta("last_birth_s") == elapsed)
		check("residual pump puffs keep aging with updated wind and birth-only uniforms unchanged",
			pump_mat.get_shader_parameter("wind_velocity") == Vector3(4, 1, -2)
			and pump_mat.get_shader_parameter("segment_end") == birth_segment_end
			and pump_mat.get_shader_parameter("carrier_velocity") == birth_carrier)
	# Fully off emitters skip all shader uploads after the last residual lifetime, then wake from
	# the most recently presented pose rather than bridging from stale birth state.
	smoke.reset()
	var dormant_pose := Transform3D(Basis.IDENTITY, Vector3(3, 4, 5))
	smoke.advance(0.0, dormant_pose, "electric_prop", 0, 2000, 12000, 0.0, Vector3.ZERO, 0,
		false, 700.0)
	var dormant_mat := smoke.pump.process_material as ShaderMaterial
	var sentinel_end := Vector3(123, 456, 789)
	var sentinel_wind := Vector3(-9, -8, -7)
	dormant_mat.set_shader_parameter("segment_end", sentinel_end)
	dormant_mat.set_shader_parameter("wind_velocity", sentinel_wind)
	var fully_off_pose := Transform3D(Basis.IDENTITY, Vector3(6, 5, 4))
	smoke.advance(1.0 / 30.0, fully_off_pose, "electric_prop", 0, 2000, 12000, 0.0, Vector3(2, 0, 0), 0,
		false, 700.0)
	check("fully dormant pump leaves birth and process shader inputs untouched",
		not smoke.pump.emitting and dormant_mat.get_shader_parameter("segment_end") == sentinel_end
		and dormant_mat.get_shader_parameter("wind_velocity") == sentinel_wind)
	var resume_pose := Transform3D(Basis.IDENTITY, Vector3(9, 7, 2))
	smoke.advance(2.0 / 30.0, resume_pose, "glow_prop", 7000, 2000, 12000, 0.5, Vector3(1, 2, 3), 1,
		true, 0.0, Vector3(0.25, 0.0, 0.0))
	check("resumed pump births use the current interval pose and wind",
		smoke.pump.emitting
		and dormant_mat.get_shader_parameter("segment_begin") == fully_off_pose * anchor.position
		and dormant_mat.get_shader_parameter("segment_end") == resume_pose * anchor.position
		and dormant_mat.get_shader_parameter("wind_velocity") == Vector3(1, 2, 3)
		and smoke.pump.get_meta("last_birth_s") == 2.0 / 30.0)
	for i in 100:
		smoke.reset()
	check("100 resets allocate no nodes and clear history", smoke.get_child_count() == count and smoke._bounds.is_empty())
	smoke.advance(1.0, Transform3D.IDENTITY, "glow_prop", 7000, 2000, 12000, 0.5, Vector3.ZERO, 1)
	smoke.advance(8.0, Transform3D.IDENTITY, "glow_prop", 7000, 2000, 12000, 0.5, Vector3.ZERO, 1)
	check("large seek primes without bridge births", not smoke.pump.emitting and smoke.presented_s == 8.0)
	smoke.free()
	airplane.root.free()
	_integration()


func _integration() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.crash_effects_enabled = false
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.session.set_physics_process(false)
	main.session.sim.set_physics_process(false)
	check("real flight attaches authored exhaust", main._smoke != null)
	main.session.sim.set_paused(false)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_H
	key.pressed = true
	main._unhandled_input(key)
	check("Input Map H toggles pump", main._smoke_key_on)
	key.echo = true
	main._unhandled_input(key)
	check("key repeat cannot toggle pump", main._smoke_key_on)
	main.session.reset()
	check("real reset clears request and births", not main._smoke_key_on and not main._smoke.pump.emitting)
	main.session.radio.connect_device(99, {name = "EdgeTX SM test radio", guid = "sm-fake", known = false})
	main.session.profiles_path = "user://sm-test-aux-profile.cfg"
	main._begin_smoke_assignment()
	check("guided assignment holds real flight", main.session.sim.paused and main._smoke_assignment != null)
	var panel: Node = main._smoke_assignment
	panel.sample_axis(99, 4, -1.0)
	panel.advance()
	panel.sample_axis(99, 4, 1.0)
	panel.advance()
	panel.sample_axis(99, 4, -1.0)
	panel.advance()
	check("assignment persists optional profile without AETR changes", main.session.radio.profile.get("aux", {}).get("smoke", {}).get("axis", -1) == 4 and main.session.radio.profile.roll.axis == 0)
	check("assignment closes and requires OFF evidence", main._smoke_assignment == null and not main.session.radio.smoke_is_armed() and not main.session.radio.armed)
	var motion := InputEventJoypadMotion.new()
	motion.device = 99
	motion.axis = 4
	motion.axis_value = -1.0
	main.session._input(motion)
	check("paused assignment cannot arm or queue AUX", not main.session.radio.smoke_is_armed() and main.session.radio.smoke_amount() == 0.0)
	main.session.resume()
	check("AUX integration resumes flight explicitly", not main.session.sim.paused)
	main.session._input(motion)
	check("active flight routes AUX OFF event", main.session.radio.smoke_is_armed())
	motion.axis_value = 1.0
	main.session._input(motion)
	check("active flight routes AUX ON event", main.session.radio.smoke_amount() == 1.0)
	main.session.radio.disconnect_device()
	main.session.radio.connect_device(100, {name = "SM fake gamepad", guid = "sm-gamepad", known = true})
	main._begin_smoke_assignment()
	panel = main._smoke_assignment
	panel.sample_button(100, 5, false)
	panel.advance()
	panel.sample_button(100, 5, true)
	panel.advance()
	panel.sample_button(100, 5, false)
	panel.advance()
	var binding: Dictionary = main.session.RcCalibration.load_smoke_binding(main.session.profiles_path, main.session.radio.device_key)
	check("gamepad AUX persists independently of the fixed rate profile", binding.get("button", -1) == 5 and main.session.radio.profile.kind == "gamepad" and main.session.radio.is_rate_throttle())
	main.session.radio.disconnect_device()
	main.session.device_info = func(_id: int) -> Dictionary: return {name = "SM fake gamepad", guid = "sm-gamepad", known = true}
	main.session._on_joy_connection_changed(100, true)
	check("gamepad reconnect restores binding and requires a fresh OFF event", main.session.radio.profile.get("aux", {}).get("smoke", {}).get("button", -1) == 5 and not main.session.radio.smoke_is_armed())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.session.profiles_path))
	main.queue_free()
	await process_frame
	print("SM engine smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
