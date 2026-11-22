extends SceneTree
## GFX-IGPU-02: the first-start/first-flight graphics notice and its per-identity marker.
## Run: godot --headless --path . --script res://tests/test_graphics_preparation.gd

const GraphicsPreparation := preload("res://render/graphics_preparation.gd")
const FlightLoading := preload("res://ui/flight_loading.gd")
const TEST_PATH := "user://test_graphics_preparation.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	GraphicsPreparation.path = TEST_PATH
	_reset()
	_check("Compatibility always explains first-use shader work",
		GraphicsPreparation.slow_first_use("gl_compatibility", "NVIDIA GeForce RTX 3090"))
	_check("a desktop GPU in Forward+ needs no notice",
		not GraphicsPreparation.slow_first_use("forward_plus", "NVIDIA GeForce RTX 3090"))
	_check("an integrated GPU explains it in any renderer",
		GraphicsPreparation.slow_first_use("forward_plus", "Intel(R) UHD Graphics 630")
		and GraphicsPreparation.slow_first_use("mobile", "llvmpipe (LLVM 15.0.7, 256 bits)"))
	_check("headless never shows the notice", not GraphicsPreparation.pending("home")
		and not GraphicsPreparation.pending("flight"))
	_check("no marker is stored before preparation", GraphicsPreparation.stored("home") == "")
	_check("unknown stages are refused", not GraphicsPreparation.mark("menu", "id-a"))
	_check("each stage records its own identity", GraphicsPreparation.mark("home", "id-a")
		and GraphicsPreparation.stored("home") == "id-a" and GraphicsPreparation.stored("flight") == "")
	_check("a later identity replaces the stage marker", GraphicsPreparation.mark("home", "id-b")
		and GraphicsPreparation.stored("home") == "id-b")
	_check("the identity names engine, renderer, adapter, driver and game version",
		GraphicsPreparation.identity().split("|").size() == 5)

	_reset()
	var committed: CanvasLayer = FlightLoading.new()
	committed.configure("Stik · Club Field · Airborne")
	_check("headless keeps the first-flight notice hidden", not committed.preparation_notice.visible)
	committed.show_preparation_notice(true)
	_check("the first-flight notice is shown with its text", committed.preparation_notice.visible
		and committed.preparation_notice.text == tr(GraphicsPreparation.FIRST_FLIGHT_TEXT))
	committed.set_committing()
	committed.free()
	_check("a committed first flight records its preparation",
		GraphicsPreparation.stored("flight") == GraphicsPreparation.identity())

	_reset()
	var cancelled: CanvasLayer = FlightLoading.new()
	cancelled.configure("Stik · Club Field · Airborne")
	cancelled.show_preparation_notice(true)
	cancelled.set_cancelling()
	cancelled.free()
	_check("a cancelled first flight does not record preparation", GraphicsPreparation.stored("flight") == "")

	_reset()
	GraphicsPreparation.path = GraphicsPreparation.PATH
	print("graphics preparation: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)
