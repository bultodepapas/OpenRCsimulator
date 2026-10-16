extends SceneTree

const ResponsiveGrid := preload("res://ui/responsive_grid.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const SkyControls := preload("res://ui/sky_controls.gd")
const WeatherDialog := preload("res://ui/weather_dialog.gd")

var _failures: int = 0
var _grid_sort_events: int = 0
var _grid_minimum_events: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for text_scale: float in [1.0, 2.0]:
			UiTheme.text_scale = text_scale
			var measured: GridContainer = _make_grid("MeasuredGrid")
			var reference: GridContainer = _make_grid("ReferenceGrid")
			measured.position = Vector2(0.0, 0.0)
			reference.position = Vector2(0.0, 450.0)
			root.add_child(measured)
			root.add_child(reference)
			await _settle()

			var case_name: String = "locale=%s text_scale=%s" % [locale, text_scale]
			var native_two_column_width: float = reference.get_combined_minimum_size().x
			var helper_width: float = ResponsiveGrid.two_column_minimum_width(measured)
			_check("minimum width matches native grid", is_equal_approx(helper_width, native_two_column_width), "%s helper=%s native=%s" % [case_name, helper_width, native_two_column_width])

			var starting_columns: int = measured.columns
			var starting_minimum: Vector2 = measured.get_combined_minimum_size()
			var events: Dictionary = { minimum = 0, sort = 0 }
			measured.minimum_size_changed.connect(func() -> void: events.minimum += 1)
			measured.sort_children.connect(func() -> void: events.sort += 1)
			for _index: int in 8:
				ResponsiveGrid.two_column_minimum_width(measured)
			await _settle()
			_check("measurement preserves columns", measured.columns == starting_columns, case_name)
			_check("measurement preserves minimum size", measured.get_combined_minimum_size().is_equal_approx(starting_minimum), case_name)
			_check("measurement emits no minimum-size or sort signals", int(events.minimum) == 0 and int(events.sort) == 0, "%s events=%s" % [case_name, events])

			for available_width: float in [helper_width - 1.0, helper_width + 1.0]:
				var expected_columns: int = 1 if helper_width > available_width else 2
				var native_columns: int = 1 if native_two_column_width > available_width else 2
				measured.columns = expected_columns
				reference.columns = native_columns
				measured.size = Vector2(available_width, 400.0)
				reference.size = Vector2(available_width, 400.0)
				await _settle()
				_check("responsive decision matches native width", measured.columns == reference.columns, "%s width=%s measured=%d native=%d" % [case_name, available_width, measured.columns, reference.columns])
				_check_child_geometry(measured, reference, case_name, available_width)

			root.remove_child(measured)
			root.remove_child(reference)
			measured.free()
			reference.free()
			await _check_condition_controls_no_churn(case_name)
	await _check_weather_no_churn()
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	print("all responsive grid checks passed" if _failures == 0 else "%d responsive grid checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_condition_controls_no_churn(case_name: String) -> void:
	var time_controls := TimeOfDayControls.new()
	time_controls.size = Vector2(960.0, 500.0)
	time_controls.theme = UiTheme.build()
	var sky_controls := SkyControls.new()
	sky_controls.size = Vector2(960.0, 500.0)
	sky_controls.theme = UiTheme.build()
	root.add_child(time_controls)
	root.add_child(sky_controls)
	await _settle()
	var grids: Array[GridContainer] = []
	grids.append_array(time_controls._responsive_grids)
	grids.append_array(sky_controls._responsive_grids)
	_connect_grid_events(grids)
	var starting_columns: Array[int] = []
	for grid: GridContainer in grids:
		starting_columns.append(grid.columns)
	_grid_sort_events = 0
	_grid_minimum_events = 0
	for _index: int in 4:
		time_controls._update_responsive_layout()
		sky_controls._update_responsive_layout()
		await process_frame
	_check("Time/Sky repeated layout pass emits no grid work", _grid_sort_events == 0 and _grid_minimum_events == 0, "%s sort=%d minimum=%d" % [case_name, _grid_sort_events, _grid_minimum_events])
	for index: int in grids.size():
		_check("Time/Sky repeated layout pass preserves columns", grids[index].columns == starting_columns[index], "%s grid=%s" % [case_name, grids[index].name])
	root.remove_child(time_controls)
	root.remove_child(sky_controls)
	time_controls.free()
	sky_controls.free()
	await _settle()


func _check_weather_no_churn() -> void:
	TranslationServer.set_locale("es")
	UiTheme.text_scale = 2.0
	root.size = Vector2i(480, 540)
	var scale_state: Dictionary = UiScale.apply(root)
	UiTheme.compact_layout = bool(scale_state.compact)
	var weather := WeatherDialog.new()
	root.add_child(weather)
	(weather.get_node("Modal") as Control).theme = UiTheme.build()
	await _settle()
	var grids: Array[GridContainer] = [weather.wind_grid, weather.turbulence_grid, weather.atmosphere_grid, weather.atmosphere_mode_row]
	_connect_grid_events(grids)
	var starting_columns: Array[int] = []
	for grid: GridContainer in grids:
		starting_columns.append(grid.columns)
	_grid_sort_events = 0
	_grid_minimum_events = 0
	for _index: int in 4:
		weather._update_scroll_height()
		await _settle()
	_check("narrow weather stress case uses one-column grids", starting_columns == [1, 1, 1, 1], "columns=%s" % [starting_columns])
	_check("weather repeated layout pass emits no grid work", _grid_sort_events == 0 and _grid_minimum_events == 0, "sort=%d minimum=%d" % [_grid_sort_events, _grid_minimum_events])
	for index: int in grids.size():
		_check("weather repeated layout pass preserves columns", grids[index].columns == starting_columns[index], "grid=%s" % grids[index].name)
	root.remove_child(weather)
	weather.free()
	await _settle()


func _connect_grid_events(grids: Array[GridContainer]) -> void:
	for grid: GridContainer in grids:
		grid.sort_children.connect(_on_grid_sort_children)
		grid.minimum_size_changed.connect(_on_grid_minimum_size_changed)


func _on_grid_sort_children() -> void:
	_grid_sort_events += 1


func _on_grid_minimum_size_changed() -> void:
	_grid_minimum_events += 1


func _make_grid(grid_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = grid_name
	grid.columns = 2
	grid.theme = UiTheme.build()
	grid.add_theme_constant_override("h_separation", 19)
	grid.add_theme_constant_override("v_separation", 7)

	var time_label := Label.new()
	time_label.text = tr("Local time")
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(time_label)

	var preset := OptionButton.new()
	preset.add_item(tr("Weather preset"))
	preset.add_item(tr("Wind preset"))
	preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(preset)
	grid.add_child(Node.new())

	var action := Button.new()
	action.text = tr("Sky & clouds")
	action.custom_minimum_size = Vector2(70.0, 28.0)
	grid.add_child(action)

	var hidden := Button.new()
	hidden.visible = false
	hidden.custom_minimum_size.x = 1200.0
	grid.add_child(hidden)

	var top_level := Button.new()
	top_level.custom_minimum_size.x = 900.0
	top_level.set_as_top_level(true)
	grid.add_child(top_level)

	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var card_label := Label.new()
	card_label.text = tr("Atmosphere mode")
	card.add_child(card_label)
	grid.add_child(card)

	var input := LineEdit.new()
	input.custom_minimum_size.x = 88.0
	grid.add_child(input)
	return grid


func _check_child_geometry(measured: GridContainer, reference: GridContainer, case_name: String, available_width: float) -> void:
	for index: int in measured.get_child_count():
		var measured_child: Control = measured.get_child(index) as Control
		var reference_child: Control = reference.get_child(index) as Control
		if measured_child == null or reference_child == null:
			continue
		if not measured_child.visible or measured_child.is_set_as_top_level():
			continue
		var same_geometry: bool = measured_child.position.is_equal_approx(reference_child.position)
		same_geometry = same_geometry and measured_child.size.is_equal_approx(reference_child.size)
		_check("native child geometry matches", same_geometry, "%s width=%s child=%s measured=%s native=%s" % [case_name, available_width, measured_child.name, measured_child.get_rect(), reference_child.get_rect()])


func _check(label_text: String, ok: bool, detail: String = "") -> void:
	if ok:
		return
	_failures += 1
	printerr("FAIL %s %s" % [label_text, detail])


func _settle() -> void:
	for _index: int in 3:
		await process_frame
