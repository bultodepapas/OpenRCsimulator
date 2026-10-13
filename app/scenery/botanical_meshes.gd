## LU-24: original, metre-scale botanical silhouettes. Shared by habitat MultiMeshes.
extends RefCounted

const MeshKit := preload("res://scenery/mesh_kit.gd")
const Palette := preload("res://scenery/palette.gd")
const SPECIES: Array[String] = ["tussock", "oat", "rosette", "clover", "daisy", "buttercup", "poppy", "cornflower", "spike", "wheat", "fieldbean"]


static func mesh(species: String, theme: String, material: Material) -> ArrayMesh:
	var k := MeshKit.new()
	var green := Palette.vegetation(Color("#66784a"), theme)
	var fresh := Palette.vegetation(Color("#80905b"), theme)
	var sage := Palette.vegetation(Color("#819275"), theme)
	match species:
		"tussock", "oat":
			for i in 5:
				var a := float(i) * 2.39996
				var dir := Vector3(cos(a), 0.0, sin(a))
				var height := 0.24 + 0.12 * float(i % 3)
				_blade(k, dir * 0.025, dir, height, 0.018, fresh.lerp(green, float(i) / 6.0))
			if species == "oat":
				for i in 3:
					var head := Vector3(-0.11 + float(i) * 0.10, 0.58 + 0.08 * float(i % 2), 0.04 * float(i % 2))
					_stem(k, Vector3(head.x * 0.3, 0, 0), head, 0.009, green)
					for j in 3:
						var p := head - Vector3(0, float(j) * 0.038, 0)
						_seed_head(k, p, Vector3(0.06 * (-1.0 if j % 2 == 0 else 1.0), -0.035, 0.025), 0.026, Color("#b6b28a"))
		"rosette", "fieldbean":
			for i in (5 if species == "rosette" else 3):
				var a := float(i) * 2.39996
				var h := 0.06 if species == "rosette" else 0.15 + 0.12 * float(i)
				var root := Vector3(0, h, 0)
				_leaf(k, root, Vector3(cos(a) * 0.25, 0.09, sin(a) * 0.25), 0.13, sage if species == "rosette" else fresh)
			if species == "fieldbean":
				_stem(k, Vector3.ZERO, Vector3(0, 0.52, 0), 0.012, green)
		"clover":
			for i in 3:
				var a := float(i) * TAU / 3.0
				var p := Vector3(cos(a) * 0.12, 0.10 + 0.02 * float(i), sin(a) * 0.12)
				for j in 3:
					var b := a + float(j) * TAU / 3.0
					_leaf(k, p, Vector3(cos(b) * 0.075, 0.025, sin(b) * 0.075), 0.07, fresh)
				var head := p + Vector3(0.025, 0.15, 0)
				_stem(k, p, head, 0.009, green)
				_flower(k, head, 6, 0.036, Color("#b38da7"), Color("#d9b7c9"), 0.032)
		"daisy", "buttercup", "poppy", "cornflower":
			var height := 0.42 if species != "poppy" else 0.58
			var head := Vector3(0.055, height, -0.035)
			_stem(k, Vector3.ZERO, head, 0.011, green)
			_leaf(k, Vector3(0.015, height * 0.34, 0), Vector3(0.19, 0.09, 0.10), 0.055, fresh)
			_leaf(k, Vector3(0.026, height * 0.58, 0), Vector3(-0.14, 0.06, -0.05), 0.045, green)
			var petals: int = {daisy = 9, buttercup = 5, poppy = 5, cornflower = 8}[species]
			var colour: Color = {daisy = Color("#ece7db"), buttercup = Color("#dabb48"), poppy = Color("#b64f42"), cornflower = Color("#728bb8")}[species]
			var radius: float = {daisy = 0.092, buttercup = 0.06, poppy = 0.105, cornflower = 0.07}[species]
			_flower(k, head, petals, radius, colour, Color("#c2a14c") if species != "poppy" else Color("#443e36"), 0.025 if species == "poppy" else 0.008)
		"spike":
			var head := Vector3(0.035, 0.70, 0.025)
			_stem(k, Vector3.ZERO, head, 0.012, green)
			for i in 3:
				var a := float(i) * 2.39996
				_leaf(k, head * (0.17 + float(i) * 0.13), Vector3(cos(a) * 0.18, 0.07, sin(a) * 0.18), 0.075, sage)
			for i in 6:
				var a := float(i) * 2.39996
				var p := head - Vector3(0, float(i) * 0.034, 0) + Vector3(cos(a) * 0.025, 0, sin(a) * 0.025)
				_flower(k, p, 3, 0.032, Color("#aa88ad"), Color("#c8a7c5"), 0.018)
		"wheat":
			# Six clustered culms with compact ears; the former pair looked like isolated poles.
			for i in 6:
				var a := float(i) * 2.39996
				var root := Vector3(cos(a) * 0.10, 0, sin(a) * 0.10)
				var top := root + Vector3(cos(a) * 0.045, 0.66 + 0.025 * float(i % 4), sin(a) * 0.025)
				k.tri(root - Vector3(0.008, 0, 0), top, root + Vector3(0.008, 0, 0), Color("#aaa06c"))
				_seed_head(k, top - Vector3(0, 0.035, 0), Vector3(0.012, 0.10, 0.005), 0.035, Color("#c5b580"))
	return k.to_mesh(material)


