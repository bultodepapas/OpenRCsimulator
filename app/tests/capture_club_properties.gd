## Fixed views for the checked runner's rendered landscape review.
extends "res://tests/capture_landscape_upgrade.gd"


func _initialize() -> void:
	var out := "user://club-properties"
	# Checked GPU jobs collect their check directory; their isolated profile is disposable.
	if OS.has_environment("OPENRC_DIAGNOSTIC_CAPTURE_ID") and OS.has_environment("XDG_DATA_HOME"):
		var job_dir := OS.get_environment("XDG_DATA_HOME").get_base_dir()
		for folder in ["check", "checks"]:
			var checked_dir := job_dir.path_join(folder)
			if DirAccess.dir_exists_absolute(checked_dir):
				out = checked_dir.path_join("club-properties")
				break
	args = {cases = "club_gate,stock_gate,stock_paddocks,club_properties,pasture_wire,pilot_north", frames = 8,
		width = 1920, height = 1080, out = out}
	super()
