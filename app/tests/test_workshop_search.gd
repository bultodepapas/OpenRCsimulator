extends SceneTree
const Search := preload("res://workshop/library_search.gd")
var failures := 0

func check(description: String, condition: bool) -> void:
	print(("ok   " if condition else "FAIL ") + description)
	if not condition: failures += 1

func _initialize() -> void:
	var titles := PackedStringArray(["Blue airshow Ugly Stik", "Blue airshow Ugly Stik", "Avión ágil", "P-51 Mustang"])
	check("empty query preserves all identities and ordering", Search.matching_indices("  ", titles) == [0, 1, 2, 3])
	check("duplicate names retain separate indices", Search.matching_indices("blue", titles) == [0, 1])
	check("reordered words find both duplicates", Search.matching_indices("airshow blue", titles) == [0, 1])
	check("typing error finds both duplicates", Search.matching_indices("airshw blue", titles) == [0, 1])
	check("accented mixed case finds original spelling", Search.matching_indices("AVIÓN ÁGIL", titles) == [2])
	check("accent omission finds original spelling", Search.matching_indices("avion agil", titles) == [2])
	check("decomposed accents match composed titles", Search.matching_indices("avio\u0301n a\u0301gil", titles) == [2])
	check("unrelated query returns no results", Search.matching_indices("zzzzqqqq", titles).is_empty())
	check("empty library remains empty", Search.matching_indices("blue", PackedStringArray()).is_empty())
	var large := PackedStringArray()
	for index in 150: large.append("Blue airshow Ugly Stik %03d" % index)
	check("exact matches are not capped at 100", Search.matching_indices("blue", large).size() == 150)
	check("fuzzy matches are not capped at 100", Search.matching_indices("airshw blue", large).size() == 150)
	check("short exact queries survive engine score filtering", Search.matching_indices("p", titles).has(3))
	print("Workshop search: %d failures" % failures)
	quit(1 if failures else 0)
