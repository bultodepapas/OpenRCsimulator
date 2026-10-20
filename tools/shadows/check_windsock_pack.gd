## Mount an export in an empty project and construct its moving windsock caster.
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("Expected one PCK path")
		quit(1)
		return
	_check.call_deferred()

func _check() -> void:
	var clock: Variant = load("res://render/shader_clock.gd")
	var loader: Variant = load("res://data/field_loader.gd")
	var builder: Variant = load("res://render/windsock.gd")
	var shadows: Variant = load("res://render/field_projected_shadows.gd")
	clock.register()
	var loaded: Dictionary = loader.load_from()
	if not loaded.get("ok", false):
		quit(1)
		return
	var cue: Dictionary = loaded.field.flight_cues.filter(func(c: Dictionary) -> bool: return c.type == "windsock")[0]
	var world := Node3D.new()
	root.add_child(world)
	var sock: Node3D = builder.build(cue)
	world.add_child(sock)
	shadows.attach(world, {flight_cues = [cue]}, {})
	var manager: Node = world.get_node_or_null("ProjectedFieldShadows")
	var okay: bool = manager != null and manager.projectors.size() == 1 \
		and manager.projectors[0].viewport.size == Vector2i(512, 512) \
		and load("res://render/windsock_deformation.gdshaderinc") is ShaderInclude \
		and load("res://render/windsock_shadow_mask.gdshader") is Shader
	print("Packaged windsock shader include, mask and 512² caster: " + ("PASS" if okay else "FAIL"))
	world.free()
	await process_frame
	quit(0 if okay else 1)
