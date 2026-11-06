# PT1h-R9: render diagnostics for the debug bridge. Renderer timing readbacks can be unavailable or stale; the
# probe reports their scope and does not infer a bottleneck. It also exposes pass counters, scene census, viewport
# debug draw modes, and reversible per-target ablation; no shader is edited.
# Guide: tools/debug/README.md#render-cost-pt1h-r9.
extends RefCounted

const PASSES := {visible = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
	shadow = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, canvas = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS}
const FLAG_HELP := {
	"@shadows": "shadow casting of every visible Light3D",
	"@fog": "Environment fog and volumetric fog",
	"@glow": "Environment glow",
	"@msaa": "3D MSAA of the root viewport",
	"@half_res": "root viewport 3D resolution scale x0.5 (is the frame pixel-bound?)",
	"@subviewports": "rendering of every SubViewport (render-to-texture work)",
	"@canvas": "every visible CanvasLayer (HUD, overlays, menus)",
}
const MAX_TARGETS := 48

var viewport: Viewport
var measuring := false
var _measured: Dictionary = {} # viewport RID -> true, measurement already enabled


func _init(target: Viewport) -> void:
	viewport = target


static func available() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "dummy"


func set_measure(on: bool) -> void:
	measuring = on and available()
	_measured.clear()
	_enable(viewport.get_viewport_rid())
	for sub: SubViewport in subviewports():
		_enable(sub.get_viewport_rid())


func _enable(rid: RID) -> void:
	if not rid.is_valid():
		return
	RenderingServer.viewport_set_measure_render_time(rid, measuring)
	if measuring:
		_measured[rid] = true


## Root-viewport GPU time of the last measured frame (ms), or -1 when not measuring. Cheap: used every frame.
func root_gpu_ms() -> float:
	if not measuring:
		return -1.0
	var value := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	return value if is_finite(value) and value > 0.0 else -1.0


func subviewports() -> Array[SubViewport]:
	var found: Array[SubViewport] = []
	var stack: Array[Node] = [viewport]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is SubViewport and node != viewport:
			found.append(node)
		stack.append_array(node.get_children(true))
	return found


## One frame: render times and pass counters; SubViewports created since the last call start measuring now.
func sample() -> Dictionary:
	var rid := viewport.get_viewport_rid()
	var out := {gpu_ms = 0.0, root_gpu_ms = 0.0, root_cpu_ms = 0.0, sub_gpu_ms = 0.0, setup_cpu_ms = 0.0,
		gpu_timing_status = "unavailable_or_zero", gpu_ms_scope = "root_only_freshness_unverified",
		sub_gpu_ms_scope = "last_readings_unverified_may_not_have_drawn",
		draw_calls = 0, primitives = 0, objects = 0, shadow_draw_calls = 0, canvas_draw_calls = 0}
	if measuring:
		var root_gpu := root_gpu_ms()
		if root_gpu > 0.0:
			out.root_gpu_ms = root_gpu
			out.gpu_timing_status = "unverified_freshness"
		out.root_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid)
		out.setup_cpu_ms = RenderingServer.get_frame_setup_time_cpu()
	out.gpu_ms = out.root_gpu_ms
	for pass_name: String in PASSES:
		var kind: int = PASSES[pass_name]
		var calls := RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		out.draw_calls += calls
		if pass_name != "canvas":
			out.primitives += RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
			out.objects += RenderingServer.viewport_get_render_info(rid, kind, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		if pass_name == "shadow":
			out.shadow_draw_calls = calls
		elif pass_name == "canvas":
			out.canvas_draw_calls = calls
	if measuring:
		for sub: SubViewport in subviewports():
			var sub_rid := sub.get_viewport_rid()
			if not _measured.has(sub_rid):
				_enable(sub_rid)
			if sub.render_target_update_mode != SubViewport.UPDATE_DISABLED:
				var sub_gpu := RenderingServer.viewport_get_measured_render_time_gpu(sub_rid)
				if is_finite(sub_gpu) and sub_gpu > 0.0: out.sub_gpu_ms += sub_gpu
	return out


## Per-viewport detail for `render`: each SubViewport's size, update mode and GPU time.
func viewport_rows() -> Array:
	var rows: Array = []
	for sub: SubViewport in subviewports():
		var rid := sub.get_viewport_rid()
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(rid) if measuring else 0.0
		var reported := measuring and is_finite(gpu) and gpu > 0.0
		rows.append({path = str(viewport.get_path_to(sub)), size = [sub.size.x, sub.size.y],
			update = ["disabled", "once", "when_visible", "when_parent_visible", "always"][sub.render_target_update_mode],
			gpu_ms = snappedf(gpu, 0.001) if reported else null,
			gpu_timing_status = "unverified_freshness" if reported else "unavailable_or_zero"})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.gpu_ms if a.gpu_ms != null else 0.0) > float(b.gpu_ms if b.gpu_ms != null else 0.0))
	return rows


