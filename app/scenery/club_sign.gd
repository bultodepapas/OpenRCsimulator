## SC-08-R2: fitted club identity board. Artistic joinery inside the existing catalog envelope.
## Letter contours reuse Godot's bundled font and join the existing opaque cell mesh.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
static var _letter_cache: Dictionary = {}

static func build(k: MeshKit) -> void:
	var trim := Palette.col("trim").darkened(0.10)
	var steel := Palette.col("steel_dark")
	for x: float in [-1.0,1.0]:
		_bevel_box(k,Vector3(0.20,0.04,0.14),Vector3(x,0.02,0),0.005,Palette.col("concrete"))
		_bevel_box(k,Vector3(0.17,0.008,0.125),Vector3(x,0.044,0),0.002,steel)
		_bevel_box(k,Vector3(0.12,2.125,0.09),Vector3(x,1.1105,0.015),0.004,Palette.col("wood"))
		_bevel_box(k,Vector3(0.128,0.15,0.128),Vector3(x,0.123,0),0.003,steel)
		_bevel_box(k,Vector3(0.14,0.027,0.14),Vector3(x,2.1865,0),0.004,steel)
		for y: float in [0.085,0.165]:
			_bolt(k,Vector3(x,y,-0.065),Vector3.FORWARD,0.007)
	# Enamel panel with four-sided protective trim, inside the original 2.5 m width.
	_bevel_box(k,Vector3(2.40,1.10,0.024),Vector3(0,1.55,-0.05),0.006,Palette.col("sign_board"))
	for y: float in [0.97,2.13]:
		_bevel_box(k,Vector3(2.50,0.06,0.12),Vector3(0,y,-0.01),0.004,trim)
	for x: float in [-1.22,1.22]:
		_bevel_box(k,Vector3(0.06,1.10,0.12),Vector3(x,1.55,-0.01),0.004,trim)
	# Flat painted graphic geometry is deliberately opaque and merged, not decal nodes.
	k.box(Vector3(2.24,0.045,0.002),Vector3(0,1.18,-0.063),Palette.col("flag_red"),true)
	k.box(Vector3(2.24,0.006,0.002),Vector3(0,1.125,-0.063),trim,true)
	_letters(k,"OPEN RC",Vector3(-0.29,1.77,-0.0635),1.42,0.215,trim)
	_letters(k,"FLIGHT CLUB",Vector3(-0.29,1.48,-0.0635),1.30,0.102,trim)
	k.box(Vector3(0.009,0.59,0.002),Vector3(0.50,1.65,-0.063),trim.darkened(0.25),true)
	_emblem(k,Vector2(0.84,1.68),trim)
	for x: float in [-1.14,1.14]:
		for y: float in [1.055,2.045]:
			_bolt(k,Vector3(x,y,-0.063),Vector3.FORWARD,0.008)
	# Back battens and diagonal strap: visible construction from the pavilion side.
	for y: float in [1.09,2.01]:
		_bevel_box(k,Vector3(2.24,0.055,0.018),Vector3(0,y,0.047),0.002,steel)
	k.beam(Vector3(-1.04,1.14,0.047),Vector3(1.04,1.96,0.047),0.018,steel)
	for x: float in [-1.0,1.0]:
		_bevel_box(k,Vector3(0.15,1.03,0.012),Vector3(x,1.55,0.06),0.002,steel)
		for y: float in [1.10,2.0]:
			_bevel_box(k,Vector3(0.06,0.045,0.095),Vector3(x,y,0.01),0.002,steel)
			_bolt(k,Vector3(x,y,0.066),Vector3.BACK,0.008)


static func _letters(k: MeshKit, text: String, centre: Vector3, max_width: float, max_height: float, color: Color) -> void:
	if not _letter_cache.has(text):
		var mesh := TextMesh.new()
		mesh.font = ThemeDB.fallback_font
		mesh.font_size = 48
		mesh.curve_step = 1.0
		mesh.depth = 0.0
		mesh.text = text
		mesh.language = "en"
		mesh.set_message_translation(false)
		_letter_cache[text] = {arrays = mesh.surface_get_arrays(0), bounds = mesh.get_aabb()}
	var item: Dictionary = _letter_cache[text]
	var arrays: Array = item.arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bounds: AABB = item.bounds
	var scale_m := minf(max_width/bounds.size.x,max_height/bounds.size.y)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for index in indices:
		pos.append((vertices[index]-bounds.get_center())*scale_m)
		nrm.append(normals[index])
		col.append(color)
	k.append_arrays(pos,nrm,col,Transform3D(Basis(Vector3.UP,PI),centre))


