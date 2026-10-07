## SCENERY-PLAN SC-04/SC-06/SC-14: the third-party models the scenery uses, all CC0 with evidence for the exact file,
## baked by tools/scenery/bake_models.gd into `openrc-scenery-model v1` JSON (app/data/scenery/models/). At runtime a
## model becomes flat-shaded triangle arrays with sRGB vertex colours; palette entries with alpha 0 are the paint, which
## each placement may recolour (car paints). Arrays are cached per id.
extends RefCounted

const FORMAT := "openrc-scenery-model v1"
const DIR := "res://data/scenery/models"

const _CARS_ARCHIVE := "qi-lowpoly-cars/1148381.zip"
const _CARS_SHA := "af8f45d6e2135cc53870e5d0882cc41ca329bd87b9923b4773d471f161d2bdc7"
const _CARS_URL := "https://quaternius.itch.io/lowpoly-cars"
const _CARS_LICENSE := "License.txt inside the archive: \"CC0 1.0 Universal (CC0 1.0) Public Domain Dedication\" (read 2026-10-07, SC-01)"
const _ANIMALS_LICENSE := "Farm Animals Pack License.txt (Drive, SHA-256 551ec32f604f57be7eca26fc6e6331b3c6d765804726ac259bc7891276634353): \"CC0 1.0 Universal\"; Poly Pizza lists the file as CC0 1.0 by Quaternius (scenery report 01)"

## id → bake and runtime facts. `size` is the baked target (w × h × l, m): length exact, width and height follow the model
## (height scaled by `height_factor`). Sizes: car lengths are typical segment values (estimated); the Quaternius sedan
## stands ~15 % low (SC-01) and gets a height factor; cow and sheep are typical adult sizes (estimated).
const CATALOG := {
	"car_sedan": {size = Vector3(1.88, 1.41, 4.4), height_factor = 1.15, tier = "standard", shadow = true, paint = true,
		archive = _CARS_ARCHIVE, archive_sha256 = _CARS_SHA, entry = "Realistic Car Pack - Nov 2018/FBX/NormalCar1.fbx",
		url = _CARS_URL, author = "Quaternius", license = "CC0-1.0", license_evidence = _CARS_LICENSE,
		paint_material = "*body", front_color = "d1955a", max_tris = 1800},
	"car_hatch": {size = Vector3(2.13, 1.49, 4.3), height_factor = 1.0, tier = "standard", shadow = true, paint = true,
		archive = _CARS_ARCHIVE, archive_sha256 = _CARS_SHA, entry = "Realistic Car Pack - Nov 2018/FBX/NormalCar2.fbx",
		url = _CARS_URL, author = "Quaternius", license = "CC0-1.0", license_evidence = _CARS_LICENSE,
		paint_material = "*body", front_color = "d1955a", max_tris = 1800},
	"car_suv": {size = Vector3(2.36, 1.71, 4.7), height_factor = 1.0, tier = "standard", shadow = true, paint = true,
		archive = _CARS_ARCHIVE, archive_sha256 = _CARS_SHA, entry = "Realistic Car Pack - Nov 2018/FBX/SUV.fbx",
		url = _CARS_URL, author = "Quaternius", license = "CC0-1.0", license_evidence = _CARS_LICENSE,
		paint_material = "*body", front_color = "d1955a", max_tris = 1800},
	"car_sport": {size = Vector3(1.96, 1.25, 4.3), height_factor = 1.0, tier = "standard", shadow = true, paint = true,
		archive = _CARS_ARCHIVE, archive_sha256 = _CARS_SHA, entry = "Realistic Car Pack - Nov 2018/FBX/SportsCar.fbx",
		url = _CARS_URL, author = "Quaternius", license = "CC0-1.0", license_evidence = _CARS_LICENSE,
		paint_material = "*body", front_color = "d1955a", max_tris = 1800},
	"cow": {size = Vector3(0.59, 1.35, 2.4), height_factor = 1.0, tier = "standard", shadow = true, paint = false,
		archive = "pp/glb/5XSc2Fka3F.glb", archive_sha256 = "5bdb18da23e114c717a8739e7defc75b6bf3d1dd54e928c141a0286bf14aa4a8",
		entry = "", url = "https://poly.pizza/m/5XSc2Fka3F", author = "Quaternius", license = "CC0-1.0",
		license_evidence = _ANIMALS_LICENSE, paint_material = "", front_color = ""},
	"sheep": {size = Vector3(0.49, 0.96, 1.3), height_factor = 1.0, tier = "standard", shadow = true, paint = false,
		archive = "pp/glb/C39AUXUUes.glb", archive_sha256 = "91aedec323b54d42b802b065b2f5005daea527b0a379a9f3fe90f3258f3c2382",
		entry = "", url = "https://poly.pizza/m/C39AUXUUes", author = "Quaternius", license = "CC0-1.0",
		license_evidence = _ANIMALS_LICENSE, paint_material = "", front_color = ""},
	"fleet_stik": {size = Vector3(1.52, 0.44, 1.33), tier = "standard", shadow = false, paint = false, kind = "fleet"},
	"fleet_extra": {size = Vector3(1.62, 0.55, 1.39), tier = "standard", shadow = false, paint = false, kind = "fleet"},
	"fleet_p51": {size = Vector3(2.82, 0.95, 2.46), tier = "standard", shadow = false, paint = false, kind = "fleet"},
	"fleet_avanti": {size = Vector3(2.0, 0.63, 2.22), tier = "standard", shadow = false, paint = false, kind = "fleet"},
}

