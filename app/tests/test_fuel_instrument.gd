## HUD-13: detached fuel presentation and motion lifecycle. Optional capture is a synthetic fixture, not a flight.
extends SceneTree

const FuelInstrument := preload("res://render/overlays/fuel_instrument.gd")
const OverlayManager := preload("res://render/overlays/overlay_manager.gd")
const FuelSample := preload("res://sim/fuel_sample.gd")
const Clock := preload("res://render/shader_clock.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _checks := 0
var _failures := 0
var _stage: Control


func _initialize() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	await process_frame
	_stage = Control.new()
	_stage.theme = UiTheme.build()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_stage)
	var widget := FuelInstrument.new()
	_stage.add_child(widget)
	widget.position = Vector2(30, 30)
	await _settle()
	_test_data(widget)
	_test_motion(widget)
	await _test_geometry(widget)
	await _test_visibility()
	widget.queue_free()
	await process_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fuel-capture-dir="):
			await _rendered_fixture(argument.trim_prefix("--fuel-capture-dir="))
	_stage.queue_free()
	await process_frame
	print("fuel instrument: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _fuel(family := "glow", fill := 0.4) -> Dictionary:
	return {ok = true, finite_fuel = true, fill_fraction = fill, volume_ml = fill * 750.0,
		fuel_remaining_kg = fill * 0.6, fuel_usable_kg = fill * 0.6, reserve_fraction = 0.12,
		low_fuel = false, reserve_estimated = false, stores = [{kind = "tank", family = family}]}


func _telemetry(time_s: float, bank := 0.0, pitch := 0.0, load_factor := 1.0) -> Dictionary:
	return {time_s = time_s, bank_deg = bank, pitch_deg = pitch, load_factor = load_factor,
		airspeed = 20.0, ground_speed = 18.0, height_agl = 30.0, vertical_speed = 0.0,
		distance_pilot = 40.0, wind_speed = 0.0, wind_up = 0.0, wind_from_deg = NAN}


func _refresh(widget: Control, fuel: Dictionary, telemetry: Dictionary) -> void:
	widget.refresh(telemetry, "metric", 20.0, {}, fuel)


func _test_data(widget: Control) -> void:
	var sample := _fuel()
	_refresh(widget, sample, _telemetry(1.0))
	_check("accepted fill, volume and mass are displayed", widget.value_label.text == "40"
		and widget.left_value.text == "300 mL" and widget.right_value.text == "240 g")
	_check("accepted fill reaches the shader", is_equal_approx(float(widget._liquid_material.get_shader_parameter("fill")), 0.4))
	for family: String in ["glow", "gasoline", "kerosene"]:
		sample = _fuel(family)
		_refresh(widget, sample, _telemetry(1.0))
		_check("accepted %s family reaches the card" % family, widget._family == family)
	_check("different main-tank families fall back to generic", FuelInstrument.fuel_family({stores = [
		{family = "glow"}, {family = "gasoline"}]}) == "")
	_check("a feed line does not override its tank family", FuelInstrument.fuel_family({stores = [
		{family = "kerosene"}, {kind = "feed_line", family = "glow"}]}) == "kerosene")
	for stores: Variant in [null, true, "bad", [true], [{family = ""}]]:
		_check("malformed or missing store metadata uses generic fuel", FuelInstrument.fuel_family({stores = stores}) == "")
	_check("omitted stores use generic fuel", FuelInstrument.fuel_family({}) == "")
	var sparse := _fuel()
	sparse.erase("stores")
	sparse.erase("fuel_usable_kg")
	_refresh(widget, sparse, _telemetry(1.0))
	_check("sparse finite sample does not invent an empty tank", widget._family == "" and not widget._empty
		and widget.value_label.text == "40")

	var empty := _fuel("glow", 0.08)
	empty.fuel_usable_kg = 0.0
	_refresh(widget, empty, _telemetry(1.0))
	_check("unusable residue retains its fill but raises the empty indication", widget._empty
		and widget.subtitle.text == "No usable fuel · land now" and widget.value_label.text == "8"
		and is_equal_approx(float(widget._liquid_material.get_shader_parameter("fill")), 0.08))
	empty.fuel_usable_kg = 0.01
	_refresh(widget, empty, _telemetry(1.0))
	_check("refuel with unchanged fill restores normal subtitle", not widget._empty
		and widget.subtitle.text == "Tank level · remaining fuel")
	var props := {ok = true, mass_kg = 2.0, cg_body_m = PackedFloat64Array([0.0, 0.0, 0.0]),
		inertia = PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0]),
		inverse = PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])}
	var tanks := [{id = "tank", family = "glow", fuel = "fixture", capacity_kg = 1.0,
		unusable_kg = 0.0, reserve_kg = 0.1, reserve_estimated = true, density_kg_m3 = 1000.0}]
	var at_reserve: Dictionary = FuelSample.build(props, tanks, {tank = 0.1}, 0, 0.0, true)
	_refresh(widget, at_reserve, _telemetry(1.0))
	_check("the accepted inclusive reserve boundary preserves estimated provenance", at_reserve.low_fuel
		and widget.subtitle.text == "Estimated reserve · land soon" and widget._graphic_color == FuelInstrument.LOW_COLOR
		and widget._reserve_estimated and widget.graphic.tooltip_text.contains("estimated reserve"))
	var bad_reserve := _fuel()
	bad_reserve.reserve_fraction = 1.5
	_refresh(widget, bad_reserve, _telemetry(1.0))
	_check("out-of-range reserve is not displayed", is_nan(widget._reserve))

	for invalid: Variant in [NAN, INF, -0.01, 1.01, "bad"]:
		var bad := _fuel()
		bad.fill_fraction = invalid
		_refresh(widget, bad, _telemetry(1.0))
		_check("invalid fill is unavailable", _is_dash(widget.value_label.text)
			and float(widget._liquid_material.get_shader_parameter("fill")) < 0.0)
	for invalid: Variant in [NAN, INF, -1.0, "bad"]:
		var bad := _fuel()
		bad.volume_ml = invalid
		_refresh(widget, bad, _telemetry(1.0))
		_check("invalid volume is unavailable", _is_dash(widget.value_label.text)
			and float(widget._liquid_material.get_shader_parameter("fill")) < 0.0)
	for invalid: Variant in [NAN, INF, -1.0, "bad"]:
		var bad := _fuel()
		bad.fuel_remaining_kg = invalid
		_refresh(widget, bad, _telemetry(1.0))
		_check("invalid mass never appears as a number", _is_dash(widget.right_value.text))
	_refresh(widget, {}, _telemetry(1.0))
	_check("missing fuel clears the previous reading and graphic", _is_dash(widget.value_label.text)
		and float(widget._liquid_material.get_shader_parameter("fill")) < 0.0)
	_refresh(widget, {ok = true, finite_fuel = false}, _telemetry(1.0))
	_check("constant-mass aircraft does not appear empty", _is_dash(widget.value_label.text)
		and not widget._empty and float(widget._liquid_material.get_shader_parameter("fill")) < 0.0)
	_refresh(widget, _fuel(), _telemetry(1.0))
	_check("valid data after an invalid interval restores the fill", widget.value_label.text == "40"
		and is_equal_approx(float(widget._liquid_material.get_shader_parameter("fill")), 0.4))


