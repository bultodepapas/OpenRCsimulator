# HUD-13-R14: motion-reactive fuel presentation. Never writes to the flight model.
extends "res://render/overlays/player_instrument.gd"

const LIQUID := preload("res://render/overlays/fuel_liquid.gdshader")
const Clock := preload("res://render/shader_clock.gd")
const LOW_COLOR := Color("ff8a75")
var _liquid: ColorRect
var _liquid_material: ShaderMaterial
var _tank_style: StyleBoxFlat
var _family := ""
var _reserve := NAN
var _reserve_estimated := false
var _empty := false
var _face_key: Array = []
var _motion_time := -INF
var _tilt := 0.0
var _velocity := 0.0
var _target := 0.0
var _energy := 0.0
var _foam := 0.0
var _force_g := 1.0
var _wave_phase := 0.0
var _bubble_phase := 0.0
var _pitch := 0.0
var _bank := 0.0
var _load := 1.0
var _fill_key := -2.0


func _init() -> void:
	super("fuel")
	Clock.register()
	_tank_style = _surface_style(Color("080e12"), 12)
	_tank_style.border_color = Color("85969d", 0.5)
	_tank_style.set_border_width_all(1)
	_liquid_material = ShaderMaterial.new()
	_liquid_material.shader = LIQUID
	_liquid = ColorRect.new()
	_liquid.name = "LiquidFuel"
	_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_liquid.material = _liquid_material
	graphic.add_child(_liquid)
	graphic.resized.connect(_resize_liquid)
	visibility_changed.connect(_reset_motion)
	minimum_size_changed.connect(_queue_content_fit)
	graphic.tooltip_text = tr("Liquid responds to flight loads. Quantity comes from the fuel tanks.")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.max_lines_visible = 2
	_apply_density()


func _apply_density() -> void:
	super()
	graphic.show()
	graphic.custom_minimum_size.y = 72 if _compact else 132
	_separator.hide()
	_resize_liquid()


func _resize_liquid() -> void:
	if _liquid == null: return
	_liquid.position = Vector2(7, 7)
	_liquid.size = Vector2(maxf(1, graphic.size.x - 46), maxf(1, graphic.size.y - 31))
	_liquid_material.set_shader_parameter("rect_size", _liquid.size)
	graphic.queue_redraw()


func reset_flight() -> void:
	super()
	_reset_motion()
	_face_key.clear()


func _reset_motion() -> void:
	_motion_time = -INF
	_tilt = 0.0
	_velocity = 0.0
	_target = 0.0
	_energy = 0.0
	_foam = 0.0
	_force_g = 1.0
	_wave_phase = 0.0
	_bubble_phase = 0.0
	_publish_motion()


func refresh(t: Dictionary, system: String, peak: float, battery: Dictionary, fuel: Dictionary, trims: Dictionary = {}, rpm: float = NAN) -> void:
	# Labels retain the shared change cache; motion has its own bounded 10 Hz input.
	super(t, system, peak, battery, fuel, trims, rpm)
	var available := bool(fuel.get("ok", false)) and bool(fuel.get("finite_fuel", false)) and is_finite(_fraction)
	var family := fuel_family(fuel) if available else ""
	var reserve := _numeric(fuel.get("reserve_fraction")) if available else NAN
	if reserve < 0.0 or reserve > 1.0: reserve = NAN
	var empty := available and _numeric(fuel.get("fuel_usable_kg")) <= 0.0
	if available and _fraction <= 0.0: empty = true
	var color: Color = {"glow": Color("bc9cff"), "gasoline": Color("61ddbe")}.get(family, ACCENT)
	if bool(fuel.get("low_fuel", false)) or empty: color = LOW_COLOR
	var estimated := bool(fuel.get("reserve_estimated", false))
	var key := [family, reserve if is_finite(reserve) else null, estimated, empty, available, color, TranslationServer.get_locale()]
	_graphic_color = color
	if key != _face_key:
		_face_key = key
		_family = family
		_reserve = reserve
		_reserve_estimated = estimated
		_empty = empty
		_liquid_material.set_shader_parameter("liquid_color", color)
		graphic.tooltip_text = tr("Liquid responds to flight loads. Quantity comes from the fuel tanks.")
		if is_finite(reserve):
			graphic.tooltip_text += "\n" + tr("Reserve: %d%% (%s)") % [roundi(reserve * 100.0), tr("estimated reserve") if estimated else tr("authored reserve")]
		graphic.queue_redraw()
	var fill_value := _fraction if available else -1.0
	if fill_value != _fill_key:
		_fill_key = fill_value
		_liquid_material.set_shader_parameter("fill", fill_value)
	if empty:
		subtitle.text = tr("No usable fuel · land now")
		subtitle.tooltip_text = subtitle.text
	elif available and not fuel.get("low_fuel", false):
		# Restore the ordinary subtitle when a refuel changes only usable fuel.
		subtitle.text = tr("Tank level · remaining fuel")
		subtitle.tooltip_text = subtitle.text
	subtitle.add_theme_color_override("font_color", LOW_COLOR if available and (empty or fuel.get("low_fuel", false)) else MUTED)
	_update_motion(t, available)


