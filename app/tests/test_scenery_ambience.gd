# SCENERY-PLAN SC-19a: the synthesised ambience is deterministic, quiet, seamless at its loop point and pausable.
# Tested on the samples, like engine_sound.gd: no sound card needed.
# Run: godot --headless --path . --script res://tests/test_scenery_ambience.gd
extends SceneTree

const Ambience = preload("res://scenery/ambience.gd")
const AmbiencePlayer = preload("res://scenery/ambience_player.gd")


class SynthesisCounter extends RefCounted:
	var calls := 0


class CountingPlayer extends "res://scenery/ambience_player.gd":
	var counter: SynthesisCounter

	func _synthesize(seed: int) -> AudioStreamWAV:
		counter.calls += 1
		var bytes := PackedByteArray()
		bytes.resize(4)
		bytes.encode_s16(0, seed)
		bytes.encode_s16(2, -seed)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 22050
		wav.data = bytes
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = 2
		return wav

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _render_on_worker(player: Node, seed: int) -> void:
	var task := WorkerThreadPool.add_task(Callable(player, "_render").bind(seed), false, "ambience cache test")
	_check("worker completed", WorkerThreadPool.wait_for_task_completion(task) == OK)


func _cache_checks() -> void:
	var counter := SynthesisCounter.new()
	var players: Array[CountingPlayer] = []
	for _i in 5:
		var player := CountingPlayer.new()
		player.counter = counter
		players.append(player)
	_render_on_worker(players[0], 1234)
	_render_on_worker(players[1], 1234)
	_check("same seed is synthesized once", counter.calls == 1, "calls=%d" % counter.calls)
	var original: PackedByteArray = players[1]._wav.data
	_check("players own separate streams with identical PCM", players[0]._wav != players[1]._wav
		and players[0]._wav.data == original)
	players[0]._wav.data = PackedByteArray([0, 0])
	players[0]._wav.loop_begin = 1
	_render_on_worker(players[2], 1234)
	_check("mutating one player cannot change another or the cache", players[1]._wav.data == original
		and players[2]._wav.data == original and players[1]._wav.loop_begin == 0 and players[2]._wav.loop_begin == 0)
	_check("the repeat still needs only one synthesis", counter.calls == 1, "calls=%d" % counter.calls)
	_render_on_worker(players[3], 4321)
	_check("a different seed is synthesized separately", counter.calls == 2 and players[3]._wav.data != original,
		"calls=%d" % counter.calls)
	_render_on_worker(players[4], 1234)
	_check("the bounded cache evicts the earlier seed", counter.calls == 3 and players[4]._wav.data == original,
		"calls=%d" % counter.calls)
	for player in players:
		player.free()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := Ambience.samples(1253)
	var b := Ambience.samples(1253)
	var c := Ambience.samples(77)
	_check("one loop is RATE × LOOP_S samples", a.size() == Ambience.RATE * Ambience.LOOP_S)
	_check("the same seed gives the same samples", a == b)
	_check("another seed gives other samples", a != c)
	var peak := 0
	var sum2 := 0.0
	for v: int in a:
		peak = maxi(peak, absi(v))
		sum2 += float(v) * v
	var rms := sqrt(sum2 / a.size()) / 32768.0
	_check("normalised to −6 dBFS (peak %d)" % peak, absi(peak - 16384) <= 2)
	_check("a bed, not silence nor noise blast (RMS %.3f FS)" % rms, rms > 0.02 and rms < 0.25)
	# Seam: the last sample flows into the first like any neighbouring pair does.
	var typical := 0.0
	for i in range(1, 2000):
		typical = maxf(typical, absf(float(a[i] - a[i - 1])))
	var seam := absf(float(a[0] - a[a.size() - 1]))
	_check("the loop point is seamless (step %d ≤ the largest of 2000 neighbouring steps, %d)" % [seam, typical], seam <= typical)
	var wav := Ambience.stream(1253)
	_check("a looping 16-bit mono stream", wav.format == AudioStreamWAV.FORMAT_16_BITS and not wav.stereo and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == a.size())
	var p := Ambience.player(1253)
	_check("the player is quiet and pausable", p.volume_db <= -12.0 and p.process_mode == Node.PROCESS_MODE_PAUSABLE)
	p.free()
	_cache_checks()
	var actual := AmbiencePlayer.new()
	_render_on_worker(actual, 1253)
	_check("worker stream exactly preserves the public producer's PCM and loop", actual._wav.data == wav.data
		and actual._wav.format == wav.format and actual._wav.mix_rate == wav.mix_rate
		and actual._wav.stereo == wav.stereo and actual._wav.loop_mode == wav.loop_mode
		and actual._wav.loop_begin == wav.loop_begin and actual._wav.loop_end == wav.loop_end)
	var warmed := AmbiencePlayer.new()
	_render_on_worker(warmed, 1253)
	_check("real warm player owns a distinct stream with the exact PCM and loop", warmed._wav != actual._wav
		and warmed._wav.data == wav.data and warmed._wav.format == wav.format and warmed._wav.mix_rate == wav.mix_rate
		and warmed._wav.stereo == wav.stereo and warmed._wav.loop_mode == wav.loop_mode
		and warmed._wav.loop_begin == wav.loop_begin and warmed._wav.loop_end == wav.loop_end)
	actual.free()
	warmed.free()
	await _lifecycle_checks()
	print("all scenery ambience checks passed" if _failures == 0 else "%d scenery ambience checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _lifecycle_checks() -> void:
	var counter := SynthesisCounter.new()
	var cold := CountingPlayer.new()
	cold.counter = counter
	cold.set_meta("seed", 2468)
	root.add_child(cold)
	_check("entering the tree starts a worker", cold._task >= 0)
	root.remove_child(cold)
	_check("immediate removal joins the cold worker", cold._task == -1 and cold._wav != null and counter.calls == 1)
	root.add_child(cold)
	_check("a detached cold player starts after re-entering", await _wait_for_playback(cold) and counter.calls == 1)
	var warm := CountingPlayer.new()
	warm.counter = counter
	warm.set_meta("seed", 2468)
	root.add_child(warm)
	_check("warm player publishes and plays the cached loop", await _wait_for_playback(warm)
		and not warm.is_processing() and counter.calls == 1)
	_check("scene players retain independent streams", warm.stream != cold._wav and warm._wav.data == cold._wav.data)
	root.remove_child(warm)
	root.add_child(warm)
	_check("a previously playing player resumes after re-entering", await _wait_for_playback(warm) and counter.calls == 1)
	warm.stop()
	warm.stream = null
	root.remove_child(warm)
	warm.free()
	cold.stop()
	cold.stream = null
	root.remove_child(cold)
	cold.free()
	await create_timer(0.1).timeout # let the dummy audio mixer release the stopped playback


func _wait_for_playback(player: CountingPlayer) -> bool:
	for _i in 500:
		if player._task < 0 and player.stream != null and player.playing:
			return true
		await create_timer(0.001).timeout
	return false
