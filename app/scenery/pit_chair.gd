## SC-08-R4: folding tubular frame and tensioned cloth in the existing cell batch.
## Visual dimensions are estimates. Fabric001 CC0 is filtered into vertex colours.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Fabric = preload("res://assets/landscape/windsock/Fabric001_1K-JPG_Color.jpg")
const TUBE_RADIAL_SEGMENTS := 4
const CLOTH_EDGE_SEGMENTS := 4
static var _fabric: Image

static func build(k: MeshKit, at: Vector3, yaw: float, seed: int) -> void:
	var saved := k.xf
	k.xf = saved*Transform3D(Basis(Vector3.UP,yaw),at)
	var cloth: Color = Palette.pick([Palette.col("fabric_green"),Palette.col("fabric_blue"),Palette.col("flag_red"),Palette.col("box_black")],seed)
	var frame := Palette.col("steel_dark")
	var rubber := Palette.col("tyre")
	for side: float in [-1.0,1.0]:
		var x := side*0.25
		# Crossing legs are offset sideways so the folding joint has real clearance.
		_tube(k,Vector3(x,0.025,-0.21),Vector3(x,0.45,0.21),0.0125,frame)
		_tube(k,Vector3(x+side*0.027,0.025,0.21),Vector3(x+side*0.027,0.45,-0.21),0.0125,frame)
		for z: float in [-0.21,0.21]:
			var fx := x+(side*0.027 if z>0 else 0.0)
			k.box(Vector3(0.041,0.026,0.055),Vector3(fx,0.013,z),rubber,true)
		_tube(k,Vector3(x,0.44,-0.21),Vector3(x,0.45,0.21),0.0125,frame)
		_tube(k,Vector3(x,0.45,0.21),Vector3(x,0.88,0.296),0.0125,frame)
		_tube(k,Vector3(x,0.88,0.296),Vector3(side*0.22,0.92,0.304),0.0125,frame)
		# Hinge plates, exposed axle and folding stop below the seat.
		k.box(Vector3(0.009,0.074,0.055),Vector3(side*0.29,0.238,0),frame.lightened(0.08),true)
		_tube(k,Vector3(side*0.285,0.238,0),Vector3(side*0.302,0.238,0),0.010,Palette.col("steel"))
		k.beam(Vector3(side*0.277,0.355,-0.116),Vector3(side*0.25,0.355,0.116),0.012,frame.lightened(0.10))
	for side: float in [-1.0,1.0]:
		var half_width := 0.25 if side<0 else 0.277
		_tube(k,Vector3(-half_width,0.085,side*0.1507),Vector3(half_width,0.085,side*0.1507),0.010,frame)
	_tube(k,Vector3(-0.22,0.92,0.304),Vector3(0.22,0.92,0.304),0.0125,frame)
	_tube(k,Vector3(-0.277,0.45,-0.21),Vector3(0.277,0.45,-0.21),0.0125,frame)
	for back: bool in [false,true]:
		_cloth(k,back,cloth,seed)
	k.xf = saved

static func _tube(k: MeshKit, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var axis := (b-a).normalized()
	var across := axis.cross(Vector3.RIGHT if absf(axis.x)<0.9 else Vector3.UP).normalized()
	var saved := k.xf
	k.xf = saved*Transform3D(Basis(across,axis,across.cross(axis)),a)
	k.cylinder(radius,radius,a.distance_to(b),TUBE_RADIAL_SEGMENTS,Vector3.ZERO,color,true,null,true)
	k.xf = saved

static func _point(u: float, v: float, back: bool) -> Vector3:
	var sag := sin(PI*u)*sin(PI*v)
	if back:
		return Vector3(lerpf(-0.24,0.24,u),lerpf(0.49,0.90,v),lerpf(0.22,0.30,v)+0.022*sag)
	return Vector3(lerpf(-0.24,0.24,u),0.45-0.026*sag,lerpf(-0.21,0.21,v))

static func _cloth(k: MeshKit, back: bool, tone: Color, seed: int) -> void:
	if _fabric == null:
		_fabric = Fabric.get_image()
		_fabric.resize(64,64,Image.INTERPOLATE_LANCZOS)
	for row in 3:
		for col in 6:
			var a := _point(col/6.0,row/3.0,back)
			var b := _point((col+1)/6.0,row/3.0,back)
			var c := _point((col+1)/6.0,(row+1)/3.0,back)
			var d := _point(col/6.0,(row+1)/3.0,back)
			var first := k.cols.size()
			k.quad(d,c,b,a,tone)
			k.quad(a,b,c,d,tone.darkened(0.12))
			var points := [d,b,c,d,a,b,a,c,b,a,d,c]
			for i in 12:
				var p: Vector3 = points[i]
				var u := fposmod(p.x*2.0+seed*0.173,1.0)
				var v := fposmod((p.y+p.z)*2.0+seed*0.319,1.0)
				var sample := _fabric.get_pixel(int(u*63),int(v*63))
				var shade := lerpf(0.88,1.08,sample.r)*(0.88 if i>=6 else 1.0)
				k.cols[first+i] = Color(tone.r*shade,tone.g*shade,tone.b*shade,1.0)
	# Double-fold edge binding and sparse stitch marks follow the curved cloth.
	var lift := Vector3(0,0,-0.001) if back else Vector3(0,0.001,0)
	for edge in 4:
		for i in CLOTH_EDGE_SEGMENTS:
			var t0 := float(i)/float(CLOTH_EDGE_SEGMENTS)
			var t1 := float(i+1)/float(CLOTH_EDGE_SEGMENTS)
			var uv0 := Vector2(t0,0) if edge==0 else Vector2(t0,1) if edge==1 else Vector2(0,t0) if edge==2 else Vector2(1,t0)
			var uv1 := Vector2(t1,0) if edge==0 else Vector2(t1,1) if edge==1 else Vector2(0,t1) if edge==2 else Vector2(1,t1)
			var inward := Vector2(0,0.018) if edge==0 else Vector2(0,-0.018) if edge==1 else Vector2(0.018,0) if edge==2 else Vector2(-0.018,0)
			var a := _point(uv0.x,uv0.y,back)+lift
			var b := _point(uv1.x,uv1.y,back)+lift
			var c := _point(uv1.x+inward.x,uv1.y+inward.y,back)+lift
			var d := _point(uv0.x+inward.x,uv0.y+inward.y,back)+lift
			k.quad(a,b,c,d,tone.darkened(0.22))
			k.quad(d,c,b,a,tone.darkened(0.22))
			if i%2==0:
				var stitch_a := a.lerp(b,0.30).lerp(d.lerp(c,0.30),0.35)+lift
				var stitch_b := a.lerp(b,0.60).lerp(d.lerp(c,0.60),0.35)+lift
				var width := (d-a)*0.15
				k.quad(stitch_a,stitch_b,stitch_b+width,stitch_a+width,tone.lightened(0.25))
				k.quad(stitch_a+width,stitch_b+width,stitch_b,stitch_a,tone.lightened(0.25))
