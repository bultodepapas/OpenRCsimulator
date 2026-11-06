extends RefCounted
## DT-MAC-06b: bounded research variants, selected before constructing the sky.
## Default keeps the production shader. No runtime compilation during flight.
const ENVIRONMENT_KEY := "OPENRC_CLOUD_DENSITY_BOUNDS"
const BASE := preload("res://render/sky.gdshader")
static var _variants: Dictionary = {}


static func density_mode() -> String:
	var requested := OS.get_environment(ENVIRONMENT_KEY)
	return requested if requested in ["three", "two_three"] else "off"


static func diagnostics() -> Dictionary:
	return {requested = OS.get_environment(ENVIRONMENT_KEY), effective = density_mode(),
		scope = "sky density and analytic relief fallback", qualified = false}


static func sky_shader() -> Shader:
	var mode := density_mode()
	if mode == "off":
		return BASE
	if not _variants.has(mode):
		var shader := Shader.new()
		shader.set_meta("openrc_base_shader_path", BASE.resource_path)
		shader.set_meta("openrc_cloud_density_bounds", mode)
		shader.code = "#define OPENRC_CLOUD_BOUNDS %d\n" % (2 if mode == "two_three" else 3) + BASE.code
		_variants[mode] = shader
	return _variants[mode]
