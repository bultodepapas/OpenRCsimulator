extends RefCounted
## Exact identity aliases for historical statistics. Persisted record IDs stay unchanged.

static func related(id: String) -> PackedStringArray:
	match id:
		"skywalker-x8", "moonrunner-x99":
			return PackedStringArray(["skywalker-x8", "moonrunner-x99"])
		"stock:skywalker-x8", "stock:moonrunner-x99":
			return PackedStringArray(["stock:skywalker-x8", "stock:moonrunner-x99"])
	return PackedStringArray([id])


static func matches(requested: String, actual: String) -> bool:
	return related(requested).has(actual)
