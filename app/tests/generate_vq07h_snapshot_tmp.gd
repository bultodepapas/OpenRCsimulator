extends SceneTree
const Snapshot := preload("res://tests/test_auto_graphics_snapshot.gd")

func _initialize() -> void:
	var rows := Snapshot.build_table()
	var result := JSON.stringify({"format": "openrc-auto-graphics-snapshot v1", "decisions": rows}, "\t", true) + "\n"
	var encoded := Marshalls.raw_to_base64(result.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))
	for part: int in range(0, encoded.length(), 512):
		print("SNAPSHOT_PART ", encoded.substr(part, 512))
	print("snapshot generated ", rows.size())
	quit()