func _refresh_fuel(fuel: Dictionary) -> void:
	if not fuel.get("ok", false) or not fuel.get("finite_fuel", false):
		super({})
		return
	_fraction = _numeric(fuel.get("fill_fraction"))
	var volume := _numeric(fuel.get("volume_ml"))
	if not is_finite(_fraction) or _fraction < 0.0 or _fraction > 1.0 or not is_finite(volume) or volume < 0.0:
		_fraction = NAN
		value_label.text = "—"
		unit_label.text = ""
		subtitle.text = tr("Fuel telemetry unavailable")
		_details(tr("REMAINING"), "—", tr("FUEL MASS"), "—")
		return
	var mass := _numeric(fuel.get("fuel_remaining_kg"))
	if not is_finite(mass) or mass < 0.0:
		var sanitized := fuel.duplicate()
		sanitized.fuel_remaining_kg = NAN
		super(sanitized)
	else:
		super(fuel)


static func _numeric(value: Variant) -> float:
	return float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] else NAN


func _make_view_key(t: Dictionary, system: String, peak: float, battery: Dictionary, fuel: Dictionary, trims: Dictionary, rpm: float) -> Array:
	var key := super(t, system, peak, battery, fuel, trims, rpm)
	var usable := _numeric(fuel.get("fuel_usable_kg"))
	key.append(usable if is_finite(usable) else null)
	return key


static func fuel_family(fuel: Dictionary) -> String:
	var family := ""
	var stores: Variant = fuel.get("stores", [])
	if not stores is Array: return ""
	for store: Variant in stores:
		if not store is Dictionary: return ""
		if str(store.get("kind", "tank")) == "feed_line": continue
		var current := str(store.get("family", ""))
		if current.is_empty(): return ""
		if not family.is_empty() and current != family: return ""
		family = current
	return family


# A damped visual spring, not a simulation of pickup, starvation or fuel mass distribution.
# The same closed form is used in the shader between accepted telemetry samples.
static func spring(position: float, velocity: float, target: float, dt: float, force_g := 1.0) -> Vector2:
	# Gravity-wave frequency scales with sqrt(g). This bounded visual analog does
	# not claim the natural frequency of an aircraft's particular tank geometry.
	var rate := sqrt(clampf(force_g, 0.04, 6.0))
	var damping := 4.0 * rate
	var frequency := 9.0 * rate
	var offset := position - target
	var coefficient := (velocity + damping * offset) / frequency
	var c := cos(frequency * dt)
	var s := sin(frequency * dt)
	var decay := exp(-damping * dt)
	return Vector2(target + decay * (offset * c + coefficient * s),
		decay * (velocity * c - (damping * coefficient + frequency * offset) * s))


func _update_motion(t: Dictionary, available: bool) -> void:
	var now := _numeric(t.get("time_s"))
	var bank := _numeric(t.get("bank_deg"))
	var pitch := _numeric(t.get("pitch_deg"))
	var load_factor := _numeric(t.get("load_factor"))
	if not available or not is_finite(now) or not is_finite(bank) or not is_finite(pitch) or not is_finite(load_factor):
		if _motion_time != -INF: _reset_motion()
		return
	# Full-circle angle from body down, toward body right. Accepted force telemetry
	# distinguishes negative-g inverted flight from a positive-g roll or banked turn.
	# Older/synthetic snapshots without lateral force retain an attitude-only fallback.
	var target := deg_to_rad(bank)
	var force_g := minf(absf(load_factor), 6.0)
	if t.has("specific_force_right_g"):
		var lateral := _numeric(t.specific_force_right_g)
		if not is_finite(lateral):
			_reset_motion()
			return
		var down := Vector2(-clampf(lateral, -12.0, 12.0), clampf(load_factor, -12.0, 12.0))
		force_g = minf(down.length(), 6.0)
		# Near zero projected g has no well-defined free surface; retain its last direction.
		target = atan2(down.x, down.y) if down.length() >= 0.05 else _target
	if not is_finite(_motion_time) or now < _motion_time or now - _motion_time > 0.5:
		_tilt = target
		_velocity = 0.0
		_energy = 0.0
		_foam = 0.0
		_wave_phase = 0.0
		_bubble_phase = 0.0
	elif now == _motion_time:
		return # Paused/repeated snapshot: no integration or new wave impulse.
	else:
		var dt := now - _motion_time
		# Unwrap the target so crossing +180/-180 never spins the liquid the long way.
		target = _target + wrapf(target - _target, -PI, PI)
		var state := spring(_tilt, _velocity, _target, dt, _force_g)
		_tilt = state.x
		_velocity = state.y
		var rate := sqrt(clampf(_force_g, 0.04, 6.0))
		_wave_phase = fposmod(_wave_phase + 5.0 * rate * dt, TAU)
		_bubble_phase = fposmod(_bubble_phase + rate * dt, 64.0)
		var impulse := absf(target - _target) * 0.45
		impulse += absf(wrapf(bank - _bank, -180.0, 180.0)) / 160.0
		impulse += absf(wrapf(pitch - _pitch, -180.0, 180.0)) / 90.0
		impulse += minf(absf(load_factor - _load), 6.0) * 0.18 + absf(force_g - _force_g) * 0.12
		_energy = minf(1.0, _energy * exp(-1.8 * dt) + impulse)
		# Entrained air outlives the wave impulse, then clears in steady flight.
		_foam = minf(1.0, _foam * exp(-0.65 * dt) + impulse * 0.8)
		if _foam < 0.001: _foam = 0.0
		if absf(_tilt - target) < 0.0005 and absf(_velocity) < 0.002 and _energy < 0.002:
			_tilt = target
			_velocity = 0.0
			_energy = 0.0
	_target = target
	_pitch = pitch
	_bank = bank
	_load = load_factor
	_force_g = force_g
	_motion_time = now
	_publish_motion()


