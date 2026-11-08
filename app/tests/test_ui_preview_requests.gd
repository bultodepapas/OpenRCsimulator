# UI-05-R3: real Home/builders with manually ordered resource completions.
extends SceneTree
const UiDriver := preload("res://tests/ui_driver.gd")
const STIK := "jensen-das-ugly-stik-60"
const EXTRA := "gp-extra-300s-60"
const JET := "sebart-avanti-s-a200-p100rx"
const TIMBER := "turbo-lumber-evolution"
const HELI := "xcell-60-research"
const PREFS := "user://test_ui_preview_requests.cfg"
class ManualResources:
	extends Node
	var callbacks: Array[Callable] = []
	func path_for(id: String, _livery := "") -> String: return id
	func request(_path: String, callback: Callable) -> void: callbacks.append(callback)
	func cancel_for(_owner: Object, _release := true) -> void: pass
# Hold and deliver a geometry completion even after cancellation to exercise the
# Home generation guard independently of the real broker's cancellation.
class ManualGeometry:
	extends Node
	var callback := Callable()
	var requests := 0
	var completions := 0
	func busy() -> bool: return callback.is_valid()
	func request(_snapshot: Dictionary, next: Callable) -> bool:
		if busy(): return false
		callback = next
		requests += 1
		return true
	func cancel_for(_owner: Object) -> void: pass
	func complete() -> void:
		var stale := callback
		callback = Callable()
		if stale.is_valid():
			completions += 1
			stale.call({"obsolete": true})
class RejectedFlight:
	extends Node
	var startup_error := "Intentional startup rejection"
	var recorder: Node
	func _set(_property: StringName, _value: Variant) -> bool: return true
class RejectingApp:
	extends "res://app_root.gd"
	func _create_flight(_aircraft_id: String = "") -> Node: return RejectedFlight.new()
class NullFlightApp:
	extends "res://app_root.gd"
	func _create_flight(_aircraft_id: String = "") -> Node: return null
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("ok   " if ok else "FAIL ", label)
func _frames(count := 4) -> void:
	for i in count: await process_frame
func _preview_settled(scene: Node3D) -> bool:
	return not scene.preview_pending and not scene.presentation_pending
