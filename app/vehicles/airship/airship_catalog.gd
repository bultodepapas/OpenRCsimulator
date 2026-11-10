## The experimental RC blimp and its skins. One physical configuration; skins change appearance only.
extends RefCounted

const DEFAULT_SKIN := "tiburon-blanco"
const SKIN_IDS := ["tiburon-blanco", "historico", "cromo-carbono-azul"]
const SKINS := {
	"tiburon-blanco": {"name": "Tiburón Blanco", "model": "res://assets/airships/rc-blimp-5m/tiburon-blanco.glb"},
	"historico": {"name": "Histórico", "model": "res://assets/airships/rc-blimp-5m/historico.glb"},
	"cromo-carbono-azul": {"name": "Cromo Carbono Azul", "model": "res://assets/airships/rc-blimp-5m/cromo-carbono-azul.glb"},
}


static func contains(skin_id: String) -> bool:
	return SKINS.has(skin_id)


static func skins() -> Array:
	var out: Array = []
	for id: String in SKIN_IDS:
		var entry: Dictionary = SKINS[id].duplicate()
		entry.id = id
		out.append(entry)
	return out
