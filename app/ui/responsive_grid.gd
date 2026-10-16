## Read-only sizing helpers for responsive GridContainer layouts.
extends RefCounted


static func two_column_minimum_width(grid: GridContainer) -> float:
	var column_widths := Vector2.ZERO
	var visible_control_count: int = 0
	for child: Node in grid.get_children():
		var control: Control = child as Control
		if control == null or control.is_set_as_top_level() or not control.visible:
			continue
		var column: int = visible_control_count % 2
		var child_width: int = int(control.get_bound_minimum_size().x)
		if column == 0:
			column_widths.x = maxf(column_widths.x, child_width)
		else:
			column_widths.y = maxf(column_widths.y, child_width)
		visible_control_count += 1

	var minimum_width: float = column_widths.x
	if visible_control_count > 1:
		minimum_width += column_widths.y + grid.get_theme_constant("h_separation")
	return maxf(grid.custom_minimum_size.x, minimum_width)
