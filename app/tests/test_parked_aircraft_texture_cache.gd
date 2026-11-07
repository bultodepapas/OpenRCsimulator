## Cold parked-Stik merge: shared texture reads, failure ordering and stock material parity.
extends SceneTree

const ParkedAircraft := preload("res://scenery/parked_aircraft.gd")

var _checks := 0
var _failures := 0


class CountingTexture extends Texture2D:
	var images: Array = []
	var reads := 0

	func _get_width() -> int:
		return 64

	func _get_height() -> int:
		return 32

	func _get_image() -> Image:
		var next: Variant = images[mini(reads, images.size() - 1)] if not images.is_empty() else null
		reads += 1
		return next as Image


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	_test_reads()
	_test_stock("assembled")
	_test_stock("service")
	print("parked texture reuse: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_reads() -> void:
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8, 0.6))
	var pixel := image.get_pixel(0, 0)
	var texture := CountingTexture.new()
	texture.images = [image]
	var pair: Array[float] = ParkedAircraft._shared_channel_means(texture,
		BaseMaterial3D.TEXTURE_CHANNEL_RED, BaseMaterial3D.TEXTURE_CHANNEL_BLUE)
	_check("one successful shared read preserves both channels on non-mipmapped input",
		texture.reads == 1 and is_equal_approx(pair[0], pixel.r) and is_equal_approx(pair[1], pixel.b))
	_check("a non-mipmapped texture keeps its full source dimensions",
		ParkedAircraft._small_mip(texture, 8).get_size() == Vector2i(64, 32))
	texture = CountingTexture.new()
	texture.images = [null, image]
	pair = ParkedAircraft._shared_channel_means(texture,
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN, BaseMaterial3D.TEXTURE_CHANNEL_ALPHA)
	_check("failed first read falls back for metallic and still reads roughness once",
		texture.reads == 2 and pair[0] == 1.0 and is_equal_approx(pair[1], pixel.a))
	texture = CountingTexture.new()
	texture.images = [image]
	pair = ParkedAircraft._shared_channel_means(texture,
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE, BaseMaterial3D.TEXTURE_CHANNEL_GREEN)
	_check("grayscale and independent color channels keep their original meanings",
		texture.reads == 1 and is_equal_approx(pair[0], pixel.get_luminance()) and is_equal_approx(pair[1], pixel.g))
	var image_ref: WeakRef = weakref(image)
	texture.images.clear()
	image = null
	_check("the returned pair does not retain its source image", image_ref.get_ref() == null)


func _test_stock(configuration: String) -> void:
	var path := "res://assets/scenery/aircraft/stik_%s.res" % configuration
	var source := load(path) as ArrayMesh
	_check(configuration + " source mesh loads", source != null)
	if source == null:
		return
	var surfaces := ParkedAircraft.detail_surfaces(source, "M_")
	var aliases := 0
	var readable_aliases := 0
	var exact := true
	var weight := 0.0
	var expected_metallic := 0.0
	var expected_roughness := 0.0
	for surface: int in surfaces:
		var material := source.surface_get_material(surface) as BaseMaterial3D
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count := float(vertices.size())
		var metallic := 0.0
		var roughness := 1.0
		if material != null:
			var metallic_mean: float = ParkedAircraft._mean_channel(material.metallic_texture, material.metallic_texture_channel)
			var roughness_mean: float = ParkedAircraft._mean_channel(material.roughness_texture, material.roughness_texture_channel)
			metallic = material.metallic * metallic_mean
			roughness = material.roughness * roughness_mean
			if material.metallic_texture != null and material.metallic_texture == material.roughness_texture \
					and material.metallic_texture is PortableCompressedTexture2D:
				aliases += 1
				var stock_image: Image = ParkedAircraft._small_mip(material.metallic_texture, 8)
				if stock_image != null and not stock_image.is_empty():
					readable_aliases += 1
				var pair: Array[float] = ParkedAircraft._shared_channel_means(material.metallic_texture,
					material.metallic_texture_channel, material.roughness_texture_channel)
				if stock_image != null and not stock_image.is_empty():
					exact = exact and pair[0] == metallic_mean and pair[1] == roughness_mean
		weight += count
		expected_metallic += metallic * count
		expected_roughness += roughness * count
	_check(configuration + " actual shared ORM channels match independent reads exactly", readable_aliases == aliases and aliases > 0 and exact)
	var merged := ParkedAircraft.merge_detail(source, "M_")
	var finish := merged.surface_get_material(merged.get_surface_count() - 1) as StandardMaterial3D
	var expected_finish := StandardMaterial3D.new()
	expected_finish.metallic = expected_metallic / maxf(weight, 1.0)
	expected_finish.roughness = expected_roughness / maxf(weight, 1.0)
	_check(configuration + " merged material preserves weighted metallic and roughness",
		finish != null and finish.metallic == expected_finish.metallic
		and finish.roughness == expected_finish.roughness)
	_check(configuration + " merge retains surface count and bounds",
		merged.get_surface_count() == source.get_surface_count() - surfaces.size() + 1
		and merged.get_aabb().is_equal_approx(source.get_aabb()))
	print("%s: %d shared ORM materials, %d with readable pixels" % [configuration, aliases, readable_aliases])
