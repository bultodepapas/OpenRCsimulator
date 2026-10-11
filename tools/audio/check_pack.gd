## Mount the export in an empty project, then resolve its imported audio and notices.
extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("Expected one readable PCK path")
		quit(1)
		return
	var base: String = "res://assets/audio/soundscape/"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
	var okay: bool = manifest is Dictionary and FileAccess.get_file_as_string(base + "LICENSE.txt").contains("MIT License")
	var count: int = 0
	if manifest is Dictionary:
		for entry: Dictionary in manifest.assets:
			var wav: AudioStreamWAV = load(base + str(entry.file)) as AudioStreamWAV
			okay = okay and wav != null
			if wav != null:
				okay = okay and wav.mix_rate == 22050 and not wav.stereo and wav.format == AudioStreamWAV.FORMAT_16_BITS
				okay = okay and wav.data.size() / 2 == int(entry.metrics.sample_count)
				count += 1
	print("AUD-04 exported audio: %d/14 sources, manifest and MIT notice: %s" % [count, "PASS" if okay and count == 14 else "FAIL"])
	quit(0 if okay and count == 14 else 1)
