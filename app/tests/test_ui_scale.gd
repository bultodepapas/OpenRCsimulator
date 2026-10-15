extends SceneTree
const Scale = preload("res://ui/ui_scale.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
 Scale.apply(root)
 for pixels in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(1920,1200),Vector2i(3440,1440),Vector2i(1024,576)]:
  root.size = pixels
  await process_frame
  await process_frame
  var logical=root.get_visible_rect().size
  var scale=Scale.automatic_factor(pixels)
  var expected=Vector2(pixels)/scale
  var ok=logical.is_equal_approx(expected) and root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
  print("ok   " if ok else "FAIL ",pixels," logical=",logical," auto=",scale)
  if not ok: failures+=1
 quit(1 if failures else 0)