func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var ui: RefCounted = UiDriver.new(self)
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await _frames()
	root.size = Vector2i(1920, 1080)
	await ui.settle()
	_check("Home viewport is 1920x1080", root.get_visible_rect().size == Vector2(1920, 1080))
	var manual := ManualResources.new()
	app.add_child(manual)
	app.home_scene.preview_resources = manual
	var original: Node3D = app.home_scene.airplane.root
	app.set_aircraft(JET)
	app.set_aircraft(TIMBER)
	app.set_aircraft(EXTRA)
	_check("burst updates card immediately and preserves old preview", app.home.aircraft_id == EXTRA and app.home_scene.airplane.root == original)
	_check("pending preview is explicit and does not disable Fly", app.home.aircraft_preview_label.visible and not app.home.fly_button.disabled)
	var dispatched: bool = await ui.wait_until(func() -> bool: return manual.callbacks.size() >= 1)
	_check("only the final burst reaches resource preparation", dispatched and manual.callbacks.size() == 1)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	manual.callbacks[-1].call(true)
	var settled: bool = await ui.wait_until(func() -> bool: return _preview_settled(app.home_scene))
	_check("latest preview is applied", settled and app.home_scene.airplane.aircraft_id == EXTRA and not app.home_scene.preview_pending)
	_check("ready hides pending label", not app.home.aircraft_preview_label.visible)
	app.set_aircraft(JET)
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() >= 2)
	_check("jet request reaches resource preparation", dispatched)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	var stale := manual.callbacks[-1]
	app.set_aircraft(TIMBER)
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() >= 3)
	_check("newer request reaches resource preparation", dispatched)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	manual.callbacks[-1].call(true)
	settled = await ui.wait_until(func() -> bool: return _preview_settled(app.home_scene))
	stale.call(true)
	_check("late success cannot replace newer aircraft", settled and app.home_scene.airplane.aircraft_id == TIMBER)
	stale.call(false)
	_check("late failure cannot overwrite ready state", not app.home.aircraft_preview_label.visible)
	app.set_aircraft(HELI)
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() >= 4)
	_check("helicopter request reaches resource preparation", dispatched)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	manual.callbacks[-1].call(false)
	_check("failure preserves last valid image and exposes error", app.home_scene.airplane.aircraft_id == TIMBER and app.home.aircraft_preview_label.visible and not app.home_scene.preview_pending)
	app.set_language("es")
	_check("failure text translates live", app.home.aircraft_preview_label.atr(app.home.aircraft_preview_label.text).begins_with("No se pudo"))
	app.set_aircraft(HELI)
	_check("loading text translates live", app.home.aircraft_preview_label.atr(app.home.aircraft_preview_label.text).begins_with("Cargando"))
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() >= 5)
	_check("retry reaches resource preparation", dispatched)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	manual.callbacks[-1].call(true)
	settled = await ui.wait_until(func() -> bool: return _preview_settled(app.home_scene))
	_check("retry after failure can succeed", settled and app.home_scene.airplane.aircraft_id == HELI)
	app.set_aircraft(TIMBER)
	_check("cached selection remains synchronous", app.home_scene.airplane.aircraft_id == TIMBER and not app.home_scene.preview_pending)
	var requested: String = app.home.aircraft_id
	app.set_aircraft("not-a-catalog-id")
	_check("invalid catalog ID cannot change intent", app.home.aircraft_id == requested)
	app.set_aircraft(JET)
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() >= 6)
	_check("detach request reaches resource preparation", dispatched)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	var detached: Node3D = app.home_scene
	var detached_callback := manual.callbacks[-1]
	var requests_before_detach := manual.callbacks.size()
	app.remove_child(detached)
	detached_callback.call(true)
	_check("detached Home cannot apply a completion", detached.airplane.aircraft_id == TIMBER)
	app.add_child(detached)
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() > requests_before_detach)
	_check("restored Home requests current intent again", dispatched and detached.preview_pending and manual.callbacks.size() == requests_before_detach + 1)
	# Reverse to a retained model without waiting for the obsolete jet.
	app.set_aircraft(TIMBER)
	manual.callbacks[-1].call(true)
	_check("cached reversal supersedes pending resource", detached.airplane.aircraft_id == TIMBER and not detached.preview_pending)
	# Also supersede an in-flight night-geometry job. Deliver its callback after
	# cancellation instead of relying on the broker to suppress it.
	app.set_time_of_day("night")
	await _frames(2)
	settled = await ui.wait_until(func() -> bool: return _preview_settled(detached))
	_check("night presentation completes before geometry race", settled)
	var geometry := ManualGeometry.new()
	app.add_child(geometry)
	detached.preview_geometry = geometry
	var before_geometry_request := manual.callbacks.size()
	app.set_aircraft(JET)
	dispatched = await ui.wait_until(func() -> bool: return manual.callbacks.size() > before_geometry_request)
	_check("geometry race starts with selected jet resource", dispatched)
	if not dispatched:
		await ui.close_app(app)
		quit(1)
		return
	manual.callbacks[-1].call(true)
	var geometry_started: bool = await ui.wait_until(func() -> bool: return geometry.requests == 1)
	_check("jet reaches a held geometry job", geometry_started and detached.preview_pending)
	if not geometry_started:
		await ui.close_app(app)
		quit(1)
		return
	var candidate: WeakRef = weakref(detached._preview_candidate)
	app.set_aircraft(TIMBER)
	geometry.complete()
	_check("stale geometry cannot replace a cached reversal", geometry.completions == 1
		and detached.airplane.aircraft_id == TIMBER and not detached.preview_pending)
	var candidate_released: bool = await ui.wait_until(func() -> bool: return candidate.get_ref() == null)
	_check("superseded geometry candidate is released", candidate_released and detached.airplane.aircraft_id == TIMBER)
	app.set_aircraft(STIK) # evicted: pending, but Fly must use this requested ID.
	_check("new selection is pending before immediate Fly", detached.preview_pending and app.home.aircraft_id == STIK)
	app.start_flight()
	var flight: Node = app.flight
	app.start_flight()
	_check("immediate Fly uses latest model and physics exactly once", flight != null and app.flight == flight and flight._airplane.aircraft_id == STIK and flight.session.aircraft.model.id == STIK)
	await _frames()
	_check("successful Fly frees Home and invalidates callbacks", app.home_scene == null and not detached_callback.is_valid())
	await ui.close_app(app)
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
	dispatched = await ui.wait_until(func() -> bool: return rollback_loader.callbacks.size() >= 1)
	_check("rollback request reaches resource preparation", dispatched)
	if not dispatched:
		await ui.close_app(rejected)
		quit(1)
		return
	var obsolete := rollback_loader.callbacks[-1]
	var previous_scene: WeakRef = weakref(rejected.home_scene)
	var rollback_model: Node3D = rejected.home_scene.airplane.root
	var before_rollback := rollback_loader.callbacks.size()
	rejected.start_flight()
	_check("failed Fly restores latest selection and usable Home", rejected.flight == null and rejected.home != null and rejected.home.aircraft_id == JET and not rejected.home.fly_button.disabled)
	_check("rollback reattaches the same Home", previous_scene.get_ref() == rejected.home_scene and rejected.home_scene.is_inside_tree())
	_check("rollback race starts without jet geometry or a busy worker", rejected.home_scene._preview_candidate == null
		and not rejected.home_scene._preview_models.has(JET) and not rejected.home_scene.preview_geometry.busy())
	obsolete.call(true)
	_check("old completion cannot begin geometry after rollback", rejected.home_scene.airplane.root == rollback_model
		and rejected.home_scene.preview_pending and rejected.home_scene._preview_candidate == null
		and not rejected.home_scene._preview_models.has(JET))
	dispatched = await ui.wait_until(func() -> bool: return rollback_loader.callbacks.size() > before_rollback)
	_check("rollback resumes the selected preview", dispatched)
	if not dispatched:
		await ui.close_app(rejected)
		quit(1)
		return
	_check("old completion cannot publish while resumed request waits", rejected.home_scene.airplane.root == rollback_model
		and rejected.home_scene.preview_pending and rejected.home_scene._preview_candidate == null
		and not rejected.home_scene._preview_models.has(JET))
	rollback_loader.callbacks[-1].call(true)
	_check("current completion starts the requested geometry", is_instance_valid(rejected.home_scene._preview_candidate)
		and rejected.home_scene.airplane.root == rollback_model and rejected.home_scene.preview_pending)
	settled = await ui.wait_until(func() -> bool: return _preview_settled(rejected.home_scene))
	_check("restored preview matches card without stale loading state", settled and rejected.home_scene.airplane.aircraft_id == JET and not rejected.home.aircraft_preview_label.visible)
	_check("preview restoration preserves launch failure message", rejected.home.note_label.text.contains("Intentional startup rejection"))
	await ui.close_app(rejected)
	var null_flight := NullFlightApp.new()
	null_flight.user_args = PackedStringArray()
	null_flight.preferences_path = PREFS
	root.add_child(null_flight)
	await _frames()
	var retained_home: Node = null_flight.home
	var retained_scene: Node3D = null_flight.home_scene
	null_flight.start_flight()
	_check("null flight factory leaves Home attached and usable", null_flight.flight == null
		and null_flight.home == retained_home and retained_home.is_inside_tree()
		and null_flight.screens.is_top("home"))
	_check("null flight error stays visible without detaching HomeScene", null_flight.home_scene == retained_scene
		and retained_scene.is_inside_tree() and retained_home.note_label.text.contains("Could not start flight"))
	await ui.close_app(null_flight)
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("Preview requests: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