## What decides the frame's cost, in one read.
func config() -> Dictionary:
	var out := {renderer = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name(),
		api = RenderingServer.get_video_adapter_api_version(), size = [viewport.size.x, viewport.size.y],
		window = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y] if available() else null,
		vsync = ["disabled", "enabled", "adaptive", "mailbox"][DisplayServer.window_get_vsync_mode()] if available() else null,
		max_fps = Engine.max_fps, refresh_hz = DisplayServer.screen_get_refresh_rate() if available() else null,
		scaling_3d_mode = viewport.scaling_3d_mode, scaling_3d_scale = viewport.scaling_3d_scale, msaa_3d = viewport.msaa_3d,
		screen_space_aa = viewport.screen_space_aa, use_taa = viewport.use_taa, mesh_lod_threshold = viewport.mesh_lod_threshold,
		debug_draw = view_mode_name(viewport.debug_draw),
		texture_mem_mib = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		buffer_mem_mib = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		video_mem_mib = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)}
	var env := environment()
	if env != null:
		out.environment = {background = env.background_mode, tonemap = env.tonemap_mode, fog = env.fog_enabled,
			volumetric_fog = env.volumetric_fog_enabled, glow = env.glow_enabled, ssao = env.ssao_enabled,
			ssr = env.ssr_enabled, ssil = env.ssil_enabled, sdfgi = env.sdfgi_enabled}
	var lights: Array = []
	for light: Light3D in _lights(scene_root()):
		lights.append({path = str(viewport.get_path_to(light)), type = light.get_class(), shadow = light.shadow_enabled,
			mode = light.get("directional_shadow_mode") if light is DirectionalLight3D else null,
			max_distance = light.get("directional_shadow_max_distance") if light is DirectionalLight3D else null})
	out.lights = lights
	out.directional_shadow_size = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 0)
	return out


func environment() -> Environment:
	var camera := viewport.get_camera_3d()
	if camera != null and camera.environment != null:
		return camera.environment
	var world := viewport.find_world_3d()
	return world.environment if world != null else null


## The topmost Node3D above the active camera: the flight's Main, Home's backdrop, the truck scene.
func scene_root() -> Node3D:
	var camera := viewport.get_camera_3d()
	if camera == null:
		return null
	var root: Node3D = camera
	var node: Node = camera.get_parent()
	while node != null and node != viewport:
		if node is Node3D:
			root = node
		node = node.get_parent()
	return root


## Geometry census of the scene root's descendants up to `depth`: visible geometry instances, MultiMesh
## instances, shadow casters and lights under each node. Sorted by geometry count.
func layers(root: Node3D, depth: int) -> Array:
	var rows: Array = []
	if root == null:
		return rows
	_collect_layers(root, root, 1, depth, rows)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.geometry > b.geometry)
	return rows


func _collect_layers(root: Node3D, parent: Node, level: int, depth: int, rows: Array) -> void:
	for child: Node in parent.get_children():
		if not child is Node3D or child is Camera3D:
			continue
		var census := _census(child)
		if census.geometry == 0 and census.lights == 0:
			continue
		census.path = str(root.get_path_to(child))
		census.level = level
		census.visible = (child as Node3D).is_visible_in_tree()
		census.script = str(child.get_script().resource_path).get_file() if child.get_script() != null else ""
		rows.append(census)
		if level < depth:
			_collect_layers(root, child, level + 1, depth, rows)


