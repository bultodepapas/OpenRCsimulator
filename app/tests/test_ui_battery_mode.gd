# BAT-13: Home's battery mode lives in the flight details, appears only for catalog aircraft with battery_data,
# toggles ideal/pack, and falls back to ideal for aircraft without pack data. The flight route is covered by
# test_overlay_battery_flight.gd (--aircraft=… --battery=pack).
extends SceneTree

const Home := preload("res://ui/home.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const TIMBER := "turbo-lumber-evolution"

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	TranslationServer.set_locale("en")
	var home: Control = Home.new()
	check("battery choice sits in the flight details", home.battery_button.get_parent() == home._flight_details)
	home.set_aircraft(Catalog.DEFAULT_ID)
	check("aircraft without pack data hide the choice and stay ideal", not home.battery_button.visible and home.battery_mode == "ideal")
	home.set_aircraft(TIMBER)
	check("Timber shows the choice, ideal by default", home.battery_button.visible and home.battery_mode == "ideal"
		and home.battery_button.text == "Battery: ideal (never runs flat)")
	home.battery_button.pressed.emit()
	check("pressing selects the finite pack", home.battery_mode == "pack" and home.battery_button.text == "Battery: finite pack (experimental)")
	home.battery_button.pressed.emit()
	check("pressing again returns to ideal", home.battery_mode == "ideal")
	home.set_battery_mode("pack")
	home.set_aircraft(Catalog.DEFAULT_ID)
	check("changing to an aircraft without pack data falls back to ideal", home.battery_mode == "ideal" and not home.battery_button.visible)
	home.set_battery_mode("magic")
	check("unknown modes are refused", home.battery_mode == "ideal")
	home.set_aircraft("xcell-60-research")
	check("rotorcraft never show the choice", not home.battery_button.visible and home.battery_mode == "ideal")
	TranslationServer.set_locale("es")
	home.set_aircraft(TIMBER)
	check("Spanish label", home.battery_button.text == "Batería: ideal (nunca se agota)")
	TranslationServer.set_locale("en")
	home.free()
	print("BAT-13 Home battery mode: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
