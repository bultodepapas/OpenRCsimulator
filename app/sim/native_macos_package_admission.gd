## Draft package-specific default admission. The producer and native package
## qualification gates do not exist yet; these checks alone are not promotion.
extends RefCounted

const ENABLED := false
const FORMAT := "openrc-macos-native-package-default v1"
const SCOPE := "package-macos-arm64"
const MARKER_SUFFIX := ".openrc-native-default"
const NATIVE_KIND := "macos-arm64-native-bundle-v1"
const REFERENCE_KIND := "macos-reference-bundle-v1"
const PAIR_FORMAT := "openrc-macos-engine-pair-binding v1"
const RESEARCH_SCOPE := "source-editor-local-custom-engine-research-v1"
const DOMAIN_PATH := "app/sim/native_macos_domain.gd"


static func _sha(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64: return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102): return false
	return true


## Inputs come only from NativePackage's independently checked native and
## reference readers. This snapshot also serves explicit research launches;
## it does not require or imply a package-promotion marker.
static func package_identity(native: Dictionary, reference: Dictionary, manifest_sha: String) -> Dictionary:
	if typeof(native.get("ok")) != TYPE_BOOL or native.ok != true or native.get("kind") != NATIVE_KIND \
			or typeof(reference.get("ok")) != TYPE_BOOL or reference.ok != true or reference.get("kind") != REFERENCE_KIND \
			or reference.get("architecture") != "arm64" \
			or native.get("reference_receipt_sha256") != reference.get("receipt_sha256"):
		return {}
	for digest: Variant in [native.get("sha256"), native.get("receipt_sha256"),
			reference.get("sha256"), reference.get("receipt_sha256"), reference.get("executable_sha256"),
			reference.get("pack_sha256"), native.get("library_sha256"), native.get("descriptor_sha256"), manifest_sha]:
		if not _sha(digest): return {}
	if native.get("manifest_sha256") != manifest_sha: return {}
	var manifest: Variant = native.get("manifest")
	if not manifest is Dictionary or not manifest.get("native_receipt") is Dictionary \
			or not manifest.native_receipt.get("platforms") is Dictionary:
		return {}
	var row: Variant = manifest.native_receipt.platforms.get("macos")
	if not row is Dictionary or not row.get("mirrored_sources") is Dictionary:
		return {}
	for key: String in ["binary_sha256", "source_sha256", "lock_sha256", "engine_sha256"]:
		if not _sha(row.get(key)): return {}
	if native.library_sha256 != row.binary_sha256: return {}
	# Older explicit research bundles may lack the later automatic-domain
	# source. Cache their identity as before; only default admission needs it.
	var domain: Variant = row.mirrored_sources.get(DOMAIN_PATH, "")
	if domain != "" and not _sha(domain): return {}
	return {kind = NATIVE_KIND, native_identity_sha256 = native.sha256,
		native_receipt_sha256 = native.receipt_sha256, reference_identity_sha256 = reference.sha256,
		reference_receipt_sha256 = reference.receipt_sha256, executable_sha256 = reference.executable_sha256,
		pack_sha256 = reference.pack_sha256, manifest_sha256 = manifest_sha,
		descriptor_sha256 = native.descriptor_sha256,
		binary_sha256 = row.binary_sha256, source_sha256 = row.source_sha256,
		lock_sha256 = row.lock_sha256, engine_sha256 = row.engine_sha256, domain_sha256 = domain}


## The planned manifest binding must be independently constructed by a future
## producer from the actual paired editor/template receipts and export input.
## No artifact may be issued by this reader or by a test fixture.
static func pair_error(pair: Variant, row: Dictionary) -> String:
	if not pair is Dictionary or pair.size() != 10 or pair.get("format") != PAIR_FORMAT:
		return "Mac package engine pair binding is missing or malformed"
	for key: String in ["editor_sha256", "template_sha256", "editor_receipt_sha256",
			"template_receipt_sha256", "pair_receipt_sha256", "export_template_sha256",
			"source_archive_sha256", "source_catalog_sha256"]:
		if not _sha(pair.get(key)): return "Mac package engine pair digest is invalid: " + key
	if not pair.get("patch_sha256") is Array or pair.patch_sha256.is_empty() or pair.patch_sha256.size() > 64:
		return "Mac package engine patch identity is missing"
	var engine: Variant = row.get("engine")
	if not engine is Dictionary or not engine.get("research_engine") is Dictionary:
		return "Mac package lacks the qualified custom editor provenance"
	var provenance: Dictionary = engine.research_engine
	if provenance.get("scope") != RESEARCH_SCOPE or engine.get("sha256") != row.get("engine_sha256") \
			or provenance.get("runtime_version") != row.get("engine_version") \
			or pair.editor_sha256 != row.get("engine_sha256") \
			or pair.editor_receipt_sha256 != provenance.get("build_receipt_sha256") \
			or pair.source_archive_sha256 != provenance.get("source_archive_sha256") \
			or pair.source_catalog_sha256 != provenance.get("source_catalog_sha256"):
		return "Mac package engine pair differs from the qualified editor"
	var patches: Variant = provenance.get("ordered_patches")
	if not patches is Array or patches.size() != pair.patch_sha256.size():
		return "Mac package engine patch list differs"
	for index: int in range(patches.size()):
		if not patches[index] is Dictionary or not _sha(pair.patch_sha256[index]) \
				or patches[index].get("sha256") != pair.patch_sha256[index]:
			return "Mac package engine patch identity differs"
	return ""


## The caller supplies the result from NativeStage's bounded actual OS check.
static func marker_error(marker: Dictionary, native: Dictionary, reference: Dictionary,
		manifest_sha: String, cpu: String, model: String, actual_os_error: String) -> String:
	if marker.get("format") != FORMAT or marker.get("scope") != SCOPE:
		return "Mac package default has another format or scope"
	var identity := package_identity(native, reference, manifest_sha)
	if identity.is_empty(): return "Mac package identity was not verified"
	if not _sha(identity.get("domain_sha256")):
		return "Mac package default lacks the qualified domain source"
	if marker.get("package_identity") != identity:
		return "Mac package default differs from the verified final bundle"
	var manifest: Dictionary = native.manifest
	var row: Dictionary = manifest.native_receipt.platforms.macos
	if cpu != "Apple M1" or model != "MacBookAir10,1" \
			or marker.get("cpu") != cpu or marker.get("hardware_model") != model:
		return "Mac package default hardware has not been qualified"
	if not actual_os_error.is_empty(): return actual_os_error
	if typeof(row.get("runtime_os_version")) != TYPE_STRING or row.runtime_os_version.is_empty() \
			or typeof(row.get("runtime_os_build")) != TYPE_STRING or row.runtime_os_build.is_empty() \
			or marker.get("os_version") != row.runtime_os_version or marker.get("os_build") != row.runtime_os_build:
		return "Mac package default OS differs from the verified receipt"
	var pair: Variant = manifest.get("engine_pair")
	var failure := pair_error(pair, row)
	if not failure.is_empty(): return failure
	if marker.get("engine_pair") != pair:
		return "Mac package default engine pair differs from the embedded binding"
	if not marker.get("allowed_selections") is Array or marker.allowed_selections.is_empty() \
			or marker.allowed_selections.size() > 1428:
		return "Mac package default has no bounded selection set"
	return ""


## Check after loading and at each later preparation boundary. This applies
## equally to an explicit experimental package and an automatic package.
static func loaded_identity_error(cached: Dictionary, current: Dictionary) -> String:
	if cached.is_empty() or current.is_empty() or cached != current:
		return "Mac package identity differs from the loaded library; restart required"
	return ""
