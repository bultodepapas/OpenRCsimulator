extends SceneTree
var app: Node
var output := ""
func _initialize() -> void: run.call_deferred()
func settle() -> void:
 for i in 8: await process_frame
 await create_timer(0.25).timeout
 await RenderingServer.frame_post_draw
func shot(name: String) -> void:
 await settle()
 root.get_texture().get_image().save_webp(output.path_join(name+".webp"),true)
 print("SHOT ",name)
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
 if output.is_empty():
  push_error("--out is required")
  quit(2)
  return
 DirAccess.make_dir_recursive_absolute(output)
 DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,true)
 DisplayServer.window_set_size(Vector2i(1280,720))
 app=load("res://app_root.tscn").instantiate()
 app.user_args=PackedStringArray()
 app.preferences_path=output.path_join("isolated.cfg")
 root.add_child(app)
 await settle()
 app.set_language("es")
 var config=app.display_preferences.config.duplicate(true)
 config.ui_scale=2.0
 app._apply_presentation(config)
 await shot("es-720-200-home")
 for route in ["settings","help","weather","controls"]:
  app.call("open_"+route)
  await shot("es-720-200-"+route)
  app.screens.pop()
 app.start_flight()
 await settle()
 app.open_pause()
 await shot("es-720-200-pause")
 app.free()
 for dimensions in [Vector2i(1024,576),Vector2i(1280,800),Vector2i(1920,1200),Vector2i(3440,1440),Vector2i(3840,2160)]:
  DisplayServer.window_set_size(dimensions)
  app=load("res://app_root.tscn").instantiate()
  app.user_args=PackedStringArray()
  app.preferences_path=output.path_join("aspect-%d.cfg" % dimensions.x)
  root.add_child(app)
  await settle()
  app.set_language("es")
  if dimensions.x == 3840:
   config.ui_scale=2.0
   app._apply_presentation(config)
  await shot("es-%dx%d-home" % [dimensions.x,dimensions.y])
  app.open_settings()
  await shot("es-%dx%d-settings" % [dimensions.x,dimensions.y])
  app.screens.pop()
  app.start_flight()
  await settle()
  app.open_pause()
  await shot("es-%dx%d-pause" % [dimensions.x,dimensions.y])
  app.free()
 quit()
