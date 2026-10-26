# FW-RGB-13: preserve scene-linear night light before Mobile's late tonemap exposure.
extends RefCounted


static func configure(viewport: Viewport) -> void:
	if viewport != null and RenderingServer.get_current_rendering_method() == "mobile":
		# Mobile's default RGB10A2 scene buffer rounds faint night values to zero.
		# Keep float precision through day/night transitions; do not reallocate each frame.
		viewport.use_hdr_2d = true


## HDR viewport readback is linear. Encode before quantizing to 8-bit display PNG/JPEG.
## This is capture-only work; SDR images retain their existing bytes and ownership.
static func display_image(source: Image, linear_hdr: bool) -> Image:
	if source == null or source.is_empty() or not linear_hdr:
		return source
	# 4.8-beta1 Image::_lin2srgb_hft4 writes the wrong destination pixel. Use Color's
	# conversion until that engine defect is fixed; converting to RGB8 first loses shadows.
	var result := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	for y in source.get_height():
		for x in source.get_width():
			result.set_pixel(x, y, source.get_pixel(x, y).linear_to_srgb())
	return result
