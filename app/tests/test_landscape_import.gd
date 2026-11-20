extends SceneTree

const Home := preload("res://ui/home.gd")
const Source := preload("res://landscapes/phoenix_source.gd")
const Library := preload("res://landscapes/phoenix_library.gd")
const Browser := preload("res://ui/landscape_import.gd")
const TITLE := "Test panorama"
const EDGE := 48
var _folder := "user://test-scenery-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
var _failed := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var input_dir := _folder.path_join("input")
	var library := _folder.path_join("library")
	DirAccess.make_dir_recursive_absolute(input_dir.path_join("medium"))
	var file := _create_source(input_dir)
	var scan := Source.scan(ProjectSettings.globalize_path(input_dir))
	_check(scan.get("sites", []).size() == 1, "discovery finds one synthetic panorama")
	if scan.get("sites", []).size() != 1:
		_finish(input_dir, file)
		return
	var site: Dictionary = scan.sites[0]
	_check(site.title == TITLE and site.panels.size() == 6, "descriptor binds the six declared panels")
	_check(site.positions.size() == 2, "duplicate positions survive the parser")
	_check(site.objects.get("complete", false) and site.objects.counts[0] == 1,
		"the object table ends after the authored plane")
	var preview := Library.prepare(site, _never_cancel)
	_check(preview.get("error", "?").is_empty() and preview.get("panorama", false),
		"generated asymmetric cube produces a draggable preview")
	if not preview.get("error", "?").is_empty():
		_finish(input_dir, file)
		return
	var zip_path := _folder.path_join("scenery.zip")
	_check(_zip_fixture(zip_path, file, site.panels), "write a nested ZIP fixture")
	var zipped := Source.scan(ProjectSettings.globalize_path(zip_path))
	_check(zipped.get("sites", []).size() == 1, "discover a scenery inside the archive")
	if zipped.get("sites", []).size() == 1:
		var from_zip := Library.prepare(zipped.sites[0], _never_cancel)
		_check(from_zip.get("id") == preview.id, "ZIP and loose files publish the same preview content")
	DirAccess.remove_absolute(zip_path)
	var calls := [0]
	var stop := func() -> bool:
		calls[0] += 1
		return calls[0] > 2
	var cancelled := Library.install(preview, stop, library)
	_check(not str(cancelled.error).is_empty() and Library.entries(library).is_empty(),
		"cancellation during staging publishes no entry")
	var inactive_stage := library.path_join(".stage-1-9-8")
	DirAccess.make_dir_absolute(inactive_stage)
	_write(inactive_stage.path_join("face-0.png"), "partial".to_utf8_buffer())
	Library.entries(library)
	_check(not DirAccess.dir_exists_absolute(inactive_stage), "opening the library removes an abandoned stage")

	TranslationServer.set_locale("en")
	var home := Home.new()
	root.size = Vector2i(1280, 720)
	root.add_child(home)
	var button: Button = home.find_child("ImportScenery", true, false)
	await process_frame
	await process_frame
	_check(button.size.x >= 112.0, "Home reserves room for the import label in its compact rail")
	button.pressed.emit()
	var browser := home.get_node("LandscapeImport") as Browser
	browser.library_root = library
	_check(browser.visible and home.landscape_id == "club_field", "Home opens the importer alongside the current field")
	browser.scan_source(ProjectSettings.globalize_path(input_dir))
	await _idle(browser)
	var results: ItemList = browser.find_child("SceneryResults", true, false)
	_check(results.item_count == 1, "browser lists the source")
	if results.item_count == 1:
		results.select(0)
		results.item_selected.emit(0)
		await _idle(browser)
		await process_frame
		var viewport_bounds := Rect2i(Vector2i.ZERO, root.size)
		var dialog_bounds := Rect2i(browser.position, browser.size)
		_check(viewport_bounds.encloses(dialog_bounds), "first loaded preview keeps the dialog inside the viewport")
		var photo: TextureRect = browser.find_child("SceneryPanel", true, false)
		var material := photo.material as ShaderMaterial
		_check(material != null and photo.texture != null, "browser exposes the panoramic preview")
		browser._show_panel(4)
		_check(material != null and is_equal_approx(material.get_shader_parameter("pitch"), PI / 2.0),
			"numbered direction faces the pole")
		if DisplayServer.get_name() != "headless":
			await _test_projection(browser, photo)
		browser._install_preview()
		await _idle(browser)
		_check(Library.entries(library).size() == 1, "install publishes exactly one immutable preview")
	_check(home.landscape_id == "club_field", "preview leaves the active flight field selected")
	browser.hide()
	home.free()

	_cleanup_input(input_dir, file)
	var recovered := Library.load_preview(preview.id, _never_cancel, library)
	_check(str(recovered.error).is_empty() and recovered.get("panorama", false),
		"installed preview loads after the source was removed")
	_check(Library.install(preview, _never_cancel, library).get("error") == ""
		and Library.entries(library).size() == 1, "reinstall deduplicates the same content")
	var bad_face := library.path_join(preview.id).path_join("face-0.png")
	_write(bad_face, "damaged".to_utf8_buffer())
	_check(not Library.load_preview(preview.id, _never_cancel, library).get("error").is_empty(),
		"a corrupt persisted face is refused")
	_check(Library.install(preview, _never_cancel, library).get("error") == "", "reimport repairs a damaged face")
	var bad_meta := library.path_join(preview.id).path_join("site.json")
	_write(bad_meta, "damaged".to_utf8_buffer())
	_check(Library.entries(library).is_empty() and Library.install(preview, _never_cancel, library).get("error") == "",
		"reimport repairs a hidden entry with damaged metadata")
	_check(Library.remove(preview.id, library) and Library.entries(library).is_empty(),
		"remove retires the installed preview")
	DirAccess.remove_absolute(library)
	_finish(input_dir, file)


