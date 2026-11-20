extends RefCounted
## Bounded render-member coordinate frames and explicitly declared v6 visual hinges.
## No physical data, channel/role assignment, propeller-axis assumption or metadata execution.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Params := preload("params.gd")
const FORMAT := "openrc-clearview-frames-v1"
const ORTHOGONAL_TOLERANCE := 0.001
const LENGTH_SEPARATION := 1.1
const MAX_HELPER_VERTICES := 8
const IDENTITY := [1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,1.0,0.0]

static func inspect(scene: Dictionary, params: Dictionary, cancel := Callable()) -> Dictionary:
	var frames: Array = []
	var marked := {}
	var world: Array = []
	var render_world: Array = []
	var ambiguous: Array = []
	for index: int in scene.nodes.size():
		if cancel.is_valid() and bool(cancel.call()):
			return R.fail(R.SOURCE_INVALID,"The import was cancelled.","source","import")
		var node: Dictionary = scene.nodes[index]
		world.append(compose(world[node.parent], local(node)) if node.parent >= 0 else local(node))
		render_world.append(render_compose(render_world[node.parent],local(node)) if node.parent >= 0 else _rounded(local(node)))
		if not str(node.name).ends_with(".XYZObject"):
			continue
		var frame := _frame(node)
		var group := str(node.name).trim_suffix(".XYZObject")
		if group.is_empty() or group.begins_with(".") or group.ends_with(".") or ".." in group:
			frame = {}
		if frame.is_empty():
			# An ambiguous helper frame cannot prepare a hinge, but it is not model geometry either:
			# hide a helper-sized marker, keep the model, and name the part that stays static.
			ambiguous.append(str(node.name))
			if node.vertices.size() <= MAX_HELPER_VERTICES:
				marked[index] = true
			continue
		frame.node = index
		frame.name = node.name
		frame.group = str(node.name).trim_suffix(".XYZObject")
		frame.world_origin = point(world[index],frame.origin)
		frame.world_axes = []
		for axis: Array in frame.axes:
			frame.world_axes.append(direction(world[index],axis))
		frame.original = {parent = node.parent,loc = node.loc,rot = node.rot,vertices = node.vertices,
			surfaces = node.surfaces,texture = node.texture,texrep = node.texrep,texoff = node.texoff}
		frames.append(frame)
		marked[index] = true
	return R.ok({frames = frames,marked = marked,world = world,render_world = render_world,requests = _requests(params),ambiguous = ambiguous})

