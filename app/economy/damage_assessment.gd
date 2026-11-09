extends RefCounted
## A local, deterministic game policy. Inputs are accepted endpoint observations;
## the resulting candidates are scenario assumptions, not measured failures.

const FORMAT := "openrc-game-damage-profile v1"
const POLICY := "local-contact-v1"
const MAX_ZONES := 512
const MAX_COMPONENTS := 256
const CHANNELS := ["compression_ratio", "depth_m", "normal_speed_mps", "slide_speed_mps"]


static func validate(profile: Variant, dossier: Dictionary, source_hash: String) -> Dictionary:
	if not profile is Dictionary or not _keys(profile, ["format", "profile_id", "policy_version", "source_sha256", "basis", "assumptions", "zones"]):
		return {ok = false, error = "Invalid game damage profile schema."}
	if profile.format != FORMAT or profile.policy_version != POLICY or profile.basis != "authored_game_policy" \
		or not _text(profile.profile_id) or profile.source_sha256 != source_hash:
		return {ok = false, error = "Incompatible game damage profile identity."}
	if not profile.assumptions is Array or profile.assumptions.is_empty() or profile.assumptions.size() > 16:
		return {ok = false, error = "Game profile assumptions are missing or unbounded."}
	for assumption: Variant in profile.assumptions:
		if not _text(assumption):
			return {ok = false, error = "Invalid game profile assumption."}
	if not profile.zones is Array or profile.zones.size() > MAX_ZONES:
		return {ok = false, error = "Game profile zones exceed their bound."}
	var parts := {}
	for part: Dictionary in dossier.get("components", []):
		parts[part.get("id")] = true
	if parts.size() > MAX_COMPONENTS:
		return {ok = false, error = "Game profile component bound exceeded."}
	var seen := {}
	for zone: Variant in profile.zones:
		if not zone is Dictionary or not _keys(zone, ["source", "probe_id", "component_ids", "response"]) \
			or zone.source not in ["hull", "gear", "propeller"] or not _text(zone.probe_id) \
			or not zone.component_ids is Array or zone.component_ids.is_empty() or zone.component_ids.size() > MAX_COMPONENTS:
			return {ok = false, error = "Invalid qualified game profile zone."}
		var key := "%s/%s" % [zone.source, zone.probe_id]
		if seen.has(key):
			return {ok = false, error = "Duplicate game profile zone."}
		seen[key] = true
		var targets := {}
		for id: Variant in zone.component_ids:
			if not id is String or not parts.has(id) or targets.has(id):
				return {ok = false, error = "Unknown or duplicate game profile component."}
			targets[id] = true
		var response: Variant = zone.response
		if not response is Dictionary or not response.get("kind") is String:
			return {ok = false, error = "Invalid game profile response."}
		match response.kind:
			"inspect", "replace_on_impact":
				if not _keys(response, ["kind"]):
					return {ok = false, error = "Unknown game response field."}
			"channel_bands":
				if not _keys(response, ["kind", "channel", "clear_below", "replace_at", "terminal_replace"]) \
					or response.channel not in CHANNELS or not response.terminal_replace is bool \
					or not _nonnegative(response.clear_below) or not _nonnegative(response.replace_at) \
					or float(response.clear_below) > float(response.replace_at):
					return {ok = false, error = "Invalid game response bands."}
			_:
				return {ok = false, error = "Unsupported game response."}
	return {ok = true, error = ""}


static func resolve(profile: Dictionary, event: Dictionary) -> Dictionary:
	var source := str(event.get("probe_source", event.get("source", "")))
	var probe_id := str(event.get("probe_id", event.get("contact_id", "")))
	for zone: Dictionary in profile.get("zones", []):
		if zone.source != source or zone.probe_id != probe_id:
			continue
		var response: Dictionary = zone.response
		var recommendation := "inspect"
		var reason := "accepted contact; local condition is unknown"
		var channel := ""
		var value: Variant = null
		if event.get("lifecycle") == "ended":
			return {matched = true, components = zone.component_ids.duplicate(), recommendation = "clear", reason = "contact ended", channel = "", value = null}
		# Water entry is exposure evidence, not proof of fracture or a blade strike.
		var water: bool = event.get("source") == "lake" and event.get("material") == "water"
		if response.kind == "replace_on_impact" and event.get("event_type") == "impact" and not water:
			recommendation = "replace"
			reason = "accepted local impact under the authored game policy"
		elif response.kind == "channel_bands":
			channel = response.channel
			value = _channel(event, channel)
			if response.terminal_replace and event.get("event_type") == "impact" \
					and event.get("response") == "terminal" and not water:
				recommendation = "replace"
				reason = "accepted local impact under the authored game policy"
			elif value != null and not water:
				if float(value) < float(response.clear_below):
					recommendation = "clear"
					reason = "endpoint game proxy below the local action band"
				elif float(value) >= float(response.replace_at):
					recommendation = "replace"
					reason = "endpoint game proxy reached the local replacement band"
				else:
					reason = "endpoint game proxy in the local inspection band"
		return {matched = true, components = zone.component_ids.duplicate(), recommendation = recommendation,
			reason = reason, channel = channel, value = value}
	return {matched = false, components = [], recommendation = "inspect", reason = "qualified contact has no game profile mapping", channel = "", value = null}


static func _channel(event: Dictionary, channel: String) -> Variant:
	var measure: Variant = event.get("measure", {})
	if not measure is Dictionary:
		return null
	if channel == "compression_ratio":
		var compression: Variant = measure.get("compression_m")
		var travel: Variant = measure.get("travel_limit_m")
		if not _nonnegative(compression) or not _nonnegative(travel) or float(travel) <= 0.0:
			return null
		var ratio := float(compression) / float(travel)
		return ratio if is_finite(ratio) else null
	var value: Variant = measure.get(channel)
	return float(value) if _nonnegative(value) else null


static func _nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 2048


static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true
