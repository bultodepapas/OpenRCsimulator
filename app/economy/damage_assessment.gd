extends RefCounted
## A local, deterministic game policy. Inputs are accepted endpoint observations;
## the resulting candidates are scenario assumptions, not measured failures.

const FORMAT := "openrc-game-damage-profile v1"
const POLICY := "local-contact-v1"
const FORMAT_V2 := "openrc-game-damage-profile v2"
const POLICY_V2 := "local-contact-v2"
const MAX_ZONES := 512
const MAX_COMPONENTS := 256
const CHANNELS := ["compression_ratio", "depth_m", "normal_speed_mps", "slide_speed_mps"]
const CHANNELS_V2 := CHANNELS + ["speed_mps", "down_speed_mps", "endpoint_normal_speed_mps", "contact_normal_proxy_mps"]
const MAX_MINOR := 9000000000000000


static func validate(profile: Variant, dossier: Dictionary, source_hash: String) -> Dictionary:
	if not profile is Dictionary:
		return {ok = false, error = "Invalid game damage profile schema."}
	var v2: bool = profile.get("format") == FORMAT_V2
	var expected := ["format", "profile_id", "policy_version", "source_sha256", "basis", "assumptions", "zones"]
	if v2:
		expected.append("propeller_followups")
	if not _keys(profile, expected):
		return {ok = false, error = "Invalid game damage profile schema."}
	if profile.format not in [FORMAT, FORMAT_V2] or profile.policy_version != (POLICY_V2 if v2 else POLICY) or profile.basis != "authored_game_policy" \
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
		var zone_fields := ["source", "probe_id", "component_ids", "response"]
		if v2:
			zone_fields.append("component_responses")
		if not zone is Dictionary or not _keys(zone, zone_fields) \
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
		var raw_responses: Variant = zone.get("component_responses", {})
		if not raw_responses is Dictionary:
			return {ok = false, error = "Invalid component-specific responses."}
		var responses: Dictionary = raw_responses
		if v2 and (not zone.component_responses is Dictionary \
			or (zone.component_ids.size() > 1 and responses.size() != targets.size()) \
			or (not responses.is_empty() and responses.size() != targets.size())):
			return {ok = false, error = "Each multi-target zone requires an independent component response."}
		if responses.is_empty():
			if not _valid_response(zone.response, v2, targets):
				return {ok = false, error = "Invalid game profile response."}
		else:
			# The common response is present but deliberately unused when component rules are authored.
			if not _valid_response(zone.response, v2, targets):
				return {ok = false, error = "Invalid default game profile response."}
			for id: Variant in responses:
				if not targets.has(id) or not _valid_response(responses[id], v2, {id: true}):
					return {ok = false, error = "Invalid component-specific game response."}
	if v2:
		var followups: Variant = profile.propeller_followups
		if not followups is Array or followups.size() > MAX_COMPONENTS:
			return {ok = false, error = "Invalid propeller follow-up list."}
		var followup_ids := {}
		for followup: Variant in followups:
			if not followup is Dictionary or not _keys(followup, ["component_id", "kind", "clear_speed_mps", "clear_rpm", "replace_speed_mps", "replace_rpm", "middle_action", "service_minor"]) \
				or followup.get("kind") != "powered_envelope_bands" \
				or followup.get("component_id") not in dossier.get("propeller_inspection_ids", []) \
				or followup_ids.has(followup.get("component_id")) \
				or not _nonnegative(followup.get("clear_speed_mps")) or not _nonnegative(followup.get("clear_rpm")) \
				or not _nonnegative(followup.get("replace_speed_mps")) or not _nonnegative(followup.get("replace_rpm")) \
				or float(followup.clear_speed_mps) >= float(followup.replace_speed_mps) \
				or float(followup.clear_rpm) >= float(followup.replace_rpm) \
				or followup.get("middle_action") not in ["inspect", "repair", "scope_clear"] \
				or (followup.middle_action == "repair" and not _minor(followup.get("service_minor"))) \
				or (followup.middle_action != "repair" and followup.get("service_minor") != null):
				return {ok = false, error = "Invalid propeller follow-up policy."}
			followup_ids[followup.component_id] = true
	return {ok = true, error = ""}


static func _valid_response(response: Variant, v2: bool, targets: Dictionary) -> bool:
	if not response is Dictionary or not response.get("kind") is String:
		return false
	match response.kind:
		"inspect", "replace_on_impact":
			return _keys(response, ["kind"])
		"channel_bands":
			var fields := ["kind", "channel", "clear_below", "replace_at", "terminal_replace"]
			if v2:
				fields.append_array(["middle_action", "service_minor_by_component"])
			if not _keys(response, fields) or response.channel not in (CHANNELS_V2 if v2 else CHANNELS) \
				or not response.terminal_replace is bool or not _nonnegative(response.clear_below) \
				or not _nonnegative(response.replace_at) or float(response.clear_below) > float(response.replace_at):
				return false
			if not v2:
				return true
			if response.middle_action not in ["inspect", "repair", "scope_clear"] \
				or not response.service_minor_by_component is Dictionary:
				return false
			if response.middle_action != "repair":
				return response.service_minor_by_component.is_empty()
			if response.service_minor_by_component.size() != targets.size():
				return false
			for id: Variant in response.service_minor_by_component:
				if not targets.has(id) or not _minor(response.service_minor_by_component[id]):
					return false
			return true
	return false


