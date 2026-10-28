## Runtime access to offline-baked, stock-livery parked-aircraft meshes.
## Geometry and material work happens in tools/scenery/bake_parked_aircraft.gd;
## a placed aircraft is one static ArrayMesh with no model-builder nodes.
extends RefCounted

const FORMAT := "openrc-parked-aircraft v1"
const DIR := "res://assets/scenery/aircraft"

## Catalog aircraft ID -> stable generated asset basename.
const AIRCRAFT := {
	"jensen-das-ugly-stik-60": "stik",
	"gp-extra-300s-60": "extra",
	"p51d-mustang-120": "p51",
	"sebart-avanti-s-a200-p100rx": "avanti",
	"turbo-lumber-evolution": "timber",
}


## SC-09-R2: equipment detail that the High scenery tier draws with its own authored materials. Below High, the
## surfaces whose material name starts with the prefix merge into one vertex-coloured surface (one draw per batch).
## The Ugly Stik's O.S. 61 engine GLB (US-V13) names all 12 of its materials M_*; the baked snapshot keeps those names.
const DETAIL_MATERIAL_PREFIX := {"stik": "M_"}
## Scenery tiers that keep every authored detail material (Scenery.QUALITIES; Scene detail High and Extreme).
const FULL_DETAIL_QUALITIES: Array[String] = ["high"]
# Albedo mip sampled per merged vertex; the engine is about 6 cm across, so 128 px exceeds its on-screen size.
const ALBEDO_MIP_PX := 128

static var _merged_cache: Dictionary = {}


## Shared generated mesh. ResourceLoader caches the immutable resource across placements. Below the High scenery
## tier, aircraft listed in DETAIL_MATERIAL_PREFIX return a derived mesh with their detail surfaces merged (cached).
static func mesh(aircraft: String, configuration: String = "assembled", quality: String = "high") -> ArrayMesh:
	var path := _path(aircraft, configuration, ".res")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var prefix := str(DETAIL_MATERIAL_PREFIX.get(str(AIRCRAFT.get(aircraft, "")), ""))
	var merge := not prefix.is_empty() and quality not in FULL_DETAIL_QUALITIES
	if merge and _merged_cache.has(path):
		return _merged_cache[path]
	var resource: Resource = load(path)
	if not (resource is ArrayMesh):
		push_error("parked aircraft: %s is not an ArrayMesh resource" % path)
		return null
	if not merge:
		return resource as ArrayMesh
	_merged_cache[path] = merge_detail(resource as ArrayMesh, prefix)
	return _merged_cache[path]


## Indices of the surfaces whose material name starts with prefix.
static func detail_surfaces(source: ArrayMesh, prefix: String) -> Array[int]:
	var result: Array[int] = []
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface)
		if material != null and material.resource_name.begins_with(prefix):
			result.append(surface)
	return result


