## Stable row indices isolate Godot's experimental fuzzy API from saved-build identity.
extends RefCounted


static func matching_indices(query: String, titles: PackedStringArray) -> Array[int]:
	var result: Array[int] = []
	var normalized := _normalize(query.strip_edges())
	var targets := PackedStringArray()
	for index in titles.size():
		targets.append(_normalize(titles[index]))
		# Preserve all existing substring matches, including short queries and large libraries.
		if normalized.is_empty() or targets[index].contains(normalized):
			result.append(index)
	if normalized.is_empty() or titles.is_empty():
		return result
	var fuzzy := FuzzySearch.new()
	fuzzy.max_results = titles.size()
	var matches := fuzzy.search_all(normalized, targets)
	# Equal-score duplicates keep library order rather than relying on engine sort stability.
	matches.sort_custom(func(a: FuzzySearchMatch, b: FuzzySearchMatch) -> bool:
		return a.original_index < b.original_index if a.score == b.score else a.score > b.score)
	var included := {}
	for index in result:
		included[index] = true
	for match_result: FuzzySearchMatch in matches:
		var index := match_result.original_index
		if index >= 0 and index < titles.size() and not included.has(index):
			result.append(index)
			included[index] = true
	return result


static func _normalize(value: String) -> String:
	var result := value.to_lower()
	# Search only: keep the user's original spelling in storage and display.
	for pair: String in ["áa", "ée", "íi", "óo", "úu", "üu", "ñn"]:
		result = result.replace(pair[0], pair[1])
	return result.replace("\u0301", "").replace("\u0308", "").replace("\u0303", "")
