extends RefCounted
## Trusted in-memory owner of one admitted model source (AC-07).
##
## Created only by `source_importer.gd` after format and resource admission. It owns the exact
## captured bytes: preview, persistence and later rebuilds consume this identity and never read
## the player's original path again. It carries no path, script or callable. It is preview data
## only: owning one says nothing about aircraft physics, and it cannot start a flight.
## GDScript has no private members, so ownership is a convention: accessors return copies.

const FORMAT_STL_BINARY := "stl-binary"
const FORMAT_STL_ASCII := "stl-ascii"
const FORMAT_GLB := "glb"

var _sealed := false
var _bytes := PackedByteArray()
var _sha256 := ""
var _format := ""
var _file_name := ""
var _triangles := 0
var _bounds_min := PackedFloat64Array([0.0, 0.0, 0.0])
var _bounds_max := PackedFloat64Array([0.0, 0.0, 0.0])
var _positions := PackedFloat32Array()
var _details := {}
var _notes: Array = []


## One-time initialization by the importer. A second call is ignored.
func adopt(fields: Dictionary) -> void:
	if _sealed:
		return
	_bytes = fields.bytes
	_sha256 = fields.sha256
	_format = fields.format
	_file_name = fields.file_name
	_triangles = fields.triangles
	_bounds_min = fields.bounds_min
	_bounds_max = fields.bounds_max
	_positions = fields.get("positions", PackedFloat32Array())
	_details = fields.get("details", {})
	_notes = fields.get("notes", [])
	_sealed = true


func is_admitted() -> bool:
	return _sealed and not _bytes.is_empty()


func source_bytes() -> PackedByteArray:
	return _bytes.duplicate()


func byte_length() -> int:
	return _bytes.size()


func sha256() -> String:
	return _sha256


func format() -> String:
	return _format


func is_stl() -> bool:
	return _format == FORMAT_STL_BINARY or _format == FORMAT_STL_ASCII


## The name the player picked, for display only. Never a key and never reopened.
func file_name() -> String:
	return _file_name


func triangle_count() -> int:
	return _triangles


## Axis-aligned bounds in source units and source axes.
func bounds_min() -> PackedFloat64Array:
	return _bounds_min.duplicate()


func bounds_max() -> PackedFloat64Array:
	return _bounds_max.duplicate()


## STL only: nine float32 per triangle in source units, authored winding.
func stl_positions() -> PackedFloat32Array:
	return _positions.duplicate()


## Format-specific counts and names from admission (data only).
func details() -> Dictionary:
	return _details.duplicate(true)


## Warnings and notes raised during admission, as diagnostics.
func notes() -> Array:
	return _notes.duplicate(true)
