# Home vehicle roster: what Home's catalog offers, in menu order. The stock aircraft come first (the aircraft catalog,
# app_state/aircraft_catalog.gd, stays airplanes and helicopters only: physics, trim, Workshop and flight preparation
# read it), then the other RC vehicles. Each of those runs as its own activity with its own data and session
# (AppRoot.start_ground_vehicle / start_airship / start_multirotor); this file only names and routes them.
# Roster ids are the vehicles' native ids; test_home_vehicle_roster.gd checks they never collide with aircraft ids.
# `name` is a proper name (not translated); `short_name`, `summary` and `status_note` are English source strings.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const GroundCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")
const AirshipCatalog := preload("res://vehicles/airship/airship_catalog.gd")
const MultirotorCatalog := preload("res://vehicles/multirotor/multirotor_catalog.gd")

const AIRCRAFT := "aircraft"
const GROUND := "ground"
const MULTIROTOR := "multirotor"
const AIRSHIP := "airship"

## The non-aircraft entries, in menu order after the aircraft. Every one is experimental.
const ACTIVITIES := [
	{
		id = "openrc-fpv5-x1", family = MULTIROTOR,
		name = "FPV quad 5\" (experimental)", short_name = "FPV quad 5\"",
		summary = "FPV racing quad · 5 in propellers · 6S electric",
		status_note = "Experimental: estimated FPV quad physics from component data; not flight-validated.",
	},
	{
		id = "rc-blimp-5m", family = AIRSHIP,
		name = "RC blimp (experimental)", short_name = "RC blimp",
		summary = "RC blimp · 5 m envelope · electric vectored rotors",
		status_note = "Experimental: estimated buoyancy and hull aerodynamics; not flight-validated. Wind and start are chosen in the blimp menu.",
	},
	{
		id = "mt8-bisonte", family = GROUND,
		name = "Bisonte MT8", short_name = "Bisonte MT8",
		summary = "RC monster truck · electric 4WD",
		status_note = "Experimental: estimated electric 4WD model; mass, suspension and tires are estimates, not measured. The car setup opens before you drive.",
	},
	{
		id = "monster-car-2", family = GROUND,
		name = "MONSTER CAR 2", short_name = "MONSTER CAR 2",
		summary = "RC monster truck · nitro 4WD",
		status_note = "Experimental: supplied nitro 4WD estimate; engine, clutch, fuel and tires are simulated estimates, not measured. The car setup opens before you drive.",
	},
]


## Every Home-selectable id: the stock aircraft, then the activities.
static func ids() -> PackedStringArray:
	var out := Catalog.player_ids()
	for entry: Dictionary in ACTIVITIES:
		out.append(entry.id)
	return out


static func has(id: String) -> bool:
	return Catalog.is_player_selectable(id) or is_activity(id)


## True for a non-aircraft vehicle that Home starts as an activity.
static func is_activity(id: String) -> bool:
	return not activity(id).is_empty()


## The activity entry for `id`, or {} (an aircraft or an unknown id).
static func activity(id: String) -> Dictionary:
	for entry: Dictionary in ACTIVITIES:
		if entry.id == id:
			return entry
	return {}


static func family(id: String) -> String:
	return str(activity(id).get("family", AIRCRAFT if Catalog.has(id) else ""))


## The Home entry for any roster id, shaped like an aircraft catalog entry ({} when unknown).
static func entry(id: String) -> Dictionary:
	var found := activity(id)
	if not found.is_empty():
		var shaped: Dictionary = found.duplicate()
		shaped.status = Catalog.EXPERIMENTAL
		return shaped
	return Catalog.entry(id) if Catalog.is_player_selectable(id) else {}


static func short_name(id: String) -> String:
	var found := entry(id)
	return str(found.get("short_name", found.get("name", "")))


## The next (+1) or previous (-1) roster id, wrapping; "" for an id outside the roster.
static func step(id: String, delta: int) -> String:
	var list := ids()
	var index := list.find(Catalog.canonical_id(id))
	return "" if index < 0 or list.is_empty() else list[posmod(index + delta, list.size())]


## Skins of a vehicle that has paint choices, as livery-picker choices [{id, label}]; [] for the others.
static func skin_choices(id: String) -> Array:
	if family(id) != AIRSHIP:
		return []
	var out: Array = []
	for skin: Dictionary in AirshipCatalog.skins():
		out.append({id = str(skin.id), label = str(skin.name)})
	return out


## The skin id that is actually flown for `wanted` (the default skin for an unknown one).
static func resolve_skin(id: String, wanted: String) -> String:
	if family(id) != AIRSHIP:
		return ""
	return wanted if AirshipCatalog.contains(wanted) else AirshipCatalog.DEFAULT_SKIN


## The roster's activity ids must stay distinct from every aircraft id (stock and technical) and must name an
## installed vehicle; returns the problems found.
static func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for entry: Dictionary in ACTIVITIES:
		var id: String = entry.id
		if Catalog.has(id):
			errors.append("activity id collides with an aircraft id: " + id)
		var installed := false
		match str(entry.family):
			GROUND: installed = GroundCatalog.contains(id)
			MULTIROTOR: installed = MultirotorCatalog.contains(id)
			AIRSHIP: installed = AirshipCatalog.is_stock_id(id)
		if not installed:
			errors.append("activity id names no installed vehicle: " + id)
	for id: String in GroundCatalog.IDS:
		if not is_activity(id):
			errors.append("RC car missing from the Home roster: " + id)
	return errors