static func _census(node: Node) -> Dictionary:
	var out := {geometry = 0, multimesh_instances = 0, shadow_casters = 0, lights = 0}
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is GeometryInstance3D and (current as GeometryInstance3D).is_visible_in_tree():
			out.geometry += 1
			if (current as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				out.shadow_casters += 1
			if current is MultiMeshInstance3D and (current as MultiMeshInstance3D).multimesh != null:
				var multimesh: MultiMesh = (current as MultiMeshInstance3D).multimesh
				out.multimesh_instances += multimesh.visible_instance_count if multimesh.visible_instance_count >= 0 else multimesh.instance_count
		elif current is Light3D and (current as Light3D).is_visible_in_tree():
			out.lights += 1
		stack.append_array(current.get_children())
	return out


static func _lights(root: Node) -> Array[Light3D]:
	var found: Array[Light3D] = []
	if root == null:
		return found
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Light3D and (node as Light3D).is_visible_in_tree():
			found.append(node)
		stack.append_array(node.get_children())
	return found


# ---- viewport debug draw -----------------------------------------------------------------------------------

static func view_modes() -> Array:
	var names: Array = []
	for constant: String in ClassDB.class_get_enum_constants("Viewport", "DebugDraw"):
		names.append(constant.trim_prefix("DEBUG_DRAW_").to_lower())
	return names


static func view_mode_name(value: int) -> String:
	var names := view_modes()
	return names[value] if value >= 0 and value < names.size() else str(value)


## name=normal|unshaded|wireframe|overdraw|lighting|...; the renderer may ignore modes it does not implement.
func set_view_mode(mode_name: String) -> Dictionary:
	var wanted := mode_name.to_lower().strip_edges()
	if wanted in ["normal", "off", "none"]:
		wanted = "disabled"
	var index := view_modes().find(wanted)
	if index < 0:
		return {ok = false, error = "unknown view mode '%s'; modes: normal, %s" % [mode_name, ", ".join(view_modes().slice(1))]}
	if wanted == "wireframe":
		RenderingServer.set_debug_generate_wireframes(true) # meshes created from now on carry wireframe data
	viewport.debug_draw = index as Viewport.DebugDraw
	var out := {ok = true, mode = view_mode_name(viewport.debug_draw)}
	if wanted == "wireframe":
		out.note = "only meshes created from now on have wireframes: set it on Home, then fly"
	return out


# ---- ablation ----------------------------------------------------------------------------------------------

## The toggles to measure: explicit `targets` (scene-root-relative node paths or @flags), else every geometry
## layer of the census plus every flag. Each target: {name, kind, apply, restore, held}.
func ablation_targets(root: Node3D, names: Array, depth: int) -> Dictionary:
	var wanted: Array = names.duplicate()
	if wanted.is_empty():
		# Flags first, then every top-level layer, then the children of a layer that holds a large share of the
		# geometry (down to `depth`), so a few large rows replace dozens of tiny ones.
		wanted.append_array(FLAG_HELP.keys())
		var rows := layers(root, depth)
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.level < b.level if a.level != b.level else a.geometry > b.geometry)
		var total := 0
		for row: Dictionary in rows:
			if row.level == 1:
				total += int(row.geometry)
		var big := {}
		for row: Dictionary in rows:
			if not row.visible or row.geometry == 0:
				continue
			var parent := str(row.path).get_base_dir()
			if row.level == 1 or (big.has(parent) and row.geometry >= maxi(3, roundi(0.05 * total))):
				wanted.append(row.path)
				if row.geometry >= maxi(10, roundi(0.15 * total)):
					big[row.path] = true
	var targets: Array = []
	var skipped: Array = [] # unknown paths, hidden layers, features already off
	var skipped_reasons := {}
	for item: Variant in wanted:
		var target_name := str(item)
		var target := _flag_target(target_name) if FLAG_HELP.has(target_name) else _node_target(root, target_name)
		if target.is_empty():
			skipped.append(target_name)
			skipped_reasons[target_name] = "non_bilinear_reconstruction" if target_name == "@half_res" \
				and not _can_half_res(viewport.scaling_3d_mode) else "unknown_hidden_or_already_off"
		else:
			targets.append(target)
	return {targets = targets.slice(0, MAX_TARGETS), skipped = skipped, skipped_reasons = skipped_reasons,
		truncated = targets.size() > MAX_TARGETS}


