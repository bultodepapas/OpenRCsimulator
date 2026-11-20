## DT-MAC-04n-R1: Pause shows which physics evaluator runs the flight, including a
## requested native evaluator that fell back, and stays silent for an explicit reference.
## Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_pause_physics.gd
extends SceneTree

const PauseMenu := preload("res://ui/pause_menu.gd")

var checks := 0
var failures := 0


class StatusSession:
	extends Node
	var status: Variant

	func _init(value: Variant) -> void:
		status = value

	func stage_backend_status() -> Variant:
		return status


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, (": " + detail) if not detail.is_empty() else "")


func _initialize() -> void:
	TranslationServer.set_locale("en")
	var pause := PauseMenu.new()
	root.add_child(pause)
	await process_frame # live language changes reach only a ready menu
	var native := StatusSession.new({requested = "native", reason = "",
		identity = {backend = "native", backend_version = "x", abi_version = 1}})
	var refused := StatusSession.new({requested = "native", identity = {backend = "gdscript_reference"},
		reason = "collision world differs from the screened stock context"})
	var unexplained := StatusSession.new({requested = "native", identity = {backend = "gdscript_reference"}, reason = ""})
	var explicit := StatusSession.new({requested = "gdscript_reference", identity = {backend = "gdscript_reference"},
		reason = ""})
	var malformed := StatusSession.new("not a status")
	var unsupported := Node.new()
	_check("native flight says so", pause.physics_backend_text(native) == "Physics: native",
		pause.physics_backend_text(native))
	_check("a refused native request shows compatibility and its reason",
		pause.physics_backend_text(refused)
		== "Physics: compatibility. Native physics is not running: collision world differs from the screened stock context",
		pause.physics_backend_text(refused))
	_check("a fallback without a reason still shows compatibility",
		pause.physics_backend_text(unexplained) == "Physics: compatibility. Native physics is not running.")
	_check("an explicit reference choice shows nothing", pause.physics_backend_text(explicit).is_empty())
	_check("a malformed status shows nothing", pause.physics_backend_text(malformed).is_empty())
	_check("a session without a physics backend shows nothing", pause.physics_backend_text(unsupported).is_empty())
	_check("no session shows nothing", pause.physics_backend_text(null).is_empty())

	pause._session = refused
	pause._refresh_physics()
	_check("Pause shows the fallback line", pause.physics_label.visible
		and pause.physics_label.text.begins_with("Physics: compatibility."), pause.physics_label.text)
	TranslationServer.set_locale("de")
	pause.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	_check("the line follows a live language change",
		pause.physics_label.text.begins_with("Physik: Kompatibilität."), pause.physics_label.text)
	TranslationServer.set_locale("en")
	pause._session = explicit
	pause._refresh_physics()
	_check("an explicit reference flight hides the line", not pause.physics_label.visible)
	pause._session = native
	pause._refresh_physics()
	_check("a native flight shows the native line", pause.physics_label.visible
		and pause.physics_label.text == "Physics: native", pause.physics_label.text)

	pause._session = null
	pause.free()
	for node: Node in [native, refused, unexplained, explicit, malformed, unsupported]:
		node.free()
	print("pause physics: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
