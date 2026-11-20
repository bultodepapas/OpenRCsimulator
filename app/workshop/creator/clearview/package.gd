extends RefCounted
## Captured ClearView package and per-model metadata outcomes. No physics admission.
const R := preload("res://workshop/creator/result.gd")
const Archive := preload("archive.gd")
const Params := preload("params.gd")
const MAX_MODELS := 64
var _archive: Archive
var _models: Array = []

static func capture(path: String, cancel := Callable()) -> Dictionary:
	var archive := Archive.capture(path, cancel)
	if not archive.ok:
		return archive
	return inspect_archive(archive.value, cancel)

static func inspect_bytes(bytes: PackedByteArray, label := "models.zip", cancel := Callable()) -> Dictionary:
	var archive := Archive.inspect(bytes, label, cancel)
	if not archive.ok:
		return archive
	return inspect_archive(archive.value, cancel)

static func inspect_archive(archive: Archive, cancel := Callable()) -> Dictionary:
	var candidates: Array[String] = []
	for name: String in archive.names():
		if name.get_file().to_lower() == "params.txt":
			candidates.append(name)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		return a.length() < b.length() if a.length() != b.length() else a < b)
	var roots: Array[String] = []
	var package := new()
	package._archive = archive
	var nested_probes := 0
	for name: String in candidates:
		# Cancellation is an operation outcome, polled even for candidates that are skipped.
		if _cancelled(cancel):
			return _cancellation()
		var root := name.get_base_dir()
		var nested := false
		for existing: String in roots:
			if existing.is_empty() or root.to_lower().begins_with(existing.to_lower() + "/"):
				nested = true
				break
		if nested:
			# Nested model folders are unsupported. A complete nested aircraft is listed as
			# unavailable with its reason; other nested params.txt files (sounds) stay silent.
			if nested_probes >= MAX_MODELS:
				continue
			nested_probes += 1
			var unsupported := _nested_model(archive, name, root, cancel)
			if _cancelled(cancel):
				return _cancellation()
			if not unsupported.is_empty():
				if package._models.size() >= MAX_MODELS:
					return R.fail(R.SOURCE_LIMIT, "The ClearView ZIP contains more than 64 model roots.", "source", "import")
				package._models.append(unsupported)
			continue
		if package._models.size() >= MAX_MODELS:
			return R.fail(R.SOURCE_LIMIT, "The ClearView ZIP contains more than 64 model roots.", "source", "import")
		var data := archive.read_member(name, Params.MAX_BYTES, cancel)
		if _cancelled(cancel):
			return _cancellation()
		var metadata: Dictionary = Params.read(data.value) if data.ok else data
		var model := {root = root, name = root.get_file() if not root.is_empty() else archive.label().get_basename(),
			params_member = name, ok = metadata.ok, diagnostics = metadata.diagnostics}
		if metadata.ok:
			model.params = metadata.value
			var visual := archive.resolve(root, "data/" + str(metadata.value.model_name))
			model.ok = visual.ok
			if visual.ok:
				model.visual_member = visual.value.name
				model.case_adjusted = visual.value.case_adjusted
			else:
				model.diagnostics = visual.diagnostics
		if model.ok:
			roots.append(root)
		package._models.append(model)
	# A cancelled final member must not fall through to a partial inventory success.
	if _cancelled(cancel):
		return _cancellation()
	if roots.is_empty():
		if candidates.is_empty():
			return R.fail(R.SOURCE_UNSUPPORTED, "The ZIP contains no ClearView model-root params.txt file.", "source", "import")
		var failures: Array = []
		for item: Dictionary in package._models:
			for entry: Dictionary in item.diagnostics:
				failures.append(R.diagnostic(str(entry.code), "ClearView model %s: %s", "source", "import",
					[item.name, R.text(entry)], str(entry.severity)))
		return R.fail_all(failures)
	return R.ok(package)

static func _cancelled(cancel: Callable) -> bool:
	return cancel.is_valid() and bool(cancel.call())

static func _cancellation() -> Dictionary:
	return R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", "import")

## A nested candidate becomes a named unavailable entry only when it is a complete model.
static func _nested_model(archive: Archive, name: String, root: String, cancel: Callable) -> Dictionary:
	var data := archive.read_member(name, Params.MAX_BYTES, cancel)
	if not data.ok:
		return {}
	var metadata := Params.read(data.value)
	if not metadata.ok or not archive.resolve(root, "data/" + str(metadata.value.model_name)).ok:
		return {}
	return {root = root, name = root.get_file(), params_member = name, ok = false, nested = true,
		diagnostics = [R.diagnostic(R.SOURCE_UNSUPPORTED,
			"This model is inside another model's folder. Nested model folders are not supported; move it to its own folder in the ZIP.",
			"source", "import")]}

func models() -> Array:
	return _models.duplicate(true)

func model(root: String) -> Dictionary:
	for item: Dictionary in _models:
		if item.root == root:
			return item.duplicate(true)
	return {}

func archive() -> Archive:
	return _archive