func _is_dash(value: String) -> bool:
	return value.begins_with("—") or value.begins_with("–")


func _test_motion(widget: Control) -> void:
	widget.reset_flight()
	var sample := _fuel()
	_refresh(widget, sample, _telemetry(10.0))
	var original_key: Array = widget._view_key.duplicate(true)
	_refresh(widget, sample, _telemetry(10.1, 70.0, 15.0, 1.4))
	var material: ShaderMaterial = widget._liquid_material
	_check("motion changes shader target and energy at the same fill", widget._view_key == original_key
		and widget.value_label.text == "40" and absf(float(material.get_shader_parameter("target_tilt"))) > 0.1
		and float(material.get_shader_parameter("wave_energy")) > 0.0)
	_refresh(widget, sample, _telemetry(10.2, 70.0, 15.0, 1.4))
	_check("spring moves toward the updated target", absf(widget._tilt) > 0.001 and absf(widget._velocity) > 0.001)
	var frozen := _motion_signature(widget)
	_refresh(widget, sample, _telemetry(10.2, -70.0, -20.0, 0.3))
	_check("repeated paused time freezes every motion uniform", _motion_signature(widget) == frozen)
	Clock.update(10.2)
	_check("presentation clock matches and freezes at the paused sample", is_equal_approx(Clock.last_clock, 10.2)
		and is_equal_approx(float(material.get_shader_parameter("sample_clock")), 10.2))
	widget.reset_flight()
	_check("same-time flight reset clears motion", not is_finite(widget._motion_time)
		and widget._tilt == 0.0 and widget._velocity == 0.0 and widget._energy == 0.0)
	_refresh(widget, sample, _telemetry(10.2, -70.0))
	_check("first sample after same-time reset seeds the new pose", widget._motion_time == 10.2
		and widget._energy == 0.0 and is_equal_approx(widget._tilt, widget._target) and widget._tilt > 0.1)
	_refresh(widget, sample, _telemetry(9.0, 30.0))
	_check("rewind reseeds instead of integrating backward", widget._motion_time == 9.0
		and is_equal_approx(widget._tilt, -0.24) and widget._velocity == 0.0 and widget._energy == 0.0)
	_refresh(widget, sample, _telemetry(11.0, -30.0))
	_check("long sample gap reseeds instead of integrating stale history", widget._motion_time == 11.0
		and is_equal_approx(widget._tilt, 0.24) and widget._velocity == 0.0 and widget._energy == 0.0)
	_refresh(widget, sample, _telemetry(11.1, NAN))
	_check("unavailable motion clears the spring", not is_finite(widget._motion_time) and widget._energy == 0.0)
	for field: String in ["time_s", "bank_deg", "pitch_deg", "load_factor"]:
		for invalid: Variant in ["bad", INF]:
			_refresh(widget, sample, _telemetry(11.15))
			var bad := _telemetry(11.16)
			bad[field] = invalid
			_refresh(widget, sample, bad)
			_check("malformed %s clears motion safely" % field, not is_finite(widget._motion_time)
				and widget._energy == 0.0)
	_refresh(widget, sample, _telemetry(11.2, 0.0))
	_refresh(widget, sample, _telemetry(11.3, 0.0, 20.0, 1.5))
	_check("pitch and load changes energize motion without a bank change", widget._target == 0.0 and widget._energy > 0.0)
	_refresh(widget, {}, _telemetry(11.4))
	_check("unavailable fuel clears motion rather than retaining a wave", not is_finite(widget._motion_time)
		and widget._energy == 0.0 and float(material.get_shader_parameter("fill")) < 0.0)
	_check("fuel card needs no per-frame or physics processing", not widget.is_processing() and not widget.is_physics_processing())


