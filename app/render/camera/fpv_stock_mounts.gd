## CAM-FPV-02: nose mounts in the structural model frame (+X right, +Y up, -Z forward).
extends RefCounted

const BASIC_STIK := "jensen-das-ugly-stik-60"
const BASIC_STIK_MANIFEST := "70946d0e1f02eab493645a7dd31b124c10f2d890407bc2c36e446061fdabd51f"
const STIK_HUB := Vector3(0.0, -0.005, -0.408276)
const X99_NOSE := Vector3(0.005990, 0.008751, -0.300727)
const LENS_AHEAD_M := 0.040
const GLOW_CONFIGURATIONS := ["stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]

## Closed, revision-bound companion to the stock model manifests. Stations are in metres;
## each is a fixed point in the model, even where it was measured from a spinning part.
const NOSES := {
	# Both builders place the shaft at equipment.prop_z/shaft_y. The glow drive nut
	# projects 22 mm beyond the hub. The electric uses its own adapter and blade geometry.
	BASIC_STIK: {sha = BASIC_STIK_MANIFEST, station = STIK_HUB},
	"stik-electric-6s": {sha = "27523d28e1fa9ec026d8e2c2655a7d237ee4d70d8a18babd6d51332d0651209d", station = STIK_HUB},
	# Procedural spinner.tip_z, transformed about spinner.back_z by the builder's right/down thrust.
	"gp-extra-300s-60": {sha = "476e4a0a077cdb7e63723ea5f6b63d2db5b259fb0e417ad4f5c2fede472bc5aa",
		station = Vector3(0.002548, -0.000637, -0.443653)},
	"p51d-mustang-120": {sha = "6665f7160b277923d48c16ae345ae269fd5a5b9ad9f8c4a68a034cce367fce83",
		station = Vector3(0.0, -0.005188, -0.668521)},
	# Corsair shaft centre at the foremost propeller_rotor vertex station of its stock GLBs.
	"f4u-corsair-250": {sha = "37456deee3c57870fed47ea623701e35aebc4ee0f38ac6fe6cc03519429c3fa0",
		station = Vector3(0.0, 0.0, -0.587133)},
	# Measured structural probe_nose_tip and nose_spinner_tip, respectively.
	"sebart-avanti-s-a200-p100rx": {sha = "b2196e4dfe6b5f7077e3ee5bdab6a435331cb68ea11f78cb69f46263bb10a82c",
		station = Vector3(0.0, -0.015120, -0.938040)},
	"turbo-lumber-evolution": {sha = "446d9d66373519a5a79e46fb1d799c3373ae7da1d5d0ddb9647cdfac2bfc46c8",
		station = Vector3(0.001116, -0.001117, -0.283461)},
	# The X99's nose_tip landmark is forward of its wing. The legacy visual has its own manifest.
	"moonrunner-x99": {sha = "15ac988ef031678012ddf69d27fb3482388a355693ce771adb4f5d0d30ede0d7", station = X99_NOSE},
	"skywalker-x8": {sha = "f735c4192228e5863323d7fa72a1d888c1ee98a4a36c4ffc40cff84d19cc7ae1", station = X99_NOSE},
}


## Called by the installation owner after visual admission, including the selected propeller.
static func front(airplane: Dictionary) -> Dictionary:
	var id := str(airplane.get("aircraft_id", ""))
	var family := BASIC_STIK if id in GLOW_CONFIGURATIONS else id
	var nose: Dictionary = NOSES.get(family, {})
	if nose.is_empty() or airplane.get("visual_family", "") != family or airplane.get("model_manifest_sha256", "") != nose.sha:
		return {}
	var origin: Vector3 = nose.station + Vector3.FORWARD * LENS_AHEAD_M
	return {id = "front", mount = Transform3D(Basis.IDENTITY, origin),
		hfov_deg = 90.0, near_m = 0.03, look_limits_deg = Vector2(12, 8), provenance = "derived"}
