## The experimental RC blimp and its skins. One physical configuration; skins change appearance only.
## BL-19: the Workshop addresses the blimp by STOCK_ID (= the data `id`) and its presentation by VISUAL_FAMILY.
## It is deliberately not an entry of the fixed-wing aircraft catalog.
extends RefCounted

const STOCK_ID := "rc-blimp-5m"
const VISUAL_FAMILY := "rc-blimp-5m"
const DATA_PATH := "res://data/airships/rc-blimp-5m.json"
const VEHICLE := "airship"
const DISPLAY_NAME := "RC blimp (experimental)"
const DEFAULT_SKIN := "tiburon-blanco"
const SKIN_IDS := ["tiburon-blanco", "historico", "cromo-carbono-azul"]
const SKINS := {
	"tiburon-blanco": {"name": "Tiburón Blanco", "model": "res://assets/airships/rc-blimp-5m/tiburon-blanco.glb"},
	"historico": {"name": "Histórico", "model": "res://assets/airships/rc-blimp-5m/historico.glb"},
	"cromo-carbono-azul": {"name": "Cromo Carbono Azul", "model": "res://assets/airships/rc-blimp-5m/cromo-carbono-azul.glb"},
}


static func contains(skin_id: String) -> bool:
	return SKINS.has(skin_id)


## Workshop stock entry, shaped like the fixed-wing catalog entries the Library lists.
static func stock_entry() -> Dictionary:
	return {id = STOCK_ID, name = DISPLAY_NAME, vehicle = VEHICLE, data = DATA_PATH, visual_family = VISUAL_FAMILY,
		player_selectable = true}


static func is_stock_id(id: String) -> bool:
	return id == STOCK_ID


static func skins() -> Array:
	var out: Array = []
	for id: String in SKIN_IDS:
		var entry: Dictionary = SKINS[id].duplicate()
		entry.id = id
		out.append(entry)
	return out
