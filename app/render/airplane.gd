# Stable presentation adapter. Authored manifests select builders and bind scene nodes.
# Physics remains scalar/float64; Godot transforms are used only at this rendering boundary.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const SurfaceContract := preload("res://physics/control_surfaces.gd")
const Controls := preload("res://aircraft/ugly_stik_controls.gd")
const UglyStik := preload("res://aircraft/ugly_stik_model.gd")
const HX700 := preload("res://aircraft/hx700_model.gd")

const STIK_ID := "jensen-das-ugly-stik-60"
const EXTRA_ID := "gp-extra-300s-60"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const P51_ID := "p51d-mustang-120"
const TIMBER_ID := "turbo-lumber-evolution"
const STIK_GLOW_55AX_ID := "stik-glow-55ax-2t"
const STIK_GLOW_FS64V_ID := "stik-glow-fs64v-4t"
const STIK_GLOW_61FX_ID := "stik-glow-61fx-2t"
const X_CELL_ID := "xcell-60-research"

# Accepted builds populate this small render-only cache. Every new build revalidates dependencies.
static var _accepted_datums: Dictionary = {}

static func _mat(color: Color) -> StandardMaterial3D:
	return UglyStik.material(color)


## Returns an independently built, validated visual for a catalog physical configuration.
static func build(id := STIK_ID, propeller_diameter_m := NAN, expected_presentation: Dictionary = {}) -> Dictionary:
	var family: String = Catalog.visual_family(id)
	if family.is_empty():
		push_error("render/airplane.gd: unknown aircraft '%s'" % id)
		return {}
	# The static Home composition may display the helicopter, but it has no
	# airplane manifest, propeller, control hinges, or AircraftData v2 record.
	# Keep that visual route explicit and out of the airplane model registry.
	if Catalog.is_rotorcraft(id):
		if id != X_CELL_ID or family != "hx-700" or not expected_presentation.is_empty():
			push_error("render/airplane.gd: unsupported rotorcraft presentation '%s'" % id)
			return {}
		var helicopter: Dictionary = HX700.build()
		if helicopter.is_empty() or not (helicopter.get("root") is Node3D):
			return {}
		helicopter.aircraft_id = id
		helicopter.visual_family = family
		helicopter.root.set_meta("aircraft_id", id)
		return helicopter
	var registry: Script = load("res://aircraft/model_registry.gd")
	var resolved: Dictionary = registry.describe(family)
	if not resolved.get("ok", false):
		push_error("Aircraft model contract: " + str(resolved.get("errors", [])))
		return {}
	if not expected_presentation.is_empty():
		if expected_presentation.get("visual_family", "") != family or expected_presentation.get("model_manifest_sha256", "") != resolved.manifest_sha256:
			push_warning("Aircraft presentation changed after the Workshop trial was frozen.")
			return {}
	var manifest: Dictionary = resolved.manifest
	var builder: Script = load(str(manifest.builder.script))
	if builder == null or not builder.has_method("build"):
		push_error("Aircraft model builder has no build method: " + str(manifest.builder.script))
		return {}
	# V1 builders keep their zero-argument ABI. V2 constructs imported scenes from checked bindings.
	var airplane: Dictionary = builder.call("build", manifest) if manifest.version == 2 else builder.call("build")
	var verified: Dictionary = registry.validate_derived(manifest, airplane)
	if not verified.get("ok", false):
		if airplane.get("root") is Node:
			airplane.root.free()
		push_error("Aircraft model bindings: " + str(verified.get("errors", [])))
		return {}
	var data_path: String = str(Catalog.entry(id).get("data", ""))
	var model: Dictionary = {}
	if not data_path.is_empty():
		var loaded: Dictionary = AircraftData.load_file(data_path)
		if not loaded.get("ok", false):
			airplane.root.free()
			push_error("Aircraft data for presentation: " + str(loaded.get("errors", [])))
			return {}
		model = loaded.model
	var glow: Dictionary = model.get("propulsion", {}).get("glow", {})
	airplane.aircraft_id = id
	airplane.visual_family = family
	airplane.model_manifest = manifest.duplicate(true)
	airplane.model_manifest_sha256 = resolved.manifest_sha256
	airplane._model_builder = builder
	airplane._finite_glow_visual = not glow.is_empty()
	if not glow.is_empty():
		airplane.propeller_spin_sign = -1.0
		var selected_diameter: float = float(propeller_diameter_m)
		if not is_finite(selected_diameter) or selected_diameter <= 0.0:
			selected_diameter = float(glow.get("propeller", {}).get("diameter_m", NAN))
		if not apply_propeller_diameter(airplane, selected_diameter):
			airplane.root.free()
			push_error("Aircraft visual has no valid propeller diameter binding.")
			return {}
	airplane.root.set_meta("aircraft_id", id)
	airplane.exhausts = airplane.root.get_meta("exhausts", [])
	_accepted_datums[id] = Vector2(float(manifest.datum.model_z_le), float(manifest.datum.model_y_thrust))
	return airplane


