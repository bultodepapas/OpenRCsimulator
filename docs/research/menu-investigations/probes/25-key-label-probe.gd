# Investigation 25 probe: what the pinned Godot returns when turning a physical (US QWERTY) key into the label the
# player sees, on the headless display server and on a real X11 window under Xvfb with several XKB layouts.
# It reports behaviour; it asserts nothing. Never run it with --path app.
#   D=$(mktemp -d); printf 'config_version=5\n' > "$D/project.godot"
#   cp docs/research/menu-investigations/probes/25-key-label-probe.gd "$D/"
#   G=.tools/Godot_v4.7.2-stable_linux.x86_64; E="XDG_CONFIG_HOME=$D/cfg XDG_DATA_HOME=$D/data"
#   # 1. Headless display server:
#   env $E $G --headless --path "$D" --script res://25-key-label-probe.gd
#   # 2. X11 under Xvfb, one fresh process per layout (setxkbmap before Godot starts):
#   for L in us fr de; do env $E xvfb-run -a -s "-screen 0 640x480x24 -noreset" sh -c "setxkbmap $L && \
#     $G --rendering-driver opengl3 --audio-driver Dummy --path '$D' --script res://25-key-label-probe.gd"; done
#   # 3. X11, hot switch inside one process (the probe runs setxkbmap itself) and a two-group layout us,fr:
#   env $E xvfb-run -a -s "-screen 0 640x480x24 -noreset" $G --rendering-driver opengl3 --audio-driver Dummy --path "$D" \
#     --script res://25-key-label-probe.gd -- --hot=us,fr,de --groups=us,fr
extends SceneTree

const KEYS := [KEY_A, KEY_W, KEY_Q, KEY_Z, KEY_S, KEY_D, KEY_LEFT, KEY_F3, KEY_ESCAPE, KEY_ENTER]


func _initialize() -> void:
	_run()


func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return ""


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _dump(tag: String) -> void:
	var ds := DisplayServer.get_name()
	var n := DisplayServer.keyboard_get_layout_count()
	var cur := DisplayServer.keyboard_get_current_layout()
	var names := []
	for i in n:
		names.append("%s/%s" % [DisplayServer.keyboard_get_layout_name(i), DisplayServer.keyboard_get_layout_language(i)])
	print("[%s] display=%s layouts=%d current=%d %s" % [tag, ds, n, cur, names])
	if ds == "headless":
		# The base DisplayServer prints "ERROR: Not supported by this display server." on each call: show one call only.
		var k := DisplayServer.keyboard_get_label_from_physical(KEY_A)
		print("  headless label(A) -> %d (%s)" % [k, OS.get_keycode_string(k)])
		var names_only := []
		for key in KEYS:
			names_only.append(OS.get_keycode_string(key))
		print("  get_keycode_string(physical) = %s" % [names_only])
		return
	for key in KEYS:
		var label := DisplayServer.keyboard_get_label_from_physical(key)
		var code := DisplayServer.keyboard_get_keycode_from_physical(key)
		print("  phys %-7s label=%-7s (%d)  keycode=%-7s (%d)" % [OS.get_keycode_string(key), OS.get_keycode_string(label),
				label, OS.get_keycode_string(code), code])


func _setxkb(layout: String) -> void:
	var out := []
	var rc := OS.execute("setxkbmap", ["-layout", layout], out, true)
	print("setxkbmap -layout %s -> rc=%d %s" % [layout, rc, "".join(out).strip_edges()])


func _run() -> void:
	await _frames(3)
	_dump("start")
	var hot := _arg("hot")
	if hot != "":
		for layout in hot.split(","):
			_setxkb(layout)
			_dump("hot %s, same frame" % layout)
			await _frames(10)
			_dump("hot %s, +10 frames" % layout)
	var groups := _arg("groups")
	if groups != "":
		_setxkb(groups)
		await _frames(10)
		_dump("groups %s" % groups)
		DisplayServer.keyboard_set_current_layout(1)
		await _frames(10)
		_dump("groups %s after keyboard_set_current_layout(1)" % groups)
	# InputEventKey built by code (what a test can inject): key_label is whatever the test sets; as_text_* only format.
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	print("event phys=W only: as_text=%s | as_text_physical_keycode=%s | as_text_key_label=%s | as_text_keycode=%s" % [
			ev.as_text(), ev.as_text_physical_keycode(), ev.as_text_key_label(), ev.as_text_keycode()])
	ev.key_label = KEY_Z
	print("event phys=W key_label=Z: as_text_key_label=%s" % ev.as_text_key_label())
	quit()
