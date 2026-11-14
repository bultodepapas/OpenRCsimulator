extends SceneTree

const Store := preload("res://input/controller_profile_store.gd")
const Profile := preload("res://input/controller_profile.gd")
const A_ID := "11111111-1111-4111-8111-111111111111"
const B_ID := "22222222-2222-4222-8222-222222222222"
const C_ID := "33333333-3333-4333-8333-333333333333"

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_run.call_deferred()


func _profile(id: String, label: String) -> Dictionary:
	var profile: Dictionary = Profile.defaults()
	profile.profile_id = id
	profile.name = label
	return profile


func _write_result(path: String, result: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()


func _child(arguments: PackedStringArray) -> void:
	var store := Store.new(arguments[1].path_join("profiles.cfg"))
	var operation := arguments[2]
	var result: Dictionary
	if operation == "orphan":
		# A process that exits here deliberately leaves its owned lock behind.
		result = store.acquire_write()
	else:
		result = store.save_profile(_profile(arguments[4], arguments[5]))
	_write_result(arguments[3], result)
	quit(0)


func _run_child(directory: String, operation: String, label: String, profile_id := B_ID, profile_name := "B") -> Dictionary:
	var result_path := directory.path_join(label + ".json")
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "--script", "res://tests/test_controller_audit_concurrency.gd", "--",
		"child", directory, operation, result_path, profile_id, profile_name])
	# Forward child diagnostics to the checked runner, including script errors
	# that an engine can otherwise report while exiting successfully.
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true)
	for record in output:
		print(record)
	if exit_code != 0:
		return {"ok": false, "test_error": "Child process failed (%d)." % exit_code}
	if not FileAccess.file_exists(result_path):
		return {"ok": false, "test_error": "Child process produced no result."}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	return parsed if parsed is Dictionary else {"ok": false, "test_error": "Child result was not a dictionary."}


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 0 and arguments[0] == "child":
		_child(arguments)
		return
	var directory := ProjectSettings.globalize_path("user://controller-audit-concurrency-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	check("create isolated fixture directory", DirAccess.make_dir_recursive_absolute(directory) == OK)
	var path := directory.path_join("profiles.cfg")
	var store := Store.new(path)
	var a := _profile(A_ID, "A initial")
	var b := _profile(B_ID, "B initial")
	check("initial A saves", store.save_profile(a).ok)
	check("initial B and preference save", store.save_profile_with_ui_preference(b, {"mode": "profile", "profile_id": B_ID}).ok)
	var claim := store.acquire_write()
	check("outer transaction acquires", claim.ok)
	var before := store.load_all()
	a.name = "A updated"
	check("nested update succeeds", store.save_profile(a).ok)
	var blocked := _run_child(directory, "save", "blocked-create", C_ID, "C")
	check("concurrent process is refused while A holds lease", not blocked.ok and not blocked.has("test_error") and "lock" in str(blocked.error).to_lower(), str(blocked))
	var still_owned := store.load_all()
	check("refused write did not alter owner snapshot", still_owned.ok and still_owned.profiles.size() == 2 \
		and still_owned.profiles[0].name == "A updated" and still_owned.ui_preference == before.ui_preference)
	store.release_write()
	var retried := _run_child(directory, "save", "retry-create", C_ID, "C")
	var created := store.load_all()
	check("retry after release commits without losing A", retried.ok and created.ok and created.profiles.size() == 3 \
		and created.profiles[0].name == "A updated" and created.profiles[2].name == "C")
	check("retry preserves menu preference", created.get("ui_preference", {}) == before.get("ui_preference", {}))

	# The service holds the same lease from its old snapshot through runtime refusal and restore.
	claim = store.acquire_write()
	before = store.load_all()
	a.name = "Rejected activation"
	check("activation candidate saves inside lease", claim.ok and store.save_profile(a).ok)
	blocked = _run_child(directory, "save", "blocked-rollback", B_ID, "B updated")
	check("another process cannot commit during pending activation", not blocked.ok and not blocked.has("test_error"), str(blocked))
	check("activation rollback restores its own snapshot", store.restore_snapshot(before).ok and store.load_all().profiles == before.profiles)
	store.release_write()
	retried = _run_child(directory, "save", "retry-edit", B_ID, "B updated")
	var edited := store.load_all()
	check("post-rollback edit survives with previous A and C", retried.ok and edited.ok and edited.profiles.size() == 3 \
		and edited.profiles[0].name == "A updated" and edited.profiles[1].name == "B updated" and edited.profiles[2].name == "C")

	# No timeout or PID test can establish that an interrupted owner is safe to reclaim.
	var orphan := _run_child(directory, "orphan", "orphan")
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var stale := store.save_profile(_profile(C_ID, "Must not save"))
	check("interrupted lease fails closed with recovery guidance", orphan.ok and not stale.ok \
		and "lock" in str(stale.error).to_lower() and FileAccess.get_file_as_bytes(path) == bytes_before, str(stale))
	check("read also refuses interrupted lease", not store.load_all().ok)
	# This is the test's own child, whose termination was observed before the explicit recovery.
	var lock := path + Store.LOCK_SUFFIX
	check("test removes known orphan owner", DirAccess.remove_absolute(lock.path_join(Store.LOCK_OWNER)) == OK)
	check("test removes known orphan lock", DirAccess.remove_absolute(lock) == OK)
	check("explicit recovery permits subsequent save", store.save_profile(_profile(C_ID, "Recovered")).ok)

	for file: String in ["profiles.cfg", "blocked-create.json", "retry-create.json", "blocked-rollback.json", "retry-edit.json", "orphan.json"]:
		if FileAccess.file_exists(directory.path_join(file)):
			DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	print("Controller audit concurrency: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
