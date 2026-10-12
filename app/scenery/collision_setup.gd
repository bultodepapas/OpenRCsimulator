## LU-05: one scenery/lighting visibility policy for the flight collision inventory.
## Builds before the session enters the tree. No scene traversal occurs in the physics tick.
extends RefCounted
const Options := preload("res://render/landscape_upgrade/options.gd")
const Scenery := preload("res://scenery/scenery.gd")
const Loader := preload("res://scenery/scenery_loader.gd")
const Prefabs := preload("res://scenery/prefabs.gd")
const Models := preload("res://scenery/models.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

static func build(field: Dictionary) -> Dictionary:
	if not Options.enabled():
		return {ok = true, world = {}, errors = PackedStringArray()}
	var scenery := {groups = []}
	var opts := Scenery.options()
	if opts.enabled and Scenery.layout_file_applies(field, opts):
		var loaded := Loader.load_from(str(opts.file), field)
		if not loaded.ok:
			return {ok = false, world = {}, errors = loaded.errors}
		scenery = loaded.scenery.duplicate(true)
		var quality: String = opts.quality if Scenery.QUALITIES.has(opts.quality) else "high"
		for group: Dictionary in scenery.groups:
			if group.type != "instances":
				continue
			var kept := []
			for placement: Dictionary in group.placements:
				var spec: Dictionary = Prefabs.CATALOG[placement.prefab] if Prefabs.CATALOG.has(placement.prefab) else Models.CATALOG[placement.prefab]
				if Scenery.keep(spec.tier, placement.seed, quality):
					kept.append(placement)
			group.placements = kept
	var lights := {}
	if field.get("id", "") == "default":
		var loaded := FieldLights.load_from()
		if not loaded.ok:
			return {ok = false, world = {}, errors = loaded.errors}
		lights = loaded.lights
	return CollisionWorld.build(field, scenery, lights)
