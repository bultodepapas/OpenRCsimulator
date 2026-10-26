extends RefCounted
## Global presentation preferences. No file access, aircraft profile edits or simulation state.
const Patterns := preload("res://render/lighting/lighting_patterns.gd")
static var quality := "standard"
static var reduced_flashes := false
static var show_vfx := true
static var _registered := false

static func register() -> void:
	if _registered: return
	RenderingServer.global_shader_parameter_add(&"aircraft_reduced_flashes", RenderingServer.GLOBAL_VAR_TYPE_BOOL, reduced_flashes)
	_registered = true

static func apply(config: Dictionary) -> void:
	quality = str(config.get("aircraft_lighting_quality", "standard"))
	if quality not in ["low", "standard", "high"]: quality = "standard"
	reduced_flashes = config.get("aircraft_lighting_reduced_flashes", false) == true
	show_vfx = config.get("aircraft_lighting_show_vfx", true) == true
	register()
	RenderingServer.global_shader_parameter_set(&"aircraft_reduced_flashes", reduced_flashes)

static func effects_allowed() -> bool:
	return show_vfx and not reduced_flashes and quality != "low"

static func effect_density() -> float:
	return 1.0 if quality == "high" else (0.5 if quality == "standard" else 0.0)

static func pattern(source: Dictionary) -> Dictionary:
	if not reduced_flashes: return source
	var result := source.duplicate(true)
	# Keep static segment colors; animated palettes/cues become their base color.
	if str(result.get("id", "steady")) != "segments": result.id = "steady"
	result.floor = 1.0
	return result

static func sample(source: Dictionary, seconds: float, u: float, sequence: Array = [], zone_id := "") -> Color:
	return Patterns.sample(pattern(source), seconds, u, sequence, zone_id)

static func resolve(source: Dictionary, seconds: float, sequence: Array = [], zone_id := "") -> Dictionary:
	return Patterns.resolve(pattern(source), seconds, sequence, zone_id)

static func reaction(source: Dictionary, telemetry: Dictionary) -> Dictionary:
	return {"available": true, "multiplier": 1.0} if reduced_flashes else Patterns.reactive_multiplier(source, telemetry)
