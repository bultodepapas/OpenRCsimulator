# FW-MOON-11: the moon presets. "moonrise" finds the first full-moon dusk with the moon just risen in front of the
# pilot (the Harvest Moon, 2026-09-26, at the reference field), "moonrise_golden" starts that evening at golden hour,
# and "night" a full moon 18–30° up in full darkness in front of the pilot. They are solved like the sun presets, so
# they stay valid at another place; the Home cycle offers "Moonrise, time passing" (×20).
# Run: godot --headless --path . --script res://tests/test_world_moon_presets.gd
extends SceneTree

const Conditions := preload("res://render/world/conditions.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _in_view(azimuth_deg: float) -> bool:
	return absf(fposmod(azimuth_deg - Conditions.PILOT_FORWARD_AZIMUTH_DEG + 180.0, 360.0) - 180.0) <= Conditions.PILOT_VIEW_HALF_WIDTH_DEG


func _view(name: String, c: Dictionary, sky: Dictionary) -> void:
	var v: Dictionary = Conditions.MOON_VIEWS[name]
	_check("%s: sun in range" % name, sky.sun.elevation_deg >= v.sun_min_deg and sky.sun.elevation_deg <= v.sun_max_deg, str(sky.sun))
	_check("%s: moon height in range" % name, sky.moon.elevation_deg >= v.moon_min_deg and sky.moon.elevation_deg <= v.moon_max_deg, str(sky.moon))
	_check("%s: full moon" % name, sky.moon.illuminated >= v.illuminated_min, str(sky.moon.illuminated))
	_check("%s: in front of the pilot" % name, _in_view(sky.moon.azimuth_deg), str(sky.moon.azimuth_deg))
	print("  %s: %04d-%02d-%02d %05.2f h, sun %.1f°, moon az %.1f° el %.1f° lit %.3f" % [name, c.when.year, c.when.month,
		c.when.day, c.when.hour, sky.sun.elevation_deg, sky.moon.azimuth_deg, sky.moon.elevation_deg, sky.moon.illuminated])


func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	var rise := Conditions.resolve(PackedStringArray(["--time_of_day=moonrise"]))
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check("moonrise resolves", rise.time_of_day and rise.preset == "moonrise")
	_check("moonrise = the Harvest Moon, 2026-09-26", rise.when.year == 2026 and rise.when.month == 9 and rise.when.day == 26, str(rise.when))
	_view("moonrise", rise, Ephemeris.sky(rise.when))
	t0 = Time.get_ticks_usec()
	Conditions.resolve(PackedStringArray(["--time_of_day=moonrise"]))
	var cached_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  moonrise solve: %.0f ms first, %.1f ms cached" % [first_ms, cached_ms])
	_check("the solve is cached", cached_ms < 50.0, str(cached_ms))

	var golden := Conditions.resolve(PackedStringArray(["--time_of_day=moonrise_golden"]))
	var golden_sky := Ephemeris.sky(golden.when)
	_check("moonrise evening starts on the same day", golden.when.day == rise.when.day and golden.when.month == rise.when.month)
	_check("moonrise evening starts at golden hour (sun 6°)", absf(golden_sky.sun.elevation_deg - 6.0) < 0.05, str(golden_sky.sun.elevation_deg))
	_check("…before the moonrise moment", golden.when.hour < rise.when.hour)

	var night := Conditions.resolve(PackedStringArray(["--time_of_day=night"]))
	_view("night", night, Ephemeris.sky(night.when))
	_check("night is after the reference date", night.when.month > 6 or night.when.year > 2026, str(night.when))

	# Another place: the solver keeps the constraints (Buenos Aires, UTC−3).
	var south := Conditions.resolve(PackedStringArray(["--time_of_day=moonrise", "--lat=-34.6", "--lon=-58.4", "--utc_offset=-3"]))
	_check("moonrise resolves in the southern hemisphere", south.time_of_day, str(south))
	if south.time_of_day:
		_view("moonrise", south, Ephemeris.sky(south.when))

	# Home: the flowing choice.
	Conditions.session_preset = "moonrise"
	var flowing := Conditions.resolve(PackedStringArray())
	Conditions.session_preset = ""
	_check("Home Moonrise flows at ×20 from golden hour", flowing.preset == "moonrise_golden" and flowing.time_scale == 20.0, str(flowing))
	_check("Moonrise is a Home choice between Evening and Night",
		Conditions.HOME_CHOICES.find("moonrise") == Conditions.HOME_CHOICES.find("evening") + 1
		and Conditions.HOME_CHOICES.find("night") == Conditions.HOME_CHOICES.find("moonrise") + 1)
	_check("Moonrise has a label and a Spanish translation", Conditions.HOME_LABELS.moonrise == "Moonrise, time passing"
		and (load("res://i18n/es.po") as Translation).get_message("Moonrise, time passing") != "")
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
