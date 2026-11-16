extends SceneTree

const PackageAdmission := preload("res://sim/native_macos_package_admission.gd")
const SourceAdmission := preload("res://sim/native_macos_admission.gd")
var checks := 0
var failures := 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("MAC_PACKAGE_ADMISSION failed: " + label)


func digest(ch: String) -> String:
	return ch.repeat(64)


func evidence() -> Dictionary:
	var short: Array[Dictionary] = []
	var long: Array[Dictionary] = []
	for index in 8:
		var row := {reference_sha256 = digest("1"), native_sha256 = digest("2"), windows_sha256 = digest("3"),
			reference_capture = "r%d" % index, native_capture = "n%d" % index}
		if index < 5: short.append(row)
		else: long.append(row)
	return {format = PackageAdmission.EVIDENCE_FORMAT, source_fleet_sha256 = digest("4"),
		package_release_sha256 = digest("5"), package_session_sha256 = digest("6"),
		ci = {head_sha = "a".repeat(40), repository = "bultodepapas/OpenRCsimulator", run_id = "1",
			attempt = "1", required_job_id = "2", macos_job_id = "3"}, short_pairs = short, long_pairs = long}


func _initialize() -> void:
	var pair := {format = PackageAdmission.PAIR_FORMAT, editor_sha256 = digest("a"),
		template_sha256 = digest("b"), editor_receipt_sha256 = digest("c"),
		template_receipt_sha256 = digest("d"), pair_receipt_sha256 = digest("e"),
		export_template_sha256 = digest("f"), source_archive_sha256 = digest("1"),
		source_catalog_sha256 = digest("2"), patch_sha256 = [digest("3"), digest("4")]}
	var row := {binary_sha256 = digest("5"), source_sha256 = digest("6"), lock_sha256 = digest("7"),
		engine_sha256 = digest("a"), engine_version = "4.8-beta2 (openrc_metalfx)",
		runtime_os_version = "27.0.1", runtime_os_build = "26A434",
		mirrored_sources = {"app/sim/native_macos_domain.gd": digest("8")},
		engine = {sha256 = digest("a"), research_engine = {scope = PackageAdmission.RESEARCH_SCOPE,
			runtime_version = "4.8-beta2 (openrc_metalfx)", build_receipt_sha256 = digest("c"),
			source_archive_sha256 = digest("1"), source_catalog_sha256 = digest("2"),
			ordered_patches = [{sha256 = digest("3")}, {sha256 = digest("4")} ]}}}
	var native := {ok = true, kind = PackageAdmission.NATIVE_KIND, sha256 = digest("9"),
		receipt_sha256 = digest("a"), reference_receipt_sha256 = digest("b"),
		manifest_sha256 = digest("c"), descriptor_sha256 = digest("d"), library_sha256 = digest("5"),
		manifest = {native_receipt = {platforms = {macos = row}}, engine_pair = pair}}
	var reference := {ok = true, kind = PackageAdmission.REFERENCE_KIND, architecture = "arm64",
		sha256 = digest("e"), receipt_sha256 = digest("b"), executable_sha256 = digest("f"),
		pack_sha256 = digest("0")}
	var selected := {ok = true, profile = "production", aircraft = "jensen-das-ugly-stik-60",
		battery = "ideal", start = "airborne", weather = "calm", start_sha256 = digest("1")}
	var allowed := {aircraft = selected.aircraft, battery = selected.battery, start = selected.start,
		weather = selected.weather, soft_hull = false, trim_profile = "production", start_sha256 = selected.start_sha256}
	var identity := PackageAdmission.package_identity(native, reference, digest("c"))
	var marker := {format = PackageAdmission.FORMAT, scope = PackageAdmission.SCOPE,
		package_identity = identity, cpu = "Apple M1", hardware_model = "MacBookAir10,1",
		os_version = "27.0.1", os_build = "26A434", engine_pair = pair, allowed_selections = [allowed], evidence = evidence()}
	check(PackageAdmission.ENABLED, "qualified marker reader is available")
	check(not identity.is_empty(), "complete verified package identity")
	check(PackageAdmission.marker_error(marker, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "matching draft marker")
	var missing_evidence := marker.duplicate(true)
	missing_evidence.erase("evidence")
	check(not PackageAdmission.marker_error(missing_evidence, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "missing qualification evidence refused")
	for field: String in ["source_fleet_sha256", "package_release_sha256", "package_session_sha256"]:
		var changed := marker.duplicate(true)
		changed.evidence[field] = ""
		check(not PackageAdmission._evidence_error(changed.evidence).is_empty(), "missing evidence digest " + field)
	for field: String in ["head_sha", "repository", "run_id", "attempt", "required_job_id", "macos_job_id"]:
		var changed := marker.duplicate(true)
		changed.evidence.ci.erase(field)
		check(not PackageAdmission._evidence_error(changed.evidence).is_empty(), "missing CI field " + field)
	var changed_pairs := marker.duplicate(true)
	changed_pairs.evidence.long_pairs.pop_back()
	check(not PackageAdmission._evidence_error(changed_pairs.evidence).is_empty(), "missing long pair refused")
	changed_pairs = marker.duplicate(true)
	changed_pairs.evidence.long_pairs[0].native_capture = changed_pairs.evidence.short_pairs[0].reference_capture
	check(not PackageAdmission._evidence_error(changed_pairs.evidence).is_empty(), "reused capture refused")
	changed_pairs = marker.duplicate(true)
	changed_pairs.evidence.short_pairs[0].windows_sha256 = "bad"
	check(not PackageAdmission._evidence_error(changed_pairs.evidence).is_empty(), "invalid matched-window digest refused")
	check(SourceAdmission.selection_allowed(marker, selected, false), "qualified production selection")
	check(not SourceAdmission.selection_allowed(marker, selected, true), "different contact mode refused")
	for field: String in ["aircraft", "battery", "start", "weather", "start_sha256", "profile"]:
		var changed := selected.duplicate(true)
		changed[field] = "changed"
		check(not SourceAdmission.selection_allowed(marker, changed, false), "changed selection " + field)
	var source_marker := marker.duplicate(true)
	source_marker.format = SourceAdmission.FORMAT
	source_marker.scope = SourceAdmission.SCOPE
	check(not PackageAdmission.marker_error(source_marker, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "source marker cannot authorize package")
	for key: String in identity:
		var changed := marker.duplicate(true)
		changed.package_identity[key] = "changed"
		check(not PackageAdmission.marker_error(changed, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "changed package identity " + key)
	for key: String in pair:
		var changed := marker.duplicate(true)
		changed.engine_pair[key] = "changed"
		check(not PackageAdmission.marker_error(changed, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "changed marker pair " + key)
	for key: String in ["editor_sha256", "editor_receipt_sha256", "source_archive_sha256", "source_catalog_sha256"]:
		var changed_native := native.duplicate(true)
		changed_native.manifest.engine_pair[key] = digest("f")
		var changed_marker := marker.duplicate(true)
		changed_marker.engine_pair = changed_native.manifest.engine_pair.duplicate(true)
		check(not PackageAdmission.marker_error(changed_marker, changed_native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "pair differs from editor provenance " + key)
	var changed_native := native.duplicate(true)
	changed_native.manifest.engine_pair.patch_sha256.reverse()
	var changed_marker := marker.duplicate(true)
	changed_marker.engine_pair = changed_native.manifest.engine_pair.duplicate(true)
	check(not PackageAdmission.marker_error(changed_marker, changed_native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "reordered patch stack refused")
	for key: String in ["ok", "kind", "sha256", "receipt_sha256", "reference_receipt_sha256", "manifest_sha256", "library_sha256", "descriptor_sha256"]:
		var changed := native.duplicate(true)
		changed.erase(key)
		check(PackageAdmission.package_identity(changed, reference, digest("c")).is_empty(), "missing native " + key)
	for key: String in ["ok", "kind", "architecture", "sha256", "receipt_sha256", "executable_sha256", "pack_sha256"]:
		var changed := reference.duplicate(true)
		changed.erase(key)
		check(PackageAdmission.package_identity(native, changed, digest("c")).is_empty(), "missing reference " + key)
	check(PackageAdmission.package_identity(native, reference, digest("f")).is_empty(), "changed manifest bytes refused")
	check(not PackageAdmission._sha("A".repeat(64)) and not PackageAdmission._sha("-" + "a".repeat(63)) \
			and not PackageAdmission._sha("g".repeat(64)), "digest syntax is lowercase ASCII hex only")
	var wrong_kind := native.duplicate(true)
	wrong_kind.kind = "selected"
	check(PackageAdmission.package_identity(wrong_kind, reference, digest("c")).is_empty(), "generic selected flag cannot substitute for package kind")
	var no_pair := native.duplicate(true)
	no_pair.manifest.erase("engine_pair")
	check(not PackageAdmission.marker_error(marker, no_pair, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "missing engine pair refused")
	var older_explicit := native.duplicate(true)
	older_explicit.manifest.native_receipt.platforms.macos.mirrored_sources.erase(PackageAdmission.DOMAIN_PATH)
	var older_identity := PackageAdmission.package_identity(older_explicit, reference, digest("c"))
	check(not older_identity.is_empty(), "older explicit research package retains a cache identity")
	var older_marker := marker.duplicate(true)
	older_marker.package_identity = older_identity
	check(not PackageAdmission.marker_error(older_marker, older_explicit, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "default requires the automatic domain")
	check(not PackageAdmission.marker_error(marker, native, reference, digest("c"), "Apple M2", "MacBookAir10,1", "").is_empty(), "different CPU refused")
	check(not PackageAdmission.marker_error(marker, native, reference, digest("c"), "Apple M1", "OtherMac", "").is_empty(), "different model refused")
	check(not PackageAdmission.marker_error(marker, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "actual OS differs").is_empty(), "actual OS mismatch refused")
	var wrong_os := marker.duplicate(true)
	wrong_os.os_build = "other"
	check(not PackageAdmission.marker_error(wrong_os, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "receipt OS mismatch refused")
	var no_rows := marker.duplicate(true)
	no_rows.allowed_selections = []
	check(not PackageAdmission.marker_error(no_rows, native, reference, digest("c"), "Apple M1", "MacBookAir10,1", "").is_empty(), "empty admission list refused")
	check(PackageAdmission.loaded_identity_error(identity, identity.duplicate(true)).is_empty(), "same cached identity")
	check(not PackageAdmission.loaded_identity_error({}, identity).is_empty(), "no cached identity refused")
	check(not PackageAdmission.loaded_identity_error(identity, {}).is_empty(), "missing current package refused")
	for key: String in identity:
		var replaced := identity.duplicate(true)
		replaced[key] = "changed"
		check(not PackageAdmission.loaded_identity_error(identity, replaced).is_empty(), "post-load replacement " + key)
	print("MAC_PACKAGE_ADMISSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
