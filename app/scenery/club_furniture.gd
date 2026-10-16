## SC-08-R1: fitted outdoor furniture, retained in the existing damage-aware cell mesh.
## Visual dimensions are estimates. Wood049 CC0 colour is sampled into vertex colours.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Wood = preload("res://assets/landscape/flightline/Wood049_1K-JPG_Color.jpg")
static var _wood: Image
const SEGMENTS := 16

static func picnic(k: MeshKit) -> void:
	for i in 5:
		_plank(k, 1.8, 0.142, 0.05, Vector3(0,0.735,-0.304+i*0.152), 0.0, i, Palette.col("wood_light"))
		for x: float in [-0.65,0.65]:
			_bolt(k, Vector3(x,0.7602,-0.304+i*0.152), Vector3.UP, 0.005)
	for side: float in [-1.0,1.0]:
		for i in 2:
			var z := side*0.6 + (float(i)-0.5)*0.131
			_plank(k, 1.8,0.119,0.05,Vector3(0,0.445,z),0.0,6+i+int(side),Palette.col("wood_light"))
			for x: float in [-0.65,0.65]:
				_bolt(k,Vector3(x,0.4702,z),Vector3.UP,0.005)
	for x: float in [-0.65,0.65]:
		for side: float in [-1.0,1.0]:
			k.beam(Vector3(x,0.035,side*0.72),Vector3(x,0.70,side*0.22),0.065,Palette.col("wood"))
			k.box(Vector3(0.075,0.025,0.095),Vector3(x,0.0125,side*0.72),Palette.col("steel_dark"),true)
			_bolt(k,Vector3(x+0.035,0.395,side*0.45),Vector3.RIGHT,0.009)
		k.beam(Vector3(x,0.395,-0.72),Vector3(x,0.395,0.72),0.055,Palette.col("wood_dark"))
		k.beam(Vector3(x,0.68,-0.34),Vector3(x,0.68,0.34),0.06,Palette.col("wood"))
		k.beam(Vector3(0,0.67,0),Vector3(x,0.35,0),0.045,Palette.col("wood"))
	k.beam(Vector3(-0.65,0.32,0),Vector3(0.65,0.32,0),0.06,Palette.col("wood_dark"))


static func bench(k: MeshKit) -> void:
	for i in 3:
		_plank(k,1.8,0.13,0.05,Vector3(0,0.455,-0.145+i*0.145),0.0,i+12,Palette.col("wood_light"))
		for x: float in [-0.76,0.76]:
			_bolt(k,Vector3(x,0.4802,-0.145+i*0.145),Vector3.UP,0.005)
	var angle := -PI*0.5+atan(0.06/0.35)
	var front := Basis(Vector3.RIGHT,angle)*Vector3.UP
	for i in 3:
		var y := 0.554+float(i)*0.117
		var centre := Vector3(0,y,0.22+(y-0.5)/0.35*0.06)
		_plank(k,1.8,0.105,0.035,centre,angle,i+22,Palette.col("wood_light"))
		for x: float in [-0.76,0.76]:
			_bolt(k,centre+Vector3(x,0,0)+front*0.0177,front,0.005)
	for x: float in [-0.76,0.76]:
		for z: float in [-0.15,0.15]:
			k.block(Vector3(0.045,0.415,0.045),Vector3(x,0.008,z),Palette.col("steel_dark"))
			k.box(Vector3(0.10,0.008,0.10),Vector3(x,0.004,z),Palette.col("steel_dark"),true)
			_bolt(k,Vector3(x+0.033,0.008,z),Vector3.UP,0.006)
		k.beam(Vector3(x,0.41,-0.20),Vector3(x,0.41,0.20),0.045,Palette.col("steel_dark"))
		k.beam(Vector3(x,0.40,0.19),Vector3(x,0.825,0.285),0.04,Palette.col("steel_dark"))
		k.beam(Vector3(x,0.17,-0.15),Vector3(x,0.38,0.15),0.025,Palette.col("steel_dark"))
	k.beam(Vector3(-0.76,0.23,0.15),Vector3(0.76,0.23,0.15),0.03,Palette.col("steel_dark"))


