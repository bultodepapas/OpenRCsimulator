## Ground activities have their own identity and visuals, separate from aircraft.
extends RefCounted

const DEFAULT_ID := "mt8-bisonte"
const IDS := [DEFAULT_ID, "monster-car-2"]
const ENTRIES := {
	"mt8-bisonte": {
		"name": "Bisonte MT8", "nitro": false,
		"model_path": "res://vehicles/ground/mt8_model.gd",
	},
	"monster-car-2": {
		"name": "MONSTER CAR 2", "nitro": true,
		"model_path": "res://vehicles/ground/monster_car_2_model.gd",
	},
}

static func contains(id: String) -> bool:
	return ENTRIES.has(id)

static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {}).duplicate(true)