func _idle(browser: Browser) -> void:
	for frame in 600:
		if browser._worker == null:
			return
		await create_timer(0.01).timeout
	_check(false, "background job finished")


func _never_cancel() -> bool:
	return false


func _test_projection(browser: Browser, photo: TextureRect) -> void:
	for index in [0, 1, 2, 3, 4, 5]:
		browser._show_panel(index)
		await process_frame
		await RenderingServer.frame_post_draw
		var output := browser.get_texture().get_image()
		var point := Vector2i(photo.get_global_rect().get_center())
		if not Rect2i(Vector2i.ZERO, output.get_size()).has_point(point):
			_check(false, "panel %d is visible inside the modal viewport" % (index + 1))
			continue
		var reference := _cube_face(index).get_pixel(EDGE >> 1, EDGE >> 1)
		var sample := output.get_pixelv(point)
		var distance := absf(sample.r - reference.r) + absf(sample.g - reference.g) + absf(sample.b - reference.b)
		_check(distance < 0.25, "rendered panel %d faces the intended direction" % (index + 1))


func _create_source(input_dir: String) -> String:
	# Stock prefix, two same-name positions and a structurally valid plane. Images are authored here.
	var descriptor := PackedByteArray()
	var objects := 2485 + 2 * 92
	descriptor.resize(objects + 4 + 4 + 0x104 + 31)
	_put_text(descriptor, 0, "PHOENIXCREATOR FLYING SITE")
	descriptor.encode_u32(32, 3)
	_put_text(descriptor, 36, TITLE)
	for index in 6:
		var name := "test_panorama%d.dds" % (index + 1)
		_put_text(descriptor, 553 + index * 256, name)
		_write(input_dir.path_join("medium").path_join(name), _cube_face(index).save_jpg_to_buffer(0.95))
	for index in 4:
		descriptor.encode_float(2101 + index * 20, 1.0)
	descriptor.encode_u32(2481, 2)
	_put_text(descriptor, 2485, "default 1")
	_put_text(descriptor, 2485 + 92, "default 1")
	descriptor.encode_float(2485 + 92 + 68, 4.0)
	descriptor.encode_u32(objects, 1)
	_put_text(descriptor, objects + 8, "Ground")
	var path := input_dir.path_join("test_panorama.pxf")
	_write(path, descriptor)
	return path


func _cube_face(face: int) -> Image:
	var image := Image.create_empty(EDGE, EDGE, false, Image.FORMAT_RGB8)
	for y in EDGE:
		for x in EDGE:
			var s := 2.0 * x / (EDGE - 1) - 1.0
			var t := 2.0 * y / (EDGE - 1) - 1.0
			var ray := Vector3.ZERO
			match face:
				0: ray = Vector3(s, -t, -1.0)
				1: ray = Vector3(1.0, -t, s)
				2: ray = Vector3(-s, -t, 1.0)
				3: ray = Vector3(-1.0, -t, -s)
				4: ray = Vector3(s, 1.0, -t)
				5: ray = Vector3(s, -1.0, t)
			ray = ray.normalized() * 0.40 + Vector3.ONE * 0.5
			image.set_pixel(x, y, Color(ray.x, ray.y, ray.z))
	return image


func _put_text(bytes: PackedByteArray, offset: int, text: String) -> void:
	var encoded := text.to_utf8_buffer()
	for index in encoded.size():
		bytes[offset + index] = encoded[index]


func _zip_fixture(path: String, descriptor: String, panels: Array) -> bool:
	var writer := ZIPPacker.new()
	if writer.open(path) != OK:
		return false
	var ok := _zip_file(writer, descriptor, "nested/" + descriptor.get_file())
	for panel: String in panels:
		ok = _zip_file(writer, panel, "nested/medium/" + panel.get_file()) and ok
	return writer.close() == OK and ok


func _zip_file(writer: ZIPPacker, source: String, entry: String) -> bool:
	if writer.start_file(entry) != OK:
		return false
	var error := writer.write_file(FileAccess.get_file_as_bytes(source))
	return writer.close_file() == OK and error == OK


func _write(path: String, buffer: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(buffer)


func _cleanup_input(input_dir: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	for index in 6:
		DirAccess.remove_absolute(input_dir.path_join("medium/test_panorama%d.dds" % (index + 1)))
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(input_dir.path_join("medium"))
	DirAccess.remove_absolute(input_dir)


func _finish(input_dir: String, path: String) -> void:
	_cleanup_input(input_dir, path)
	DirAccess.remove_absolute(_folder)
	print("Landscape import: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		printerr("FAIL ", description)
