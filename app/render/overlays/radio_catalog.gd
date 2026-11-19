# HUD-RADIO-01: presentation identities only. No USB mapping, calibration or firmware execution.
extends RefCounted

const VERSION := 1
const DEFAULT_ID := "jeti_ds24_ii"
# Preserve the existing saved identities and order; new appearances follow them.
const IDS := ["jeti_ds24_ii", "radiolink_t16d", "jumper_t18_h7", "radiolink_t12d"]
const DEFINITIONS := {
	jeti_ds24_ii = {
		label = "JETI DS-24 II", artwork = "res://assets/ui/jeti_ds24_ii_orange.png",
		canvas_size = Vector2(180.0, 222.0), gimbals = [Vector2(39.0, 126.0), Vector2(139.0, 126.0)],
		lcd = Rect2(58.0, 23.0, 67.0, 64.0), accent = Color("ff8d40"),
		artwork_kind = "existing", firmware_family = "jeti", firmware_targets = [],
	},
	radiolink_t16d = {
		label = "Radiolink T16D", artwork = "res://assets/ui/radiolink_t16d.png",
		canvas_size = Vector2(180.0, 213.0), gimbals = [Vector2(39.0, 108.0), Vector2(139.0, 108.0)],
		lcd = Rect2(62.0, 154.0, 56.0, 42.0), accent = Color("ff5259"),
		artwork_kind = "existing", firmware_family = "radiolink", firmware_targets = [],
	},
	jumper_t18_h7 = {
		label = "Jumper T18-H7", artwork = "res://assets/ui/jumper_t18_h7_schematic.svg",
		canvas_size = Vector2(180.0, 213.0), gimbals = [Vector2(43.0, 91.0), Vector2(137.0, 91.0)],
		lcd = Rect2(45.0, 143.0, 90.0, 51.0), accent = Color("f8aa51"),
		artwork_kind = "schematic", firmware_family = "edgetx", firmware_targets = ["t18h7"],
	},
	radiolink_t12d = {
		label = "Radiolink T12D", artwork = "res://assets/ui/radiolink_t12d_schematic.svg",
		canvas_size = Vector2(180.0, 213.0), gimbals = [Vector2(42.0, 92.0), Vector2(138.0, 92.0)],
		lcd = Rect2(52.0, 143.0, 76.0, 57.0), accent = Color("53cbd0"),
		artwork_kind = "schematic", firmware_family = "radiolink", firmware_targets = [],
	},
}


static func contains(id: String) -> bool:
	return DEFINITIONS.has(id)


## Callers own the returned geometry/capabilities; unknown persisted IDs use the existing default.
static func definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id, DEFINITIONS[DEFAULT_ID]).duplicate(true)


static func label(id: String) -> String:
	return str(DEFINITIONS.get(id, DEFINITIONS[DEFAULT_ID]).label)