func _node_target(root: Node3D, path: String) -> Dictionary:
	var node: Node = root.get_node_or_null(path) if root != null else null
	if not node is Node3D or not (node as Node3D).visible:
		return {}
	return _toggle(path, "layer", [[node, "visible"]], [false])


static func _can_half_res(mode: int) -> bool:
	return mode == Viewport.SCALING_3D_MODE_BILINEAR


func _flag_target(flag: String) -> Dictionary:
	var bindings: Array = []
	var off: Array = []
	match flag:
		"@shadows":
			for light: Light3D in _lights(scene_root()):
				if light.shadow_enabled:
					bindings.append([light, "shadow_enabled"])
					off.append(false)
		"@fog", "@glow":
			var env := environment()
			for prop: String in (["fog_enabled", "volumetric_fog_enabled"] if flag == "@fog" else ["glow_enabled"]):
				if env != null and bool(env.get(prop)):
					bindings.append([env, prop])
					off.append(false)
		"@msaa":
			if viewport.msaa_3d != Viewport.MSAA_DISABLED:
				bindings.append([viewport, "msaa_3d"])
				off.append(Viewport.MSAA_DISABLED)
		"@half_res":
			if _can_half_res(viewport.scaling_3d_mode):
				bindings.append([viewport, "scaling_3d_scale"])
				off.append(viewport.scaling_3d_scale * 0.5)
		"@subviewports":
			for sub: SubViewport in subviewports():
				if sub.render_target_update_mode != SubViewport.UPDATE_DISABLED:
					bindings.append([sub, "render_target_update_mode"])
					off.append(SubViewport.UPDATE_DISABLED)
		"@canvas":
			var stack: Array[Node] = [viewport]
			while not stack.is_empty():
				var node: Node = stack.pop_back()
				if node is CanvasLayer and (node as CanvasLayer).visible and (node as CanvasLayer).get_viewport() == viewport:
					bindings.append([node, "visible"])
					off.append(false)
				stack.append_array(node.get_children())
	return _toggle(flag, "flag", bindings, off) if not bindings.is_empty() else {}


## Capture the live values at phase start, not while constructing the target list.
## Weak references let freed scene nodes be reported as unavailable without a script error.
static func _toggle(target_name: String, kind: String, bindings: Array, off: Array) -> Dictionary:
	var references: Array = []
	var discovered: Array = []
	for binding: Array in bindings:
		var object: Variant = binding[0]
		references.append([weakref(object) if is_instance_valid(object) else null, binding[1]])
		discovered.append({value = object.get(binding[1])} if is_instance_valid(object) else null)
	var state := {values = [], discovered = discovered, applied = false, missing = false, changed = false,
		discovery_unchanged = true}
	return {name = target_name, kind = kind, apply = _apply_toggle.bind(references, off, state),
		restore = _restore_toggle.bind(references, off, state), held = _toggle_held.bind(references, off, state)}


static func _apply_toggle(bindings: Array, off: Array, state: Dictionary) -> void:
	if state.applied: return
	state["values"] = []
	state.missing = false
	state.changed = false
	state.discovery_unchanged = true
	for i in bindings.size():
		var reference: Variant = bindings[i][0]
		var object: Variant = reference.get_ref() if reference != null else null
		if object == null:
			state["values"].append(null)
			state.missing = true
			continue
		var before: Variant = object.get(bindings[i][1])
		state["values"].append({value = before})
		if not state.discovered[i] is Dictionary or not _same_value(before, state.discovered[i].value):
			state.discovery_unchanged = false
		state.changed = bool(state.changed) or not _same_value(before, off[i])
		object.set(bindings[i][1], off[i])
	state.applied = true


