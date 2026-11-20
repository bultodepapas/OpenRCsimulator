extends SceneTree
## Audit 2026-11-19 F28: reordering a full sky-layer set rebinds retained tiles instead of cascading evictions and
## rebakes. Counts use the cache's own bake serial and tile set; synthetic images exercise state transitions only.
const Atmosphere := preload("res://render/atmosphere.gd")
const Cache := preload("res://render/cloud_shadow_map.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", str(detail))


func _image(seed: int) -> Image:
	var image := Image.create_empty(Cache.SIZE, Cache.SIZE, false, Image.FORMAT_RGH)
	for index in Cache.SAMPLE_COUNT:
		var point: Vector2i = Cache._sample_point(index)
		image.set_pixel(point.x, point.y, Cache._reference_sample(seed, point))
	return image


func _ready_all(seeds: Array) -> void:
	for seed: int in seeds:
		Cache._complete_bake(self, seed, _image(seed), "")


func _reset(keys: Array) -> void:
	for key: String in keys:
		OS.set_environment(key, "0")
	Cache.diagnostics()
	for key: String in keys:
		OS.set_environment(key, "1")


## One apply_sky: bakes started, tiles admitted and tiles evicted (by seed).
func _transition(mat: ShaderMaterial, seeds: Array) -> Dictionary:
	var before: Array = Cache._tiles.keys()
	var serial: int = Cache._bake_serial
	Cache.apply_sky(mat, seeds)
	var evicted: Array = []
	for key: int in before:
		if not Cache._tiles.has(key):
			evicted.append(key)
	var admitted: Array = []
	for key: int in Cache._tiles.keys():
		if not before.has(key):
			admitted.append(key)
	return {bakes = Cache._bake_serial - serial, evicted = evicted, admitted = admitted}


func _keys_are(expected: Array) -> bool:
	var actual: Array = Cache._tiles.keys()
	actual.sort()
	var want := expected.duplicate()
	want.sort()
	return actual == want


func _run() -> void:
	var keys := [Cache.ENVIRONMENT_KEY, Cache.GROUND_ENVIRONMENT_KEY, Cache.SKY_ENVIRONMENT_KEY]
	var old := {}
	for key: String in keys:
		old[key] = OS.get_environment(key)
		OS.set_environment(key, "1")
	var a := 710001
	var b := 710002
	var c := 710003
	var d := 710004
	var e := 710005
	var f := 710006
	var g := 710007
	var h := 710008
	var sky := ShaderMaterial.new()
	sky.shader = Atmosphere.SKY_SHADER

	# Full-capacity shift [A,B,C,D] -> [E,A,B,C].
	Cache.apply_sky(sky, [a, b, c, d])
	_ready_all([a, b, c, d])
	check("setup: four ready tiles fill the cache", Cache._tiles.size() == Cache.MAX_TILES and _keys_are([a, b, c, d])
		and Cache.baked(a) and Cache.baked(b) and Cache.baked(c) and Cache.baked(d))
	var texture_a: Variant = Cache._tiles[a].texture
	var texture_b: Variant = Cache._tiles[b].texture
	var texture_c: Variant = Cache._tiles[c].texture
	var step := _transition(sky, [e, a, b, c])
	check("shift admits and bakes exactly E", step.bakes == 1 and step.admitted == [e], step)
	check("shift evicts exactly D", step.evicted == [d] and _keys_are([e, a, b, c]), step)
	check("retained tiles keep their ready textures (no evict-and-rebake)",
		Cache._tiles[a].status == "ready" and Cache._tiles[a].texture == texture_a
		and Cache._tiles[b].texture == texture_b and Cache._tiles[c].texture == texture_c)
	check("slot 0 waits analytically on E", str(Cache._tiles[e].status) == "pending"
		and sky.get_shader_parameter(Cache._slot_parameter(0, "_enabled")) != true)
	check("slots 1-3 bind the retained A, B, C immediately",
		sky.get_shader_parameter(Cache._slot_parameter(1, "")) == texture_a
		and sky.get_shader_parameter(Cache._slot_parameter(1, "_enabled")) == true
		and sky.get_shader_parameter(Cache._slot_parameter(2, "")) == texture_b
		and sky.get_shader_parameter(Cache._slot_parameter(3, "")) == texture_c)

	# A pure permutation of the same set starts nothing.
	step = _transition(sky, [c, b, a, e])
	check("permutation starts no bake and changes no tile", step.bakes == 0 and step.admitted.is_empty()
		and step.evicted.is_empty() and _keys_are([a, b, c, e]), step)
	check("permuted bindings follow the new slots", sky.get_shader_parameter(Cache._slot_parameter(0, "")) == texture_c
		and sky.get_shader_parameter(Cache._slot_parameter(2, "")) == texture_a)

	# Partial overlap evicts only the tile outside the new set (the pending E).
	step = _transition(sky, [f, c, b, a])
	check("overlap admits F and evicts only the unowned pending E",
		step.bakes == 1 and step.admitted == [f] and step.evicted == [e] and _keys_are([f, c, b, a]), step)
	check("retained overlap tiles are untouched", Cache._tiles[a].texture == texture_a
		and Cache._tiles[b].texture == texture_b and Cache._tiles[c].texture == texture_c)

	# Rapid synchronous changes cost one bake and one eviction per step, within capacity.
	var token_f: int = Cache._tiles[f].token
	var serial_before: int = Cache._bake_serial
	step = _transition(sky, [g, f, c, b])
	check("rapid step 1 is one bake, one eviction", step.bakes == 1 and step.evicted == [a], step)
	step = _transition(sky, [h, g, f, c])
	check("rapid step 2 is one bake, one eviction", step.bakes == 1 and step.evicted == [b], step)
	check("rapid changes stay bounded and keep pending bakes alive",
		Cache._bake_serial - serial_before == 2 and Cache._tiles.size() == Cache.MAX_TILES
		and _keys_are([h, g, f, c]) and Cache._tiles[f].token == token_f)

	# Another owner (ground) holding D keeps it; the sky shift must not cascade.
	_reset(keys)
	Cache.apply_sky(sky, [a, b, c, d])
	_ready_all([a, b, c, d])
	var ground := ShaderMaterial.new()
	ground.shader = Atmosphere.GROUND_SHADER
	Cache.apply(ground, d)
	texture_a = Cache._tiles[a].texture
	step = _transition(sky, [e, a, b, c])
	check("a tile owned by ground blocks admission without any eviction or rebake",
		step.bakes == 0 and step.admitted.is_empty() and step.evicted.is_empty() and _keys_are([a, b, c, d])
		and str(Cache._consumers[sky.get_instance_id()].status) == "capacity", step)
	check("the capacity layer stays analytic while retained layers stay bound",
		sky.get_shader_parameter(Cache._slot_parameter(0, "_enabled")) != true
		and sky.get_shader_parameter(Cache._slot_parameter(1, "")) == texture_a
		and sky.get_shader_parameter(Cache._slot_parameter(1, "_enabled")) == true)
	Cache.clear_ground(ground)
	step = _transition(sky, [e, a, b, c])
	check("once ground releases D the waiting layer admits E exactly once",
		step.bakes == 1 and step.admitted == [e] and step.evicted == [d] and _keys_are([e, a, b, c]), step)

	for frame in (Cache.BAKE_FRAMES + 2) * Cache.MAX_ATTEMPTS + 3:
		await process_frame
	_reset(keys)
	for key: String in keys:
		OS.set_environment(key, old[key])
	print("cloud shadow reorder: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
