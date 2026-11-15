## Portable receipt fixture; no executable or native library is run.
extends SceneTree

const Package := preload("res://app_state/native_package.gd")
const Admission := preload("res://sim/native_macos_package_admission.gd")
const SourceAdmission := preload("res://sim/native_macos_admission.gd")
const Stage := preload("res://sim/native_stage.gd")
var checks := 0
var failures := 0
var fixture_root := ""
var bundle := ""
var manifest_sha := ""
var probe_sha := ""


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("MAC_PACKAGE_CACHE failed: " + label)


func write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "fixture write: " + path)
		return
	file.store_buffer(bytes)
	file.close()


func write_text(path: String, value: String) -> void:
	write_bytes(path, value.to_utf8_buffer())


func create_pack(text: String, output: String) -> void:
	var source := fixture_root.path_join("pack-input.txt")
	write_text(source, text)
	var packer := PCKPacker.new()
	check(packer.pck_start(output) == OK, "pack starts")
	check(packer.add_file("res://fixture.txt", source) == OK, "pack includes file")
	check(packer.flush() == OK, "pack flushes")


func reference_receipt() -> void:
	var files := [Package.MAC_NATIVE_LIBRARY, "Contents/MacOS/openrc", Package.MAC_NATIVE_LICENSE,
		"Contents/Resources/openrc.pck", Package.MAC_NATIVE_DESCRIPTOR]
	files.sort()
	var lines := [Package.MAC_RECEIPT_FORMAT, "bundle\tfixture.app", "architectures\tarm64",
		"executable\tContents/MacOS/openrc", "pack\tContents/Resources/openrc.pck",
		"source_commit\t" + "a".repeat(40), "source_tree\t" + "b".repeat(40),
		"source_worktree_sha256\t" + "c".repeat(64), "source_receipt_sha256\t" + "d".repeat(64),
		"probe_sha256\t" + probe_sha]
	for path: String in files:
		lines.append("file\t" + FileAccess.get_sha256(bundle.path_join(path)) + "\t" + path)
	write_text(bundle + Package.MAC_RECEIPT_SUFFIX, "\n".join(lines) + "\n")


func native_receipt() -> void:
	var lines := [Package.MAC_NATIVE_RECEIPT_FORMAT, "bundle\tfixture.app", "architecture\tarm64",
		"reference_receipt_sha256\t" + FileAccess.get_sha256(bundle + Package.MAC_RECEIPT_SUFFIX),
		"manifest_sha256\t" + manifest_sha,
		"descriptor_sha256\t" + FileAccess.get_sha256(bundle.path_join(Package.MAC_NATIVE_DESCRIPTOR)),
		"library_sha256\t" + FileAccess.get_sha256(bundle.path_join(Package.MAC_NATIVE_LIBRARY))]
	write_text(bundle + Package.MAC_NATIVE_RECEIPT_SUFFIX, "\n".join(lines) + "\n")


