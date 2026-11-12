extends SceneTree
## UI-28-R5: loading presentation. The shared bar is monotonic and truthful, the intro keeps its
## atmosphere alive after settle() while seek() stays still, stage reports map to milestones, and
## the staged first Home builds the same tree as the synchronous Home with the stage names the
## startup and flight surfaces expect.

const LoadingBar := preload("res://ui/loading_bar.gd")
const Intro := preload("res://ui/brand_intro.gd")
const Startup := preload("res://ui/startup.gd")
const FlightLoading := preload("res://ui/flight_loading.gd")
const HomeScene := preload("res://ui/home_scene.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const RendererGuard := preload("res://app_state/renderer_guard.gd")
const WORLD_STAGES := ["Preparing world", "Building landscape", "Preparing sky", "Preparing field lighting",
	"Finalizing world"]

var failures := 0
var checks := 0


func _initialize() -> void:
	TranslationServer.set_locale("en")
	_run.call_deferred()


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if passed:
		print("ok  ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _frames(count := 3) -> void:
	for _frame in count:
		await process_frame


func _run() -> void:
	await _bar_checks()
	await _intro_checks()
	_startup_stage_checks()
	_flight_stage_checks()
	_renderer_guard_hold_checks()
	await _staged_home_checks()
	print("Startup loading: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _bar_checks() -> void:
	var bar: Control = LoadingBar.new()
	bar.size = Vector2(400.0, 8.0)
	root.add_child(bar)
	bar.value = 0.5
	bar.value = 0.3
	bar.value = NAN
	check("bar value is monotonic and ignores non-finite input", is_equal_approx(bar.value, 0.5))
	bar.value = 4.0
	check("bar value is clamped to one", is_equal_approx(bar.value, 1.0))
	var nudged: Control = LoadingBar.new()
	nudged.value = 0.5
	for _step in 200:
		nudged.nudge(0.6, 0.12)
	check("sub-stage nudges approach but never reach the next milestone", nudged.value > 0.59 and nudged.value < 0.6)
	nudged.nudge(0.4)
	check("a nudge below the value is ignored", nudged.value > 0.59)
	nudged.free()
	bar.shown = 0.0
	await _frames(30)
	check("the drawn fill eases toward the value without passing it", bar.shown > 0.0 and bar.shown <= bar.value)
	bar.reduced_motion = true
	check("reduced motion draws the value directly", is_equal_approx(bar.shown, bar.value))
	bar.queue_free()
	await _frames(1)


func _intro_checks() -> void:
	root.size = Vector2i(1920, 1080)
	var intro: Control = Intro.new()
	root.add_child(intro)
	await _frames()
	check("a live intro animates its atmosphere", intro.playing and intro._atmosphere.get_shader_parameter("live") == 1.0)
	intro.settle()
	var settled: float = intro.elapsed
	await _frames(5)
	check("settle() resolves the lockup and keeps the clock running", settled >= Intro.DURATION
		and intro.playing and intro.elapsed > settled and float(intro._ink.get_shader_parameter("idle_clock")) >= 0.0)
	intro.progress = 0.5
	intro.progress = 0.2
	check("intro progress is monotonic and reaches its bar", is_equal_approx(intro.progress, 0.5)
		and is_equal_approx(intro.progress_bar.value, 0.5))
	for resolution in [Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = resolution
		await _frames(2)
		var bar_rect: Rect2 = intro.progress_bar.get_global_rect()
		check("bar sits inside the viewport above the footer at %s" % resolution,
			root.get_visible_rect().encloses(bar_rect) and bar_rect.size.x > 0.0
			and not bar_rect.intersects(intro.status_label.get_global_rect())
			and not bar_rect.intersects(intro.skip_button.get_global_rect())
			and bar_rect.end.y < intro._footer.get_global_rect().position.y)
	root.size = Vector2i(1920, 1080)
	intro.seek(Intro.DURATION)
	check("seek() keeps the still review frame without live decoration", not intro.playing
		and intro._atmosphere.get_shader_parameter("live") == 0.0
		and float(intro._ink.get_shader_parameter("idle_clock")) < 0.0 and intro.progress_bar.reduced_motion)
	intro.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	intro.seek(2.0)
	check("the trailer's self_modulate hides the bar with the caption", intro.progress_bar.modulate.a == 0.0)
	intro.queue_free()
	await _frames(1)


func _startup_stage_checks() -> void:
	var startup: Node = Startup.new()
	var intro: Control = Intro.new()
	startup.intro = intro
	var steps := Startup.MILESTONES
	intro.progress = 1.0 / steps # the shell scene load completed
	startup._on_home_stage("Preparing world")
	check("the first Home stage keeps the scene-load milestone", is_equal_approx(intro.progress, 1.0 / steps)
		and intro.detail_text == "Preparing world")
	startup._on_home_stage("Building landscape")
	check("a top-level stage sets its milestone", is_equal_approx(intro.progress, 2.0 / steps))
	for _chunk in 60:
		startup._on_home_stage("Building field scenery")
	check("sub-stages fill the secondary line and keep the stage line stable",
		intro.detail_text == "Building landscape" and intro.subdetail_text == "Building field scenery")
	check("repeated sub-stages advance only within their segment", intro.progress > 2.0 / steps
		and intro.progress < 3.0 / steps)
	startup._on_home_stage("Preparing aircraft")
	var before: float = intro.progress
	startup._on_home_stage("Preparing aircraft")
	startup._on_home_stage("Preparing sky")
	check("skipped stages jump ahead; repeats and earlier stages never move back", is_equal_approx(before, 6.0 / steps)
		and is_equal_approx(intro.progress, before))
	intro.free()
	startup.free()


func _flight_stage_checks() -> void:
	var count := float(FlightLoading.STAGES.size())
	var loading: CanvasLayer = FlightLoading.new()
	loading.set_stage("Preparing resources")
	check("flight progress starts empty", is_equal_approx(loading.progress_bar.value, 0.0))
	loading.set_stage("Preparing flight scene")
	check("each top-level flight stage marks the stages completed before it",
		is_equal_approx(loading.progress_bar.value, 1.0 / count))
	loading.set_stage("Building landscape")
	for _chunk in 80:
		loading.set_stage("Near grass")
	check("flight sub-stages fill the detail line and keep the stage line stable",
		loading.stage_label.text == "Building landscape" and loading.detail_label.text == "Near grass"
		and loading.detail_label.visible)
	var landscape := FlightLoading.STAGES.find("Building landscape")
	check("flight sub-stages stay inside their stage", loading.progress_bar.value > landscape / count
		and loading.progress_bar.value < (landscape + 1.0) / count)
	loading.set_stage("Preparing sky")
	check("a new stage clears the detail but keeps its height", loading.stage_label.text == "Preparing sky"
		and loading.detail_label.visible and loading.detail_label.text.strip_edges() == "")
	loading.set_stage("Finishing flight")
	var finishing: float = loading.progress_bar.value
	loading.set_stage("Preparing sky")
	check("a skipped optional stage is passed over and order never reverses",
		is_equal_approx(finishing, (count - 1.0) / count) and is_equal_approx(loading.progress_bar.value, finishing))
	loading.set_cancelling()
	check("cancelling stops the activity sweep", not loading.progress_bar.active)
	loading.free()
	UiTheme.reduced_motion = true
	var still: CanvasLayer = FlightLoading.new()
	check("reduced motion keeps the bar but no live atmosphere", still.progress_bar.reduced_motion
		and still.backdrop.material.get_shader_parameter("live") == 0.0 and is_equal_approx(still.backdrop.color.a, 1.0))
	still.free()
	UiTheme.reduced_motion = false
	for stage: String in WORLD_STAGES:
		check("flight surface knows world stage " + stage, FlightLoading.STAGES.has(stage))
	check("the return-to-Home surface and the startup share one stage order", FlightLoading.HOME_STAGES == Startup.HOME_STAGES)
	var home_surface: CanvasLayer = FlightLoading.new()
	var cancels := [0]
	home_surface.cancel_requested.connect(func() -> void: cancels[0] += 1)
	home_surface.configure_home("Club field")
	home_surface.cancel_button.pressed.emit()
	home_surface.surface.close_requested.emit()
	check("the return-to-Home surface is titled for Home and cannot be cancelled",
		home_surface.title_label.text == TranslationServer.translate("Preparing home…")
		and not home_surface.cancel_button.visible and cancels[0] == 0 and home_surface.summary_label.text == "Club field")
	home_surface.set_stage("Building landscape")
	var home_landscape := FlightLoading.HOME_STAGES.find("Building landscape")
	check("Home stages map onto the Home stage order", is_equal_approx(home_surface.progress_bar.value,
		float(home_landscape) / FlightLoading.HOME_STAGES.size()))
	home_surface.free()


func _renderer_guard_hold_checks() -> void:
	var confirmer: Node = RendererGuard.confirmer_for("")
	var confirmed := [0]
	confirmer.on_stable = func() -> void: confirmed[0] += 1
	check("renderer confirmation is not held by default", not RendererGuard.confirm_hold)
	RendererGuard.confirm_hold = true
	for _frame in RendererGuard.CONFIRM_FRAMES * 2:
		confirmer._process(0.016)
	check("a held confirmer counts no frames while the intro covers Home", confirmer._frames == 0 and confirmed[0] == 0)
	RendererGuard.confirm_hold = false
	confirmer._process(0.016)
	check("released, the confirmer starts a fresh window", confirmer._frames == 1 and confirmed[0] == 0)
	confirmer.free()


func _staged_home_checks() -> void:
	var sync: Node3D = HomeScene.new()
	var staged: Node3D = HomeScene.new(HomeScene.AirplaneBuilder.STIK_ID, HomeScene.FieldLoader.DEFAULT_PATH, {}, {}, {},
		HomeScene.Landscapes.DEFAULT_ID, "", true)
	check("a staged HomeScene only validates in its constructor", staged.field_errors.is_empty()
		and staged.camera == null and staged.get_child_count() == 0)
	var stages: Array[String] = []
	var record := func(stage: String) -> bool:
		stages.append(stage)
		return true
	var built: bool = await staged.build_world_staged(record)
	staged.finish_construction()
	check("the staged world completes and the aircraft and camera follow", built and staged.camera != null
		and not staged.airplane.is_empty() and staged.get_node_or_null("Field") != null)
	var top_level: Array = []
	for stage in stages:
		if WORLD_STAGES.has(stage):
			top_level.append(stage)
	check("World.build_staged reports the stage names the startup expects, in order", top_level == WORLD_STAGES,
		str(top_level))
	for stage: String in WORLD_STAGES:
		check("startup knows world stage " + stage, Startup.HOME_STAGES.has(stage))
	check("the field reports sub-stages between them", stages.size() > WORLD_STAGES.size() + 3, str(stages.size()))
	var sync_tree := _signature(sync)
	var staged_tree := _signature(staged)
	check("staged and synchronous Home build the same node tree", sync_tree == staged_tree,
		"sync=%d staged=%d first difference=%s" % [sync_tree.size(), staged_tree.size(), _first_difference(sync_tree, staged_tree)])
	staged.finish_construction()
	check("a second finish_construction() is ignored",
		staged.get_children().filter(func(child: Node) -> bool: return child is Camera3D).size() == 1)
	sync.free()
	staged.free()
	for landscape: Dictionary in HomeScene.Landscapes.ADAPTERS.map(func(adapter: Variant) -> Dictionary:
			return HomeScene.Landscapes.entry(str(adapter.ID))):
		if landscape.id == HomeScene.Landscapes.DEFAULT_ID:
			continue # compared above, with its stage order
		var plain: Node3D = HomeScene.new(HomeScene.AirplaneBuilder.STIK_ID, landscape.field_path, {}, {}, {}, landscape.id, "")
		var stepped: Node3D = HomeScene.new(HomeScene.AirplaneBuilder.STIK_ID, landscape.field_path, {}, {}, {},
			landscape.id, "", true)
		var stepped_ok: bool = await stepped.build_world_staged(func(_stage: String) -> bool: return true)
		stepped.finish_construction()
		var plain_tree := _signature(plain)
		var stepped_tree := _signature(stepped)
		check("staged and synchronous Home match on " + str(landscape.id), stepped_ok and plain_tree == stepped_tree,
			_first_difference(plain_tree, stepped_tree))
		plain.free()
		stepped.free()
	var cancelled: Node3D = HomeScene.new(HomeScene.AirplaneBuilder.STIK_ID, HomeScene.FieldLoader.DEFAULT_PATH, {}, {}, {},
		HomeScene.Landscapes.DEFAULT_ID, "", true)
	var stop := func(stage: String) -> bool:
		return stage != "Building landscape"
	var completed: bool = await cancelled.build_world_staged(stop)
	cancelled.finish_construction()
	check("a cancelled staged build reports failure and never builds the aircraft", not completed and cancelled.camera == null
		and cancelled.airplane.is_empty())
	cancelled.free()
	await _frames(2)


static func _signature(node: Node) -> Array[String]:
	var result: Array[String] = []
	for child: Node in node.find_children("*", "", true, false):
		var label := str(child.name)
		if label.begins_with("@"):
			label = "@"
		result.append("%s/%s:%s" % [str(node.get_path_to(child.get_parent())), label, child.get_class()])
	result.sort()
	return result


static func _first_difference(a: Array[String], b: Array[String]) -> String:
	for index in mini(a.size(), b.size()):
		if a[index] != b[index]:
			return "%s | %s" % [a[index], b[index]]
	return "length" if a.size() != b.size() else "none"
