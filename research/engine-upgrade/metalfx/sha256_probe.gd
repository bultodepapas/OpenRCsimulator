extends SceneTree

# Diagnostic fixture: fresh explicit output directory, no project or package mutation.
const EXPECTED := {
	0: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	1: "e7cf46a078fed4fafd0b5e3aff144802b853f8ae459a4f0c14add3314b7cc3a6",
	3: "b39fad1a1075f64570b3226d339ea818f9c66ecd2f1c59fd8b9c5a32b54c513f",
	55: "2900465fcb533e05a158fd2b3be0e5e3b03740d83060aa3580e0d98a96bf2384",
	56: "31454ff48ef36af2f08fd511bdc37d9d5855ac23e992e5ff5445cb6b7674a674",
	63: "5f6401b96532c36de4e65beec0409b69b1d181864c8009b7a04f43e5d56350d1",
	64: "94eb5de4943613fd048dc93393ab06877405faa39c11f53e9386083339833e7e",
	65: "fc518669b6eb4b4dd91827ecacef86689c725bd5bab888fd3b26dbb196eec954",
	32767: "9d344cd7a5c9ae44a3aa5ef63a6a0199b44ba198c863062b1f3419df8b8f0ccc",
	32768: "a06fa47c2671def27679fe048a287aeb2823c07a1e15d6395e02b3cec681c73d",
	32769: "9cc2c0a06e539982a30dd20dded669f0e6a806e42f642bbac880e9cbaa48443b",
	1000000: "047207f05c235c6490b408242a86a6f1d4c03d0e754902bd13efeb29f7f08a66",
}
const MUTANT := "9c68d7914cd8cc0405c894cd0a531015c12c902c3a89a22441974857cceaf477"

var checks := 0
var failures := 0


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SHA256_PROBE FAIL ", label)


func _initialize() -> void:
	var options := {}
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			printerr("SHA256_PROBE requires --out-dir and optional --target/--target-sha256")
			quit(1)
			return
		var split := arg.substr(2).split("=", true, 1)
		if split.size() != 2 or options.has(split[0]) or split[1].is_empty() \
				or split[0] not in ["out-dir", "target", "target-sha256"]:
			printerr("SHA256_PROBE invalid or duplicate option")
			quit(1)
			return
		options[split[0]] = split[1]
	var out_dir := str(options.get("out-dir", ""))
	if not out_dir.is_absolute_path() or DirAccess.dir_exists_absolute(out_dir) \
			or FileAccess.file_exists(out_dir) or DirAccess.make_dir_absolute(out_dir) != OK:
		printerr("SHA256_PROBE requires a fresh absolute output directory with an existing parent")
		quit(1)
		return
	for length: int in EXPECTED:
		var data := PackedByteArray()
		data.resize(length)
		for index: int in length:
			data[index] = (index * 37 + 11) & 255
		var path := out_dir.path_join("vector-%d.bin" % length)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_check("create vector %d" % length, false)
			continue
		file.store_buffer(data)
		file.close()
		var digest := FileAccess.get_sha256(path)
		_check("file vector %d" % length, digest == EXPECTED[length])
		var context := HashingContext.new()
		var good := context.start(HashingContext.HASH_SHA256) == OK
		var offset := 0
		while good and offset < length:
			var next := mini(offset + 997, length)
			good = context.update(data.slice(offset, next)) == OK
			offset = next
		_check("incremental vector %d" % length,
			good and context.finish().hex_encode() == EXPECTED[length])
	var changed := PackedByteArray()
	changed.resize(32769)
	for index: int in changed.size():
		changed[index] = (index * 37 + 11) & 255
	changed[16384] ^= 1
	var changed_path := out_dir.path_join("changed.bin")
	var changed_file := FileAccess.open(changed_path, FileAccess.WRITE)
	if changed_file == null:
		_check("create changed vector", false)
	else:
		changed_file.store_buffer(changed)
		changed_file.close()
		var changed_hash := FileAccess.get_sha256(changed_path)
		_check("changed buffer has independent expected digest",
			changed_hash == MUTANT and changed_hash != EXPECTED[32769])
	if options.has("target") or options.has("target-sha256"):
		var target := str(options.get("target", ""))
		var expected := str(options.get("target-sha256", ""))
		if not target.is_absolute_path() or expected.length() != 64 or not expected.is_valid_hex_number():
			_check("target requires an absolute file and SHA-256", false)
		else:
			var source := FileAccess.open(target, FileAccess.READ)
			if source == null:
				_check("benchmark target readable", false)
			else:
				var count := source.get_length()
				source.close()
				var started := Time.get_ticks_usec()
				var observed := FileAccess.get_sha256(target)
				var elapsed := Time.get_ticks_usec() - started
				_check("target digest matches", observed == expected.to_lower())
				print("SHA256_PROBE target_bytes=%d elapsed_usec=%d sha256=%s" % [count, elapsed, observed])
	print("SHA256_PROBE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
