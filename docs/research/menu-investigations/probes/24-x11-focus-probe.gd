# Investigation 24 probe (real X11 window under Xvfb): which focus notifications arrive, in what order and with what
# delay when another X client takes the keyboard focus, and what Input.is_physical_key_pressed(KEY_UP) reads for a key
# held across the focus change. Driven by 24-x11-focus-driver.py (XSetInputFocus + XTEST via ctypes; no WM, no xdotool).
# It reports behaviour; it asserts nothing. Never run it with --path app.
#   D=$(mktemp -d); printf 'config_version=5\n' > "$D/project.godot"
#   cp docs/research/menu-investigations/probes/24-x11-focus-probe.gd "$D/"
#   XDG_CONFIG_HOME="$D/cfg" XDG_DATA_HOME="$D/data" timeout 40 xvfb-run -a -s "-screen 0 640x480x24" sh -c \
#     ".tools/Godot_v4.7.2-stable_linux.x86_64 --rendering-driver opengl3 --audio-driver Dummy --path '$D' \
#      --script res://24-x11-focus-probe.gd -- --wid=$D/wid & \
#      python3 docs/research/menu-investigations/probes/24-x11-focus-driver.py $D/wid; wait"
# Times are wall-clock milliseconds (last 5 digits) so they line up with the driver's log: pipe the output through
# `sort -s -k1,1n` (and `grep -v echo=true` to hide the X server's key repeats). Add --no-autorepeat after the driver's
# argument to turn the X server's key autorepeat off.
extends SceneTree

const NAMES := {2016: "APP_FOCUS_IN", 2017: "APP_FOCUS_OUT", 1004: "WM_WINDOW_FOCUS_IN", 1005: "WM_WINDOW_FOCUS_OUT"}
const LOGGER := """
extends %s
var tag := ""
var cb: Callable
func _notification(what: int) -> void:
	cb.call(tag, what)
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.physical_keycode == KEY_UP:
		cb.call(tag, -1 if e.pressed else -2, e.echo)
"""

var _last_up := false
var _end := 0


static func now() -> String:
	return "%05d" % (int(Time.get_unix_time_from_system() * 1000.0) % 100000)


func _initialize() -> void:
	var wid_file := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wid="):
			wid_file = a.substr(6)
	for base in ["Node3D", "Control"]:
		var s := GDScript.new()
		s.source_code = LOGGER % base
		s.reload()
		var n: Node = ClassDB.instantiate(base)
		n.set_script(s)
		n.set("tag", "Flight(Node3D)" if base == "Node3D" else "Menu(Control)")
		n.set("cb", _on_event)
		if base == "Control":
			var layer := CanvasLayer.new()
			root.add_child(layer)
			layer.add_child(n)
		else:
			root.add_child(n)
	root.focus_entered.connect(func(): print(now(), " root Window signal focus_entered"))
	root.focus_exited.connect(func(): print(now(), " root Window signal focus_exited"))
	var wid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	print(now(), " display=", DisplayServer.get_name(), " x11 window=", wid)
	var f := FileAccess.open(wid_file, FileAccess.WRITE)
	f.store_string(str(wid))
	f.close()
	_end = Time.get_ticks_msec() + 9000


func _on_event(tag: String, what: int, echo := false) -> void:
	if what == -1 or what == -2:
		print(now(), " ", tag, " _input UP ", "pressed" if what == -1 else "released", " echo=", echo)
	elif NAMES.has(what):
		print(now(), " ", tag, " ", NAMES[what], " (UP reads ", Input.is_physical_key_pressed(KEY_UP), ")")


func _process(_delta: float) -> bool:
	var up := Input.is_physical_key_pressed(KEY_UP)
	if up != _last_up:
		print(now(), " poll: is_physical_key_pressed(UP) -> ", up)
		_last_up = up
	return Time.get_ticks_msec() > _end
