# D6e: dual rates and expo as stick shaping (input layer, never aerodynamic data). Checks the expo curve, the
# profile loaded from the aircraft data, and the session: "full" (the default of every FlightSession, so scripted
# maneuvers and goldens are untouched) flies the maximum throws; "normal" shapes the keyboard sticks by the manual's
# travel fractions and expo, adds the trims in maximum-throw units afterwards, and aircraft without controls.rates
# are unaffected under either name.
# Run: godot --headless --path . --script res://tests/test_rates.gd
extends SceneTree

const Commands := preload("res://input/commands.gd")
const AD := preload("res://physics/aircraft_data.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	# Expo: ends kept, centre softened, odd and monotonic.
	_check("expo keeps the ends", Commands.expo(1.0, 0.4) == 1.0 and Commands.expo(-1.0, 0.4) == -1.0 and Commands.expo(0.0, 0.4) == 0.0)
	_check("expo 0.4 takes a half stick to %.3f ((1 − 0.4)·0.5 + 0.4·0.125 = 0.35)" % Commands.expo(0.5, 0.4), absf(Commands.expo(0.5, 0.4) - 0.35) < 1e-12)
	_check("expo is odd", Commands.expo(-0.3, 0.6) == -Commands.expo(0.3, 0.6))
	var monotonic := true
	var last := -1.0
	for i in range(1, 201):
		var y := Commands.expo(-1.0 + i / 100.0, 0.9)
		monotonic = monotonic and y > last
		last = y
	_check("expo 0.9 is strictly increasing", monotonic)
	_check("no expo is the identity", Commands.expo(0.37, 0.0) == 0.37)
	var profile := { aileron = 0.5, elevator = 0.5, rudder = 0.8, aileron_expo = 0.2, elevator_expo = 0.4, rudder_expo = 0.6 }
	var shaped := Commands.shape_sticks({ roll = 1.0, pitch = -1.0, yaw = 0.5, throttle = 0.7 }, profile)
	_check("full sticks reach the travel fractions; throttle untouched", shaped.roll == 0.5 and shaped.pitch == -0.5 and absf(shaped.yaw - Commands.expo(0.5, 0.6) * 0.8) < 1e-12 and shaped.throttle == 0.7)
	var travel_only := Commands.shape_sticks({ roll = 0.5, pitch = 0.5, yaw = 0.5, throttle = 0.0 }, profile, false)
	_check("without expo only the travel applies", travel_only.roll == 0.25 and travel_only.pitch == 0.25 and travel_only.yaw == 0.4)

	# Data: the generated aircraft declare the manuals' normal rates; the Stik declares none.
	var avanti: Dictionary = AD.load_file(Catalog.entry("sebart-avanti-s-a200-p100rx").data)
	_check("Avanti data loads with controls.rates.normal", avanti.ok and avanti.model.controls.has("rates"), str(avanti.get("errors", [])))
	if avanti.ok and avanti.model.controls.has("rates"):
		var n: Dictionary = avanti.model.controls.rates.normal
		_check("Avanti normal mode: elevator 50 % travel, 40 % expo (manual p. 4)", n.elevator == 0.5 and n.elevator_expo == 0.4, str(n))
	for id in ["gp-extra-300s-60", "p51d-mustang-120"]:
		var data: Dictionary = AD.load_file(Catalog.entry(id).data)
		_check("%s declares controls.rates.normal with travel below 1" % id, data.ok and data.model.controls.has("rates")
			and data.model.controls.rates.normal.elevator < 1.0, str(data.get("errors", [])))
	var stik: Dictionary = AD.load_file(Catalog.entry(Catalog.DEFAULT_ID).data)
	_check("Stik declares no rates (its 20° throw is already its low rate)", stik.ok and not stik.model.controls.has("rates"))
	# Loader rejects an incomplete profile.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry("sebart-avanti-s-a200-p100rx").data))
	raw.controls.rates.normal.erase("rudder_expo")
	_check("an incomplete rates profile is an error", not AD.validate_and_derive(raw).ok)
	raw = JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry("sebart-avanti-s-a200-p100rx").data))
	raw.controls.rates.normal.elevator.value = 1.5
	_check("a travel fraction above 1 is an error", not AD.validate_and_derive(raw).ok)

	# Session: default "full" leaves the former behaviour; "normal" shapes the keyboard sticks; trims add afterwards.
	var session := FlightSession.new()
	session.setup(Catalog.entry("sebart-avanti-s-a200-p100rx").data, "sebart-avanti-s-a200-p100rx")
	root.add_child(session)
	session.input_enabled = false
	_check("a new session flies the full profile", session.rate_profile == "full" and not session.rates_active())
	session.commands = { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = session.start.throttle }
	var full: Dictionary = session.flown_commands()
	_check("full: a full pull is the trim plus one (clamped)", full.pitch == clampf(1.0 + session.trims.pitch, -1.0, 1.0), str(full))
	session.rate_profile = "normal"
	_check("normal: active on the keyboard with the Avanti's profile", session.rates_active())
	var normal: Dictionary = session.flown_commands()
	_check("normal: a full pull is half the throw plus the trim", absf(normal.pitch - clampf(0.5 + session.trims.pitch, -1.0, 1.0)) < 1e-12, str(normal))
	session.commands = { roll = 0.0, pitch = 0.5, yaw = 0.0, throttle = session.start.throttle }
	var half: Dictionary = session.flown_commands()
	_check("normal: half stick goes through 40 %% expo then 50 %% travel = %.4f plus the trim" % (Commands.expo(0.5, 0.4) * 0.5),
		absf(half.pitch - clampf(Commands.expo(0.5, 0.4) * 0.5 + session.trims.pitch, -1.0, 1.0)) < 1e-12)
	session.commands = { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = session.start.throttle }
	_check("normal: hands off is the trim alone (the start stays trimmed)", session.flown_commands().pitch == clampf(session.trims.pitch, -1.0, 1.0))
	var stik_session := FlightSession.new()
	stik_session.setup()
	root.add_child(stik_session)
	stik_session.input_enabled = false
	stik_session.rate_profile = "normal"
	stik_session.commands = { roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = stik_session.start.throttle }
	_check("Stik under 'normal': no profile, so the maximum throws", not stik_session.rates_active()
		and stik_session.flown_commands().pitch == clampf(1.0 + stik_session.trims.pitch, -1.0, 1.0))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
