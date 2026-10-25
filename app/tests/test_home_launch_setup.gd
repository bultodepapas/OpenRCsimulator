# UI-34c: preparation observes effective setup changes, including direct button cycles.
extends SceneTree

const Home := preload("res://ui/home.gd")
const Weather := preload("res://physics/wind_config.gd")
var _failures := 0


func _initialize() -> void:
	var home: Control = Home.new()
	var changes := {count = 0}
	home.launch_setup_changed.connect(func() -> void: changes.count += 1)
	home.set_aircraft("turbo-lumber-evolution")
	home.set_battery_mode("pack")
	changes.count = 0
	home.set_battery_mode("pack")
	home.set_battery_mode("invalid")
	_check("repeated or invalid battery selection keeps debounce", changes.count == 0)
	home._cycle_battery_mode()
	_check("battery button cycle notifies effective change", changes.count == 1 and home.battery_mode == "ideal")
	home._cycle_battery_mode()
	_check("return to pack notifies again", changes.count == 2 and home.battery_mode == "pack")
	home.set_fuel_fill(0.5)
	_check("unavailable finite fuel does not invalidate actual setup", changes.count == 2 and home.fuel_start_fill == 1.0)
	home.set_aircraft("gp-extra-300s-60")
	home.set_fuel_fill(1.0)
	changes.count = 0
	home.set_fuel_fill(1.0)
	home._cycle_fuel_fill()
	_check("fuel button cycle notifies effective change", changes.count == 1 and home.fuel_start_fill != 1.0)
	home.set_fuel_fill(home.fuel_start_fill)
	home.set_fuel_fill(-1.0)
	_check("repeated or invalid fuel does not restart debounce", changes.count == 1)
	home.set_start_choice("airborne")
	changes.count = 0
	home.set_start_choice("airborne")
	home.set_start_choice("runway")
	_check("start notifies only actual transition", changes.count == 1 and home.start_choice == "runway")
	home.runway_available = false
	home.reapply_start_preference()
	_check("field constraint changing effective start notifies", changes.count == 2 and home.start_choice == "airborne")
	home.set_weather_config(Weather.defaults())
	changes.count = 0
	home.set_weather_config(Weather.defaults())
	home.set_weather_config({})
	_check("same or invalid weather normalizing to defaults keeps debounce", changes.count == 0)
	home.set_weather_config(Weather.GENTLE_PRACTICE)
	_check("validated weather change notifies", changes.count == 1)
	home.set_weather_config(Weather.GENTLE_PRACTICE.duplicate(true))
	_check("equal detached weather does not restart debounce", changes.count == 1)
	home.free()
	print("Home launch setup: 11 checks, %d failed" % _failures)
	quit(1 if _failures else 0)


func _check(label: String, passed: bool) -> void:
	print("ok   " + label if passed else "FAIL " + label)
	if not passed:
		_failures += 1
