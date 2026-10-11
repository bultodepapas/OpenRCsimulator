## SCENERY-PLAN: the scenery track's single entry point. render/field.gd calls `attach(field_node, field)` once; with the
## switch off (the default until Gate SC) it returns at once and nothing changes, byte for byte. With it on, the
## validated `openrc-scenery v1` data becomes compact 40 m cells — each ONE merged mesh with ONE vertex-colour material
## (Compatibility does no 3D batching: SC-01) — plus contact shadows, moving parts on sim_clock, flower MultiMeshes,
## the parked fleet and the synthesised ambience. Visual only: nothing here reads or writes the simulation.
extends RefCounted

const Loader = preload("res://scenery/scenery_loader.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Prefabs = preload("res://scenery/prefabs.gd")
const Models = preload("res://scenery/models.gd")
const Palette = preload("res://scenery/palette.gd")
const GroundFeatures = preload("res://scenery/ground_features.gd")
const Flowers = preload("res://scenery/flowers.gd")
const Ambience = preload("res://scenery/ambience.gd")
const Birds = preload("res://scenery/birds.gd")
const Frames = preload("res://render/frames.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const MOTION_SHADER: Shader = preload("res://scenery/motion.gdshader")

const CELL_M := 40.0
const FAR_CELL_M := 400.0
const FAR_M := 400.0
const SHADOW_RANGE_M := 300.0
const QUALITIES: Array[String] = ["low", "balanced", "high"]


## The switch and options. CLI (after --) wins, then the environment, then the defaults. On by default (SC-02a).
static func options() -> Dictionary:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "on"
	var get := func(key: String, env: String, fallback: String) -> String:
		if args.has(key):
			return str(args[key])
		var e := OS.get_environment(env)
		return e if not e.is_empty() else fallback
	var on := func(v: String) -> bool: return ["on", "1", "true", "yes"].has(v.to_lower())
	return {
		enabled = on.call(get.call("scenery", "OPENRC_SCENERY", "on")),
		theme = get.call("scenery_theme", "OPENRC_SCENERY_THEME", ""),
		quality = get.call("scenery_quality", "OPENRC_SCENERY_QUALITY", "high"),
		audio = on.call(get.call("scenery_audio", "OPENRC_SCENERY_AUDIO", "on")),
		birds = on.call(get.call("scenery_birds", "OPENRC_SCENERY_BIRDS", "off")),
		file = get.call("scenery_file", "OPENRC_SCENERY_FILE", Loader.DEFAULT_PATH),
	}


static func enabled() -> bool:
	return options().enabled


## Called by render/field.gd after it built the field. No-op when the switch is off.
static func attach(field_node: Node3D, field: Dictionary, lighting: Dictionary = {}) -> void:
	var opts := options()
	if not opts.enabled:
		return
	var loaded := Loader.load_from(str(opts.file), field)
	if not loaded.ok:
		for e: String in loaded.errors:
			push_error("scenery: " + e)
		return
	field_node.add_child(build(field, loaded.scenery, opts, lighting))


static func opaque_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.88
	m.metallic_specular = 0.3
	return m


static func shadow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = -1
	return m


## Tier filter (SC-24): low keeps landmarks and standard props; balanced drops half the ornaments (a fixed, seeded half,
## so changing quality never reshuffles); high keeps everything.
static func keep(tier: String, seed: int, quality: String) -> bool:
	if tier == "landmark" or tier == "standard" or quality == "high":
		return true
	if quality == "low":
		return false
	return Palette.hash01(seed, 4242) < 0.5


static func _cell(n: float, e: float) -> Vector2i:
	var far := Vector2(n, e).length() > FAR_M
	var size := FAR_CELL_M if far else CELL_M
	var key := Vector2i(floori(n / size), floori(e / size))
	return key * (1000 if far else 1) + (Vector2i(1, 1) * 1000000 if far else Vector2i.ZERO)


static func _kit(cells: Dictionary, key: Vector2i) -> MeshKit:
	if not cells.has(key):
		cells[key] = MeshKit.new()
	return cells[key]


static func _placement_xf(n: float, e: float, heading_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(heading_deg)), Frames.ned_to_render([n, e, 0.0]))


static func build(field: Dictionary, scenery: Dictionary, opts: Dictionary, lighting: Dictionary = {}) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var root := Node3D.new()
	root.name = "Scenery"
	var theme: String = opts.theme if Palette.THEMES.has(opts.theme) else scenery.theme
	var quality: String = opts.quality if QUALITIES.has(opts.quality) else "high"
	var opaque := opaque_material()
	var shade := shadow_material()
	var sun := Atmosphere.sun_direction(lighting)
	var shadow_strength: float = Atmosphere.shadow_strength(lighting)
	shade.albedo_color.a = shadow_strength
	var pilot := Vector2(float(field.pilot.north), float(field.pilot.east))
	var cells := {}
	var shadow_cells := {}
	var shadow_groups: Dictionary = {}
	var stats := {instances = 0, skipped = 0, shadows = 0, motion = 0, flowers = 0, fleet = 0, theme = theme, quality = quality}
	var motion_parent := Node3D.new()
	motion_parent.name = "Motion"
	root.add_child(motion_parent)
	var timing := {}
	for group: Dictionary in scenery.groups:
		var g0 := Time.get_ticks_usec()
		match group.type:
			"instances":
				for pl: Dictionary in group.placements:
					var prefab: String = pl.prefab
					var spec: Dictionary = Prefabs.CATALOG[prefab] if Prefabs.CATALOG.has(prefab) else Models.CATALOG[prefab]
					if not keep(spec.tier, pl.seed, quality):
						stats.skipped += 1
						continue
					var xf := _placement_xf(pl.north, pl.east, pl.heading)
					var kit := _kit(cells, _cell(pl.north, pl.east))
					if Prefabs.CATALOG.has(prefab):
						kit.xf = xf
						var moving: Array = Prefabs.build(prefab, kit, pl.seed, theme)
						kit.xf = Transform3D.IDENTITY
						for part: Dictionary in moving:
							motion_parent.add_child(_motion_node(part, xf, pl.seed))
							stats.motion += 1
					else:
						var arr := Models.arrays(prefab)
						if arr.is_empty():
							continue
						var paint: Variant = Palette.pick(Palette.PAINTS, pl.seed, 17) if spec.get("paint", false) else null
						kit.xf = Transform3D.IDENTITY
						kit.append_arrays(arr.pos, arr.nrm, arr.col, xf, paint)
					stats.instances += 1
					var mode: Variant = spec.get("shadow", false)
					if mode != false and Vector2(pl.north, pl.east).distance_to(pilot) <= SHADOW_RANGE_M:
						var shadow_cell: Vector2i = _cell(pl.north, pl.east)
						if not shadow_groups.has(shadow_cell):
							shadow_groups[shadow_cell] = []
						var shadow_mode: String = "solid" if mode == true else str(mode)
						shadow_groups[shadow_cell].append({transform = xf, size = spec.size, mode = shadow_mode})
						if shadow_strength > 0.0:
							GroundFeatures.contact_shadow(_kit(shadow_cells, shadow_cell), xf, spec.size, shadow_mode, sun)
							stats.shadows += 1
			"fleet": # baked snapshots (tools/scenery/bake_fleet.gd): merged into the shelter's cell, ~5 k triangles each
				for pl: Dictionary in group.placements:
					var model_id := str(Models.FLEET.find_key(str(pl.aircraft)))
					var arr := Models.arrays(model_id)
					if arr.is_empty():
						continue
					var kit := _kit(cells, _cell(pl.north, pl.east))
					kit.xf = Transform3D.IDENTITY
					kit.append_arrays(arr.pos, arr.nrm, arr.col, _placement_xf(pl.north, pl.east, pl.heading))
					stats.fleet += 1
			"hedge", "fence":
				var pts: Array = group.points
				for i in pts.size() - 1:
					var a: Vector2 = pts[i]
					var b: Vector2 = pts[i + 1]
					var mid := (a + b) * 0.5
					var kit := _kit(cells, _cell(mid.x, mid.y))
					var seg := PackedVector2Array([_xz(a), _xz(b)])
					if group.type == "hedge":
						GroundFeatures.hedge(kit, seg, group.height, group.width, theme, group.seed + i * 17)
					else:
						GroundFeatures.fence(kit, seg, group.style, group.seed + i * 17)
			"track", "patch":
				var poly := PackedVector2Array()
				for p: Vector2 in group.points:
					poly.append(_xz(p))
				var first: Vector2 = group.points[0]
				var kit := _kit(cells, _cell(first.x, first.y) + Vector2i(0, 7777)) # its own cell: flat, drawn once
				if group.type == "track":
					GroundFeatures.track(kit, poly, group.width, group.surface, theme)
				else:
					GroundFeatures.patch(kit, poly, group.surface, theme, group.seed)
			"flowers":
				var keep_flower := func(i: int) -> bool: return keep("ornament", group.seed + i, quality)
				for node: MultiMeshInstance3D in Flowers.build(group.positions, theme, keep_flower):
					root.add_child(node)
					stats.flowers += node.multimesh.instance_count
		timing[group.type] = float(timing.get(group.type, 0.0)) + (Time.get_ticks_usec() - g0) / 1000.0
	var m0 := Time.get_ticks_usec()
	var keys := cells.keys()
	keys.sort()
	for key: Vector2i in keys:
		var kit: MeshKit = cells[key]
		if kit.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "cell_%d_%d" % [key.x, key.y]
		mi.mesh = kit.to_mesh(opaque)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var shadow_nodes: Dictionary = {}
	var skeys: Array = shadow_groups.keys()
	skeys.sort()
	for key: Vector2i in skeys:
		var kit: MeshKit = shadow_cells[key] if shadow_cells.has(key) else MeshKit.new()
		var mi := MeshInstance3D.new()
		mi.name = _shadow_batch_name(key)
		mi.mesh = kit.to_mesh(shade)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		shadow_nodes[key] = mi
	if opts.get("audio", false):
		root.add_child(Ambience.player())
	if opts.get("birds", false):
		root.add_child(Birds.flock(Vector2(pilot.x, pilot.y)))
	timing["meshes"] = (Time.get_ticks_usec() - m0) / 1000.0
	stats.timing_ms = timing
	stats.cells = keys.size()
	stats.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	root.set_meta("stats", stats)
	root.set_meta("directional_shadow_material", shade)
	root.set_meta("directional_shadow_groups", shadow_groups)
	root.set_meta("directional_shadow_nodes", shadow_nodes)
	root.set_meta("directional_shadow_signature", _shadow_signature(sun, shadow_strength))
	root.set_meta("directional_shadow_strength", shadow_strength)
	return root


## Prepare scene-local scenery shadows from their retained source placements. No live scene resources are changed here,
## so callers can prepare all visual state before restoring physics or committing a checkpoint.
static func prepare_lighting(field_node: Node3D, lighting: Dictionary) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var root: Node3D = _find_scenery(field_node)
	if root == null or not root.has_meta("directional_shadow_nodes"):
		return {ok = true, changed = false, no_op = true, prepare_ms = 0.0, batches = []}
	var material: StandardMaterial3D = root.get_meta("directional_shadow_material") as StandardMaterial3D
	var nodes: Dictionary = root.get_meta("directional_shadow_nodes")
	var groups: Dictionary = root.get_meta("directional_shadow_groups")
	var sun: Vector3 = Atmosphere.sun_direction(lighting)
	var strength: float = Atmosphere.shadow_strength(lighting)
	var signature: Dictionary = _shadow_signature(sun, strength)
	var geometry_changed: bool = signature != root.get_meta("directional_shadow_signature", {})
	var strength_changed: bool = strength != float(root.get_meta("directional_shadow_strength", 1.0))
	var prepared_batches: Array[Dictionary] = []
	var triangles: int = 0
	if geometry_changed:
		var keys: Array = nodes.keys()
		keys.sort()
		for key: Vector2i in keys:
			var kit := MeshKit.new()
			if strength > 0.0:
				for source: Dictionary in groups.get(key, []):
					GroundFeatures.contact_shadow(kit, source.transform, source.size, source.mode, sun)
			triangles += kit.triangle_count()
			prepared_batches.append({node = nodes[key], mesh = kit.to_mesh(material)})
	return {
		ok = true,
		changed = geometry_changed or strength_changed,
		no_op = false,
		root = root,
		material = material,
		strength = strength,
		base_signature = root.get_meta("directional_shadow_signature", {}),
		base_strength = float(root.get_meta("directional_shadow_strength", 1.0)),
		signature = signature,
		batches = prepared_batches,
		geometry_changed = geometry_changed,
		triangles = triangles,
		prepare_ms = float(Time.get_ticks_usec() - started) / 1000.0,
	}


## Commit a prepared scenery-lighting update. The existing shadow material and per-cell nodes stay stable; only their
## alpha and ArrayMesh resources change. Returns false only if the prepared field no longer owns that scenery root.
static func commit_lighting(field_node: Node3D, prepared: Dictionary) -> bool:
	if not bool(prepared.get("ok", false)):
		return false
	if bool(prepared.get("no_op", false)):
		return true
	var root: Node3D = prepared.get("root") as Node3D
	if not is_instance_valid(root) or _find_scenery(field_node) != root:
		return false
	if root.get_meta("directional_shadow_signature", {}) != prepared.get("base_signature", {}):
		return false
	if float(root.get_meta("directional_shadow_strength", 1.0)) != float(prepared.get("base_strength", 1.0)):
		return false
	var material: StandardMaterial3D = prepared.get("material") as StandardMaterial3D
	if not is_instance_valid(material) or root.get_meta("directional_shadow_material", null) != material:
		return false
	var replacements: Array = prepared.get("batches", [])
	for replacement: Dictionary in replacements:
		var node: MeshInstance3D = replacement.get("node") as MeshInstance3D
		var mesh: ArrayMesh = replacement.get("mesh") as ArrayMesh
		if not is_instance_valid(node) or node.get_parent() != root or not is_instance_valid(mesh):
			return false
	var tint: Color = material.albedo_color
	tint.a = float(prepared.get("strength", tint.a))
	material.albedo_color = tint
	for replacement: Dictionary in replacements:
		var node: MeshInstance3D = replacement.get("node") as MeshInstance3D
		node.mesh = replacement.get("mesh") as ArrayMesh
	root.set_meta("directional_shadow_signature", prepared.get("signature", {}))
	root.set_meta("directional_shadow_strength", float(prepared.get("strength", tint.a)))
	return true


## Convenience for live time-of-day changes that do not need a separate atomic prepare/commit boundary.
static func update_lighting(field_node: Node3D, lighting: Dictionary) -> bool:
	var prepared: Dictionary = prepare_lighting(field_node, lighting)
	return commit_lighting(field_node, prepared)


static func _find_scenery(field_node: Node3D) -> Node3D:
	if field_node == null:
		return null
	if field_node.name == "Scenery" and field_node.has_meta("directional_shadow_nodes"):
		return field_node
	return field_node.get_node_or_null("Scenery") as Node3D


static func _shadow_batch_name(cell: Vector2i) -> String:
	return "shadows_%d_%d" % [cell.x, cell.y]


static func _shadow_signature(sun: Vector3, strength: float) -> Dictionary:
	var visible: bool = strength > 0.0
	return {cast = GroundFeatures.shadow_cast(sun) if visible else Vector2.ZERO, visible = visible}


static func _xz(ne: Vector2) -> Vector2:
	var p := Frames.ned_to_render([ne.x, ne.y, 0.0])
	return Vector2(p.x, p.z)


static func _motion_node(part: Dictionary, xf: Transform3D, seed: int) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = MOTION_SHADER
	mat.set_shader_parameter("mode", 0 if part.kind == "rotor" else 1)
	mat.set_shader_parameter("rate", float(part.get("rate", 0.0)))
	mat.set_shader_parameter("phase", float(part.get("phase", Palette.hash01(seed, 77))))
	var kit: MeshKit = part.kit
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [part.kind, seed]
	mi.mesh = kit.to_mesh(mat)
	mi.transform = xf * Transform3D(Basis.IDENTITY, part.pivot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := mi.mesh.get_aabb()
	if part.kind == "rotor": # bounds cover every rotation (VQ §10)
		var r := maxf(box.size.x, box.size.y)
		mi.custom_aabb = AABB(Vector3(-r, -r, box.position.z - 1.0), Vector3(2.0 * r, 2.0 * r, box.size.z + 2.0))
	else:
		mi.custom_aabb = box.grow(0.6)
	return mi