## Folded leaf: two broad triangles meet on a raised midrib; real geometry catches light.
static func _leaf(k: MeshKit, root: Vector3, reach: Vector3, width: float, colour: Color) -> void:
	var side := Vector3(-reach.z, 0, reach.x).normalized() * width * 0.5
	if side.length_squared() < 1e-8:
		side = Vector3(width * 0.5, 0, 0)
	var middle := root + reach * 0.48
	var ridge := middle + Vector3(0, width * 0.12, 0)
	k.tri(root, middle - side, ridge, colour.darkened(0.04))
	k.tri(root, ridge, middle + side, colour)
	k.tri(ridge, middle - side, root + reach, colour.darkened(0.04))
	k.tri(ridge, root + reach, middle + side, colour)


static func _stem(k: MeshKit, root: Vector3, tip: Vector3, width: float, colour: Color) -> void:
	var side := Vector3(width * 0.5, 0, 0)
	k.quad(root - side, tip - side * 0.4, tip + side * 0.4, root + side, colour)


static func _blade(k: MeshKit, root: Vector3, dir: Vector3, height: float, width: float, colour: Color) -> void:
	var side := Vector3(-dir.z, 0, dir.x) * width
	var middle := root + dir * height * 0.18 + Vector3(0, height * 0.56, 0)
	var tip := root + dir * height * 0.50 + Vector3(0, height, 0)
	k.quad(root - side, middle - side * 0.62, middle + side * 0.62, root + side, colour)
	k.tri(middle - side * 0.62, tip, middle + side * 0.62, colour.lightened(0.06))


static func _flower(k: MeshKit, head: Vector3, petals: int, radius: float, colour: Color, pollen: Color, cup: float) -> void:
	for i in petals:
		var a := TAU * float(i) / float(petals)
		var half_angle := PI / float(petals) * 0.65
		var inner := head + Vector3(cos(a), 0, sin(a)) * radius * 0.25
		var outer := head + Vector3(cos(a) * radius, cup, sin(a) * radius)
		var left := head + Vector3(cos(a - half_angle) * radius * 0.76, cup * 0.6, sin(a - half_angle) * radius * 0.76)
		var right := head + Vector3(cos(a + half_angle) * radius * 0.76, cup * 0.6, sin(a + half_angle) * radius * 0.76)
		k.tri(inner, left, outer, colour)
		k.tri(inner, outer, right, colour.lightened(0.025))
		var next := TAU * float(i + 1) / float(petals)
		k.tri(head + Vector3(0, 0.003, 0), head + Vector3(cos(a), 0, sin(a)) * radius * 0.26,
			head + Vector3(cos(next), 0, sin(next)) * radius * 0.26, pollen)


static func _seed_head(k: MeshKit, root: Vector3, reach: Vector3, width: float, colour: Color) -> void:
	var side := Vector3(-reach.z, 0.0, reach.x).normalized() * width * 0.5
	var middle := root + reach * 0.48
	k.quad(root, middle - side, root + reach, middle + side, colour)