## A copy of source whose detail surfaces become one opaque surface. Each vertex keeps its material's linear albedo
## (a small mip of the albedo texture sampled at its UV, times the albedo colour); metallic and roughness are
## vertex-weighted means. Normal maps are dropped. Other surfaces, their materials and LODs are untouched.
## Returns source if fewer than two surfaces match.
static func merge_detail(source: ArrayMesh, prefix: String) -> ArrayMesh:
	var merged_surfaces := detail_surfaces(source, prefix)
	if merged_surfaces.size() < 2:
		return source
	var colored := ArrayMesh.new()
	var weight := 0.0
	var metallic_sum := 0.0
	var roughness_sum := 0.0
	var cull := BaseMaterial3D.CULL_BACK
	for surface: int in merged_surfaces:
		var arrays := source.surface_get_arrays(surface)
		var material := source.surface_get_material(surface) as BaseMaterial3D
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := Color.WHITE
		var metallic := 0.0
		var roughness := 1.0
		var albedo: Image = null
		if material != null:
			base = material.albedo_color.srgb_to_linear()
			metallic = material.metallic * _mean_channel(material.metallic_texture, material.metallic_texture_channel)
			roughness = material.roughness * _mean_channel(material.roughness_texture, material.roughness_texture_channel)
			albedo = _small_mip(material.albedo_texture, ALBEDO_MIP_PX)
			if material.cull_mode == BaseMaterial3D.CULL_DISABLED:
				cull = BaseMaterial3D.CULL_DISABLED
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		colors.fill(Color(base.r, base.g, base.b, 1.0))
		if albedo != null and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var width := albedo.get_width()
			var height := albedo.get_height()
			for vertex in vertices.size():
				var texel := albedo.get_pixel(posmod(int(uvs[vertex].x * width), width),
					posmod(int(uvs[vertex].y * height), height)).srgb_to_linear()
				colors[vertex] = Color(base.r * texel.r, base.g * texel.g, base.b * texel.b, 1.0)
		var plain := []
		plain.resize(Mesh.ARRAY_MAX)
		plain[Mesh.ARRAY_VERTEX] = vertices
		plain[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		plain[Mesh.ARRAY_COLOR] = colors
		plain[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plain)
		weight += vertices.size()
		metallic_sum += metallic * vertices.size()
		roughness_sum += roughness * vertices.size()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in colored.get_surface_count():
		tool.append_from(colored, surface, Transform3D.IDENTITY)
	var result := source.duplicate() as ArrayMesh
	for i in range(merged_surfaces.size() - 1, -1, -1):
		result.surface_remove(merged_surfaces[i])
	tool.commit(result)
	var merged := StandardMaterial3D.new()
	merged.resource_name = "%smerged_detail" % prefix
	merged.vertex_color_use_as_albedo = true
	merged.metallic = metallic_sum / maxf(weight, 1.0)
	merged.roughness = roughness_sum / maxf(weight, 1.0)
	merged.cull_mode = cull
	result.surface_set_material(result.get_surface_count() - 1, merged)
	return result


## The first mip level no larger than max_px, decompressed alone (decompressing the whole chain costs about 3 ms per
## 1024 px texture). Null when the texture has no CPU-side image.
static func _small_mip(texture: Texture2D, max_px: int) -> Image:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	var level := 0
	while image.has_mipmaps() and level < image.get_mipmap_count() \
			and maxi(image.get_width() >> level, image.get_height() >> level) > max_px:
		level += 1
	if level > 0:
		var start := image.get_mipmap_offset(level)
		var stop := image.get_mipmap_offset(level + 1) if level < image.get_mipmap_count() else image.get_data_size()
		image = Image.create_from_data(maxi(image.get_width() >> level, 1), maxi(image.get_height() >> level, 1), false,
			image.get_format(), image.get_data().slice(start, stop))
	if image.is_compressed() and image.decompress() != OK:
		return null
	return image


## Mean of one channel over an 8 px mip; 1.0 (the scalar alone) without a texture.
static func _mean_channel(texture: Texture2D, channel: BaseMaterial3D.TextureChannel) -> float:
	var image := _small_mip(texture, 8)
	if image == null:
		return 1.0
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			match channel:
				BaseMaterial3D.TEXTURE_CHANNEL_GREEN: total += color.g
				BaseMaterial3D.TEXTURE_CHANNEL_BLUE: total += color.b
				BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: total += color.a
				BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: total += color.get_luminance()
				_: total += color.r
	return total / float(image.get_width() * image.get_height())


## Authored dimensions and broad collision proxies for a normalized snapshot.
static func info(aircraft: String, configuration: String = "assembled") -> Dictionary:
	var path := _path(aircraft, configuration, ".json")
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or str(parsed.get("format", "")) != FORMAT:
		return {}
	return (parsed as Dictionary).duplicate(true)


## Placement coordinates remain NED (north/east); mesh forward is local -Z and bottom is local y = 0.
static func transform_for(placement: Dictionary) -> Transform3D:
	var north := _number(placement.get("north", 0.0), 0.0)
	var east := _number(placement.get("east", 0.0), 0.0)
	var heading_deg := _number(placement.get("heading", 0.0), 0.0)
	var scale := _number(placement.get("scale", 1.0), 1.0)
	var elevation := _number(placement.get("elevation", 0.0), 0.0)
	if scale < 0.25 or scale > 1.5:
		scale = 1.0
	var basis := Basis(Vector3.UP, -deg_to_rad(heading_deg)).scaled(Vector3.ONE * scale)
	var origin := Vector3(east, elevation, -north)
	return Transform3D(basis, origin)


static func _path(aircraft: String, configuration: String, extension: String) -> String:
	if not AIRCRAFT.has(aircraft) or configuration not in ["assembled", "service"]:
		return ""
	var basename: String = str(AIRCRAFT[aircraft])
	if configuration == "service" and basename != "stik":
		return ""
	return "%s/%s_%s%s" % [DIR, basename, configuration, extension]


static func _number(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return float(value)
