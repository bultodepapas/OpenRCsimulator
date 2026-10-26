extends SceneTree

const ViewportColor := preload("res://render/viewport_color.gd")

var _failures := 0


func _initialize() -> void:
	_test_hdr_display_encoding()
	_test_hdr_half_float_multrow()
	_test_fast_paths()
	_test_actual_renderer_configuration()
	print("all viewport color checks passed" if _failures == 0 else "%d viewport color checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_hdr_display_encoding() -> void:
	var source := Image.create(4, 1, false, Image.FORMAT_RGBAF)
	var faint := Color(0.001, 0.001, 0.001, 0.25)
	var black := Color(0.0, 0.0, 0.0, 1.0)
	var white := Color(1.0, 1.0, 1.0, 0.5)
	var mixed := Color(0.25, 0.5, 0.75, 0.0)
	source.set_pixel(0, 0, faint)
	source.set_pixel(1, 0, black)
	source.set_pixel(2, 0, white)
	source.set_pixel(3, 0, mixed)
	var source_before: PackedByteArray = source.get_data().duplicate()

	var display: Image = ViewportColor.display_image(source, true)
	_check("HDR readback becomes RGBA8", display != null and display.get_format() == Image.FORMAT_RGBA8)
	if display == null or display.is_empty():
		return
	var encoded_faint := faint.linear_to_srgb()
	var expected_faint := roundf(encoded_faint.r * 255.0) / 255.0
	var encoded_pixel := display.get_pixel(0, 0)
	_check("faint linear 0.001 is sRGB-encoded before 8-bit quantization",
		encoded_pixel.r > 0.0 and is_equal_approx(encoded_pixel.r, expected_faint),
		"red=%0.8f expected=%0.8f" % [encoded_pixel.r, expected_faint])
	_check("black remains black and alpha is preserved",
		display.get_pixel(1, 0).is_equal_approx(black))
	var encoded_white := display.get_pixel(2, 0)
	_check("white stays white and alpha quantizes without gamma encoding",
		is_equal_approx(encoded_white.r, 1.0) and is_equal_approx(encoded_white.g, 1.0)
		and is_equal_approx(encoded_white.b, 1.0)
		and absf(encoded_white.a - white.a) <= 1.0 / 255.0)
	var encoded_mixed := display.get_pixel(3, 0)
	_check("mixed channels are each encoded while zero alpha stays zero",
		encoded_mixed.r > 0.0 and encoded_mixed.g > encoded_mixed.r
		and encoded_mixed.b > encoded_mixed.g and encoded_mixed.a == 0.0)
	_check("HDR conversion leaves its source image unchanged", source.get_data() == source_before
		and source.get_pixel(0, 0).is_equal_approx(faint))


func _test_hdr_half_float_multrow() -> void:
	var source := Image.create(2, 2, false, Image.FORMAT_RGBAH)
	source.set_pixel(0, 0, Color(0.001, 0.01, 0.1, 0.125))
	source.set_pixel(1, 0, Color(0.03, 0.2, 0.5, 0.375))
	source.set_pixel(0, 1, Color(0.5, 0.75, 0.9, 0.625))
	source.set_pixel(1, 1, Color(0.0, 0.003, 0.25, 0.875))
	var source_before: PackedByteArray = source.get_data().duplicate()

	var display: Image = ViewportColor.display_image(source, true)
	_check("RGBAH readback keeps its 2x2 extent in RGBA8",
		display != null and display.get_format() == Image.FORMAT_RGBA8
		and display.get_width() == 2 and display.get_height() == 2)
	if display == null or display.is_empty():
		return
	for y in 2:
		for x in 2:
			var linear := source.get_pixel(x, y)
			var actual := display.get_pixel(x, y)
			var expected := Color(
				_quantize_unorm8(_standard_linear_to_srgb(linear.r)),
				_quantize_unorm8(_standard_linear_to_srgb(linear.g)),
				_quantize_unorm8(_standard_linear_to_srgb(linear.b)),
				_quantize_unorm8(linear.a))
			_check("RGBAH pixel (%d,%d) matches independent sRGB encoding and alpha" % [x, y],
				absf(actual.r - expected.r) < 0.000001
				and absf(actual.g - expected.g) < 0.000001
				and absf(actual.b - expected.b) < 0.000001
				and absf(actual.a - expected.a) < 0.000001,
				"actual=%s expected=%s" % [str(actual), str(expected)])
	_check("RGBAH conversion leaves all source bytes unchanged", source.get_data() == source_before)


func _test_fast_paths() -> void:
	var sdr := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	sdr.set_pixel(0, 0, Color(0.1, 0.2, 0.3, 0.4))
	var sdr_before: PackedByteArray = sdr.get_data().duplicate()
	var sdr_result: Image = ViewportColor.display_image(sdr, false)
	_check("SDR conversion returns the same image instance and bytes",
		sdr_result != null and sdr_result.get_instance_id() == sdr.get_instance_id()
		and sdr_result.get_data() == sdr_before)

	var null_result: Image = ViewportColor.display_image(null, true)
	_check("null readback stays null", null_result == null)
	var empty := Image.new()
	var empty_result: Image = ViewportColor.display_image(empty, true)
	_check("empty readback returns the same empty image", empty_result != null
		and empty_result.get_instance_id() == empty.get_instance_id() and empty_result.is_empty())


func _test_actual_renderer_configuration() -> void:
	var viewport := SubViewport.new()
	var rendering_method := RenderingServer.get_current_rendering_method()
	viewport.use_hdr_2d = false
	ViewportColor.configure(viewport)
	_check("HDR 2D is enabled only for the active Mobile renderer",
		viewport.use_hdr_2d == (rendering_method == "mobile"),
		"active rendering method=%s use_hdr_2d=%s" % [rendering_method, str(viewport.use_hdr_2d)])
	viewport.use_hdr_2d = true
	ViewportColor.configure(viewport)
	_check("configuration preserves an existing HDR setting", viewport.use_hdr_2d)
	viewport.free()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _standard_linear_to_srgb(value: float) -> float:
	if value <= 0.0031308:
		return 12.92 * value
	return 1.055 * pow(value, 1.0 / 2.4) - 0.055


func _quantize_unorm8(value: float) -> float:
	return roundf(value * 255.0) / 255.0
