## SC-08-R3: fitted cladding and weatherproof details for the existing storage shed.
## Dimensions are artistic estimates; all parts remain in the opaque scenery cell.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Timber = preload("res://scenery/club_furniture.gd")

static func build(k: MeshKit) -> void:
	var wood := Palette.col("wood_grey")
	var trim := wood.lightened(0.28)
	k.block(Vector3(3.04,0.08,2.44),Vector3.ZERO,Palette.col("concrete_dark"))
	k.block(Vector3(3.0,2.1,2.4),Vector3.ZERO,wood.darkened(0.24))
	for side: float in [-1.0,1.0]:
		var face := Basis(Vector3.UP,Vector3(0,0,side),Vector3(side,0,0))
		for i in 18:
			var x := -1.416667+i/6.0
			if side < 0 and x > 0.09 and x < 1.11:
				continue
			Timber.board(k,1.98,0.157,0.028,Vector3(x,1.07,side*1.213),face,i+int(side)*19,wood)
		face = Basis(Vector3.UP,Vector3(side,0,0),Vector3(0,0,-side))
		for i in 14:
			Timber.board(k,1.98,0.162,0.028,Vector3(side*1.513,1.07,-1.114286+i*2.4/14.0),face,40+i+int(side)*17,wood)
		for z: float in [-1.2,1.2]:
			k.box(Vector3(0.075,1.98,0.075),Vector3(side*1.488,1.07,z),trim)
		# Metal shoes protect the end grain at the damp base of each corner.
		for z: float in [-1.2,1.2]:
			k.box(Vector3(0.078,0.12,0.078),Vector3(side*1.488,0.14,z),Palette.col("steel_dark"))
	_door(k,trim)
	for side: float in [-1.0,1.0]:
		_vent(k,side,trim)
	_roof(k,trim)

static func _door(k: MeshKit, trim: Color) -> void:
	var paint := Palette.col("door_green").lightened(0.08)
	var metal := Palette.col("steel_dark")
	k.box(Vector3(0.94,1.93,0.055),Vector3(0.6,1.005,-1.242),paint.darkened(0.3))
	for i in 6:
		Timber.board(k,1.84,0.143,0.022,Vector3(0.225+i*0.15,1.005,-1.276),Basis(Vector3.UP,Vector3.FORWARD,Vector3.LEFT),i+71,paint,6)
	for x: float in [0.105,1.095]:
		k.box(Vector3(0.065,1.96,0.075),Vector3(x,1.02,-1.265),trim)
	k.box(Vector3(1.055,0.07,0.095),Vector3(0.6,2.015,-1.272),trim)
	k.box(Vector3(1.08,0.065,0.20),Vector3(0.6,0.0625,-1.28),Palette.col("concrete"))
	for y: float in [0.25,1.76]:
		k.box(Vector3(0.80,0.055,0.028),Vector3(0.6,y,-1.299),paint.lightened(0.08))
	k.beam(Vector3(0.23,0.28,-1.299),Vector3(0.97,1.73,-1.299),0.042,paint.lightened(0.08))
	for y: float in [0.29,1.02,1.72]:
		k.box(Vector3(0.23,0.035,0.016),Vector3(0.25,y,-1.323),metal)
		k.cylinder(0.012,0.012,0.09,8,Vector3(0.145,y-0.045,-1.325),metal)
		for x: float in [0.20,0.32]:
			_screw(k,Vector3(x,y,-1.333))
	k.box(Vector3(0.042,0.15,0.014),Vector3(0.96,1.03,-1.323),metal)
	k.box(Vector3(0.105,0.018,0.03),Vector3(0.927,1.04,-1.348),Palette.col("steel"))
	for y: float in [0.978,1.082]:
		_screw(k,Vector3(0.96,y,-1.333))

static func _screw(k: MeshKit, p: Vector3) -> void:
	var saved := k.xf
	k.xf = saved*Transform3D(Basis(Vector3.RIGHT,-PI*0.5),p)
	k.cylinder(0.0055,0.0055,0.003,6,Vector3.ZERO,Palette.col("steel"))
	k.xf = saved

static func _vent(k: MeshKit, side: float, trim: Color) -> void:
	k.box(Vector3(0.48,0.27,0.025),Vector3(0,2.40,side*1.213),Palette.col("steel_dark"))
	for x: float in [-0.25,0.25]:
		k.box(Vector3(0.035,0.31,0.045),Vector3(x,2.40,side*1.23),trim)
	for y: float in [2.25,2.55]:
		k.box(Vector3(0.53,0.035,0.045),Vector3(0,y,side*1.23),trim)
	for i in 5:
		var saved := k.xf
		k.xf = saved*Transform3D(Basis(Vector3.RIGHT,side*0.38),Vector3(0,2.29+i*0.053,side*1.24))
		k.box(Vector3(0.45,0.025,0.042),Vector3.ZERO,trim.darkened(0.13))
		k.xf = saved

static func _roof(k: MeshKit, trim: Color) -> void:
	var roof := Palette.col("roof_green")
	var metal := Palette.col("steel_dark")
	k.gable_roof(3.0,2.4,2.1,0.75,0.2,roof,Palette.col("wood_grey"))
	for side: float in [-1.0,1.0]:
		for i in 8:
			var z := -1.4+i*0.35
			var a := Vector3(0,2.853,z)
			var b := Vector3(side*1.7,2.003,z)
			var c := b+Vector3(0,0,0.35)
			var d := a+Vector3(0,0,0.35)
			var tone := roof.lightened(0.015*(i%3))
			if side > 0:
				k.quad(d,c,b,a,tone)
			else:
				k.quad(a,b,c,d,tone)
		for i in 9:
			var z := -1.39+i*2.78/8.0
			k.beam(Vector3(0,2.861,z),Vector3(side*1.69,2.016,z),0.014,roof.lightened(0.08))
		# Folded ridge flashing and gable fascia.
		var a := Vector3(0,2.88,-1.4)
		var b := Vector3(side*0.085,2.836,-1.4)
		var c := b+Vector3(0,0,2.8)
		var d := a+Vector3(0,0,2.8)
		if side > 0:
			k.quad(d,c,b,a,roof.lightened(0.06))
		else:
			k.quad(a,b,c,d,roof.lightened(0.06))
		for z: float in [-1.402,1.402]:
			k.beam(Vector3(0,2.839,z),Vector3(side*1.665,2.007,z),0.055,trim)
		# Open U-shaped gutter, rear downpipe and wall clips.
		k.box(Vector3(0.075,0.018,2.78),Vector3(side*1.657,1.956,0),metal)
		for x: float in [1.625,1.69]:
			k.box(Vector3(0.012,0.055,2.78),Vector3(side*x,1.979,0),metal)
		k.cylinder(0.026,0.026,1.77,10,Vector3(side*1.60,0.15,1.29),metal)
		k.beam(Vector3(side*1.60,1.90,1.29),Vector3(side*1.657,1.96,1.29),0.046,metal)
		for y: float in [0.45,1.55]:
			k.box(Vector3(0.13,0.032,0.06),Vector3(side*1.566,y,1.29),Palette.col("steel"))
		k.beam(Vector3(side*1.60,0.17,1.29),Vector3(side*1.60,0.10,1.39),0.046,metal)
