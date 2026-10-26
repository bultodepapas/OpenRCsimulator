# The aircraft catalog (EX-03, AV-03, P51-03, MENU-PLAN UI-05): the one place where an aircraft ID resolves to its physics
# data file, its visual builder and its anchors, so a flight never mixes one airplane's model with another's physics.
# Presentation and paths only: no physical parameter is copied here (they live in the data files).
# Paths are strings, not preloads: the simulation side reads `data` without loading render code.
extends RefCounted

## What the menu may offer: FLYABLE (the reference flight model: trimmed, regression-tested with golden flights and compared
## with independent data; pilot validation at Gate 2 still pending), EXPERIMENTAL (flies on a first, unvalidated physics
## estimate), PREVIEW (a visual model only: no flight data, Fly is refused).
const FLYABLE := "flyable"
const EXPERIMENTAL := "experimental"
const PREVIEW := "preview"

const DEFAULT_ID := "jensen-das-ugly-stik-60"
## Per-ID answers read from stock data files, which never change while the application runs.
static var _finite_fuel_cache := {}
static var _runway_cache := {}
static var _hand_launch_cache := {}

## In menu order. `short_name` (UI-34b) is the one-line label for the Home card and catalog list; `name` stays complete in
## details and tooltips. `name` is a proper name (never translated; the Timber's fictional name is the one exception: es.po carries
## its Spanish form and ui/home.gd passes names through tr()); `summary` and `status_note` are English source strings
## (tr() at the call site). `data` is "" for a preview. render/airplane.gd builds each ID with the model team's builder
## and knows its datum; tests/test_aircraft_catalog.gd checks that every ID builds and every flyable one trims.
const ENTRIES := [
	{
		id = "jensen-das-ugly-stik-60",
		visual_family = "jensen-das-ugly-stik-60",
		name = "Ugly Stick",
		short_name = "Ugly Stick",
		summary = "High-wing sport trainer · 1.52 m · .61 glow",
		status = FLYABLE,
		status_note = "Full-rudder sideslip and R02 yaw damping acceptance remain pending.",
		data = "res://data/aircraft/jensen_ugly_stik_60.json",
	},
	{
		# NITRO-61FX: the default Stik's own O.S. MAX-61FX on its APC 12x6, flown by the glow engine model.
		id = "stik-glow-61fx-2t",
		visual_family = "jensen-das-ugly-stik-60",
		name = "Ugly Stick · MAX-61FX",
		short_name = "Ugly Stick · 61FX",
		summary = "High-wing sport trainer · 1.52 m · .61 2-stroke glow",
		status = EXPERIMENTAL,
		status_note = "Experimental: the Stik's own O.S. MAX-61FX on the glow engine model; profile scaled from the MAX-55AX, not flight-validated.",
		data = "res://data/aircraft/stik_glow_61fx_2t.json",
	},
	{
		id = "stik-glow-55ax-2t",
		visual_family = "jensen-das-ugly-stik-60",
		name = "Ugly Stick · MAX-55AX",
		short_name = "Ugly Stick · 55AX",
		summary = "High-wing sport trainer · 1.52 m · .55 2-stroke glow",
		status = EXPERIMENTAL,
		status_note = "Experimental: inferred O.S. MAX-55AX 2-stroke installation and engine profile; not flight-validated.",
		data = "res://data/aircraft/stik_glow_55ax_2t.json",
	},
	{
		id = "stik-glow-fs64v-4t",
		visual_family = "jensen-das-ugly-stik-60",
		name = "Ugly Stick · FS-64V",
		short_name = "Ugly Stick · FS-64V",
		summary = "High-wing sport trainer · 1.52 m · .64 4-stroke glow",
		status = EXPERIMENTAL,
		status_note = "Experimental: inferred O.S. FS-64V 4-stroke installation and engine profile; not flight-validated.",
		data = "res://data/aircraft/stik_glow_fs64v_4t.json",
	},
	{
		id = "gp-extra-300s-60",
		visual_family = "gp-extra-300s-60",
		name = "Great Planes Extra 300S .60",
		short_name = "Extra 300S",
		summary = "Low-wing aerobat · 1.63 m · .61 glow",
		status = EXPERIMENTAL,
		status_note = "Experimental finite MAX-61FX glow installation from the NITRO candidate profile; Extra-specific fuel-feed calibration is unavailable, and physical validation is pending.",
		data = "res://data/aircraft/gp_extra_300s_60.json",
	},
	{
		id = "p51d-mustang-120",
		visual_family = "p51d-mustang-120",
		name = "P-51D Mustang 1/4",
		short_name = "P-51D Mustang",
		summary = "Giant-scale warbird · 2.82 m · 120 cc gasoline",
		status = EXPERIMENTAL,
		status_note = "Experimental: estimated quarter-scale physics, not yet flight-tested.",
		data = "res://data/aircraft/p51d_mustang_120.json",
	},
	{
		# F4U-09: the author's g1.3 model (1:4.5, CARF-Models class) with a Moki S250 radial; historical name as the P-51
		# (owner decision F4U-13: no licence required).
		id = "f4u-corsair-250",
		visual_family = "f4u-corsair-250",
		name = "F4U-1D Corsair 1/4.5",
		short_name = "F4U Corsair",
		summary = "Giant-scale warbird · 2.78 m · Moki 250 radial",
		status = EXPERIMENTAL,
		status_note = "Experimental: estimated 1/4.5 physics (CARF-class kit, Moki S250 radial), not yet flight-tested. Runway or airborne start.",
		data = "res://data/aircraft/f4u_corsair_250.json",
	},
	{
		id = "sebart-avanti-s-a200-p100rx",
		visual_family = "sebart-avanti-s-a200-p100rx",
		name = "Ventage Jet",
		short_name = "Ventage Jet",
		summary = "Sport jet · 2.00 m · JetCat P100-RX turbine",
		status = EXPERIMENTAL,
		status_note = "Experimental: first physics estimate (turbine, kit and owner data), not yet flight-tested. Runway or airborne start.",
		data = "res://data/aircraft/sebart_avanti_s_a200.json",
	},
	{
		# TT-06: the author's r1 glTF model (assets/aircraft/turbo-lumber-evolution), inspired by the E-flite Turbo Timber
		# Evolution; fictional name (Spanish "Turbo Tronco Evolución" in es.po). TT-07/08 estimated electric configuration.
		id = "turbo-lumber-evolution",
		visual_family = "turbo-lumber-evolution",
		name = "Turbo Lumber Evolution",
		short_name = "Turbo Lumber",
		summary = "High-wing STOL · 1.55 m · 4S electric",
		status = EXPERIMENTAL,
		status_note = "Experimental: estimated electric motor and borrowed propeller data. Fixed wheels, flaps up, assists off.",
		data = "res://data/aircraft/turbo_lumber_evolution.json",
		# BAT-13: the same airframe with a finite 4S LiPo class pack, ESC low-voltage cutoff and battery telemetry.
		battery_data = "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json",
	},
	{
		# X8-09: the author's r4 model (assets/aircraft/skywalker-x8), inspired by the Skywalker X8: NTNU flight-identified
		# aerodynamics on the tailless strip law (X8-04), elevon mixing (X8-03), pusher (X8-05), no landing gear, EPO
		# tolerant hull (X8-08). Working display name pending the owner's decision (docs/X8-PLAN.md D1).
		id = "skywalker-x8",
		visual_family = "skywalker-x8",
		name = "X8 Flying Wing",
		short_name = "X8 Wing",
		summary = "EPO flying wing · 2.12 m · 6S electric pusher",
		status = EXPERIMENTAL,
		status_note = "Experimental: NTNU flight-identified aerodynamics with an estimated electric drive; elevons, no landing gear (airborne start), tougher foam airframe. Not flight-validated.",
		data = "res://data/aircraft/skywalker_x8.json",
		# The finite 6S 5000 mAh class pack is the default battery mode, as on the Turbo Lumber.
		battery_data = "res://data/aircraft/battery/skywalker_x8_6s_pack.json",
	},
	{
		id = "xcell-60-research",
		vehicle = "rotorcraft",
		visual_family = "hx-700",
		name = "RC Helicopter Research Trainer",
		short_name = "X-Cell .60 Trainer",
		summary = "X-Cell reference physics · HX-700 visual",
		status = EXPERIMENTAL,
		status_note = "Experimental: X-Cell .60 reference physics with an HX-700 visual surrogate; ground pad or practice hover; not flight-validated.",
		data = "res://data/aircraft/xcell_60_research.json",
	},
]


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		out.append(e.id)
	return out


