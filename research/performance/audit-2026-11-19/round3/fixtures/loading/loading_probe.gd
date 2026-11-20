extends SceneTree
const App = preload("res://app_root.gd")
const Prep = preload("res://ui/home_flight_preparation.gd")
const Broker = preload("res://ui/home_preview_resources.gd")
const Prefs = preload("res://app_state/preferences.gd")
const Fonts = preload("res://i18n/fonts.gd")

class Gate extends RefCounted:
 var entered := Semaphore.new()
 var release := Semaphore.new()
 func load_scene(_path: String, _type: String) -> Resource:
  entered.post()
  release.wait()
  var node := Node.new()
  var scene := PackedScene.new()
  scene.pack(node)
  node.free()
  return scene

class StubBroker extends Broker:
 func request(_path: String, _callback: Callable) -> void:
  pass

class StubHomeScene extends Node3D:
 var field := {"id":"default"}
 var source_landscape := "club_field"
 var preview_pending := false
 var presentation_pending := false
 var retain_resources_on_exit := false
 var camera: Camera3D
 func _init() -> void:
  camera = Camera3D.new()
  add_child(camera)
 func request_aircraft(_id: String, _livery := "") -> void: pass
 func suspend_preview() -> void: pass
 func resume_preview() -> void: pass
 func can_refresh_presentation(_path: String, _id: String) -> bool: return false

class StubFlight extends Node:
 var app: Node
 var startup_error := ""
 var recorder: Node
 var session: Node
 func _ready() -> void: app.ready_count += 1
 func _set(_property: StringName, _value: Variant) -> bool: return true

class TestApp extends App:
 var gate: Gate
 var create_count := 0
 var ready_count := 0
 var rebuild_count := 0
 var created_id := ""
 func _ready() -> void:
  has_home = true
  flight_loading_enabled = true
  home_flight_prefetch_mode = "scene"
  home_flight_prefetch_delay_msec = 0
  preferences_path = "user://loading_probe.cfg"
  preferences = Prefs.DEFAULTS.duplicate(true)
  _home_preview_resources = StubBroker.new()
  add_child(_home_preview_resources)
  home_scene = StubHomeScene.new()
  add_child(home_scene)
  var surface := Home.new()
  screens.push("home", surface, null, false)
 func _process(_delta: float) -> void:
  _tick_home_flight_preparation()
  if not _home_scene_preparation_busy() and _home_rebuild_queued:
   _flush_home_scene_rebuild()
 func _new_flight_scene_load() -> Node:
  var job := FlightSceneLoad.new()
  job.load_resource = gate.load_scene
  return job
 func _create_flight(id: String = "") -> Node:
  create_count += 1
  created_id = id
  var result := StubFlight.new()
  result.app = self
  return result
 func _rebuild_home_scene_staged() -> void:
  rebuild_count += 1
  home_scene.source_landscape = landscape_id
 func _rebuild_home_scene() -> bool:
  rebuild_count += 1
  home_scene.source_landscape = landscape_id
  return true

var failed := 0
func check(label: String, ok: bool, detail: Dictionary = {}) -> void:
 print("CHECK ", label, " ", "PASS" if ok else "FAIL", " ", JSON.stringify(detail))
 if not ok: failed += 1
func _initialize() -> void: _run.call_deferred()
func frames(count: int) -> void:
 for i in count: await process_frame
func begin_app() -> Dictionary:
 var gate := Gate.new()
 var app := TestApp.new()
 app.gate = gate
 root.add_child(app)
 await frames(4)
 app._home_flight_preparation.mark_home_drawn()
 var entered := false
 for i in 500:
  if gate.entered.try_wait():
   entered = true
   break
  await process_frame
 check("worker_gate_entered", entered and app._home_scene_preparation_busy())
 return {app = app, gate = gate}
func drain(f: Dictionary) -> void:
 f.gate.release.post()
 for i in 1000:
  if not f.app._home_scene_preparation_busy(): break
  await process_frame
 await frames(5)
func close_app(app: Node) -> void:
 await app.shutdown_home_flight_preparation()
 app.screens.clear()
 app.queue_free()
 await frames(4)
func _run() -> void:
 Fonts._japanese = ThemeDB.fallback_font
 Fonts._chinese = ThemeDB.fallback_font
 var f: Dictionary = await begin_app()
 var app: TestApp = f.app
 var selected := app.set_landscape("green_paradise")
 check("change_while_busy_queued", selected and app._home_rebuild_queued and app.landscape_id == "green_paradise" and app.home_scene.source_landscape == "club_field")
 await drain(f)
 check("control_without_fly_rebuilds", app.rebuild_count == 1 and app.home_scene.source_landscape == "green_paradise", {"rebuilds":app.rebuild_count,"selected":app.landscape_id,"shown":app.home_scene.source_landscape})
 await close_app(app)

 f = await begin_app()
 app = f.app
 selected = app.set_landscape("green_paradise")
 app.start_flight()
 app.cancel_flight_loading()
 await frames(5)
 check("early_cancel_clears_queued_rebuild", selected and not app._loading_active and not app._home_rebuild_queued and app.home_scene.source_landscape == "club_field" and app.landscape_id == "green_paradise", {"queued":app._home_rebuild_queued,"selected":app.landscape_id,"shown":app.home_scene.source_landscape,"status":app.last_flight_loading.get("status","")})
 await drain(f)
 check("released_worker_does_not_rebuild", app.rebuild_count == 0 and app.home_scene.source_landscape == "club_field" and app.home.landscape_id == "green_paradise", {"rebuilds":app.rebuild_count,"selected":app.home.landscape_id,"shown":app.home_scene.source_landscape})
 await close_app(app)

 f = await begin_app()
 app = f.app
 var heli := app.set_aircraft("xcell-60-research")
 app.start_flight()
 app.cancel_flight_loading()
 await frames(5)
 check("heli_early_cancel_control", heli and not app._loading_active and app.create_count == 0 and app.last_flight_loading.get("status","") == "cancelled", {"creations":app.create_count,"status":app.last_flight_loading.get("status","")})
 await drain(f)
 await close_app(app)

 f = await begin_app()
 app = f.app
 heli = app.set_aircraft("xcell-60-research")
 app.start_flight()
 await frames(8)
 var blocked := app._loading_active and app._home_scene_preparation_busy() and not app.home_scene.is_inside_tree() and app.create_count == 0
 app.cancel_flight_loading()
 await frames(3)
 check("heli_cancel_waits_without_candidate", heli and blocked and app._loading_active and app.create_count == 0, {"blocked":blocked,"creations":app.create_count})
 await drain(f)
 await frames(8)
 check("heli_cancel_still_constructs", not app._loading_active and app.created_id == "xcell-60-research" and app.create_count == 1 and app.ready_count == 1 and app.flight == null and app.last_flight_loading.get("status","") == "cancelled", {"creations":app.create_count,"ready":app.ready_count,"route":app.created_id,"status":app.last_flight_loading.get("status","")})
 await close_app(app)
 print("PROBE_COMPLETE failures=",failed)
 quit(0 if failed == 0 else 1)
