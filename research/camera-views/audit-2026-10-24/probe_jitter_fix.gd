# CAM-AUD-2026-10-24 probe: does physics_jitter_fix bend the presented (interpolated) time away from the wall clock?
# Presented time is built as main.gd does: last tick minus one step plus get_physics_interpolation_fraction() steps.
# Run from the repository root (repeat; the VM clock is noisy):
#   godot --headless --path app --script "$PWD/research/camera-views/audit-2026-10-24/probe_jitter_fix.gd" -- --fix=0.5 --fps=50 --seconds=5
extends SceneTree

var _fix := 0.5
var _fps := 60
var _seconds := 6.0
var _ticks := 0
var _rows: Array = []
var _start_usec := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() == 2:
			match kv[0]:
				"fix": _fix = float(kv[1])
				"fps": _fps = int(kv[1])
				"seconds": _seconds = float(kv[1])
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 12
	Engine.physics_jitter_fix = _fix
	Engine.max_fps = _fps
	_start_usec = Time.get_ticks_usec()


func _physics_process(_delta: float) -> bool:
	_ticks += 1
	return false


func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	# Presented time, as main.gd builds it: last tick time minus one step plus the fraction of a step.
	var step := 1.0 / 240.0
	var presented := (_ticks - 1) * step + Engine.get_physics_interpolation_fraction() * step
	_rows.append([now, delta, presented])
	if (now - _start_usec) * 1e-6 > _seconds:
		_report()
		quit(0)
	return false


func _report() -> void:
	# Skip the first second (start-up hitches). Compare presented-time steps with wall-clock steps and with delta.
	var errs_wall: Array = []
	var errs_delta: Array = []
	var off: Array = []
	var base_wall := 0.0
	var base_pres := 0.0
	var first := true
	for i in range(1, _rows.size()):
		if (_rows[i][0] - _start_usec) * 1e-6 < 1.0:
			continue
		var dwall: float = (_rows[i][0] - _rows[i - 1][0]) * 1e-6
		var dpres: float = _rows[i][2] - _rows[i - 1][2]
		errs_wall.append(dpres - dwall)
		errs_delta.append(dpres - float(_rows[i][1]))
		if first:
			base_wall = _rows[i][0] * 1e-6
			base_pres = _rows[i][2]
			first = false
		off.append((_rows[i][2] - base_pres) - (_rows[i][0] * 1e-6 - base_wall))
	print("jitter_fix=%.2f fps=%d frames=%d  |Δpresented−Δwall| rms %.3f ms max %.3f ms   |Δpresented−delta| rms %.3f ms max %.3f ms   drift presented−wall range %.2f ms" % [
		_fix, _fps, errs_wall.size(), _rms(errs_wall) * 1e3, _maxabs(errs_wall) * 1e3, _rms(errs_delta) * 1e3,
		_maxabs(errs_delta) * 1e3, (off.max() - off.min()) * 1e3])


static func _rms(values: Array) -> float:
	var s := 0.0
	for v: float in values:
		s += v * v
	return sqrt(s / maxf(1.0, values.size()))


static func _maxabs(values: Array) -> float:
	var m := 0.0
	for v: float in values:
		m = maxf(m, absf(v))
	return m
