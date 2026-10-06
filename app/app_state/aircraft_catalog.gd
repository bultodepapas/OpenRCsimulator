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

## In menu order. `name` is a proper name (never translated); `summary` and `status_note` are English source strings
## (tr() at the call site). `data` is "" for a preview. render/airplane.gd builds each ID with the model team's builder
## and knows its datum; tests/test_aircraft_catalog.gd checks that every ID builds and every flyable one trims.
const ENTRIES := [
	{
		id = "jensen-das-ugly-stik-60",
		name = "Jensen Das Ugly Stik 60",
		summary = "High-wing sport trainer · 1.52 m · .61 glow",
		status = FLYABLE,
		status_note = "Flight model under evaluation.",
		data = "res://data/aircraft/jensen_ugly_stik_60.json",
	},
	{
		id = "gp-extra-300s-60",
		name = "Great Planes Extra 300S .60",
		summary = "Low-wing aerobat · 1.63 m · .61 glow",
		status = EXPERIMENTAL,
		status_note = "Experimental: first physics estimate from the plans, not yet flight-tested.",
		data = "res://data/aircraft/gp_extra_300s_60.json",
	},
	{
		id = "p51d-mustang-120",
		name = "P-51D Mustang 1/4",
		summary = "Giant-scale warbird · 2.82 m · 120 cc gasoline",
		status = EXPERIMENTAL,
		status_note = "Experimental: first physics estimate from the full-size airplane scaled 1/4, not yet flight-tested.",
		data = "res://data/aircraft/p51d_mustang_120.json",
	},
	{
		id = "sebart-avanti-s-a200-p100rx",
		name = "SebArt Avanti S",
		summary = "Sport jet · 2.00 m · JetCat P100-RX turbine",
		status = PREVIEW,
		status_note = "Preview only: turbine propulsion is not simulated yet.",
		data = "",
	},
]


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in ENTRIES:
		out.append(e.id)
	return out


static func has(id: String) -> bool:
	return ids().has(id)


## The entry for `id`, or {} when unknown (callers must refuse it, never substitute another airplane).
static func entry(id: String) -> Dictionary:
	for e in ENTRIES:
		if e.id == id:
			return e
	return {}


static func can_fly(id: String) -> bool:
	var e := entry(id)
	return not e.is_empty() and e.status != PREVIEW and e.data != ""


## The next (step +1) or previous (step -1) ID in menu order, wrapping around.
static func step(id: String, delta: int) -> String:
	var list := ids()
	var i := list.find(id)
	return list[posmod((i if i >= 0 else 0) + delta, list.size())]