static func _emblem(k: MeshKit, centre: Vector2, color: Color) -> void:
	var radius := 0.245
	for i in 40:
		var a := TAU*float(i)/40.0
		var b := TAU*float(i+1)/40.0
		var a0 := centre+Vector2(cos(a),sin(a))*radius
		var a1 := centre+Vector2(cos(a),sin(a))*(radius-0.008)
		var b0 := centre+Vector2(cos(b),sin(b))*radius
		var b1 := centre+Vector2(cos(b),sin(b))*(radius-0.008)
		k.quad(Vector3(a0.x,a0.y,-0.0635),Vector3(a1.x,a1.y,-0.0635),Vector3(b1.x,b1.y,-0.0635),Vector3(b0.x,b0.y,-0.0635),color)
	# Tapered fuselage and swept tips keep the top-view aircraft legible at distance.
	_flat(k,centre,PackedVector2Array([Vector2(-0.025,-0.16),Vector2(0.025,-0.16),Vector2(0.036,0.11),Vector2(0,0.19),Vector2(-0.036,0.11)]),color)
	_flat(k,centre,PackedVector2Array([Vector2(-0.195,0.01),Vector2(0.195,0.01),Vector2(0.17,0.07),Vector2(-0.17,0.07)]),color)
	_flat(k,centre,PackedVector2Array([Vector2(-0.09,-0.15),Vector2(0.09,-0.15),Vector2(0.075,-0.115),Vector2(-0.075,-0.115)]),color)


static func _flat(k: MeshKit, centre: Vector2, points: PackedVector2Array, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(points)
	for i in range(0,triangles.size(),3):
		var a := points[triangles[i]]+centre
		var b := points[triangles[i+1]]+centre
		var c := points[triangles[i+2]]+centre
		k.tri(Vector3(a.x,a.y,-0.064),Vector3(c.x,c.y,-0.064),Vector3(b.x,b.y,-0.064),color)


static func _bolt(k: MeshKit, origin: Vector3, normal: Vector3, radius: float) -> void:
	var saved := k.xf
	var tangent := normal.cross(Vector3.RIGHT).normalized()
	k.xf = saved*Transform3D(Basis(tangent,normal,tangent.cross(normal)),origin)
	k.cylinder(radius*1.4,radius*1.4,0.001,10,Vector3.ZERO,Palette.col("steel"))
	k.cylinder(radius,radius,0.002,6,Vector3.UP*0.001,Palette.col("steel").lightened(0.15))
	k.xf = saved


static func _bevel_box(k: MeshKit, size: Vector3, centre: Vector3, bevel: float, color: Color) -> void:
	var h := size*0.5
	var b := minf(bevel,minf(h.x,minf(h.y,h.z))*0.4)
	var rings: Array[PackedVector3Array] = []
	for r in 4:
		var inset := b if r == 0 or r == 3 else 0.0
		var hx := h.x-inset
		var hz := h.z-inset
		var edge := minf(b,minf(hx,hz)*0.4)
		var y: float = [-h.y,-h.y+b,h.y-b,h.y][r]
		var ring := PackedVector3Array()
		for p: Vector2 in [Vector2(hx-edge,-hz),Vector2(hx,-hz+edge),Vector2(hx,hz-edge),Vector2(hx-edge,hz),Vector2(-hx+edge,hz),Vector2(-hx,hz-edge),Vector2(-hx,-hz+edge),Vector2(-hx+edge,-hz)]:
			ring.append(centre+Vector3(p.x,y,p.y))
		rings.append(ring)
	for r in 3:
		for i in 8:
			var j := (i+1)%8
			k.quad(rings[r][i],rings[r+1][i],rings[r+1][j],rings[r][j],color)
	k.poly(rings[0],color)
	var cap := rings[3]
	cap.reverse()
	k.poly(cap,color)
