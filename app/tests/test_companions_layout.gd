## AFC-28: real focus navigation and scroll reachability at supported display/text sizes.
extends SceneTree

const Dialog := preload("res://ui/companions_dialog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")

var failures := 0
var checks := 0
var capture_directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, accepted: bool) -> void:
	checks += 1
	if not accepted:
		failures += 1
		printerr("FAIL ", label)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_directory = argument.trim_prefix("--capture=")
	if not capture_directory.is_empty():
		if DisplayServer.get_name() == "headless" or DirAccess.dir_exists_absolute(capture_directory) \
				or DirAccess.make_dir_recursive_absolute(capture_directory) != OK:
			printerr("Native layout capture needs a renderer and a new directory.")
			quit(2)
			return
	InputMap.load_from_project_settings()
	var ui := UiDriver.new(self)
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for pixels: Vector2i in [Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(3840, 2160)]:
			root.size = pixels
			var sizing: Dictionary = UiScale.apply(root)
			UiTheme.compact_layout = sizing.compact
			for text_scale: float in [1.0, 1.3]:
				UiTheme.text_scale = text_scale
				var dialog := Dialog.new()
				dialog.configure({}, {in_flight = true, active = 3, airborne = 2, requested = 3})
				root.add_child(dialog)
				await ui.settle()
				await ui.settle()
				var label := "%s %s scale %.1f" % [locale, pixels, text_scale]
				var viewport: Rect2 = root.get_visible_rect()
				_check(label + " card fits viewport", viewport.grow(1.0).encloses(dialog.dialog_panel.get_global_rect()))
				_check(label + " readable scroll viewport", dialog._body_scroll.size.y >= 80.0)
				_check(label + " persistent Apply fits viewport", viewport.encloses(dialog.apply_button.get_global_rect()))
				var controls: Array[Control] = [dialog.enabled_check, dialog.count_picker, dialog.seed_edit,
					dialog.volume_slider, dialog.labels_check, dialog.label_distance.get_line_edit(),
					dialog.save_default_check, dialog.remove_button, dialog.cancel_button, dialog.apply_button]
				controls[0].grab_focus()
				await ui.settle()
				for index: int in controls.size():
					var control: Control = controls[index]
					_check(label + " Tab reaches " + control.name, root.gui_get_focus_owner() == control)
					var bounds: Rect2 = dialog._body_scroll.get_global_rect() if index < 8 else viewport
					_check(label + " focused control visible " + control.name,
						bounds.grow(1.0).encloses(control.get_global_rect()))
					if not capture_directory.is_empty() and index == 5 and pixels.x <= 1280:
						await RenderingServer.frame_post_draw
						var image: Image = root.get_texture().get_image()
						_check(label + " capture", image.save_png(capture_directory.path_join(
							"%s-%d-%.1f.png" % [locale, pixels.x, text_scale])) == OK)
					await ui.tap(KEY_TAB)
				root.remove_child(dialog)
				dialog.free()
				await ui.settle()
	UiTheme.text_scale = 1.0
	UiTheme.compact_layout = false
	TranslationServer.set_locale("en")
	print("companion layout: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
