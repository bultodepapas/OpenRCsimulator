extends RefCounted
## GFX-IGPU-02: the first start and the first flight on a computer compile and cache its shaders. With the
## Compatibility renderer or a weak integrated GPU that blocks whole frames for seconds: a UHD 630 with cold caches
## froze 9-12 s while starting and about 7 s while loading its first flight; later starts reuse Godot's and the
## driver's shader caches (docs/research/god-test/2026-11-22-linux-uhd630-comparison.md). OpenGL compiles on the main
## thread, so no loading thread can hide it. The startup and loading surfaces say so before the frozen frames instead
## of appearing hung. One marker per stage records the engine, renderer, adapter, driver and game version it covers.

const GpuCapability := preload("res://render/gpu_capability.gd")

const PATH := "user://graphics_preparation.cfg"
const STAGES: Array[String] = ["home", "flight"]
const FIRST_START_TEXT := "Preparing graphics for this computer. Only the first start takes this long."
const FIRST_FLIGHT_TEXT := "Preparing graphics for the first flight on this computer. Later flights load faster."

## Test seam: tests point this at a private file.
static var path := PATH


## The cache identity a marker covers: a new engine, renderer, GPU, driver or game version compiles again.
static func identity() -> String:
	return "|".join([str(Engine.get_version_info().get("string", "")), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		str(ProjectSettings.get_setting("application/config/version", ""))])


## First-use shader work is slow enough to explain with Compatibility or an integrated or software GPU.
static func slow_first_use(method: String, adapter: String) -> bool:
	if method == "gl_compatibility":
		return true
	return str(GpuCapability.lookup(adapter).get("class", "")) in ["integrated", "software"]


## Whether `stage` ("home" or "flight") still has to prepare its graphics on this host. Headless never shows it.
static func pending(stage: String, current_identity: String = "") -> bool:
	if stage not in STAGES or DisplayServer.get_name() == "headless":
		return false
	if not slow_first_use(RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()):
		return false
	return stored(stage) != (current_identity if not current_identity.is_empty() else identity())


static func stored(stage: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return ""
	return str(cfg.get_value(stage, "identity", ""))


## Records that `stage` prepared its graphics for this identity. A failed write only shows the notice again.
static func mark(stage: String, current_identity: String = "") -> bool:
	if stage not in STAGES:
		return false
	var cfg := ConfigFile.new()
	cfg.load(path) # a missing file starts empty
	cfg.set_value(stage, "identity", current_identity if not current_identity.is_empty() else identity())
	return cfg.save(path) == OK
