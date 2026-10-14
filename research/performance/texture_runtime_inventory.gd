# VQ-02a: read-only inventory of assigned resources, not draw-call residency.
extends RefCounted

var _seen: Dictionary = {} # Resource keys keep identities alive until the scan ends.
var _records: Array[Dictionary] = []
var _nodes := 0


func scan(scene: Node) -> Dictionary:
	_seen.clear()
	_records.clear()
	_nodes = 0
	_visit_node(scene, str(scene.name))
	var textures: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	for record: Dictionary in _records:
		if record.kind == "texture":
			textures.append(record)
		elif record.kind == "material":
			materials.append(record)
	var links: Array[Dictionary] = []
	for record: Dictionary in _records:
		links.append({id = record.id, resource_type = record.resource_type, path = record.path, consumers = record.consumers})
	var result := {nodes = _nodes, resources = _records.size(), resource_links = links,
		textures = textures, materials = materials}
	_seen.clear()
	return result


func _visit_node(node: Node, path: String) -> void:
	_nodes += 1
	_properties(node, path)
	for child: Node in node.get_children():
		_visit_node(child, path + "/" + str(child.name))


func _properties(object: Object, owner: String) -> void:
	for property: Dictionary in object.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or property.name == "script":
			continue
		# Do not read mesh buffers, pixel data or unrelated scalar state.
		if int(property.type) in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY]:
			_value(object.get(property.name), owner + ":" + str(property.name), 0)


func _value(value: Variant, consumer: String, depth: int) -> void:
	if value is Resource:
		_resource(value, consumer)
	elif depth < 8 and value is Array:
		for i: int in range(value.size()):
			_value(value[i], consumer + "[%d]" % i, depth + 1)
	elif depth < 8 and value is Dictionary:
		for key: Variant in value:
			_value(value[key], consumer + "[%s]" % str(key), depth + 1)


func _resource(resource: Resource, consumer: String) -> void:
	if resource is Script:
		return
	if _seen.has(resource):
		var existing: Dictionary = _records[_seen[resource]]
		if not consumer in existing.consumers:
			existing.consumers.append(consumer)
		return
	var index := _records.size()
	_seen[resource] = index
	var record := {id = "r%d" % index, kind = "resource", resource_type = resource.get_class(),
		path = resource.resource_path, consumers = [consumer]}
	_records.append(record)
	if resource is Texture:
		record.kind = "texture"
		_texture(resource, record)
		# Atlas and proxy sources remain independently visible; bytes are not summed.
		if resource is AtlasTexture:
			record.region = str(resource.region)
			if resource.atlas != null:
				_resource(resource.atlas, record.id + ":atlas")
		return
	if resource is Mesh:
		for surface: int in range(resource.get_surface_count()):
			var material: Material = resource.surface_get_material(surface)
			if material != null:
				_resource(material, record.id + ":surface[%d]" % surface)
		return
	if resource is Material:
		record.kind = "material"
		if resource is BaseMaterial3D:
			record.texture_filter = resource.texture_filter
			record.texture_repeat = resource.texture_repeat
			record.roughness_texture_channel = resource.roughness_texture_channel
			record.metallic_texture_channel = resource.metallic_texture_channel
			record.ao_texture_channel = resource.ao_texture_channel
		if resource is ShaderMaterial and resource.shader != null:
			record.shader_path = resource.shader.resource_path
			record.shader_code_sha256 = resource.shader.code.sha256_text()
			record.sampler_bindings = []
			# Shader.get_shader_uniform_list() hides uniforms with default textures.
			for uniform: Dictionary in RenderingServer.get_shader_parameter_list(resource.shader.get_rid()):
				if not int(uniform.type) in [TYPE_OBJECT, TYPE_RID] or not "Texture" in str(uniform.hint_string):
					continue
				var name: String = uniform.name
				var texture: Variant = resource.get_shader_parameter(name)
				var source := "material"
				if texture == null:
					texture = resource.shader.get_default_texture_parameter(name)
					source = "shader_default"
				var binding := {uniform = name, source = source, status = "unbound_or_engine_default"}
				if texture is Texture:
					_resource(texture, record.id + ":uniform/" + name)
					binding.status = "assigned"
					binding.texture_id = _records[_seen[texture]].id
				record.sampler_bindings.append(binding)
	_properties(resource, record.id)


func _texture(texture: Texture, record: Dictionary) -> void:
	record.image_status = "unsupported_texture_class"
	if not texture is Texture2D:
		return
	record.width = texture.get_width()
	record.height = texture.get_height()
	if texture is ViewportTexture:
		record.image_status = "viewport_readback_excluded"
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		record.image_status = "unavailable"
		return
	var data := image.get_data()
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(data)
	record.image_status = "read"
	record.image_width = image.get_width()
	record.image_height = image.get_height()
	record.image_format = image.get_format()
	record.image_compressed = image.is_compressed()
	record.has_mipmaps = image.has_mipmaps()
	record.mipmap_count = image.get_mipmap_count()
	record.cpu_image_bytes = data.size()
	record.image_sha256 = hash_context.finish().hex_encode()
