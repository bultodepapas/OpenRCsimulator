# FUEL-07: start fill of a finite-fuel tank. The session refuels every reset to the selected fraction of the
# authored full tank, trims and flies from there, and records a non-default fill; Home offers the choice only
# for finite-fuel aircraft and keeps the preference across aircraft.
# Run: godot --headless --path app --script res://tests/test_fuel_start_fill.gd
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Home := preload("res://ui/home.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")

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
	_checkpoint_json_bounds()
	_session()
	_checkpoint_selection()
	_home()
	print("FUEL-07 start fill: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _checkpoint_json_bounds() -> void:
	var malformed: String = _carrier(PackedByteArray([0, 1, 2, 3]))
	_check("checksummed malformed Variant bytes are rejected", not CheckpointJson.decode(malformed).get("ok", false))
	var overlong_text: String = " ".repeat(int(CheckpointJson.MAX_TEXT_BYTES) + 1)
	_check("oversized checkpoint text is rejected", not CheckpointJson.decode(overlong_text).get("ok", false))
	var oversized_payload := PackedByteArray()
	oversized_payload.resize(int(CheckpointJson.MAX_PAYLOAD_BYTES) + 1)
	oversized_payload.fill(0)
	_check("JSON encoder refuses native payloads above 16 MiB",
		CheckpointJson.encode({"oversized": oversized_payload}).is_empty())
	_check("JSON decoder refuses raw payloads above 16 MiB",
		not CheckpointJson.decode(_carrier(oversized_payload)).get("ok", false))


func _carrier(payload: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(payload)
	return JSON.stringify({
		"format": CheckpointJson.FORMAT,
		"payload_base64": Marshalls.raw_to_base64(payload),
		"sha256": hashing.finish().hex_encode(),
	})


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


func _checkpoint_selection() -> void:
	for fill: float in [0.1, 0.5, 1.0]:
		var source: Node = Flight.new()
		source.input_enabled = false
		source.setup(GLOW)
		var full: float = source.aircraft.model.propulsion.glow.capacity_fuel_kg
		source.set_fuel_start_fill(fill)
		source.reset()
		var saved: Dictionary = source.checkpoint()
		# Selection metadata survives a JSON carrier; authoritative simulation arrays retain native bits.
		saved.fuel_session = JSON.parse_string(JSON.stringify(saved.fuel_session, "", true, true))
		var destination: Node = Flight.new()
		destination.input_enabled = false
		destination.setup(GLOW)
		_check("cross-session checkpoint restores selected fill %s" % fill,
			destination.restore_checkpoint(saved) and destination.fuel_start_fill == fill
			and destination.sim.continuous == source.sim.continuous)
		var transported: String = source.checkpoint_json()
		_check("lossless complete JSON checkpoint restores selected fill %s" % fill,
			destination.restore_checkpoint_json(transported) and destination.fuel_start_fill == fill
			and var_to_bytes(source.sim.checkpoint()) == var_to_bytes(destination.sim.checkpoint()))
		var before_transport: Dictionary = destination.checkpoint()
		var damaged: Dictionary = JSON.parse_string(transported)
		damaged.sha256 = "00"
		_check("damaged JSON carrier is refused transactionally", not destination.restore_checkpoint_json(JSON.stringify(damaged))
			and var_to_bytes(destination.checkpoint()) == var_to_bytes(before_transport))
		source.sim.step()
		destination.sim.step()
		_check("selected-fill checkpoint continues exactly %s" % fill,
			var_to_bytes(source.sim.checkpoint()) == var_to_bytes(destination.sim.checkpoint()))
		destination.reset()
		_check("restored reset refuels to source selection %s" % fill,
			is_equal_approx(destination.sim.continuous[1], destination.start_fuel_kg()))
		var before: Dictionary = destination.checkpoint()
		for bad: Variant in [0.0, -0.1, 1.01, NAN, "0.5", true]:
			var invalid: Dictionary = saved.duplicate(true)
			invalid.fuel_session.start_fill = bad
			_check("malformed fill restore is transactional %s" % str(bad),
				not destination.restore_checkpoint(invalid)
				and var_to_bytes(destination.checkpoint()) == var_to_bytes(before))
		var legacy: Dictionary = saved.duplicate(true)
		legacy.erase("fuel_session")
		_check("legacy checkpoint explicitly marks source fill unknown", destination.restore_checkpoint(legacy)
			and destination.trace_meta().get("fuel_start_fill_known", true) == false)
		if fill == 0.1:
			var unknown_selection: Dictionary = destination.checkpoint()
			var unknown_json: String = destination.checkpoint_json()
			var bad_unknown: Dictionary = unknown_selection.duplicate(true)
			bad_unknown.fuel_session.start_fill = "0.5"
			var before_bad_unknown: PackedByteArray = var_to_bytes(destination.checkpoint())
			_check("malformed unknown native selection is refused transactionally",
				not destination.restore_checkpoint(bad_unknown)
				and var_to_bytes(destination.checkpoint()) == before_bad_unknown)
			var decoded_unknown: Dictionary = CheckpointJson.decode(unknown_json)
			var bad_json_snapshot: Dictionary = decoded_unknown.snapshot.duplicate(true)
			bad_json_snapshot.fuel_session.start_fill = true
			var bad_unknown_json: String = CheckpointJson.encode(bad_json_snapshot)
			var before_bad_json: PackedByteArray = var_to_bytes(destination.checkpoint())
			_check("malformed unknown JSON selection is refused transactionally",
				not destination.restore_checkpoint_json(bad_unknown_json)
				and var_to_bytes(destination.checkpoint()) == before_bad_json)
			var next_destination: Node = Flight.new()
			next_destination.input_enabled = false
			next_destination.setup(GLOW)
			next_destination.set_fuel_start_fill(0.75)
			_check("native re-checkpoint preserves the next destination preference and exact state",
				next_destination.restore_checkpoint(unknown_selection)
				and next_destination.fuel_start_fill == 0.75
				and next_destination.trace_meta().get("fuel_start_fill_known", true) == false
				and next_destination.sim.continuous == destination.sim.continuous
				and var_to_bytes(next_destination.sim.checkpoint()) == var_to_bytes(destination.sim.checkpoint()))
			next_destination.reset()
			_check("native unknown selection resets to the receiving preference",
				next_destination.fuel_start_fill == 0.75
				and is_equal_approx(next_destination.mass_properties().fuel_remaining_kg, 0.75 * full)
				and next_destination.trace_meta().get("fuel_start_fill_known", true),
				"fill=%s remaining=%s expected=%s known=%s" % [next_destination.fuel_start_fill,
				str(next_destination.mass_properties().fuel_remaining_kg), str(0.75 * full),
					str(next_destination.trace_meta().get("fuel_start_fill_known", true))])
			next_destination.free()
			var json_destination: Node = Flight.new()
			json_destination.input_enabled = false
			json_destination.setup(GLOW)
			json_destination.set_fuel_start_fill(0.25)
			_check("JSON re-checkpoint preserves the next destination preference and exact state",
				json_destination.restore_checkpoint_json(unknown_json)
				and json_destination.fuel_start_fill == 0.25
				and json_destination.trace_meta().get("fuel_start_fill_known", true) == false
				and json_destination.sim.continuous == destination.sim.continuous
				and var_to_bytes(json_destination.sim.checkpoint()) == var_to_bytes(destination.sim.checkpoint()))
			var before_bad_unknown_json: PackedByteArray = var_to_bytes(json_destination.checkpoint())
			_check("malformed unknown JSON restore leaves state and selection untouched",
				not json_destination.restore_checkpoint_json(bad_unknown_json)
				and var_to_bytes(json_destination.checkpoint()) == before_bad_unknown_json
				and json_destination.fuel_start_fill == 0.25)
			json_destination.reset()
			_check("JSON unknown selection resets to the receiving preference",
				json_destination.fuel_start_fill == 0.25
				and is_equal_approx(json_destination.mass_properties().fuel_remaining_kg, 0.25 * full)
				and json_destination.trace_meta().get("fuel_start_fill_known", true),
				"fill=%s remaining=%s expected=%s known=%s" % [json_destination.fuel_start_fill,
				str(json_destination.mass_properties().fuel_remaining_kg), str(0.25 * full),
				str(json_destination.trace_meta().get("fuel_start_fill_known", true))])
			json_destination.free()
		source.free()
		destination.free()


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
