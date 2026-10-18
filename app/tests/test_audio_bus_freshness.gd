## Editor-assigned resource identity must not hide actual audio setting drift.
extends SceneTree

const Generator := preload("res://../tools/audio/make_bus_layout.gd")


func _initialize() -> void:
	var base := '[gd_resource type="AudioBusLayout" format=3]\n\n[resource]\nrelease = 2.0\n'
	var imported := base.replace('format=3]', 'format=3 uid="uid://abc123"]')
	var checks := [
		Generator._without_root_uid(imported) == base,
		Generator._without_root_uid(base) == base,
		Generator._without_root_uid(imported.replace("release = 2.0", "release = 1.0")) != base,
		Generator._without_root_uid(imported + 'uid="uid://abc123"\n') != base,
		Generator._without_root_uid(imported.replace('type="AudioBusLayout"', 'type="Resource"')) != base,
		Generator._without_root_uid(imported + '\n') != base,
	]
	for passed: bool in checks:
		if not passed:
			push_error("Audio freshness normalization hid content drift or rejected import metadata")
			quit(1)
			return
	print("audio bus freshness: %d checks passed" % checks.size())
	quit(0)
