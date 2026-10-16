# UI-23-R4: real Control geometry across aspect ratios, text sizes and live reflow.
extends SceneTree
const ThemeSpec = preload("res://ui/ui_theme.gd")
var vp: SubViewport
var records: Array = []
var checks := 0
const Scale = preload("res://ui/ui_scale.gd")
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for f in 6: await process_frame
func run() -> void:
	vp = SubViewport.new()
	root.add_child(vp)
	for lang in ["en", "es"]:
		TranslationServer.set_locale(lang)
		for scale in [1.0, 2.0]:
			ThemeSpec.text_scale = scale
			for route in ["settings", "help", "failures", "random", "workshop", "overlays"]:
				vp.size = Vector2i(1920,1080)
				ThemeSpec.compact_layout = false
				var screen: CanvasLayer
				var manager: CanvasLayer
				match route:
					"settings": screen = load("res://ui/settings_screen.gd").new()
					"help": screen = load("res://ui/help_screen.gd").new()
					"failures": screen = load("res://ui/failures_menu.gd").new({})
					"random": screen = load("res://ui/natural_random_screen.gd").new()
					"workshop": screen = load("res://ui/workshop.gd").new()
					"overlays":
						manager = load("res://render/overlays/overlay_manager.gd").new()
						screen = load("res://ui/overlays_dialog.gd").new(manager)
				if route == "random": screen.set_repeat_available(true)
				vp.add_child(screen)
				await settle()
				for pixels in [Vector2i(1920,1080),Vector2i(960,540),Vector2i(1024,576),Vector2i(1024,768),Vector2i(1280,720),Vector2i(1280,800),Vector2i(1366,768),Vector2i(1600,900),Vector2i(1920,1200),Vector2i(2560,1440),Vector2i(3440,1440),Vector2i(3840,2160),Vector2i(2560,1080),Vector2i(1920,1080)]:
					var dimensions: Vector2i = Scale.logical_size_for(pixels)
					vp.size = dimensions
					ThemeSpec.compact_layout = dimensions.x < 1500 or dimensions.y < 850
					screen.get_child(0).theme = ThemeSpec.build()
					await settle()
					var pages: Array = ["default"]
					if route == "settings": pages = [0,1,2]
					if route == "failures": pages = ["settings","availability"]
					if route == "random": pages = ["default", "error"]
					for page in pages:
						if route == "settings": screen._show_category(page)
						if route == "failures": screen.call("_show_" + str(page))
						if route == "random":
							if page == "error": screen.show_error("Could not prepare random flight: candidate rejected")
							else: screen.set_scenario({})
						await settle()
						checks += 1
						var issues: Array = []
						walk(screen,Rect2(Vector2.ZERO,Vector2(dimensions)),issues)
						if not issues.is_empty(): records.append({"route":route,"page":page,"lang":lang,"scale":scale,"size":str(dimensions),"issues":issues})
				print("checked ",lang," ",scale," ",route)
				screen.free()
				if manager != null: manager.free()
	for result in records:
		printerr("FAIL responsive ",JSON.stringify(result))
	print("Responsive modals: %d cases, %d failures" % [checks,records.size()])
	quit(0 if records.is_empty() else 1)

func walk(node: Node, bounds: Rect2, issues: Array, in_scroll := false) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Control and not (node is ScrollBar):
		var rect: Rect2 = node.get_global_rect()
		if rect.position.x < -1 or rect.end.x > bounds.end.x+1 or (not in_scroll and (rect.position.y < -1 or rect.end.y > bounds.end.y+1)):
			issues.append({"node":str(node.get_path()),"rect":str(rect),"min":str(node.get_combined_minimum_size())})
		if node is ScrollContainer:
			for content in node.get_children():
				if content is Control and not content is ScrollBar and content.size.x > node.size.x + 1:
					issues.append({"wide_scroll_content":str(node.get_path()),"width":content.size.x,"scroll_width":node.size.x})
			if node.size.y < 60: issues.append({"collapsed_scroll":str(node.get_path()),"height":node.size.y})
			in_scroll = true
	for child in node.get_children(): walk(child,bounds,issues,in_scroll)