## Reuse the filtered source timber for fixed cladding in another local orientation.
static func board(k: MeshKit, length_m: float, width: float, thickness: float,
		centre: Vector3, orientation: Basis, seed: int, tone: Color, segments: int = 4) -> void:
	var saved := k.xf
	k.xf = saved*Transform3D(orientation,centre)
	_plank(k,length_m,width,thickness,Vector3.ZERO,0.0,seed,tone,maxi(1,segments))
	k.xf = saved


static func _plank(k: MeshKit, length_m: float, width: float, thickness: float,
		centre: Vector3, angle: float, seed: int, tone: Color, segments: int = SEGMENTS) -> void:
	var saved := k.xf
	k.xf = saved*Transform3D(Basis(Vector3.RIGHT,angle),centre)
	var bevel := 0.003
	var rings: Array[PackedVector3Array] = []
	for r in range(segments+3):
		var end := r == 0 or r == segments+2
		var x := lerpf(-length_m*0.5+bevel,length_m*0.5-bevel,float(r-1)/segments)
		if end:
			x = -length_m*0.5 if r == 0 else length_m*0.5
		var h := thickness*0.5 - (bevel if end else 0.0)
		var w := width*0.5 - (bevel if end else 0.0)
		var ring := PackedVector3Array()
		for p: Vector2 in [Vector2(h-bevel,-w),Vector2(h,-w+bevel),Vector2(h,w-bevel),Vector2(h-bevel,w),Vector2(-h+bevel,w),Vector2(-h,w-bevel),Vector2(-h,-w+bevel),Vector2(-h+bevel,-w)]:
			ring.append(Vector3(x,p.x,p.y))
		rings.append(ring)
	for r in rings.size()-1:
		for j in 8:
			var next := (j+1)%8
			_face(k,rings[r][next],rings[r+1][next],rings[r+1][j],rings[r][j],tone,seed)
	# Cross-section faces positive X; reverse only the negative-X cap.
	var cap := rings[0]
	cap.reverse()
	k.poly(cap,tone.darkened(0.08))
	k.poly(rings[-1],tone.darkened(0.08))
	k.xf = saved


static func _face(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tone: Color, seed: int) -> void:
	if _wood == null:
		_wood = Wood.get_image()
		# Filter before vertex sampling: no glittering single-texel grain or extra draw.
		_wood.resize(96,64,Image.INTERPOLATE_LANCZOS)
	var first := k.cols.size()
	k.quad(a,b,c,d,tone)
	var points := [a,c,b,a,d,c]
	for i in 6:
		var p: Vector3 = points[i]
		var u := fposmod(p.x/0.8+float(seed)*0.173,1.0)
		var v := fposmod((p.z+p.y*2.0)/0.8+float(seed)*0.319,1.0)
		var sample := _wood.get_pixel(int(u*95),int(v*63))
		var light := (sample.r+sample.g+sample.b)/3.0
		var shade := clampf(1.0+(light-0.39)*3.0,0.78,1.18)
		shade *= 0.91+0.13*float(seed%5)/4.0
		k.cols[first+i] = Color(tone.r*shade,tone.g*shade,tone.b*shade,1.0)


static func _bolt(k: MeshKit, origin: Vector3, normal: Vector3, radius: float) -> void:
	var saved := k.xf
	var axis := Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD
	var tangent := normal.cross(axis).normalized()
	k.xf = saved*Transform3D(Basis(tangent,normal,tangent.cross(normal)),origin)
	k.cylinder(radius*1.3,radius*1.3,0.001,8,Vector3.ZERO,Palette.col("steel"))
	k.cylinder(radius,radius,0.002,6,Vector3.UP*0.001,Palette.col("steel").lightened(0.13))
	k.xf = saved
