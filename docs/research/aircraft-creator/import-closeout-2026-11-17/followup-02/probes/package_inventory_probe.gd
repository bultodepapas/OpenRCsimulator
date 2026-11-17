extends SceneTree
## Observe inventory cancellation and nested roots using the production public API.
const Fixture := preload("res://tests/test_creator_clearview_readers.gd")
const Archive := preload("res://workshop/creator/clearview/archive.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")


func _initialize() -> void:
	var params := "verNumber 5.0\nmodelType 1.0\nmodelName body.ac\n".to_ascii_buffer()
	var visual := Fixture._ac_fixture().to_ascii_buffer()
	var bytes: PackedByteArray = Fixture._zip_bytes([
		["One/params.txt", params], ["One/data/body.ac", visual],
		["Two/params.txt", params], ["Two/data/body.ac", visual]])
	var indexed: Dictionary = Archive.inspect(bytes, "two-valid-roots.zip")
	if not indexed.ok:
		printerr("Probe archive setup failed: ", indexed)
		quit(1)
		return
	var control: Dictionary = Package.inspect_archive(indexed.value)
	var report := {base_commit = "08f948265d40d83fbb4726a302b9e1c9490ccfce",
		uncancelled_ok = control.ok, uncancelled_models = control.value.models() if control.ok else [],
		cancellation_sweep = [], nested_roots = {}}
	for cancel_at: int in range(1, 18):
		var polls := [0]
		var seen := [false]
		var result: Dictionary = Package.inspect_archive(indexed.value, func() -> bool:
			polls[0] += 1
			if polls[0] >= cancel_at:
				seen[0] = true
				return true
			return false)
		var outcomes: Array = []
		if result.ok:
			for model: Dictionary in result.value.models():
				outcomes.append({root = model.root, ok = model.ok, diagnostics = model.diagnostics})
		report.cancellation_sweep.append({cancel_at = cancel_at, polls = polls[0],
			cancellation_observed = seen[0], package_ok = result.ok,
			models = outcomes, diagnostics = result.diagnostics})
	var nested_bytes: PackedByteArray = Fixture._zip_bytes([
		["Outer/params.txt", params], ["Outer/data/body.ac", visual],
		["Outer/Inner/params.txt", params], ["Outer/Inner/data/body.ac", visual]])
	var nested: Dictionary = Package.inspect_bytes(nested_bytes, "nested-valid-roots.zip")
	var inner_bytes: PackedByteArray = Fixture._zip_bytes([
		["Outer/Inner/params.txt", params], ["Outer/Inner/data/body.ac", visual]])
	var inner: Dictionary = Package.inspect_bytes(inner_bytes, "inner-alone.zip")
	report.nested_roots = {combined_ok = nested.ok,
		combined_models = nested.value.models() if nested.ok else [],
		inner_alone_ok = inner.ok, inner_alone_models = inner.value.models() if inner.ok else []}
	print("AUDIT_PACKAGE_JSON: ", JSON.stringify(report, "", true, true))
	print("AUDIT_PACKAGE_COMPLETE")
	quit(0)
