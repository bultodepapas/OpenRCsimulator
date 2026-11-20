extends RefCounted
## VQ-01c / A33: keep a departing world's disk-backed meshes, materials and textures referenced while the next
## world builds. Godot's ResourceLoader cache only keeps resources somebody references, so freeing a flight before
## Home is rebuilt reloaded every imported model, texture and parked-aircraft mesh from disk. Holding the references
## (not the nodes) lets the next build reuse them; generated, path-less resources are not retained.
## Headless measurement (default field, 2026-11-18): field rebuild 1000 → 742 ms; collection 3.6 ms, 378 resources.


## Disk-backed resources drawn under `root`. Materials are followed into their textures and next passes.
static func collect(root: Node) -> Array[Resource]:
	var held: Array[Resource] = []
	if root == null or not is_instance_valid(root):
		return held
	var seen := {}
	var materials: Array[Material] = []
	var nodes: Array[Node] = [root]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		nodes.append_array(node.get_children(true))
		if not node is GeometryInstance3D:
			continue
		var geometry := node as GeometryInstance3D
		var mesh: Mesh = null
		if geometry is MeshInstance3D:
			var instance := geometry as MeshInstance3D
			mesh = instance.mesh
			for surface: int in instance.get_surface_override_material_count():
				_queue_material(materials, instance.get_surface_override_material(surface))
		elif geometry is MultiMeshInstance3D and (geometry as MultiMeshInstance3D).multimesh != null:
			mesh = (geometry as MultiMeshInstance3D).multimesh.mesh
		_queue_material(materials, geometry.material_override)
		_queue_material(materials, geometry.material_overlay)
		if mesh != null and _first_visit(seen, mesh):
			_keep(held, mesh)
			for surface: int in mesh.get_surface_count():
				_queue_material(materials, mesh.surface_get_material(surface))
	while not materials.is_empty():
		var material: Material = materials.pop_back()
		if not _first_visit(seen, material):
			continue
		_keep(held, material)
		_queue_material(materials, material.next_pass)
		if material is BaseMaterial3D:
			for channel: int in BaseMaterial3D.TEXTURE_MAX:
				_keep_texture(held, seen, (material as BaseMaterial3D).get_texture(channel))
		elif material is ShaderMaterial and (material as ShaderMaterial).shader != null:
			var shader_material := material as ShaderMaterial
			for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
				var value: Variant = shader_material.get_shader_parameter(uniform.name)
				if value is Texture:
					_keep_texture(held, seen, value as Texture)
	return held


static func _queue_material(materials: Array[Material], material: Material) -> void:
	if material != null:
		materials.append(material)


static func _first_visit(seen: Dictionary, resource: Resource) -> bool:
	var id := resource.get_instance_id()
	if seen.has(id):
		return false
	seen[id] = true
	return true


static func _keep_texture(held: Array[Resource], seen: Dictionary, texture: Texture) -> void:
	if texture != null and _first_visit(seen, texture):
		_keep(held, texture)


static func _keep(held: Array[Resource], resource: Resource) -> void:
	if not resource.resource_path.is_empty():
		held.append(resource)