## Called only on the converter's trusted parsed IR. Never reads a saved GLB receipt as authority.
static func prepare(gltf: Dictionary, scene: Dictionary, inspected: Dictionary, cancel := Callable()) -> Dictionary:
	var plans: Array = []
	var unresolved: Array = []
	for marker: String in inspected.get("ambiguous",[]):
		unresolved.append({group = marker.trim_suffix(".XYZObject") if not marker.trim_suffix(".XYZObject").is_empty() else marker,reason = "ambiguous_coordinate_marker",servos = []})
	var attempted := 0
	for group: String in inspected.requests:
		if cancel.is_valid() and bool(cancel.call()):
			return R.fail(R.SOURCE_INVALID,"The import was cancelled.","source","import")
		var request: Dictionary = inspected.requests[group]
		var matches: Array = []
		for frame: Dictionary in inspected.frames:
			if frame.group == group:
				matches.append(frame)
		var reason := str(request.reason)
		if reason.is_empty() and matches.size() != 1:
			reason = "missing_or_duplicate_render_frame"
		if not reason.is_empty():
			unresolved.append({group = group,reason = reason,servos = request.servos})
			continue
		attempted += 1
		if attempted > 32:
			unresolved.append({group = group,reason = "hinge_limit",servos = request.servos})
			continue
		var roots: Array = []
		var peers := {}
		for index: int in scene.nodes.size():
			if not inspected.marked.has(index) and str(scene.nodes[index].name).begins_with(group + "."):
				peers[index] = true
		for index: int in peers:
			var ancestor: int = scene.nodes[index].parent
			while ancestor >= 0 and not peers.has(ancestor):
				ancestor = scene.nodes[ancestor].parent
			if ancestor < 0:
				roots.append(index)
		if reason.is_empty() and roots.is_empty():
			reason = "missing_render_group"
		var parent := -1 if roots.is_empty() else int(scene.nodes[roots[0]].parent)
		for root: int in roots:
			if scene.nodes[root].parent != parent:
				reason = "multiple_render_parents"
		var moving_meshes := 0
		var total_meshes := 0
		for index: int in gltf.nodes.size():
			if not gltf.nodes[index].has("mesh"):
				continue
			total_meshes += 1
			if _below(scene,index,roots):
				moving_meshes += 1
				var name: String = scene.nodes[index].name
				if not name.begins_with(group + "."):
					reason = "foreign_render_descendant"
				for other: Dictionary in inspected.frames:
					if other.group != group and (name == other.group or name.begins_with(str(other.group) + ".")):
						reason = "nested_coordinate_group"
		if reason.is_empty() and (moving_meshes == 0 or moving_meshes == total_meshes):
			reason = "empty_or_whole_model_group"
		var parent_world: Array = IDENTITY if parent < 0 else inspected.world[parent]
		if reason.is_empty() and (not _rigid(parent_world) or not _rigid(inspected.world[matches[0].node])):
			reason = "non_rigid_coordinate_frame"
		if not reason.is_empty():
			unresolved.append({group = group,reason = reason,servos = request.servos})
			continue
		if plans.size() >= 32:
			unresolved.append({group = group,reason = "hinge_limit",servos = request.servos})
			continue
		plans.append({group = group,axis = request.axis,servos = request.servos,frame = matches[0],roots = roots,parent = parent,parent_world = parent_world})
	# Resolve overlap before mutating any graph. Independent controls cannot own shared/nested parts.
	var overlapping := {}
	for a: int in plans.size():
		for b: int in range(a + 1,plans.size()):
			for root: int in plans[a].roots:
				if _below(scene,root,plans[b].roots):
					overlapping[a] = true
					overlapping[b] = true
			for root: int in plans[b].roots:
				if _below(scene,root,plans[a].roots):
					overlapping[a] = true
					overlapping[b] = true
	var prepared: Array = []
	for index: int in plans.size():
		if cancel.is_valid() and bool(cancel.call()):
			return R.fail(R.SOURCE_INVALID,"The import was cancelled.","source","import")
		var plan: Dictionary = plans[index]
		var reason := "overlapping_render_groups" if overlapping.has(index) else ""
		if gltf.nodes.size() >= Limits.GLB_NODES:
			reason = "node_limit"
		var chain_depth := 1
		var ancestor: int = plan.parent
		while ancestor >= 0:
			chain_depth += 1
			ancestor = scene.nodes[ancestor].parent
		for node: int in scene.nodes.size():
			if _below(scene,node,plan.roots):
				var depth := chain_depth + 1
				ancestor = node
				while ancestor not in plan.roots:
					depth += 1
					ancestor = scene.nodes[ancestor].parent
				if depth > Limits.GLB_DEPTH:
					reason = "depth_limit"
		if not reason.is_empty():
			unresolved.append({group = plan.group,reason = reason,servos = plan.servos})
			continue
		var axis: Array = _unit(plan.frame.world_axes[["x","y","z"].find(plan.axis)])
		var helper := [0.0,1.0,0.0] if absf(axis[1]) < 0.9 else [1.0,0.0,0.0]
		var y := _unit(_cross(helper,axis))
		var z := _cross(axis,y)
		var origin: Array = plan.frame.world_origin
		var hinge := [axis[0],y[0],z[0],origin[0],axis[1],y[1],z[1],origin[1],axis[2],y[2],z[2],origin[2]]
		var transform := compose(inverse(plan.parent_world),hinge)
		var undo := inverse(transform)
		var children: Array = []
		var locals: Array = []
		for root: int in plan.roots:
			var adjusted := compose(undo,local(scene.nodes[root]))
			if not _same(compose(hinge,adjusted),inspected.world[root]):
				reason = "neutral_transform_mismatch"
			locals.append(adjusted)
			children.append(root)
		if reason.is_empty() and not _render_neutral(scene,gltf,inspected,plan,transform,locals):
			reason = "render_precision"
		if not reason.is_empty():
			unresolved.append({group = plan.group,reason = reason,servos = plan.servos})
			continue
		var pivot: int = gltf.nodes.size()
		var siblings: Array = gltf.scenes[0].nodes if plan.parent < 0 else gltf.nodes[plan.parent].children
		var replaced: Array = []
		var inserted := false
		for sibling: int in siblings:
			if sibling in plan.roots:
				if not inserted:
					replaced.append(pivot)
					inserted = true
			else:
				replaced.append(sibling)
		if plan.parent < 0:
			gltf.scenes[0].nodes = replaced
		else:
			gltf.nodes[plan.parent].children = replaced
		for slot: int in children.size():
			gltf.nodes[children[slot]].matrix = matrix(locals[slot])
		gltf.nodes.append({name = plan.group + " [ClearView " + str(plan.axis).to_upper() + " pivot]",matrix = matrix(transform),children = children,
			extras = {openrc_creator_part = {format = "openrc-creator-part-hint-v1",axis = "x"}}})
		prepared.append({group = plan.group,node = pivot,axis = "x",source_axis = plan.axis,marker_node = plan.frame.node,children = children,servos = plan.servos})
	return R.ok({format = FORMAT,float_encoding = "ieee754-binary64-le-hex",orthogonal_tolerance = exact(ORTHOGONAL_TOLERANCE),
		length_separation = exact(LENGTH_SEPARATION),frames = exact(inspected.frames),prepared = prepared,unresolved = unresolved})