static func _restore_toggle(bindings: Array, off: Array, state: Dictionary) -> void:
	if not state.applied: return
	for i in bindings.size():
		var reference: Variant = bindings[i][0]
		var object: Variant = reference.get_ref() if reference != null else null
		if object != null and state["values"][i] is Dictionary and _same_value(object.get(bindings[i][1]), off[i]):
			object.set(bindings[i][1], state["values"][i].value)
	state.applied = false


static func _same_value(actual: Variant, expected: Variant) -> bool:
	return is_equal_approx(actual, float(expected)) if actual is float else actual == expected


## False if any sampled binding was freed, already off, or no longer holds the probe's value.
static func _toggle_held(bindings: Array, off: Array, state: Dictionary) -> bool:
	if not state.applied or state.missing or not state.changed or not state.discovery_unchanged: return false
	for i in bindings.size():
		var reference: Variant = bindings[i][0]
		var object: Variant = reference.get_ref() if reference != null else null
		if object == null or not _same_value(object.get(bindings[i][1]), off[i]): return false
	return true


static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := floori(sorted.size() / 2.0)
	return sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) / 2.0


## 1.4826 x median absolute deviation; this summary cannot establish timestamp freshness.
static func robust_sd(values: PackedFloat64Array) -> float:
	var center := median(values)
	var deviations := PackedFloat64Array()
	for value: float in values:
		deviations.append(absf(value - center))
	return 1.4826 * median(deviations)