## Always scale from the authored diameter, so repeated setup/reload calls never compound scale.
static func apply_propeller_diameter(airplane: Dictionary, diameter_m: float) -> bool:
	if not airplane.get("_finite_glow_visual", false) or not is_finite(diameter_m) or diameter_m <= 0.0:
		return false
	var propeller: Node3D = airplane.get("propeller")
	var manifest: Dictionary = airplane.get("model_manifest", {})
	var base_diameter: float = float(manifest.get("bindings", {}).get("rotor", {}).get("authored_diameter_m", NAN))
	if propeller == null or not is_finite(base_diameter) or base_diameter <= 0.0:
		return false
	var ratio: float = diameter_m / base_diameter
	propeller.scale = Vector3(ratio, ratio, propeller.scale.z)
	airplane.propeller_diameter_m = diameter_m
	return true


## Called each rendered frame: accepted model data, with no disk reads on this path.
static func datum(id: String) -> Vector2:
	if _accepted_datums.has(id):
		return _accepted_datums[id]
	var family: String = Catalog.visual_family(id)
	if family.is_empty():
		return Vector2.ZERO
	var registry: Script = load("res://aircraft/model_registry.gd")
	var resolved: Dictionary = registry.describe(family)
	if not resolved.get("ok", false):
		return Vector2.ZERO
	var declared: Dictionary = resolved.manifest.datum
	_accepted_datums[id] = Vector2(float(declared.model_z_le), float(declared.model_y_thrust))
	return _accepted_datums[id]


## Existing conventional commands keep their signs and physical throws.
static func apply_surfaces(airplane: Dictionary, rotations: Dictionary) -> void:
	var manifest: Dictionary = airplane.model_manifest
	if str(manifest.builder.adapter) != "euler_hinges":
		var builder: Script = airplane._model_builder
		builder.call(str(manifest.surface_method), airplane, surface_degrees(rotations))
		return
	for surface_name: String in rotations:
		var r: Dictionary = rotations[surface_name]
		var binding: Dictionary = manifest.bindings.controls[surface_name]
		for hinge: Dictionary in binding.hinges:
			airplane.hinges[str(hinge.key)].rotation = Vector3(r.x, r.y, 0)
	if airplane.has("controls"):
		Controls.update(airplane.controls)


## Optional legacy throttle linkage. Finite glow visuals retain their existing shaft behavior.
static func apply_throttle(airplane: Dictionary, throttle: float) -> void:
	if airplane.has("controls") and not airplane.get("_finite_glow_visual", false):
		Controls.set_throttle(airplane.controls, throttle)


## The inverse of Commands.hinge_rotations(): trailing-edge deflections in degrees (up for ailerons/elevator,
## right for the rudder), as Commands.surface_deflections_deg() gives them.
static func surface_degrees(rotations: Dictionary) -> Dictionary:
	return SurfaceContract.from_hinge_rotations(rotations)


## Optional visual gear state from simulation; angles in radians around model axes. Each aircraft has its own wheels
## (Stik: left, right, nose; Extra, P-51 and Timber: left, right, tail; Avanti: none yet). Positive wheel rotation is
## around +X; positive steering is around +Y.
static func apply_gear(airplane: Dictionary, wheel_angles: Dictionary, steering_rad: float) -> void:
	var gear: Dictionary = airplane.get("gear", {})
	var bindings: Dictionary = airplane.model_manifest.bindings.gear.keys
	for role: String in ["left", "right", "nose", "tail"]:
		var key: String = str(bindings.get(role, ""))
		if not key.is_empty():
			gear[key].rotation.x = float(wheel_angles.get(role, 0.0))
	var steering_key: String = str(bindings.get("steering", ""))
	if not steering_key.is_empty():
		gear[steering_key].rotation.y = steering_rad


## Inspector-only access: restore false before returning to assembled views.
static func set_maintenance(airplane: Dictionary, visible: bool) -> void:
	if airplane.has("controls"): Controls.set_maintenance(airplane.controls, visible)
