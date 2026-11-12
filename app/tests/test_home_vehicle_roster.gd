## UI-39: the Home vehicle roster (aircraft, then RC vehicles), the render-only backdrop models of the RC vehicles and
## the additive preferences that remember Home's RC vehicle selection.
extends SceneTree

const Roster := preload("res://app_state/vehicle_roster.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const VehiclePreview := preload("res://ui/home_vehicle_preview.gd")
const PreviewResources := preload("res://ui/home_preview_resources.gd")
const AirshipCatalog := preload("res://vehicles/airship/airship_catalog.gd")
const GroundCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")
const PREFS := "user://test_home_vehicle_roster.cfg"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s %s" % [label, detail])


func _run() -> void:
	var errors := Roster.validation_errors()
	check("every RC vehicle id is installed and distinct from every aircraft id", errors.is_empty(), str(errors))
	var ids := Roster.ids()
	var aircraft := Catalog.player_ids()
	check("the roster lists the stock aircraft first, in catalog order", ids.slice(0, aircraft.size()) == aircraft)
	check("then the FPV quad, the RC blimp and every RC car", ids.slice(aircraft.size()) \
		== PackedStringArray(["openrc-fpv5-x1", "rc-blimp-5m"] + GroundCatalog.IDS), str(ids))
	check("technical aircraft stay out of the roster", not ids.has("stik-glow-61fx-2t") and not Roster.has("stik-glow-61fx-2t"))
	for id: String in ids:
		var entry := Roster.entry(id)
		check("%s has a name, summary, note and status" % id, not str(entry.get("name", "")).is_empty()
			and not str(entry.get("summary", "")).is_empty() and not str(entry.get("status_note", "")).is_empty()
			and entry.get("status") in [Catalog.FLYABLE, Catalog.EXPERIMENTAL, Catalog.PREVIEW])
	check("RC vehicles are experimental activities, never aircraft", Roster.ACTIVITIES.all(func(entry: Dictionary) -> bool:
		return Roster.entry(entry.id).status == Catalog.EXPERIMENTAL and Roster.is_activity(entry.id) and not Catalog.has(entry.id)))
	check("step wraps through the whole roster", Roster.step(ids[ids.size() - 1], 1) == ids[0] and Roster.step(ids[0], -1) == ids[ids.size() - 1]
		and Roster.step("unknown", 1).is_empty())
	check("only the blimp has paints, one per skin", Roster.skin_choices("rc-blimp-5m").size() == AirshipCatalog.SKIN_IDS.size()
		and Roster.skin_choices("mt8-bisonte").is_empty() and Roster.skin_choices(Catalog.DEFAULT_ID).is_empty())
	check("an unknown blimp skin flies the default skin", Roster.resolve_skin("rc-blimp-5m", "nope") == AirshipCatalog.DEFAULT_SKIN
		and Roster.resolve_skin("rc-blimp-5m", "historico") == "historico")

	# Render-only backdrop models: each delivered model builds, stands on the ground and is preloadable.
	for entry: Dictionary in Roster.ACTIVITIES:
		var id: String = entry.id
		var path := PreviewResources.path_for(id, "historico")
		check("%s preview model is a packaged resource (%s)" % [id, path], not path.is_empty() and ResourceLoader.exists(path))
		var model := VehiclePreview.build(id, "historico")
		check("%s preview builds" % id, not model.is_empty() and model.root is Node3D and model.aircraft_id == id)
		if model.is_empty():
			continue
		var bounds := HomeBounds.of(model.root)
		var presentation := VehiclePreview.prepare(model, bounds)
		check("%s preview rests on its lowest point" % id, bounds.size.length() > 0.1
			and is_equal_approx(float(presentation.lift), -bounds.position.y + 0.005) and presentation.alignment == Basis.IDENTITY,
			str(bounds))
		model.root.free()
	check("an aircraft preview path is unchanged", PreviewResources.path_for(Catalog.DEFAULT_ID) == PreviewResources.path_for(Catalog.DEFAULT_ID, ""))

	# Additive preferences: the RC vehicle and blimp skin survive a save/load; invalid values fall back safely.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var prefs := Preferences.load_from(PREFS)
	check("defaults select the aircraft", str(prefs.home_vehicle).is_empty() and prefs.airship_skin == AirshipCatalog.DEFAULT_SKIN)
	prefs.home_vehicle = "monster-car-2"
	prefs.airship_skin = "cromo-carbono-azul"
	check("an RC vehicle selection saves", Preferences.save_to(PREFS, prefs) == OK)
	var loaded := Preferences.load_from(PREFS)
	check("an RC vehicle selection and blimp skin load back", loaded.home_vehicle == "monster-car-2"
		and loaded.airship_skin == "cromo-carbono-azul" and loaded.aircraft == prefs.aircraft)
	loaded.home_vehicle = Catalog.DEFAULT_ID # an aircraft id is never an RC vehicle selection
	loaded.airship_skin = "missing"
	check("invalid values still save", Preferences.save_to(PREFS, loaded) == OK)
	var sanitized := Preferences.load_from(PREFS)
	check("invalid values fall back to the aircraft and the default skin", str(sanitized.home_vehicle).is_empty()
		and sanitized.airship_skin == AirshipCatalog.DEFAULT_SKIN)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("Home vehicle roster: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


class HomeBounds:
	static func of(root: Node3D) -> AABB:
		return preload("res://ui/home_presentation.gd").mesh_bounds(root, root)