func _motion_signature(widget: Control) -> Array:
	var material: ShaderMaterial = widget._liquid_material
	return [widget._motion_time, widget._tilt, widget._velocity, widget._target, widget._energy,
		material.get_shader_parameter("sample_clock"), material.get_shader_parameter("tilt"),
		material.get_shader_parameter("tilt_velocity"), material.get_shader_parameter("target_tilt"),
		material.get_shader_parameter("wave_energy")]


func _test_geometry(widget: Control) -> void:
	widget.set_appearance("normal", 0.94, false)
	await _settle()
	var normal_height: float = widget.graphic.size.y
	_check("full tank graphic has matching shader dimensions", _geometry_matches(widget))
	widget.set_appearance("small", 0.94, true)
	await _settle()
	_check("compact tank remains visible and shorter", widget.graphic.visible and widget.graphic.size.y < normal_height
		and widget.scale.is_equal_approx(Vector2(0.85, 0.85)) and _geometry_matches(widget))
	widget.set_appearance("large", 0.94, false)
	await _settle()
	_check("large tank restores geometry at the requested scale", widget.graphic.visible
		and widget.scale.is_equal_approx(Vector2(1.2, 1.2)) and _geometry_matches(widget))


func _geometry_matches(widget: Control) -> bool:
	var liquid: ColorRect = widget._liquid
	var rect_size: Vector2 = widget._liquid_material.get_shader_parameter("rect_size")
	return liquid.size.x > 0.0 and liquid.size.y > 0.0 and liquid.position.x >= 0.0 and liquid.position.y >= 0.0 \
		and liquid.position.x + liquid.size.x <= widget.graphic.size.x \
		and liquid.position.y + liquid.size.y <= widget.graphic.size.y and rect_size.is_equal_approx(liquid.size)


func _test_visibility() -> void:
	var manager := OverlayManager.new({preset = "custom", visible = ["fuel"]}, "en")
	root.add_child(manager)
	await _settle()
	var sample := _fuel()
	manager.refresh_numbers({telemetry = _telemetry(1.0), mass_sample = sample})
	manager.refresh_numbers({telemetry = _telemetry(1.1, 70.0), mass_sample = sample})
	var widget: Control = manager.frames.fuel
	var before := _motion_signature(widget)
	manager.visible = false
	var hidden := _motion_signature(widget)
	manager.refresh_numbers({telemetry = _telemetry(1.2, -70.0), mass_sample = sample})
	_check("manager-hidden fuel skips motion updates", _motion_signature(widget) == hidden)
	manager.visible = true
	manager.refresh_numbers({telemetry = _telemetry(1.3, -70.0), mass_sample = sample})
	_check("reopened fuel adopts current motion without stale impulse", widget._motion_time == 1.3
		and is_equal_approx(widget._tilt, widget._target) and widget._energy == 0.0, str([before, hidden, _motion_signature(widget)]))
	manager.set_overlay_visible("fuel", false)
	var closed := _motion_signature(widget)
	manager.refresh_numbers({telemetry = _telemetry(1.4, 45.0), mass_sample = sample})
	_check("closed fuel skips motion updates", _motion_signature(widget) == closed)
	manager.set_overlay_visible("fuel", true)
	manager.refresh_numbers({telemetry = _telemetry(1.5, 45.0), mass_sample = sample})
	_check("reopened widget seeds the latest pose", widget._motion_time == 1.5
		and is_equal_approx(widget._tilt, widget._target) and widget._energy == 0.0)
	manager.queue_free()
	await process_frame


