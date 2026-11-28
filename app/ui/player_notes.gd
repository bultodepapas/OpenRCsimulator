# UI-40d: the one sentence a player reads about a catalog entry's status. English source strings; tr() at the call
# site. Each entry's `status_note` keeps the engineering detail for the details card and tooltips.
# Presentation copy lives here, not in app_state/aircraft_catalog.gd: that file is a mirrored native-kernel source, and
# any byte change there disables the qualified native backend until it is rebuilt.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")

const NOTES := {
	Catalog.FLYABLE: "Reference flight model.",
	Catalog.EXPERIMENTAL: "Experimental: estimated physics, not yet compared with the real aircraft.",
	Catalog.PREVIEW: "Model only; it cannot fly yet.",
}


static func player_note(entry: Dictionary) -> String:
	return str(NOTES.get(str(entry.get("status", "")), NOTES[Catalog.PREVIEW]))
