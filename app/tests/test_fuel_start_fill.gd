# FUEL-07: start fill of a finite-fuel tank. The session refuels every reset to the selected fraction of the
# authored full tank, trims and flies from there, and records a non-default fill; Home offers the choice only
# for finite-fuel aircraft and keeps the preference across aircraft.
# Run: godot --headless --path app --script res://tests/test_fuel_start_fill.gd
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Home := preload("res://ui/home.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"
const GLOW_ID := "stik-glow-61fx-2t"

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_session()
	_home()
	print("FUEL-07 start fill: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _session() -> void:
	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.setup(GLOW)
	var full: float = flight.aircraft.model.propulsion.glow.initial_fuel_kg
	_check("a full tank is the default", flight.fuel_start_fill == 1.0 and flight.sim.continuous[1] == full)
	_check("fractions outside (0, 1] are refused", not flight.set_fuel_start_fill(0.0) and not flight.set_fuel_start_fill(1.2)
		and not flight.set_fuel_start_fill(NAN) and not flight.set_fuel_start_fill(-0.5) and flight.fuel_start_fill == 1.0)
	_check("trace metadata of a full start carries no fill key", not flight.trace_meta().has("fuel_start_fill"))
	_check("half fill accepted", flight.set_fuel_start_fill(0.5))
	flight.reset()
	_check("the reset loads half the tank and the session stays flyable",
		flight.is_flyable() and flight.sim.continuous[1] == 0.5 * full and flight.sim.fault_reason.is_empty(),
		"fuel %s kg" % str(flight.sim.continuous[1]))
	var live: Dictionary = flight.mass_properties()
	_check("the half-tank start sits behind the datum (the full-tank CG) and is lighter",
		live.get("ok", false) and live.cg_body_m[0] < 0.0 and live.mass_kg < flight.aircraft.model.mass_kg)
	_check("trace metadata records the start fill", flight.trace_meta().get("fuel_start_fill", NAN) == 0.5)
	for _tick in 480:
		flight.sim.step()
	_check("two seconds of flight from the half-tank trim stay healthy and keep burning",
		flight.sim.fault_reason.is_empty() and flight.sim.continuous[1] < 0.5 * full)
	flight.reset()
	_check("a later reset refuels to the selected fill, not to full", flight.sim.continuous[1] == 0.5 * full)
	flight.free()


func _home() -> void:
	TranslationServer.set_locale("en")
	var home: Control = Home.new()
	_check("fuel choice sits in the flight details", home.fuel_button.get_parent() == home._flight_details)
	_check("the catalog knows which aircraft burn a finite tank",
		Catalog.has_finite_fuel(GLOW_ID) and not Catalog.has_finite_fuel(Catalog.DEFAULT_ID) and not Catalog.has_finite_fuel("xcell-60-research"))
	home.set_aircraft(GLOW_ID)
	_check("a glow Stik shows the choice, full by default", home.fuel_button.visible and home.fuel_start_fill == 1.0
		and home.fuel_button.text == "Fuel: full tank")
	home.fuel_button.pressed.emit()
	_check("pressing selects three quarters", home.fuel_start_fill == 0.75 and home.fuel_button.text == "Fuel: 75 % of the tank")
	home.fuel_button.pressed.emit()
	home.fuel_button.pressed.emit()
	_check("then a half and a quarter", home.fuel_start_fill == 0.25)
	home.fuel_button.pressed.emit()
	_check("and back to full", home.fuel_start_fill == 1.0)
	home.set_fuel_fill(0.5)
	home.set_aircraft(Catalog.DEFAULT_ID)
	_check("a fixed-fuel aircraft hides the choice and flies its build", not home.fuel_button.visible and home.fuel_start_fill == 1.0)
	home.set_aircraft(GLOW_ID)
	_check("returning to a glow Stik keeps the half-tank preference", home.fuel_start_fill == 0.5)
	home.set_fuel_fill(0.33)
	_check("fills outside the offered steps are ignored", home.fuel_start_fill == 0.5)
	TranslationServer.set_locale("es")
	home.set_fuel_fill(1.0)
	_check("Spanish label", home.fuel_button.text == "Combustible: depósito lleno")
	home.set_fuel_fill(0.5)
	_check("Spanish fraction label", home.fuel_button.text == "Combustible: 50 % del depósito")
	TranslationServer.set_locale("en")
	home.free()