static func has(id: String) -> bool:
	return ids().has(id)


## Vehicle ownership is explicit where the catalog crosses into aircraft-only systems.
## Entries predating this field are airplanes.
static func is_rotorcraft(id: String) -> bool:
	return str(entry(id).get("vehicle", "airplane")) == "rotorcraft"


## Entries that carry flight data (never a PREVIEW): what physics, trace and session tests may load.
static func flyable_entries() -> Array:
	return ENTRIES.filter(func(e: Dictionary) -> bool: return e.status != PREVIEW and e.data != "")


## Flyable airplane configurations for airplane-only solvers and evidence loops.
static func airplane_flyable_entries() -> Array:
	return flyable_entries().filter(func(e: Dictionary) -> bool: return not is_rotorcraft(str(e.get("id", ""))))


## IDs of flyable_entries(), in menu order. Previews are skipped explicitly, never silently substituted.
static func flyable_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in flyable_entries():
		out.append(e.id)
	return out


## IDs of airplane_flyable_entries(), in catalog order.
static func airplane_flyable_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in airplane_flyable_entries():
		out.append(e.id)
	return out


## Unique visual families owned by the airplane model contract, including airplane previews.
static func airplane_visual_families() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids():
		if is_rotorcraft(id):
			continue
		var family := visual_family(id)
		if not out.has(family):
			out.append(family)
	return out