static func resolve(profile: Dictionary, event: Dictionary) -> Dictionary:
	var source := str(event.get("probe_source", event.get("source", "")))
	var probe_id := str(event.get("probe_id", event.get("contact_id", "")))
	for zone: Dictionary in profile.get("zones", []):
		if zone.source != source or zone.probe_id != probe_id:
			continue
		var actions := {}
		for id: String in zone.component_ids:
			var response: Dictionary = zone.get("component_responses", {}).get(id, zone.response)
			actions[id] = _resolve_response(profile, event, response, id)
		var first: Dictionary = actions[zone.component_ids[0]]
		var out := first.duplicate(true)
		out["matched"] = true
		out["components"] = zone.component_ids.duplicate()
		out["actions"] = actions
		return out
	return {matched = false, components = [], recommendation = "inspect", reason = "qualified contact has no game profile mapping", channel = "", value = null, actions = {}}


static func _resolve_response(profile: Dictionary, event: Dictionary, response: Dictionary, id: String) -> Dictionary:
		var recommendation := "inspect"
		var reason := "accepted contact; local condition is unknown"
		var channel := ""
		var value: Variant = null
		if event.get("lifecycle") == "ended":
			return {matched = true, recommendation = "clear", reason = "contact ended", channel = "", value = null, service_minor = null}
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
					if profile.get("format") == FORMAT_V2:
						recommendation = response.middle_action
					reason = "accepted endpoint game proxy in the authored local action band"
			if channel == "contact_normal_proxy_mps" and value != null:
				var stage := "prior accepted rigid-point normal sample" if event.get("event_type") == "hull_contact" \
					else ("lake bank crossing model sample" if event.get("source") == "lake" else \
					("scenery sweep model sample" if event.get("source") == "scenery" else "detected-state point/normal proxy"))
				reason += "; " + stage
		return {matched = true, recommendation = recommendation, reason = reason, channel = channel,
			value = value, service_minor = response.get("service_minor_by_component", {}).get(id)}


static func propeller_followup(profile: Dictionary, event: Dictionary, component_id: String) -> Dictionary:
	if profile.get("format") != FORMAT_V2 or event.get("source") != "propeller" or event.get("event_type") != "strike":
		return {matched = false}
	for row: Dictionary in profile.propeller_followups:
		if row.component_id != component_id:
			continue
		var velocity: Variant = event.get("velocity_ned")
		var rpm: Variant = event.get("measure", {}).get("rpm")
		if not velocity is PackedFloat64Array or velocity.size() != 3 or not _nonnegative(rpm):
			return {matched = true, recommendation = "inspect", reason = "required endpoint strike channels are unavailable"}
		var speed := sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2])
		if not is_finite(speed):
			return {matched = true, recommendation = "inspect", reason = "endpoint strike speed is out of range"}
		var recommendation: String = row.middle_action
		if speed <= float(row.clear_speed_mps) and float(rpm) <= float(row.clear_rpm):
			recommendation = "scope_clear"
		elif speed >= float(row.replace_speed_mps) or float(rpm) >= float(row.replace_rpm):
			recommendation = "replace"
		return {matched = true, recommendation = recommendation, reason = "authored powered-envelope endpoint game policy",
			service_minor = row.service_minor, speed_mps = speed, rpm = float(rpm)}
	return {matched = false}


static func _channel(event: Dictionary, channel: String) -> Variant:
	if channel == "contact_normal_proxy_mps":
		if event.get("source") == "hull" and event.get("event_type") == "hull_contact":
			var raw: Variant = event.get("measure", {}).get("normal_speed_mps")
			return float(raw) if _nonnegative(raw) else null
		if event.get("source") == "lake" and event.get("material") == "bank_ground" and event.get("probe_source") == "hull":
			var raw: Variant = event.get("measure", {}).get("normal_speed_mps")
			return float(raw) if _nonnegative(raw) else null
		if event.get("source") == "scenery" and event.get("probe_source") == "hull":
			var raw: Variant = event.get("measure", {}).get("normal_speed_mps")
			return float(raw) if _nonnegative(raw) else null
		return _channel(event, "endpoint_normal_speed_mps")
	if channel == "endpoint_normal_speed_mps":
		# Hull impact snapshots carry detected point velocity and an outward
		# surface normal in NED. This is not incoming velocity, work or force.
		if event.get("event_type") != "impact" or event.get("source") != "hull":
			return null
		var velocity: Variant = event.get("velocity_ned")
		var normal: Variant = event.get("normal_ned")
		if not velocity is PackedFloat64Array or not normal is PackedFloat64Array or velocity.size() != 3 or normal.size() != 3:
			return null
		var length := sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
		if not is_finite(length) or length < 0.000001:
			return null
		var inward: float = -(velocity[0] * normal[0] + velocity[1] * normal[1] + velocity[2] * normal[2]) / length
		return maxf(0.0, inward) if is_finite(inward) else null
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


static func _minor(value: Variant) -> bool:
	return _nonnegative(value) and float(value) <= float(MAX_MINOR) and floor(float(value)) == float(value)


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 2048


static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if key not in expected:
			return false
	return true