static func _frame(node: Dictionary) -> Dictionary:
	if node.type != "poly" or not node.children.is_empty() or node.get("has_data",false) or node.vertices.size() != 4 or node.surfaces.size() != 2:
		return {}
	var counts := [0,0,0,0]
	for face: Dictionary in node.surfaces:
		if face.flags != 0x30 or face.refs.size() != 3:
			return {}
		var unique := {}
		for ref: Dictionary in face.refs:
			unique[ref.vertex] = true
			counts[ref.vertex] += 1
		if unique.size() != 3:
			return {}
	var shared: Array = []
	for index: int in 4:
		if counts[index] == 2:
			shared.append(index)
	if shared.size() != 2 or counts.count(1) != 2:
		return {}
	var candidates: Array = []
	for origin: int in shared:
		var ends: Array = []
		for index: int in 4:
			if index != origin:
				var delta := _sub(node.vertices[index],node.vertices[origin])
				var length := sqrt(_dot(delta,delta))
				if not (length > 0.0) or not is_finite(length):
					return {}
				ends.append({vertex = index,length = length,axis = _unit(delta)})
		ends.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.length < b.length)
		if ends[1].vertex not in shared or ends[1].length < ends[0].length * LENGTH_SEPARATION or ends[2].length < ends[1].length * LENGTH_SEPARATION:
			continue
		var x: Array = ends[1].axis
		var y: Array = ends[0].axis
		var z: Array = ends[2].axis
		if maxf(absf(_dot(x,y)),maxf(absf(_dot(y,z)),absf(_dot(z,x)))) > ORTHOGONAL_TOLERANCE or _dot(_cross(x,y),z) <= 0.0:
			continue
		candidates.append({origin = node.vertices[origin],axes = [x,y,z],lengths = [ends[1].length,ends[0].length,ends[2].length],origin_vertex = origin})
	return candidates[0] if candidates.size() == 1 else {}

