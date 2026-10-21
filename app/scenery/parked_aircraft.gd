## Runtime access to offline-baked, stock-livery parked-aircraft meshes.
## Geometry and material work happens in tools/scenery/bake_parked_aircraft.gd;
## a placed aircraft is one static ArrayMesh with no model-builder nodes.
extends RefCounted

const FORMAT := "openrc-parked-aircraft v1"
const DIR := "res://assets/scenery/aircraft"

## Catalog aircraft ID -> stable generated asset basename.
const AIRCRAFT := {
	"jensen-das-ugly-stik-60": "stik",
	"gp-extra-300s-60": "extra",
	"p51d-mustang-120": "p51",
	"sebart-avanti-s-a200-p100rx": "avanti",
	"turbo-lumber-evolution": "timber",
}


## Shared generated mesh. ResourceLoader caches the immutable resource across placements.
static func mesh(aircraft: String, configuration: String = "assembled") -> ArrayMesh:
	var path := _path(aircraft, configuration, ".res")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource is ArrayMesh:
		return resource as ArrayMesh
	push_error("parked aircraft: %s is not an ArrayMesh resource" % path)
	return null


## Authored dimensions and broad collision proxies for a normalized snapshot.
static func info(aircraft: String, configuration: String = "assembled") -> Dictionary:
	var path := _path(aircraft, configuration, ".json")
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or str(parsed.get("format", "")) != FORMAT:
		return {}
	return (parsed as Dictionary).duplicate(true)


## Placement coordinates remain NED (north/east); mesh forward is local -Z and bottom is local y = 0.
static func transform_for(placement: Dictionary) -> Transform3D:
	var north := _number(placement.get("north", 0.0), 0.0)
	var east := _number(placement.get("east", 0.0), 0.0)
	var heading_deg := _number(placement.get("heading", 0.0), 0.0)
	var scale := _number(placement.get("scale", 1.0), 1.0)
	var elevation := _number(placement.get("elevation", 0.0), 0.0)
	if scale < 0.25 or scale > 1.5:
		scale = 1.0
	var basis := Basis(Vector3.UP, -deg_to_rad(heading_deg)).scaled(Vector3.ONE * scale)
	var origin := Vector3(east, elevation, -north)
	return Transform3D(basis, origin)


static func _path(aircraft: String, configuration: String, extension: String) -> String:
	if not AIRCRAFT.has(aircraft) or configuration not in ["assembled", "service"]:
		return ""
	var basename: String = str(AIRCRAFT[aircraft])
	if configuration == "service" and basename != "stik":
		return ""
	return "%s/%s_%s%s" % [DIR, basename, configuration, extension]


static func _number(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return float(value)