## The entry for `id`, or {} when unknown (callers must refuse it, never substitute another airplane).
static func entry(id: String) -> Dictionary:
	for e in ENTRIES:
		if e.id == id:
			return e
	return {}


## BAT-13 battery modes: "ideal" flies the aircraft's main data; "pack" flies its optional finite-pack data
## (same airframe and aircraft id, pack_ecm energy). Aircraft without battery data only offer "ideal".
## Owner decision 2026-10-19: the finite pack is the default wherever an aircraft provides it.
const BATTERY_MODES := ["ideal", "pack"]


static func battery_data(id: String) -> String:
	return str(entry(id).get("battery_data", ""))


## Whether the aircraft declares a finite fuel consumer, so a finite-store start fill applies.
## Stock data never changes while the application runs, so each answer is read once (UI-34c, UI-30 AS-8).
static func has_finite_fuel(id: String) -> bool:
	if not _finite_fuel_cache.has(id):
		_finite_fuel_cache[id] = _read_finite_fuel(id)
	return _finite_fuel_cache[id]


## Whether a runway start is supported (FlightSession validates the aircraft data's gear), cached per stock ID.
static func runway_supported(id: String) -> bool:
	if not _runway_cache.has(id):
		_runway_cache[id] = bool(load("res://sim/flight_session.gd").runway_aircraft_supported(id))
	return _runway_cache[id]


## X8-07: an airplane without landing gear starts by hand from the field instead of on the runway.
static func hand_launch_supported(id: String) -> bool:
	if not _hand_launch_cache.has(id):
		_hand_launch_cache[id] = bool(load("res://sim/flight_session.gd").hand_launch_aircraft_supported(id))
	return _hand_launch_cache[id]


## The one-line label for the Home card and catalog list; falls back to the full name.
static func short_name(id: String) -> String:
	var e := entry(id)
	return str(e.get("short_name", e.get("name", "")))


static func _read_finite_fuel(id: String) -> bool:
	if not can_fly(id) or is_rotorcraft(id):
		return false
	var path: String = str(entry(id).get("data", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary and raw.get("capabilities") is Dictionary):
		return false
	return str(raw.capabilities.get("energy", "")) in ["finite_glow_fuel", "finite_liquid_fuel"]


static func default_battery_mode(id: String) -> String:
	return "pack" if has_battery_mode(id, "pack") else "ideal"


static func has_battery_mode(id: String, mode: String) -> bool:
	return mode == "ideal" and has(id) or mode == "pack" and can_fly(id) and not battery_data(id).is_empty()


## Physics data path for a flight. Callers must check has_battery_mode() first; unknown modes return "".
static func data_for(id: String, mode: String = "ideal") -> String:
	if not has_battery_mode(id, mode):
		return ""
	return battery_data(id) if mode == "pack" else str(entry(id).get("data", ""))


static func can_fly(id: String) -> bool:
	var e := entry(id)
	return not e.is_empty() and e.status != PREVIEW and e.data != ""


## Physical configurations may share an authored visual family. Unknown IDs never borrow a default model.
static func visual_family(id: String) -> String:
	return str(entry(id).get("visual_family", ""))


## The next (step +1) or previous (step -1) ID in menu order, wrapping around.
static func step(id: String, delta: int) -> String:
	var list := ids()
	var i := list.find(id)
	return list[posmod((i if i >= 0 else 0) + delta, list.size())]