static func _requests(params: Dictionary) -> Dictionary:
	if params.version != 6:
		return {}
	var sections := {}
	var movements := {}
	for record: Dictionary in params.records:
		if not sections.has(record.section):
			sections[record.section] = {}
		var value := Params._without_comment(record.raw_rhs)
		var fields: Dictionary = sections[record.section]
		fields[record.key] = value if not fields.has(record.key) or fields[record.key] == value else ""
		if record.key == "controlledPartMovement":
			if not movements.has(record.section):
				movements[record.section] = []
			if value not in movements[record.section]:
				movements[record.section].append(value)
	var requests := {}
	var roster: String = sections.get("params",{}).get("modelServos","")
	var active: Array = []
	var roster_ok := not roster.is_empty()
	for id: String in roster.replace("\t"," ").split(" ",false):
		if not Params._identifier(id) or id in active:
			roster_ok = false
		active.append(id)
	if roster_ok:
		for id: String in active:
			if not sections.has("servo."+id):
				requests["[servo."+id+"]"] = {axis = "",reason = "missing_listed_servo",servos = ["servo."+id]}
	for section: String in sections:
		if not section.begins_with("servo."):
			continue
		var servo: Dictionary = sections[section]
		var declared: Array = movements.get(section,[])
		# Input-only throttle and explicitly absent targets are not missing visual hinges.
		# Every servo with a real target is either prepared or named as unresolved below.
		if servo.get("controlledPartType","") == "none" and servo.get("controlledPartName","") == "none" and declared.size() <= 1:
			continue
		if declared.is_empty() and not servo.has("controlledPartType") and not servo.has("controlledPartName"):
			continue
		var target := str(servo.get("controlledPartType","")) + "." + str(servo.get("controlledPartName",""))
		var group := str(sections.get(target,{}).get("renderGroupName",""))
		var axis := str(servo.get("controlledAxisName",""))
		var reason := "" if not group.is_empty() and axis in ["x","y","z"] else "missing_or_conflicting_servo_mapping"
		if servo.get("controlledPartMovement","") != "rotate":
			# A single declared non-rotation (move/input) keeps its part static and is named.
			reason = "unsupported_servo_movement" if declared.size() == 1 and declared[0] != "rotate" \
				else "unsupported_or_conflicting_servo_movement"
		if servo.get("controlledPartType","") != "liftsurface":
			reason = "unsupported_servo_target_type"
		if not roster_ok or section.trim_prefix("servo.") not in active:
			reason = "missing_or_conflicting_model_servos" if not roster_ok else "unlisted_servo_section"
			group = "[" + section + "]" # An unused section cannot conflict with an active group's declaration.
		if group.is_empty():
			group = "[" + section + "]"
		if requests.has(group):
			reason = "multiple_servos_for_render_group"
			requests[group].servos.append(section)
			if not reason.is_empty():
				requests[group].reason = reason
		else:
			requests[group] = {axis = axis,reason = reason,servos = [section]}
	return requests

static func _below(scene: Dictionary, node: int, roots: Array) -> bool:
	while node >= 0:
		if node in roots:
			return true
		node = scene.nodes[node].parent
	return false

## A mathematically exact reparenting can still erase a small translation after float32 upload.
## Compare the actual render precision of transformed bounds before committing the wrapper.
static func _render_neutral(scene: Dictionary,gltf: Dictionary,inspected: Dictionary,plan: Dictionary,hinge: Array,locals: Array) -> bool:
	var parent_render: Array = IDENTITY if plan.parent < 0 else inspected.render_world[plan.parent]
	var pivot := render_compose(parent_render,hinge)
	var candidate: Array = inspected.render_world.duplicate()
	for index: int in scene.nodes.size():
		if not _below(scene,index,plan.roots):
			continue
		var slot: int = plan.roots.find(index)
		candidate[index] = render_compose(pivot,locals[slot]) if slot >= 0 else render_compose(candidate[scene.nodes[index].parent],local(scene.nodes[index]))
		if not gltf.nodes[index].has("mesh"):
			continue
		var low := [INF,INF,INF]
		var high := [-INF,-INF,-INF]
		for vertex: Array in scene.nodes[index].vertices:
			for axis: int in 3:
				low[axis] = minf(low[axis],vertex[axis])
				high[axis] = maxf(high[axis],vertex[axis])
		var before: Array = []
		var after: Array = []
		var world_low := [INF,INF,INF]
		var world_high := [-INF,-INF,-INF]
		for corner: int in 8:
			var v := [high[0] if corner & 1 else low[0],high[1] if corner & 2 else low[1],high[2] if corner & 4 else low[2]]
			before.append(_render_point(inspected.render_world[index],v))
			after.append(_render_point(candidate[index],v))
			var original := point(inspected.world[index],v)
			for axis: int in 3:
				world_low[axis] = minf(world_low[axis],original[axis])
				world_high[axis] = maxf(world_high[axis],original[axis])
		var extent := maxf(world_high[0]-world_low[0],maxf(world_high[1]-world_low[1],world_high[2]-world_low[2]))
		for corner: int in 8:
			for axis: int in 3:
				if not is_finite(after[corner][axis]) or absf(before[corner][axis]-after[corner][axis]) > 0.00001*maxf(extent,0.000001):
					return false
	return true

