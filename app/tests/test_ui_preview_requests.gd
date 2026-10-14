# UI-05-R3: real Home/builders with manually ordered resource completions.
extends SceneTree
const STIK := "jensen-das-ugly-stik-60"
const EXTRA := "gp-extra-300s-60"
const JET := "sebart-avanti-s-a200-p100rx"
const TIMBER := "turbo-lumber-evolution"
const HELI := "xcell-60-research"
const PREFS := "user://test_ui_preview_requests.cfg"
class ManualResources:
	extends Node
	var callbacks: Array[Callable] = []
	func path_for(id: String) -> String: return id
	func request(_path: String, callback: Callable) -> void: callbacks.append(callback)
	func cancel_for(_owner: Object, _release := true) -> void: pass
class RejectedFlight:
	extends Node
	var startup_error := "Intentional startup rejection"
	var recorder: Node
	func _set(_property: StringName, _value: Variant) -> bool: return true
class RejectingApp:
	extends "res://app_root.gd"
	func _create_flight(_aircraft_id: String = "") -> Node: return RejectedFlight.new()
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("ok   " if ok else "FAIL ", label)
func _frames(count := 4) -> void:
	for i in count: await process_frame
func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await _frames()
	var manual := ManualResources.new()
	app.add_child(manual)
	app.home_scene.preview_resources = manual
	var original: Node3D = app.home_scene.airplane.root
	app.set_aircraft(JET)
	app.set_aircraft(TIMBER)
	app.set_aircraft(EXTRA)
	_check("burst updates card immediately and preserves old preview", app.home.aircraft_id == EXTRA and app.home_scene.airplane.root == original)
	_check("pending preview is explicit and does not disable Fly", app.home.aircraft_preview_label.visible and not app.home.fly_button.disabled)
	await _frames()
	_check("only the final burst reaches resource preparation", manual.callbacks.size() == 1)
	manual.callbacks[-1].call(true)
	_check("latest preview is applied", app.home_scene.airplane.aircraft_id == EXTRA and not app.home_scene.preview_pending)
	_check("ready hides pending label", not app.home.aircraft_preview_label.visible)
	app.set_aircraft(JET)
	await _frames()
	var stale := manual.callbacks[-1]
	app.set_aircraft(TIMBER)
	await _frames()
	manual.callbacks[-1].call(true)
	stale.call(true)
	_check("late success cannot replace newer aircraft", app.home_scene.airplane.aircraft_id == TIMBER)
	stale.call(false)
	_check("late failure cannot overwrite ready state", not app.home.aircraft_preview_label.visible)
	app.set_aircraft(HELI)
	await _frames()
	manual.callbacks[-1].call(false)
	_check("failure preserves last valid image and exposes error", app.home_scene.airplane.aircraft_id == TIMBER and app.home.aircraft_preview_label.visible and not app.home_scene.preview_pending)
	app.set_language("es")
	_check("failure text translates live", app.home.aircraft_preview_label.atr(app.home.aircraft_preview_label.text).begins_with("No se pudo"))
	app.set_aircraft(HELI)
	_check("loading text translates live", app.home.aircraft_preview_label.atr(app.home.aircraft_preview_label.text).begins_with("Cargando"))
	await _frames()
	manual.callbacks[-1].call(true)
	_check("retry after failure can succeed", app.home_scene.airplane.aircraft_id == HELI)
	app.set_aircraft(TIMBER)
	_check("cached selection remains synchronous", app.home_scene.airplane.aircraft_id == TIMBER and not app.home_scene.preview_pending)
	var requested: String = app.home.aircraft_id
	app.set_aircraft("not-a-catalog-id")
	_check("invalid catalog ID cannot change intent", app.home.aircraft_id == requested)
	app.set_aircraft(JET)
	await _frames()
	var detached: Node3D = app.home_scene
	var detached_callback := manual.callbacks[-1]
	var requests_before_detach := manual.callbacks.size()
	app.remove_child(detached)
	detached_callback.call(true)
	_check("detached Home cannot apply a completion", detached.airplane.aircraft_id == TIMBER)
	app.add_child(detached)
	await _frames(5)
	_check("restored Home requests current intent again", detached.preview_pending and manual.callbacks.size() == requests_before_detach + 1)
	# Reverse to a retained model without waiting for the obsolete jet.
	app.set_aircraft(TIMBER)
	manual.callbacks[-1].call(true)
	_check("cached reversal supersedes pending resource", detached.airplane.aircraft_id == TIMBER and not detached.preview_pending)
	app.set_aircraft(STIK) # evicted: pending, but Fly must use this requested ID.
	_check("new selection is pending before immediate Fly", detached.preview_pending and app.home.aircraft_id == STIK)
	app.start_flight()
	var flight: Node = app.flight
	app.start_flight()
	_check("immediate Fly uses latest model and physics exactly once", flight != null and app.flight == flight and flight._airplane.aircraft_id == STIK and flight.session.aircraft.model.id == STIK)
	await _frames()
	_check("successful Fly frees Home and invalidates callbacks", app.home_scene == null and not detached_callback.is_valid())
	app.queue_free()
	await _frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var rejected := RejectingApp.new()
	rejected.user_args = PackedStringArray()
	rejected.preferences_path = PREFS
	root.add_child(rejected)
	await _frames()
	var rollback_loader := ManualResources.new()
	rejected.add_child(rollback_loader)
	rejected.home_scene.preview_resources = rollback_loader
	rejected.set_aircraft(JET)
	await _frames()
	var obsolete := rollback_loader.callbacks[-1]
	var previous_scene: WeakRef = weakref(rejected.home_scene)
	rejected.start_flight()
	await _frames()
	_check("failed Fly restores latest selection and usable Home", rejected.flight == null and rejected.home != null and rejected.home.aircraft_id == JET and not rejected.home.fly_button.disabled)
	_check("rollback replaces Home and invalidates old callbacks", previous_scene.get_ref() == null and not obsolete.is_valid())
	_check("restored preview matches card without stale loading state", rejected.home_scene.airplane.aircraft_id == JET and not rejected.home.aircraft_preview_label.visible)
	_check("preview restoration preserves launch failure message", rejected.home.note_label.text.contains("Intentional startup rejection"))
	rejected.queue_free()
	await _frames()
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("Preview requests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
