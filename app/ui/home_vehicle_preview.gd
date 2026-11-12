# UI-39: render-only Home backdrop models for the RC vehicles that are not aircraft (RC cars, the FPV quad, the RC blimp).
# Each is built by its activity's own visual builder, so Home shows exactly the delivered model; nothing here reads or
# advances a session, and no physics source is involved beyond the quad's pure data preparation (rotor layout).
# The dictionary mirrors the parts of an AirplaneBuilder model that Home uses: {root, aircraft_id, livery, vehicle}.
extends RefCounted

const Roster := preload("res://app_state/vehicle_roster.gd")
const GroundCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")
const AirshipCatalog := preload("res://vehicles/airship/airship_catalog.gd")
const MultirotorCatalog := preload("res://vehicles/multirotor/multirotor_catalog.gd")
const MultirotorData := preload("res://physics/multirotor_data.gd")
const MultirotorVisual := preload("res://vehicles/multirotor/multirotor_visual.gd")
const AirshipVisual := preload("res://vehicles/airship/airship_visual.gd")
const Mt8Model := preload("res://vehicles/ground/mt8_model.gd")
const MonsterCar2Model := preload("res://vehicles/ground/monster_car_2_model.gd")


static func handles(id: String) -> bool:
	return Roster.is_activity(id)


## The model's GLB, for a worker preload before the main-thread build ("" when there is none to preload).
static func resource_path(id: String, skin := "") -> String:
	match Roster.family(id):
		Roster.GROUND:
			return Mt8Model.SCENE if id == "mt8-bisonte" else MonsterCar2Model.SCENE if id == "monster-car-2" else ""
		Roster.MULTIROTOR:
			return MultirotorVisual.MODEL_PATH
		Roster.AIRSHIP:
			return str(AirshipCatalog.SKINS[Roster.resolve_skin(id, skin)].model)
	return ""


## The parked model, or {} when it cannot be built (Home then reports the preview as failed).
static func build(id: String, skin := "") -> Dictionary:
	var root: Node3D = null
	var keep: Variant = null
	match Roster.family(id):
		Roster.GROUND:
			var entry: Dictionary = GroundCatalog.entry(id)
			var builder := load(str(entry.get("model_path", ""))) as Script
			var built: Dictionary = builder.call("build") if builder != null else {}
			if not bool(built.get("ok", false)):
				push_warning("Home preview: %s" % built.get("error", "no RC car model"))
				return {}
			root = built.root
		Roster.MULTIROTOR:
			var loaded: Dictionary = MultirotorData.load_file(MultirotorCatalog.DATA_PATH)
			var prepared: Dictionary = MultirotorData.prepare(loaded.data, str(loaded.sha256)) if loaded.get("ok", false) else {}
			var visual := MultirotorVisual.new()
			if not prepared.get("ok", false) or not visual.build(prepared.prepared):
				push_warning("Home preview: the FPV quad model could not be built %s" % visual.error)
				if visual.root != null: visual.root.free()
				return {}
			root = visual.root
			keep = visual
		Roster.AIRSHIP:
			var presentation: Variant = _airship_presentation()
			var visual := AirshipVisual.new()
			if not presentation is Dictionary or not visual.build(presentation, Roster.resolve_skin(id, skin)):
				push_warning("Home preview: the RC blimp model could not be built %s" % visual.error)
				if visual.root != null: visual.root.free()
				return {}
			root = visual.root
			keep = visual
	if root == null:
		return {}
	root.set_meta("aircraft_id", id)
	return {root = root, aircraft_id = id, livery = skin, vehicle = Roster.family(id), visual = keep}


## Upright on its lowest visible point: no hull fitting (the hull search reads every vertex and would tilt a blimp onto
## its fins). Same shape as HomePresentation.prepare().
static func prepare(model: Dictionary, bounds: AABB) -> Dictionary:
	return {bounds = bounds, alignment = Basis.IDENTITY, lift = -bounds.position.y + 0.005,
		contacts = PackedVector3Array(), grounded = true}


static func _airship_presentation() -> Variant:
	var file := FileAccess.open(AirshipCatalog.DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed.get("presentation") if parsed is Dictionary else null
