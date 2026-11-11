extends SceneTree
## Second process of test_creator_store.gd (AC-13): opens the Creator store of one root, reports
## what it got, and either leaves or keeps the writer lock until it is killed.
##
## User arguments: --root=user://<store root>  --out=user://<report file>  --mode=try|hold
##   [--draft=<uuid>] saves one draft and reports the outcome  [--seconds=<n>] longest life (20).
## The report is JSON, written under a temporary name and renamed, so a reader never sees half.

const Store := preload("res://workshop/creator/store.gd")

var _store: RefCounted
var _deadline_msec := 0


func _initialize() -> void:
	var options := {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			options[argument.get_slice("=", 0)] = argument.substr(argument.find("=") + 1)
	var root := str(options.get("--root", ""))
	var out := str(options.get("--out", ""))
	if root.is_empty() or out.is_empty():
		quit(2)
		return
	var report := {"process_id": OS.get_process_id(), "opened": false, "writer": false, "lock_status": "",
		"generation": -1, "drafts": 0, "save": ""}
	var opened: Dictionary = Store.open(root)
	if opened.ok:
		var store: RefCounted = opened.value
		report["opened"] = true
		report["writer"] = store.is_writer()
		report["lock_status"] = store.lock_status()
		if options.has("--draft"):
			var saved: Dictionary = store.save_draft({draft_id = str(options["--draft"]), name = "Peer draft",
				aircraft_uuid = "", snapshot = {"from": "peer"}, source_bytes = PackedByteArray([7, 7, 7]),
				source_file_name = "peer.stl"}, "")
			report["save"] = "ok" if saved.ok else str(saved.diagnostics[0].code)
		report["generation"] = store.generation()
		report["drafts"] = store.list_drafts(true).size()
		if str(options.get("--mode", "try")) == "hold" and store.is_writer():
			_store = store
		else:
			store.close()
	_report(out, report)
	if _store == null:
		quit(0)
		return
	_deadline_msec = Time.get_ticks_msec() + int(float(str(options.get("--seconds", "20"))) * 1000.0)


## Keeps the lock until the test kills this process; leaves by itself if the test never does.
func _process(_delta: float) -> bool:
	OS.delay_msec(20)
	return Time.get_ticks_msec() > _deadline_msec


func _report(out: String, report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(out)
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report))
	file.close()
	DirAccess.rename_absolute(path + ".part", path)
