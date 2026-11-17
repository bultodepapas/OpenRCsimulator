extends RefCounted
## Receipt for the association the trusted Creator publication path checked in this process.
## This is not a signature or authentication of a compiler, source, or local store history.
const Bytes := preload("res://workshop/creator/bytes.gd")

const FORMAT := "openrc-creator-compile-binding v1"
## Profile is a versioned compiler-contract claim, not a hash or proof of executable code.
## Change it when compilation semantics change; readers must retain support for older profiles.
const PROFILE := "openrc-creator-v4-servo-compiler-v1"
const REVISION_FORMAT := "openrc-creator-aircraft v2"
const KEYS := ["format", "profile", "definition_sha256", "raw_sha256"]


## Only the accepted-candidate capture path should create and persist a binding.
static func make(definition_sha256: String, raw_sha256: String) -> Dictionary:
	if not Bytes.is_sha256(definition_sha256) or not Bytes.is_sha256(raw_sha256):
		return {}
	return {"format": FORMAT, "profile": PROFILE, "definition_sha256": definition_sha256, "raw_sha256": raw_sha256}


## Check the closed receipt and compare to independently calculated blob hashes.
static func matches(value: Variant, definition_sha256: Variant, raw_sha256: Variant) -> bool:
	if not value is Dictionary or value.size() != KEYS.size() \
			or not Bytes.is_sha256(definition_sha256) or not Bytes.is_sha256(raw_sha256):
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in KEYS or typeof(value[key]) != TYPE_STRING:
			return false
	return value.get("format") == FORMAT and value.get("profile") == PROFILE \
		and value.get("definition_sha256") == definition_sha256 and value.get("raw_sha256") == raw_sha256