func _initialize() -> void:
	# This portable fixture writes res://native/kernel; never run it in the
	# canonical application or any project with a real native installation.
	if ProjectSettings.get_setting("application/config/name", "") != "OpenRC Package Admission Draft Fixture":
		printerr("MAC_PACKAGE_CACHE refused: isolated fixture project required")
		quit(1)
		return
	fixture_root = ProjectSettings.globalize_path("user://package-cache-%d" % OS.get_process_id())
	bundle = fixture_root.path_join("fixture.app")
	var executable := bundle.path_join("Contents/MacOS/openrc")
	var pack := bundle.path_join("Contents/Resources/openrc.pck")
	# Reference reader requires at least 32 bytes, but never executes this file.
	write_text(executable, "fixture-executable-000000000000000000000000")
	write_text(bundle.path_join(Package.MAC_NATIVE_LIBRARY), "fixture-library")
	write_text(bundle.path_join(Package.MAC_NATIVE_DESCRIPTOR), "fixture-descriptor")
	write_text(bundle.path_join(Package.MAC_NATIVE_LICENSE), "fixture-license")
	create_pack("first pack", pack)
	var diagnostics := {}
	for name: String in Package.MAC_NATIVE_DIAGNOSTICS:
		var path := "res://native/kernel/qualification/" + name
		write_text(ProjectSettings.globalize_path(path), "fixture " + name)
		diagnostics[name] = FileAccess.get_sha256(path)
	probe_sha = diagnostics["session_probe.gd"]
	var lib_sha := FileAccess.get_sha256(bundle.path_join(Package.MAC_NATIVE_LIBRARY))
	var pair := {format = Admission.PAIR_FORMAT, editor_sha256 = "c".repeat(64),
		template_sha256 = "1".repeat(64), editor_receipt_sha256 = "2".repeat(64),
		template_receipt_sha256 = "3".repeat(64), pair_receipt_sha256 = "4".repeat(64),
		export_template_sha256 = "5".repeat(64), source_archive_sha256 = "6".repeat(64),
		source_catalog_sha256 = "7".repeat(64), patch_sha256 = ["8".repeat(64)]}
	var row := {platform = "macos", architecture = "arm64", backend = "native",
		backend_version = "openrc-native-kernel-stage-v2", abi_version = 2,
		qualification_scope = Package.MAC_NATIVE_SCOPE, engine_version = Engine.get_version_info().string,
		binary_sha256 = lib_sha, source_sha256 = "a".repeat(64), lock_sha256 = "b".repeat(64),
		engine_sha256 = "c".repeat(64), runtime_os_version = "27.0.1", runtime_os_build = "26A434",
		mirrored_sources = {"app/sim/native_macos_domain.gd": "d".repeat(64)}, verification = {fixture = true},
		engine = {sha256 = pair.editor_sha256, research_engine = {scope = Admission.RESEARCH_SCOPE,
			runtime_version = Engine.get_version_info().string, build_receipt_sha256 = pair.editor_receipt_sha256,
			source_archive_sha256 = pair.source_archive_sha256, source_catalog_sha256 = pair.source_catalog_sha256,
			ordered_patches = [{sha256 = pair.patch_sha256[0]}]}}}
	var receipt := {format = "openrc-native-kernel-receipt", backend = "native",
		backend_version = "openrc-native-kernel-stage-v2", abi_version = 2, platforms = {macos = row}}
	var manifest := {format = Package.MAC_NATIVE_MANIFEST_FORMAT, platform = "macos", architecture = "arm64",
		engine_version = Engine.get_version_info().string, solver_sha256 = "e".repeat(64),
		license_sha256 = FileAccess.get_sha256(bundle.path_join(Package.MAC_NATIVE_LICENSE)),
		native_receipt = receipt, qualification_sources = diagnostics, engine_pair = pair}
	var manifest_path := ProjectSettings.globalize_path(Package.MAC_NATIVE_MANIFEST_PATH)
	write_text(manifest_path, JSON.stringify(manifest))
	manifest_sha = FileAccess.get_sha256(manifest_path)
	reference_receipt()
	native_receipt()
	var native := Package.mac_native_identity(executable, "arm64")
	check(native.get("ok", false), "real native package reader accepts complete fixture")
	check(not Package.mac_native_identity(executable, "arm64", PackedStringArray(["--path=other"])).get("ok", false),
		"package reader refuses a project override")
	if not native.get("ok", false):
		print("MAC_PACKAGE_CACHE checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var reference: Dictionary = native.reference_identity
	var startup_sha := Package._macos_raw_receipt_sha256(executable)
	check(startup_sha == reference.receipt_sha256, "startup pin hashes the real bounded receipt bytes")
	check(Package._macos_process_receipt_error(true, startup_sha, reference.receipt_sha256).is_empty(),
		"same verified receipt is allowed without any native load")
	check(not Package._macos_process_receipt_error(false, startup_sha, reference.receipt_sha256).is_empty(),
		"missing startup pin is refused")
	check(not Package._macos_process_receipt_error(true, "", reference.receipt_sha256).is_empty(),
		"unreadable startup receipt cannot be repinned later")
	check(not Package._macos_process_receipt_error(true, startup_sha, "").is_empty(),
		"missing current verified receipt is refused")
	if not Package._macos_process_receipt_pinned:
		check(not Package.macos_process_reference_error(reference).is_empty(),
			"verified fixture cannot grant a missing process pin")
	var cached := Admission.package_identity(native, reference, manifest_sha)
	check(not cached.is_empty(), "verified receipt produces a cache identity")
	check(native.manifest_sha256 == manifest_sha and native.library_sha256 == lib_sha,
		"exposed identities match verified receipt bytes")
	check(Admission.loaded_identity_error(cached, cached.duplicate(true)).is_empty(), "identical receipt remains admitted")
	var snapshot := {native = native, reference = reference, identity = cached}
	var provisional := Stage._macos_replay_identity_from_snapshot(snapshot, {}, false)
	var loaded := Stage._macos_replay_identity_from_snapshot(snapshot, cached, true)
	check(provisional.kind == Package.MAC_NATIVE_IDENTITY_KIND and provisional.sha256 == native.sha256,
		"real receipt gives provisional pre-load replay identity")
	check(loaded == provisional and loaded.get("stage_backend", {}).get("binary_sha256") == lib_sha,
		"same verified package binds replay identity to loaded stage")
	check(Stage._macos_replay_identity_from_snapshot(snapshot, {}, true).kind == "unavailable",
		"recording and post-install replay require a loaded cache")
	check(Stage._macos_replay_identity_from_snapshot({}, cached, true).kind == "unavailable",
		"missing current package cannot inherit a cached identity")
	var selected := {ok = true, profile = "production", aircraft = "fixture", battery = "ideal",
		start = "airborne", weather = "calm", start_sha256 = "9".repeat(64)}
	var allowed := {aircraft = selected.aircraft, battery = selected.battery, start = selected.start,
		weather = selected.weather, soft_hull = false, trim_profile = "production", start_sha256 = selected.start_sha256}
	var marker := {format = Admission.FORMAT, scope = Admission.SCOPE, package_identity = cached,
		cpu = "Apple M1", hardware_model = "MacBookAir10,1", os_version = row.runtime_os_version,
		os_build = row.runtime_os_build, engine_pair = pair, allowed_selections = [allowed]}
	check(not Admission.ENABLED, "package default stays disabled")
	check(Admission.marker_error(marker, native, reference, manifest_sha, "Apple M1", "MacBookAir10,1", "").is_empty()
		and SourceAdmission.selection_allowed(marker, selected, false),
		"fixture marker matches actual verified receipt and selected start")
	var wrong_marker := marker.duplicate(true)
	wrong_marker.erase("package_identity")
	check(not Admission.marker_error(wrong_marker, native, reference, manifest_sha,
		"Apple M1", "MacBookAir10,1", "").is_empty(), "missing marker package identity is refused")
	var next_pack := fixture_root.path_join("second.pck")
	create_pack("second pack with different bytes", next_pack)
	write_bytes(pack, FileAccess.get_file_as_bytes(next_pack))
	check(not Package.mac_native_identity(executable, "arm64").get("ok", false), "unreceipted pack replacement is refused")
	reference_receipt()
	native_receipt()
	var replacement := Package.mac_native_identity(executable, "arm64")
	check(replacement.get("ok", false), "new complete receipts validate independently")
	if replacement.get("ok", false):
		check(replacement.library_sha256 == native.library_sha256 and replacement.manifest_sha256 == native.manifest_sha256,
			"replacement preserves native library and embedded manifest")
		check(not Package._macos_process_receipt_error(true, startup_sha,
			replacement.reference_identity.receipt_sha256).is_empty(),
			"startup A refuses verified B before first native prepare or reference recording")
		var fresh_sha := Package._macos_raw_receipt_sha256(executable)
		check(fresh_sha == replacement.reference_identity.receipt_sha256 \
			and Package._macos_process_receipt_error(true, fresh_sha, fresh_sha).is_empty(),
			"fresh process B may use its own matching reference receipt")
		var current := Admission.package_identity(replacement, replacement.reference_identity, manifest_sha)
		check(not current.is_empty() and current != cached, "replacement has a distinct package identity")
		check(not Admission.loaded_identity_error(cached, current).is_empty(), "loaded package rejects valid replacement until restart")
		var replacement_snapshot := {native = replacement, reference = replacement.reference_identity, identity = current}
		check(Stage._macos_replay_identity_from_snapshot(replacement_snapshot, {}, false).sha256 == replacement.sha256,
			"replacement is independently valid before any load")
		check(Stage._macos_replay_identity_from_snapshot(replacement_snapshot, cached, true).kind == "unavailable",
			"recording cannot label loaded A as independently receipted B")
		check(Stage._macos_replay_identity_from_snapshot(replacement_snapshot, cached, false).kind == "unavailable",
			"replay also refuses B once A is loaded")
		check(not Admission.marker_error(marker, replacement, replacement.reference_identity, manifest_sha,
			"Apple M1", "MacBookAir10,1", "").is_empty(), "A marker does not authorize valid replacement B")
	print("MAC_PACKAGE_CACHE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