## Optional production-widget fixture; it does not claim a running flight or hardware qualification.
func _rendered_fixture(requested_dir: String) -> void:
	if requested_dir.is_empty():
		_check("capture directory is supplied", false)
		return
	var output := requested_dir
	if not output.is_absolute_path():
		output = ProjectSettings.globalize_path("res://").path_join(output).simplify_path()
	for filename: String in ["board.png", "motion_before.png", "motion_after.png"]:
		if FileAccess.file_exists(output.path_join(filename)):
			_check("fixture never overwrites a prior image", false, output.path_join(filename))
			return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		_check("fixture output directory was created", false, output)
		return
	var background := ColorRect.new()
	background.color = Color("18232c")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(background)
	_stage.move_child(background, 0)
	var widgets: Array = []
	var families := ["glow", "gasoline", "kerosene", "kerosene", ""]
	for i in families.size():
		var widget := FuelInstrument.new()
		_stage.add_child(widget)
		widget.position = Vector2(20 + i * 370, 40)
		var sample := _fuel(families[i], 0.5 if i < 3 else 0.08)
		if i == 3:
			sample.low_fuel = true
			sample.reserve_estimated = true
		if i == 4: sample = {}
		_refresh(widget, sample, _telemetry(20.0))
		widgets.append(widget)
	Clock.update(20.0)
	await _settle()
	await RenderingServer.frame_post_draw
	var board: Image = root.get_texture().get_image()
	_check("fixture board uses a 1080p viewport", board.get_size() == Vector2i(1920, 1080), str(board.get_size()))
	_check("fixture board was saved", board.save_png(output.path_join("board.png")) == OK)

	var tank: Control = widgets[0]
	var sample := _fuel("glow", 0.5)
	tank.reset_flight()
	_refresh(tank, sample, _telemetry(20.0))
	_refresh(tank, sample, _telemetry(20.1, 70.0, 15.0, 1.4))
	Clock.update(20.1)
	var before: Image = await _tank_image(tank)
	Clock.update(20.25)
	var after: Image = await _tank_image(tank)
	var repeated: Image = await _tank_image(tank)
	_check("fixed-fill liquid pixels change with motion", before.get_data() != after.get_data())
	_check("identical paused clock produces identical liquid pixels", after.get_data() == repeated.get_data())
	_check("motion before image was saved", before.save_png(output.path_join("motion_before.png")) == OK)
	_check("motion after image was saved", after.save_png(output.path_join("motion_after.png")) == OK)

	# No wave phase: a rendered clock slightly behind the accepted sample must clamp to zero elapsed time.
	tank._liquid_material.set_shader_parameter("wave_energy", 0.0)
	Clock.update(20.1)
	var aligned: Image = await _tank_image(tank)
	Clock.update(20.09)
	var behind: Image = await _tank_image(tank)
	_check("render clock just behind the sample does not jump the spring", aligned.get_data() == behind.get_data())
	for fill: float in [0.0, 1.0]:
		sample = _fuel("glow", fill)
		tank.reset_flight()
		_refresh(tank, sample, _telemetry(30.0, 0.0))
		Clock.update(30.0)
		var level: Image = await _tank_image(tank)
		tank.reset_flight()
		_refresh(tank, sample, _telemetry(30.0, 85.0))
		var tilted: Image = await _tank_image(tank)
		_check("tilt cannot change an endpoint fill %.0f" % fill, level.get_data() == tilted.get_data())
	for widget: Control in widgets:
		widget.queue_free()
	background.queue_free()
	await process_frame


func _tank_image(widget: Control) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var rect: Rect2 = widget._liquid.get_global_rect()
	var pixels := Rect2i(Vector2i(roundi(rect.position.x), roundi(rect.position.y)),
		Vector2i(roundi(rect.size.x), roundi(rect.size.y)))
	return root.get_texture().get_image().get_region(pixels)
