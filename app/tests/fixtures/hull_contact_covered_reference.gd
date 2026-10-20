## LU-25-R2: original caller methods; unchanged helpers inherited from production.
extends "res://physics/hull_contact.gd"


static func prop_disc_depth(s: PackedFloat64Array, disc: Dictionary, lake: Dictionary = {}, time_s: float = 0.0) -> Dictionary:
	if disc.is_empty():
		return {depth = -INF, point_ned = PackedFloat64Array()}
	if (not lake.is_empty() and not LakeSurface.is_valid_definition(lake)) or not is_finite(time_s):
		return {depth = NAN, point_ned = PackedFloat64Array()}
	var down := _down_row(s)
	var a: PackedFloat64Array = disc.axis
	var along := down[0] * a[0] + down[1] * a[1] + down[2] * a[2]
	var p := PackedFloat64Array([down[0] - along * a[0], down[1] - along * a[1], down[2] - along * a[2]])
	var p_len := M.norm(p)
	var lowest: PackedFloat64Array = disc.hub.duplicate()
	if p_len > 1.0e-9: # an axis pointing straight down leaves the disc horizontal: every rim point is as deep
		lowest = M.add(lowest, M.scale(p, float(disc.radius) / p_len))
	var depth := s[RB.POS + 2] + down[0] * lowest[0] + down[1] * lowest[1] + down[2] * lowest[2]
	var point_ned: PackedFloat64Array = M.add(RB._slice3(s, RB.POS), M.q_rotate(RB._att(s), lowest))
	if not lake.is_empty():
		var terrain: Dictionary = LakeSurface.sample_terrain_validated(lake, point_ned[0], point_ned[1])
		if bool(terrain.get("covered", false)):
			var surface_down: float = LakeSurface.water_height_down(lake, point_ned[0], point_ned[1], time_s)
			if not is_finite(surface_down):
				surface_down = float(terrain.ground_down_m)
			depth = point_ned[2] - surface_down
	return {depth = depth, point_ned = point_ned}
