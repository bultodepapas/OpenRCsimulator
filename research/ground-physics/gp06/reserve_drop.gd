# GP-06c: reserve-energy drop report for every geared catalog airplane (former 14 CFR 23.473(d)/(e), 23.725, 23.727;
# see app/tests/test_gear_reserve_energy.gd, which owns the drop and asserts the reserve case). Prints one line per
# attitude and sink and writes the full result (peak compression per contact, travel, ground-reaction load factor).
# Run: godot --headless --path app --script "$PWD/research/ground-physics/gp06/reserve_drop.gd" -- --out=<file.json>
extends SceneTree

const Reserve := preload("res://tests/test_gear_reserve_energy.gd")


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var rows: Array = Reserve.fleet_report()
	var finite := true
	for row: Dictionary in rows:
		for result: Dictionary in row.cases:
			var line := "%-30s %-16s sink %.3f:" % [row.id, result.attitude, result.sink_mps]
			for i in result.names.size():
				line += " %s %.0f/%.0f mm (%.0f%%)" % [result.names[i], 1000.0 * float(result.peak[i]),
					1000.0 * float(result.travel[i]), 100.0 * float(result.peak[i]) / float(result.travel[i])]
			print(line + "  peak n %.1f" % result.peak_load_factor)
			finite = finite and result.finite
	if not out_path.is_empty():
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({format = "openrc-gp06-reserve-drop v1", limit_sink_mps = Reserve.LIMIT_SINK_MPS,
			reserve_sink_mps = Reserve.RESERVE_SINK_MPS, lift_fraction = Reserve.LIFT_FRACTION, hz = Reserve.HZ,
			aircraft = rows}, "  ", false) + "\n")
		file.close()
	quit(0 if finite else 1)
