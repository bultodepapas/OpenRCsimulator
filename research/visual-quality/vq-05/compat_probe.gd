# VQ-05 renderer probe (research only, not part of the app): three Compatibility-renderer questions behind the
# propeller blur design. Run from the repository root under a display or Xvfb:
#   xvfb-run -a -s "-screen 0 1280x720x24" "$(app/get-godot.sh)" --path app --rendering-driver opengl3 \
#     --audio-driver Dummy --script "$PWD/research/visual-quality/vq-05/compat_probe.gd" -- --out=/tmp/compat-probe.png
# It prints sampled pixel values:
#   A: three white quads with GeometryInstance3D.transparency 0.0 / 0.5 / 0.9 (identical on Compatibility: ignored);
#   B: a cull-disabled lit quad facing the camera and the same quad turned 180 deg (equal: back faces are lit with
#      the normal flipped);
#   C: a vertex-colour alpha gradient strip wound counter-clockwise as seen by the camera (alpha blends; the strip is
#      lit at ambient only because its winding makes it a back face whose flipped normal points away from the sun).
# 2026-10-12 result on Godot 4.7.2 / llvmpipe: docs/research/visual-quality-implementation/VQ-05/README.md.
extends SceneTree

var _out := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.trim_prefix("--out=")
	_run()

func _quad(parent: Node, pos: Vector3, mat: Material, flip := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	if flip: mi.rotation.y = PI
	parent.add_child(mi)
	return mi

func _run() -> void:
	var r: Window = root
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.0, 0.0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.1, 0.1, 0.1)
	r.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 0, 0) # light from above-front, toward -Z... camera at +Z looks at -Z
	sun.light_energy = 1.0
	r.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 6)
	r.add_child(cam)
	cam.current = true
	# A: opaque white quads with transparency 0, 0.5, 0.9 (left to right)
	for i in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1)
		var mi := _quad(r, Vector3(-2.0 + 2.0 * i, 1.5, 0), m)
		mi.transparency = [0.0, 0.5, 0.9][i]
	# B: lit, cull-disabled quad facing the camera (left) and flipped (right); shading per-pixel
	for i in 2:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.8, 0.8)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_quad(r, Vector3(-1.0 + 2.0 * i, -0.2, 0), m, i == 1)
	# C: vertex-colour alpha disc strip: ArrayMesh with COLOR alpha gradient
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := [Vector3(-1, -1.9, 0), Vector3(1, -1.9, 0), Vector3(1, -1.3, 0), Vector3(-1, -1.3, 0)]
	var cols := [Color(1, 0.8, 0.2, 1.0), Color(1, 0.8, 0.2, 0.0), Color(1, 0.8, 0.2, 0.0), Color(1, 0.8, 0.2, 1.0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(cols[idx]); st.set_normal(Vector3(0, 0, 1)); st.add_vertex(verts[idx])
	var mesh := st.commit()
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cmi := MeshInstance3D.new(); cmi.mesh = mesh; cmi.material_override = cm; r.add_child(cmi)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var img := r.get_texture().get_image()
	var err := img.save_png(_out)
	var w := img.get_width(); var h := img.get_height()
	print("saved ", _out, " err=", err, " size=", w, "x", h, " driver=", RenderingServer.get_current_rendering_driver_name(), " method=", RenderingServer.get_current_rendering_method())
	# sample centres: camera at z=6, fov 75 default; quads at y=1.5 (A row), y=-0.2 (B row), y=-1.6 (C strip)
	var samples := {
		"A_t0.0": cam.unproject_position(Vector3(-2, 1.5, 0)), "A_t0.5": cam.unproject_position(Vector3(0, 1.5, 0)), "A_t0.9": cam.unproject_position(Vector3(2, 1.5, 0)),
		"B_front": cam.unproject_position(Vector3(-1, -0.2, 0)), "B_back": cam.unproject_position(Vector3(1, -0.2, 0)),
		"C_left_a1": cam.unproject_position(Vector3(-0.9, -1.6, 0)), "C_mid": cam.unproject_position(Vector3(0, -1.6, 0)), "C_right_a0": cam.unproject_position(Vector3(0.9, -1.6, 0)),
	}
	for k in samples:
		var p: Vector2 = samples[k]
		var c := img.get_pixel(int(p.x), int(p.y))
		print("%s px=(%d,%d) rgb=(%.3f,%.3f,%.3f)" % [k, int(p.x), int(p.y), c.r, c.g, c.b])
	quit(0)
