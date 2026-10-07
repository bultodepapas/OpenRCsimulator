## SCENERY-PLAN: the one scenery palette (VQ §2: natural, moderate colours). Every prop is coloured from here, so the
## field reads as one place and a theme (SC-23) can shift the vegetation in one function. Values are design choices
## (kind: estimated), picked against the L6a tree atlas and the ACES 0.6 grade; saturated colours stay behind the pilot.
extends RefCounted

const C := {
	# timber, metal, masonry
	"wood": Color("#7a5c3e"), "wood_light": Color("#a0835f"), "wood_dark": Color("#55402d"), "wood_grey": Color("#8a8072"),
	"roof_metal": Color("#a9b1b6"), "roof_metal_dark": Color("#828b91"), "roof_slate": Color("#5a6067"),
	"roof_terracotta": Color("#9c573b"), "roof_green": Color("#4f6656"),
	"wall_white": Color("#e4e0d6"), "wall_cream": Color("#ddd0b0"), "wall_brick": Color("#9a5b45"), "trim": Color("#f0ede6"),
	"glass": Color("#36424d"), "glass_light": Color("#5d6f7c"), "door": Color("#6b4a32"), "door_green": Color("#3f5a48"),
	"concrete": Color("#b3afa5"), "concrete_dark": Color("#8f8b82"), "steel": Color("#8d9296"), "steel_dark": Color("#55595d"),
	"gravel": Color("#a59b88"), "gravel_dark": Color("#8c8371"), "dirt": Color("#86704f"), "worn_grass": Color("#6f7a3e"),
	# farm
	"barn_red": Color("#8c3a2d"), "barn_trim": Color("#ebe5d8"), "silo": Color("#c8c4ba"), "silo_dome": Color("#8a9095"),
	"tractor": Color("#3e6b3a"), "tractor_yellow": Color("#d0a83a"), "tyre": Color("#2a2a2a"),
	"hay": Color("#c9b274"), "hay_end": Color("#b79c5c"), "hay_ring": Color("#9f8549"),
	# vegetation (themed by vegetation())
	"hedge": Color("#3d6a2e"), "hedge_light": Color("#567f39"), "leaf": Color("#4b7833"), "leaf_dark": Color("#335d27"),
	"leaf_light": Color("#6a9142"), "trunk": Color("#5d4532"), "stem": Color("#4f7a33"),
	# small props
	"cooler_blue": Color("#3a6ea5"), "cooler_red": Color("#b5413a"), "cooler_white": Color("#e8e6e0"), "fuel_red": Color("#b23a2e"),
	"fuel_green": Color("#3f7a45"), "box_black": Color("#2e3033"), "box_orange": Color("#c8682c"), "foam": Color("#d9d2bf"),
	"tablecloth": Color("#c9c4b6"), "fabric_green": Color("#4c6b4f"), "fabric_blue": Color("#3c5878"),
	"flag_red": Color("#b8322b"), "flag_white": Color("#efeee8"), "flag_blue": Color("#2c4a7a"), "sign_board": Color("#2f4a63"),
	# far landmarks
	"turbine": Color("#e6e6e3"), "pylon": Color("#8b9095"), "stone": Color("#b8ad97"), "stone_dark": Color("#9a8f7a"),
}

## Car paints, weighted toward what car parks actually contain (white, grey, black, silver dominate).
const PAINTS: Array[Color] = [Color("#e3e3df"), Color("#e3e3df"), Color("#b7bbbf"), Color("#b7bbbf"), Color("#2a2c2f"),
	Color("#2a2c2f"), Color("#6a6e72"), Color("#2b3d5b"), Color("#8e2a26"), Color("#3c5945"), Color("#c3b08a"), Color("#5b2f3b")]
const SHIRTS: Array[Color] = [Color("#2f5d8a"), Color("#b8443a"), Color("#e0d06a"), Color("#efefe8"), Color("#3e7a4f"),
	Color("#6a4b8a"), Color("#2b2b2b"), Color("#d77b3a"), Color("#8aa6c4"), Color("#a83a5c")]
const TROUSERS: Array[Color] = [Color("#2d3440"), Color("#5b4a3a"), Color("#3a3f45"), Color("#7a6a55"), Color("#41526b"), Color("#a59b84")]
const SKIN: Array[Color] = [Color("#e2b893"), Color("#c68e63"), Color("#8d5a3b"), Color("#f1cfb0"), Color("#a8714c")]
const HATS: Array[Color] = [Color("#efefe8"), Color("#2f4a63"), Color("#b8443a"), Color("#c9b274"), Color("#3a3f45")]
const FLOWERS := {
	"buttercup": Color("#e7c531"), "daisy": Color("#f1efe5"), "clover": Color("#a272ad"), "poppy": Color("#c63b2b"),
	"cornflower": Color("#5272b8"), "campion": Color("#d07aa0"),
}
const THEMES: Array[String] = ["temperate", "summer", "autumn"]


static func col(name: String) -> Color:
	return C[name]


## Integer hash → [0, 1). Same family as the treeline identity (L6b): integers only, so CPU runs repeat exactly.
static func hash01(a: int, b: int = 0, c: int = 0) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


static func pick(list: Array, a: int, b: int = 0, c: int = 0) -> Variant:
	return list[int(hash01(a, b, c) * list.size()) % list.size()]


## Theme a vegetation colour (SC-23). Non-vegetation colours never pass through here.
static func vegetation(color: Color, theme: String) -> Color:
	match theme:
		"summer": # dry Mediterranean summer: yellowed, paler, less saturated
			return Color.from_hsv(fposmod(color.h - 0.035, 1.0), color.s * 0.72, minf(1.0, color.v * 1.12))
		"autumn":
			return Color.from_hsv(fposmod(color.h - 0.13, 1.0), minf(1.0, color.s * 1.05), color.v * 0.98)
		_:
			return color


## A vegetation palette entry, themed.
static func veg(name: String, theme: String) -> Color:
	return vegetation(C[name], theme)