## The parked fleet (SC-09): the catalog aircraft baked by tools/scenery/bake_fleet.gd from the model teams' builders.
const FLEET := {"fleet_stik": "jensen-das-ugly-stik-60", "fleet_extra": "gp-extra-300s-60",
	"fleet_p51": "p51d-mustang-120", "fleet_avanti": "sebart-avanti-s-a200-p100rx"}

static var _cache := {}


## {pos, nrm, col} flat-shaded arrays for a model, or {} when the file is missing or invalid.
static func arrays(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := "%s/%s.json" % [DIR, id]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or (parsed as Dictionary).get("format") != FORMAT:
		push_error("scenery: model %s missing or not %s" % [path, FORMAT])
		return {}
	var m: Dictionary = parsed
	var palette: Array[Color] = []
	for h: Variant in m.palette:
		palette.append(Color.html(str(h)))
	var p_mm := PackedInt32Array(m.positions_mm) # C++ conversion; indexing packed arrays is much faster in GDScript
	var tri := PackedInt32Array(m.triangles)
	var n_tri := tri.size() / 4
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	pos.resize(n_tri * 3)
	nrm.resize(n_tri * 3)
	col.resize(n_tri * 3)
	for t in n_tri:
		var b := t * 4
		var i0 := tri[b] * 3
		var i1 := tri[b + 1] * 3
		var i2 := tri[b + 2] * 3
		var va := Vector3(p_mm[i0], p_mm[i0 + 1], p_mm[i0 + 2]) * 0.001
		var vb := Vector3(p_mm[i1], p_mm[i1 + 1], p_mm[i1 + 2]) * 0.001
		var vc := Vector3(p_mm[i2], p_mm[i2 + 1], p_mm[i2 + 2]) * 0.001
		var n := (vc - va).cross(vb - va) # stored in Godot's clockwise order
		n = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
		var o := t * 3
		pos[o] = va
		pos[o + 1] = vb
		pos[o + 2] = vc
		nrm[o] = n
		nrm[o + 1] = n
		nrm[o + 2] = n
		var c := palette[tri[b + 3]]
		col[o] = c
		col[o + 1] = c
		col[o + 2] = c
	var out := {pos = pos, nrm = nrm, col = col, size = Vector3(m.size_m[0], m.size_m[1], m.size_m[2])}
	_cache[id] = out
	return out