func _publish_motion() -> void:
	if _liquid_material == null: return
	_liquid_material.set_shader_parameter("sample_clock", Clock.value(_motion_time) if is_finite(_motion_time) else 0.0)
	_liquid_material.set_shader_parameter("tilt", _tilt)
	_liquid_material.set_shader_parameter("tilt_velocity", _velocity)
	_liquid_material.set_shader_parameter("target_tilt", _target)
	_liquid_material.set_shader_parameter("wave_energy", _energy)
	_liquid_material.set_shader_parameter("foam_energy", _foam)
	_liquid_material.set_shader_parameter("force_g", _force_g)
	_liquid_material.set_shader_parameter("wave_phase", _wave_phase)
	_liquid_material.set_shader_parameter("bubble_phase", _bubble_phase)


func _draw_instrument() -> void:
	if _tank_style == null: return
	var w := graphic.size.x
	var h := graphic.size.y
	var chamber := Rect2(1, 1, w - 34, h - 19)
	graphic.draw_style_box(_tank_style, chamber)
	# Inner ribs and witness lines remain visible through the translucent liquid.
	var inner := Rect2(Vector2(7, 7), Vector2(w - 46, h - 31))
	for i: int in [1, 2]:
		var x := inner.position.x + inner.size.x * i / 3.0
		graphic.draw_line(Vector2(x, inner.position.y + 5), Vector2(x, inner.end.y - 5), Color("a6bec8", 0.16), 3, true)
		graphic.draw_line(Vector2(x + 2, inner.position.y + 5), Vector2(x + 2, inner.end.y - 5), Color("03090c", 0.65), 1, true)
	for i: int in [1, 2, 3]:
		var y := inner.position.y + inner.size.y * i / 4.0
		graphic.draw_line(Vector2(inner.position.x + 5, y), Vector2(inner.end.x - 5, y), Color("a6bec8", 0.07), 1, true)
	# Fixed graduation scale remains readable while the liquid surface moves.
	for i in 11:
		var y := 7.0 + (h - 31.0) * i / 10.0
		graphic.draw_line(Vector2(w - 32, y), Vector2(w - (25 if i % 5 == 0 else 28), y), MUTED if i % 5 == 0 else TRACK, 1, true)
		if i % 5 == 0:
			_graphic_text(str(100 - i * 10), Vector2(w, y + 3), MUTED, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	if is_finite(_reserve):
		var y := 7.0 + (h - 31.0) * (1.0 - clampf(_reserve, 0.0, 1.0))
		graphic.draw_colored_polygon(PackedVector2Array([Vector2(0, y), Vector2(-4, y - 4), Vector2(-4, y + 4)]), LOW_COLOR)
		# Side marker represents the accepted aggregate reserve; never a guessed 10%.
		graphic.draw_line(Vector2(w - 36, y), Vector2(w - 28, y), LOW_COLOR, 2, true)
	var family_text: String = {"kerosene": tr("TURBINE"), "glow": tr("NITRO / GLOW"), "gasoline": tr("GASOLINE")}.get(_family, tr("FUEL"))
	graphic.draw_circle(Vector2(4, h - 4), 2.5, _graphic_color if is_finite(_fraction) else MUTED, true, -1, true)
	_graphic_text(family_text, Vector2(12, h - 1), MUTED, 9)
	if is_finite(_reserve):
		_graphic_text("%s %s%d%%" % [tr("RESERVE"), "~" if _reserve_estimated else "", roundi(_reserve * 100.0)], Vector2(w, h - 1), LOW_COLOR, 9, HORIZONTAL_ALIGNMENT_RIGHT)
