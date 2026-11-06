extends SceneTree

const Original := preload("res://aircraft/extra_300s_model.gd")
const Indexed := preload("res://aircraft/extra_300s_model_indexed.gd")
const PaintAdapter := preload("res://aircraft/procedural_skin.gd")

func _initialize() -> void:
	call_deferred("run")

func one_build(builder: Script) -> int:
	var start := Time.get_ticks_usec()
	var m: Dictionary = builder.build()
	var us := Time.get_ticks_usec() - start
	m.root.free()
	return us

func one_paint(builder: Script) -> int:
	var m: Dictionary = builder.build()
	var start := Time.get_ticks_usec()
	var prepared: Dictionary = PaintAdapter.prepare(PaintAdapter.EXTRA, m.root)
	var us := Time.get_ticks_usec() - start
	if not prepared.ok:
		printerr("BENCH_FAILED: ", prepared.errors)
		quit(1)
	m.root.free()
	return us

func run() -> void:
	for n in 3:
		one_build(Original)
		one_build(Indexed)
	for n in 2:
		one_paint(Original)
		one_paint(Indexed)
	var build := []
	for n in 16:
		var a: int
		var b: int
		if n % 2 == 0:
			a = one_build(Original)
			b = one_build(Indexed)
		else:
			b = one_build(Indexed)
			a = one_build(Original)
		build.append({"original_us": a, "indexed_us": b})
	var paint := []
	for n in 8:
		var a: int
		var b: int
		if n % 2 == 0:
			a = one_paint(Original)
			b = one_paint(Indexed)
		else:
			b = one_paint(Indexed)
			a = one_paint(Original)
		paint.append({"original_us": a, "indexed_us": b})
	print("BENCH_ENV ", JSON.stringify({"engine": Engine.get_version_info(), "os": OS.get_name(), "processor": OS.get_processor_name(), "renderer": RenderingServer.get_rendering_device() != null, "build_warmup_per_role": 3, "paint_warmup_per_role": 2, "build_pairs": build.size(), "paint_pairs": paint.size(), "order": "alternating AB, BA; all elapsed wall times use Time.get_ticks_usec"}))
	print("BENCH_BUILD_PAIRS ", JSON.stringify(build))
	print("BENCH_PAINT_PAIRS ", JSON.stringify(paint))
	print("BENCH_INDEX_DONE")
	quit()
