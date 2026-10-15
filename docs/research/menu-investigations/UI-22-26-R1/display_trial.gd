extends SceneTree
var app: Node
var output := ""
func _initialize() -> void: run.call_deferred()
func settle() -> void:
 for i in 8: await process_frame
 await create_timer(0.2).timeout
 await RenderingServer.frame_post_draw
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
 app.start_flight()
 await settle()
 app.open_pause()
 app.open_settings()
 await settle()
 var settings=app.screens.get_screen("settings")
 var tick=int(app.flight.session.sim.tick)
 var before=DisplayServer.window_get_size()
 var before_mode=DisplayServer.window_get_mode()
 var start=Time.get_ticks_msec()
 settings._window_mode_selected(1)
 await settle()
 var preview=DisplayServer.window_get_size()
 root.get_texture().get_image().save_webp(output.path_join("borderless-preview.webp"),true)
 await create_timer(15.2).timeout
 await settle()
 var after=DisplayServer.window_get_size()
 var result={"cached_size":str(app._windowed_size),"cached_mode":app._windowed_mode,"before_mode":before_mode,"after_mode":DisplayServer.window_get_mode(),"before":str(before),"preview":str(preview),"after":str(after),"elapsed_ms":Time.get_ticks_msec()-start,"full_monitor":preview==DisplayServer.screen_get_size(),"restored":after==before,"not_persisted":not FileAccess.file_exists(app.preferences_path+".display"),"still_settings":app.screens.is_top("settings"),"flight_held":tick==app.flight.session.sim.tick}
 root.get_texture().get_image().save_webp(output.path_join("automatic-revert.webp"),true)
 var f=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
 f.store_string(JSON.stringify(result,"  "))
 print(result)
 app.free()
 quit()
