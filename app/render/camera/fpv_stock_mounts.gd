## CAM-FPV-02a: forward-looking optical mounts in metres relative to the aircraft's structural model root.
extends RefCounted

const StikGeometry := preload("res://aircraft/ugly_stik_geometry.gd")

const BASIC_STIK := "jensen-das-ugly-stik-60"
## Admitted procedural build, including the OS .61 engine, drive washer, propeller and fuselage.
const BASIC_STIK_MANIFEST := "70946d0e1f02eab493645a7dd31b124c10f2d890407bc2c36e446061fdabd51f"
## The front of the drive nut lies 22 mm ahead of the hub datum. A virtual lens 40 mm ahead
## keeps the entire forward image clear of the turning assembly, including the blur disc.
const LENS_AHEAD_OF_HUB_M := 0.040


## Called after stock visual admission. The basic Stik has one fixed prop installation.
## Positions use its structural datum, so prop rotation and CG changes cannot move the lens in the model.
static func front(airplane: Dictionary) -> Dictionary:
	if airplane.get("aircraft_id", "") != BASIC_STIK or airplane.get("visual_family", "") != BASIC_STIK \
			or airplane.get("model_manifest_sha256", "") != BASIC_STIK_MANIFEST:
		return {}
	var equipment: Dictionary = StikGeometry.DATA.equipment
	var origin := Vector3(0.0, float(equipment.shaft_y), float(equipment.prop_z) - LENS_AHEAD_OF_HUB_M)
	return {id = "front", mount = Transform3D(Basis.IDENTITY, origin),
		hfov_deg = 90.0, near_m = 0.03, look_limits_deg = Vector2(12, 8), provenance = "derived"}