static func _render_point(m: Array,v: Array) -> Array:
	var out: Array = []
	for row: int in 3:
		out.append(_f32(_f32(_f32(_f32(m[row*4]*_f32(v[0]))+_f32(m[row*4+1]*_f32(v[1])))+_f32(m[row*4+2]*_f32(v[2])))+m[row*4+3]))
	return out

static func render_compose(a: Array,b: Array) -> Array:
	var left := _rounded(a)
	var right := _rounded(b)
	var out: Array = IDENTITY.duplicate()
	for row: int in 3:
		for col: int in 4:
			var sum := 0.0
			for k: int in 3:
				sum = _f32(sum+_f32(left[row*4+k]*right[k*4+col]))
			out[row*4+col] = _f32(sum+left[row*4+3]) if col == 3 else sum
	return out

static func _rounded(m: Array) -> Array:
	var out: Array = []
	for value: float in m:
		out.append(_f32(value))
	return out

static func _f32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0,value)
	return bytes.decode_float(0)

static func local(node: Dictionary) -> Array:
	var r: Array = node.rot
	return [r[0],r[1],r[2],node.loc[0],r[3],r[4],r[5],node.loc[1],r[6],r[7],r[8],node.loc[2]]

static func matrix(m: Array) -> Array:
	return [m[0],m[4],m[8],0.0,m[1],m[5],m[9],0.0,m[2],m[6],m[10],0.0,m[3],m[7],m[11],1.0]

static func compose(a: Array,b: Array) -> Array:
	var out: Array = IDENTITY.duplicate()
	for row: int in 3:
		for col: int in 4:
			out[row*4+col] = (a[row*4+3] if col == 3 else 0.0)
			for k: int in 3:
				out[row*4+col] += a[row*4+k]*b[k*4+col]
	return out

## General affine inverse: even a rounded AC3D rotation is not exactly orthogonal.
static func inverse(m: Array) -> Array:
	var a := _cross([m[4],m[5],m[6]],[m[8],m[9],m[10]])
	var b := _cross([m[8],m[9],m[10]],[m[0],m[1],m[2]])
	var c := _cross([m[0],m[1],m[2]],[m[4],m[5],m[6]])
	var det := _dot([m[0],m[1],m[2]],a)
	var out: Array = IDENTITY.duplicate()
	for row: int in 3:
		for col: int in 3:
			out[row*4+col] = [a,b,c][col][row]/det
		out[row*4+3] = -out[row*4]*m[3]-out[row*4+1]*m[7]-out[row*4+2]*m[11]
	return out

static func direction(m: Array,v: Array) -> Array:
	return [m[0]*v[0]+m[1]*v[1]+m[2]*v[2],m[4]*v[0]+m[5]*v[1]+m[6]*v[2],m[8]*v[0]+m[9]*v[1]+m[10]*v[2]]

static func point(m: Array,v: Array) -> Array:
	var out := direction(m,v)
	return [out[0]+m[3],out[1]+m[7],out[2]+m[11]]

static func _rigid(m: Array) -> bool:
	var axes := [[m[0],m[4],m[8]],[m[1],m[5],m[9]],[m[2],m[6],m[10]]]
	for a: int in 3:
		for b: int in 3:
			if absf(_dot(axes[a],axes[b])-(1.0 if a == b else 0.0)) > 0.00001:
				return false
	return _dot(_cross(axes[0],axes[1]),axes[2]) > 0.0

static func _same(a: Array,b: Array) -> bool:
	for index: int in 12:
		if absf(a[index]-b[index]) > 1.0e-9*maxf(1.0,maxf(absf(a[index]),absf(b[index]))):
			return false
	return true

static func _sub(a: Array,b: Array) -> Array:
	return [a[0]-b[0],a[1]-b[1],a[2]-b[2]]

static func _dot(a: Array,b: Array) -> float:
	return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]

static func _cross(a: Array,b: Array) -> Array:
	return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]

static func _unit(a: Array) -> Array:
	var length := sqrt(_dot(a,a))
	return [a[0]/length,a[1]/length,a[2]/length]

## Exact, versioned provenance only; never deserialize it to grant capabilities or execute rigging.
static func exact(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0,value)
		return {f64le = bytes.hex_encode()}
	if value is Array:
		var out: Array = []
		for entry: Variant in value:
			out.append(exact(entry))
		return out
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = exact(value[key])
		return out
	return value
