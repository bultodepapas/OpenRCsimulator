# Sonda de la investigación 14 (demos oficiales): reproduce en el Godot fijado tres patrones
# tomados de godot-demo-projects@6ad6167 (tag 4.7-6ad6167) sin abrir las demos.
# Ejecutar sin proyecto, fuera de app/:
#   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --script docs/research/menu-investigations/probes/14-demo-patterns-probe.gd
# Imprime líneas "PROBE <clave> = <valor>". Escribe solo en user:// (datos de "[unnamed project]")
# y borra lo que crea.
extends SceneTree

func _p(k: String, v) -> void:
	print("PROBE %s = %s" % [k, v])

func _init() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	_p("version", Engine.get_version_info().string)

	# 1. gui/pseudolocalization: activar en ejecución, sin archivos de traducción.
	var label := Label.new()
	label.text = "Volar"
	root.add_child(label)
	await _frames(2)
	var w0 := label.get_minimum_size().x
	_p("pseudo.tr_before", tr("Volar"))
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.3)
	ProjectSettings.set_setting("internationalization/pseudolocalization/replace_with_accents", true)
	TranslationServer.pseudolocalization_enabled = true
	TranslationServer.reload_pseudolocalization()
	await _frames(2)
	_p("pseudo.tr_after", tr("Volar"))
	_p("pseudo.label_min_width_before", w0)
	_p("pseudo.label_min_width_after", label.get_minimum_size().x)
	root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	await _frames(2)
	_p("pseudo.label_min_width_after_notify", label.get_minimum_size().x)
	var late := Label.new()
	late.text = "Volar"
	root.add_child(late)
	await _frames(2)
	_p("pseudo.label_created_after_enable_width", late.get_minimum_size().x)
	var long := "Baja el acelerador para habilitar el motor"
	_p("pseudo.long_len_ratio", snappedf(float(tr(long).length()) / long.length(), 0.01))
	TranslationServer.pseudolocalization_enabled = false
	TranslationServer.reload_pseudolocalization()
	label.queue_free()
	late.queue_free()

	# 2. gui/multiple_resolutions y 3d/graphics_settings: dos formas de escalar la UI.
	var full := Control.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(full)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(1280, 720)
	await _frames(2)
	_p("scale.window_size", root.size)
	_p("scale.factor1.control_size", full.size)
	root.content_scale_factor = 2.0
	await _frames(2)
	_p("scale.factor2.control_size", full.size)
	root.content_scale_factor = 1.0
	root.content_scale_size = Vector2i(640, 360) # graphics_settings: "Larger (200%)" = base * 0.5
	await _frames(2)
	_p("scale.size_half.control_size", full.size)
	full.queue_free()

	# 3. Persistencia: ConfigFile (misc/hdr_output) frente a store_var(full_objects) (gui/input_mapping).
	var path := "user://probe14_settings.cfg"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[ui]\nscale=\"grande\"\nautozoom=1\n")
	f.close()
	var cf := ConfigFile.new()
	_p("cfg.load_err", cf.load(path))
	var scale = cf.get_value("ui", "scale", 1.0)
	_p("cfg.tampered_scale_type", type_string(typeof(scale)))
	_p("cfg.tampered_autozoom_type", type_string(typeof(cf.get_value("ui", "autozoom", true))))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	var vpath := "user://probe14_keymap.dat"
	var vf := FileAccess.open(vpath, FileAccess.WRITE)
	vf.store_var({"throttle_up": ev}, true)
	vf.close()
	_p("store_var.one_key_bytes", FileAccess.get_file_as_bytes(vpath).size())
	vf = FileAccess.open(vpath, FileAccess.READ)
	_p("store_var.read_without_objects", vf.get_var(false))
	vf.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vpath))
	var cf2 := ConfigFile.new()
	cf2.set_value("keys", "throttle_up", ev)
	_p("cfg.event_as_text_len", cf2.encode_to_text().length())
	var cf3 := ConfigFile.new()
	_p("cfg.parse_object_err", cf3.parse(cf2.encode_to_text()))
	var back = cf3.get_value("keys", "throttle_up", null)
	_p("cfg.parse_object_class", back.get_class() if back is Object else type_string(typeof(back)))
	quit()