## Frame-by-frame measurement, interleaved A-B-A: baseline, target 1 off, baseline, target 2 off, ..., baseline.
## Each target is compared with the mean of its adjacent baselines; even this cannot establish scene stability
## or timing freshness. advance() runs once per frame and returns
## true when finished; result() ranks the targets. Each phase discards `warmup` frames (render-time readback lag,
## pipeline compilation after a toggle) and then keeps `frames` samples; a baseline keeps the same count.
class Ablation extends RefCounted:
	var probe: RefCounted
	var phases: Array = []
	var warmup := 10
	var frames := 60
	var _index := -1
	var _frame := 0
	var _rows: Array = []
	var _acc: Array = []
	var _applied := {}
	var _held_during := true

	func _init(owner: RefCounted, targets: Array, warmup_frames: int, measure_frames: int) -> void:
		probe = owner
		warmup = warmup_frames
		frames = measure_frames
		for target: Dictionary in targets:
			phases.append({name = "@baseline", kind = "baseline"})
			phases.append(target)
		phases.append({name = "@baseline", kind = "baseline"})

	func total_frames() -> int:
		return phases.size() * (warmup + frames)

	func advance() -> bool:
		if _index < 0:
			_start(0)
		var phase: Dictionary = phases[_index]
		if phase.has("held") and not bool(phase.held.call()):
			_held_during = false
		_frame += 1
		if _frame > warmup:
			_acc.append(probe.sample())
		if _frame < warmup + frames:
			return false
		_finish()
		if _index + 1 >= phases.size():
			_index = phases.size()
			return true
		_start(_index + 1)
		return false

	func _start(index: int) -> void:
		_index = index
		_frame = 0
		_acc = []
		_held_during = true
		var phase: Dictionary = phases[index]
		if phase.has("apply"):
			phase.apply.call()
			_applied[index] = true

	func _finish() -> void:
		var phase: Dictionary = phases[_index]
		var held := _held_during
		if phase.has("held"):
			held = held and bool(phase.held.call())
		if phase.has("restore"):
			phase.restore.call()
			_applied.erase(_index)
		var statuses := {}
		for sample: Dictionary in _acc:
			var gpu: Variant = sample.get("gpu_ms")
			var positive: bool = (gpu is float or gpu is int) and is_finite(float(gpu)) and float(gpu) > 0.0
			statuses[str(sample.get("gpu_timing_status", "unverified_freshness")) if positive else "unavailable_or_zero"] = true
		var row := {name = phase.name, kind = phase.kind, overridden = not held,
			gpu_timing_status = statuses.keys()[0] if statuses.size() == 1 else "mixed_or_unavailable"}
		for key: String in ["gpu_ms", "draw_calls", "primitives", "objects", "root_cpu_ms"]:
			var values := PackedFloat64Array()
			for sample: Dictionary in _acc:
				var value := float(sample[key])
				values.append(value if is_finite(value) and value >= 0.0 else 0.0)
			row[key] = probe.median(values)
		_rows.append(row)

	## Undo whatever is still applied (an aborted run: the route changed, the client left).
	func abort() -> void:
		for index: int in _applied.keys():
			if phases[index].has("restore"):
				phases[index].restore.call()
		_applied.clear()

	func result() -> Dictionary:
		var baselines := PackedFloat64Array()
		var steps := PackedFloat64Array()
		for i in range(0, _rows.size(), 2):
			baselines.append(_rows[i].gpu_ms)
			if i >= 2:
				steps.append(_rows[i].gpu_ms - _rows[i - 2].gpu_ms)
		# Noise: the spread of the change between consecutive baselines, a difference of two medians like a saving.
		var noise_ms: float = probe.robust_sd(steps) if steps.size() >= 3 else 0.0
		if steps.size() > 0 and steps.size() < 3:
			for step: float in steps: noise_ms = maxf(noise_ms, absf(step))
		var rows: Array = []
		for i in range(1, _rows.size() - 1, 2):
			var before: Dictionary = _rows[i - 1]
			var after: Dictionary = _rows[i + 1]
			var row: Dictionary = _rows[i]
			var base := {}
			for key: String in ["gpu_ms", "draw_calls", "primitives", "objects", "root_cpu_ms"]:
				base[key] = (float(before[key]) + float(after[key])) / 2.0
			var saved: float = base.gpu_ms - row.gpu_ms
			var synthetic: bool = before.gpu_timing_status == "synthetic_valid" and row.gpu_timing_status == "synthetic_valid" \
				and after.gpu_timing_status == "synthetic_valid"
			var timing_status: String = before.gpu_timing_status if before.gpu_timing_status == row.gpu_timing_status \
				and row.gpu_timing_status == after.gpu_timing_status else "mixed_or_unavailable"
			rows.append({name = row.name, kind = phases[i].kind, saved_gpu_ms = snappedf(saved, 0.001),
				saved_pct = snappedf(100.0 * saved / base.gpu_ms, 0.1) if base.gpu_ms > 0.0 else 0.0,
				gpu_ms = snappedf(row.gpu_ms, 0.001), baseline_gpu_ms = snappedf(base.gpu_ms, 0.001),
				gpu_timing_status = timing_status,
				significant = synthetic and not row.overridden and absf(saved) > maxf(3.0 * noise_ms, 0.005),
				saved_draw_calls = roundi(base.draw_calls - row.draw_calls),
				saved_primitives = roundi(base.primitives - row.primitives),
				saved_objects = roundi(base.objects - row.objects),
				saved_cpu_ms = snappedf(base.root_cpu_ms - row.root_cpu_ms, 0.001), overridden = row.overridden})
		if rows.all(func(row: Dictionary) -> bool: return row.gpu_timing_status == "synthetic_valid"):
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved_gpu_ms > b.saved_gpu_ms)
		var sorted := baselines.duplicate()
		sorted.sort()
		var statuses := {}
		for phase_row: Dictionary in _rows: statuses[phase_row.gpu_timing_status] = true
		return {baseline = {gpu_ms = snappedf(probe.median(baselines), 0.001), min_ms = snappedf(sorted[0], 0.001),
				max_ms = snappedf(sorted[sorted.size() - 1], 0.001), drift_ms = snappedf(baselines[baselines.size() - 1] - baselines[0], 0.001),
				draw_calls = roundi(_rows[0].draw_calls), primitives = roundi(_rows[0].primitives)},
			noise_ms = snappedf(noise_ms, 0.001), significance = "synthetic timing only; real timing freshness unverified",
			gpu_timing_status = statuses.keys()[0] if statuses.size() == 1 else "mixed_or_unavailable",
			gpu_ms_scope = "root_only_freshness_unverified", warmup = warmup, frames = frames,
			rows = rows}
