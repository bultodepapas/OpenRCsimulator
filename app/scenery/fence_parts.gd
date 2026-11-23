## CR-17a: one fence recipe for visual beams, collision envelopes and local damage IDs.
extends RefCounted
const Palette := preload("res://scenery/palette.gd")

## Points are render X/Z. Each post and each rail/wire bay can fail independently.
static func build(points: PackedVector2Array, style: String, seed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var spacing := 3.0 if style == "wire" else 2.5
	var post := Palette.col("wood_grey") if style == "wire" else Palette.col("wood")
	for segment: int in points.size() - 1:
		var a := points[segment]
		var b := points[segment + 1]
		var length := a.distance_to(b)
		if length <= 1.0e-6:
			continue
		var bays := maxi(1, roundi(length / spacing))
		for at: int in bays + (1 if segment == points.size() - 2 else 0):
			var p := a.lerp(b, float(at) / bays)
			var lean := (Palette.hash01(seed, segment * 1000 + at) - 0.5) * 0.06
			result.append({id = "%02d:post:%02d" % [segment, at], part = "post", profile = "wood",
				a = Vector3(p.x, 0, p.y), b = Vector3(p.x + lean, 1.25 if style == "wire" else 1.15, p.y),
				width = 0.10 if style == "wire" else 0.13, color = post.darkened(0.15 * Palette.hash01(seed, at, segment))})
		var levels: Array = [0.55, 0.85, 1.12] if style == "wire" else [0.45, 0.95]
		for bay: int in bays:
			var start := a.lerp(b, float(bay) / bays)
			var finish := a.lerp(b, float(bay + 1) / bays)
			for level: int in levels.size():
				var height: float = levels[level]
				result.append({id = "%02d:bay:%02d:%d" % [segment, bay, level], part = style,
					profile = "wire" if style == "wire" else "wood", a = Vector3(start.x, height, start.y),
					b = Vector3(finish.x, height, finish.y), width = 0.012 if style == "wire" else 0.08,
					color = Palette.col("steel") if style == "wire" else post.lightened(0.05)})
	return result
