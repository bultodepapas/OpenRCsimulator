extends SceneTree
const Package := preload("res://workshop/creator/clearview/package.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Images := preload("res://workshop/creator/clearview/images.gd")
const Fixture := preload("res://tests/test_creator_clearview_readers.gd")
const PngCheck := preload("res://workshop/creator/png_check.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_images()
	_conversion()
	_helicopters_and_limits()
	print("ClearView visual: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ",label)

func _images() -> void:
	for signed_height: int in [2,-2]:
		var bmp := PackedByteArray()
		bmp.resize(62)
		bmp[0] = 66
		bmp[1] = 77
		bmp.encode_u32(2,62)
		bmp.encode_u32(10,54)
		bmp.encode_u32(14,40)
		bmp.encode_s32(18,1)
		bmp.encode_s32(22,signed_height)
		bmp.encode_u16(26,1)
		bmp.encode_u16(28,24)
		bmp[56] = 255 # red first row, blue second row, DWORD row padding
		bmp[58] = 255
		var normalized := Images.normalize(bmp)
		check("24-bit BMP normalized", normalized.ok)
		if normalized.ok:
			var decoded := PngCheck.decode(normalized.value.png)
			check("BMP row orientation and BGR channels", decoded.ok and decoded.value.image.get_pixel(0,0).is_equal_approx(Color.BLUE if signed_height > 0 else Color.RED))
		check("bitmap cancellation", not Images.normalize(bmp,func() -> bool: return true).ok)
		# Real downloads (Sopwith Camel): up to three alignment bytes after the rows, declared in the size.
		var padded := bmp.duplicate()
		padded.append_array(PackedByteArray([0, 0]))
		padded.encode_u32(2, padded.size())
		check("bitmap with two trailing alignment bytes accepted", Images.normalize(padded).ok)
		padded.append_array(PackedByteArray([0, 0]))
		padded.encode_u32(2, padded.size())
		check("bitmap with four trailing bytes refused", not Images.normalize(padded).ok)
		bmp.encode_s32(18,5000)
		check("bitmap limits before decoding", not Images.normalize(bmp).ok)
	var rgba := Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,PackedByteArray([255,0,0,128])).save_png_to_buffer()
	var png := Images.normalize(rgba)
	check("RGBA alpha retained", png.ok and png.value.has_alpha)
	var indexed := _indexed_png()
	check("indexed tRNS alpha retained", Images.normalize(indexed).ok and Images.normalize(indexed).value.has_alpha)
	check("unqualified image refused", not Images.normalize(PackedByteArray([255,216,255,217])).ok)

func _conversion() -> void:
	var body := Fixture._ac_fixture()
	var result := _convert(body)
	check("AC scene becomes an admitted self-contained GLB", result.ok)
	if not result.ok:
		printerr(result)
		return
	var source: RefCounted = result.value.source
	check("one triangle preserved", source.triangle_count() == 1)
	check("receipt distinguishes physical authoring", not result.value.receipt.physics_imported)
	var document := _document(source.source_bytes())
	check("parent translation retained", document.nodes[1].matrix.slice(12,15) == [1.0,2.0,3.0])
	var rotated := _convert(body.replace("loc 1 2 3","rot 0 -1 0 1 0 0 0 0 1\nloc 1 2 3"))
	check("asymmetric local rotation retained", rotated.ok and _document(rotated.value.source.source_bytes()).nodes[1].matrix == [0.0,1.0,0.0,0.0,-1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1.0,2.0,3.0,1.0])
	var concave := body.replace("numvert 3\n0 0 0\n1 0 0\n0 1 1", "numvert 5\n0 0 0\n2 0 0\n2 2 2\n1 1 1\n0 2 2").replace("refs 3\n0 0 0\n1 1 0\n2 0 1", "refs 5\n0 0 0\n1 1 0\n2 1 1\n3 0.5 0.5\n4 0 1")
	var concave_result := _convert(concave)
	if not concave_result.ok:
		printerr("Concave conversion: ",concave_result)
	check("concave polygon triangulates without a fan", concave_result.ok and concave_result.value.source.triangle_count() == 3)
	check("texture-free output needs no image collection", not document.has("images"))
	check("material provenance persisted in source bytes", document.asset.extras.openrc_clearview.original_materials[0].specular == [0.5,0.5,0.5])
	check("reopened source retains import notes", Converter.source_notes(source).size() >= 2)
	for hostile: Variant in [null,false,2.0,[],{},"other"]:
		var receipt: Dictionary = result.value.receipt.duplicate(true)
		receipt.format = hostile
		var changed := Importer.inspect_bytes(_with_receipt(source.source_bytes(),receipt),"edited.glb")
		check("untrusted receipt format never raises an engine error", changed.ok and Converter.source_notes(changed.value).is_empty())
		receipt.format = Converter.VERSION
		receipt.physics_imported = hostile
		changed = Importer.inspect_bytes(_with_receipt(source.source_bytes(),receipt),"edited.glb")
		check("untrusted receipt physics flag is type checked", changed.ok and (Converter.source_notes(changed.value).is_empty() if typeof(hostile) != TYPE_BOOL else not Converter.source_notes(changed.value).is_empty()))
	var marker := "OBJECT poly\nname \"COORD_NOSETIP\"\nloc 0 0 0\nnumvert 1\n5 6 7\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 1\n0 0 0\nkids 0\n"
	result = _convert(body.replace("kids 1","kids 2") + marker)
	check("legacy point retained as metadata", result.ok and result.value.receipt.markers[0].vertices[0][1] == [5.0,6.0,7.0])
	check("legacy degenerate omission counted", result.ok and result.value.receipt.dropped_degenerate_surfaces == 1)
	var collinear := "OBJECT poly\nname \"collinear\"\nnumvert 3\n-0.690866 0.057032 0.0395824\n-0.690866 0.057032 -0.0478006\n-0.690866 0.057032 -0.0041091\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n"
	result = _convert(body.replace("kids 1","kids 2") + collinear)
	check("translated collinear geometry is reported despite Newell residue", result.ok and result.value.receipt.dropped_degenerate_surfaces == 1)
	var many := "OBJECT poly\nname \"markers\"\nnumvert 1\n0 0 0\nnumsurf 20\n"
	for face: int in 20:
		many += "SURF 0x32\nmat 0\nrefs 256\n" + "0 0 0\n".repeat(256)
	many += "kids 0\n"
	var refused := _convert(body.replace("kids 1","kids 2") + many)
	check("repeated marker references are bounded", not refused.ok and refused.diagnostics[0].code == "SOURCE_LIMIT")
	var bow := body.replace("numvert 3\n0 0 0\n1 0 0\n0 1 1", "numvert 4\n0 0 0\n1 1 1\n0 1 1\n1 0 0").replace("refs 3\n0 0 0\n1 1 0\n2 0 1", "refs 4\n0 0 0\n1 1 1\n2 0 1\n3 1 0")
	check("a model whose only surface is a cancelling bow-tie is refused", not _convert(bow).ok)
	# Real downloads (Red Arrows): an exactly cancelling bow-tie beside real geometry is omitted.
	var cancelling := "OBJECT poly\nname \"tie\"\nnumvert 4\n0 0 0\n1 1 1\n0 1 1\n1 0 0\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 4\n0 0 0\n1 1 1\n2 0 1\n3 1 0\nkids 0\n"
	var tied := _convert(body.replace("kids 1","kids 2") + cancelling)
	check("cancelling bow-tie omitted and counted like any crossing", tied.ok and tied.value.source.triangle_count() == 1
		and tied.value.receipt.omitted_self_intersecting_surfaces == 1 and tied.value.receipt.dropped_degenerate_surfaces == 0)
	# Real downloads (DR 107, Cap 580): an exactly collinear triangle whose cross product has -0.0 parts.
	var negative_zero := "OBJECT poly\nname \"sliver\"\nnumvert 3\n-0.04335 0.0234211 0.562649\n-0.04195 0.0234921 0.553229\n-0.04265 0.0234566 0.557939\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 0 0\n2 0 0\nkids 0\n"
	var signed := _convert(body.replace("kids 1","kids 2") + negative_zero)
	if not signed.ok:
		printerr("Negative-zero sliver: ", signed)
	check("negative-zero collinear triangle is a reported zero-area omission", signed.ok and signed.value.receipt.dropped_degenerate_surfaces == 1)
	# Real downloads (E-starter, Force One): a 0.1 mm line marker far from the origin renders nothing.
	var line_marker := "OBJECT poly\nname \"COORD_TWHEEL\"\nnumvert 2\n0.134842 -0.337895 0.00586971\n0.134942 -0.337895 0.00586971\nnumsurf 1\nSURF 0x32\nmat 0\nrefs 2\n0 0 0\n1 0 0\nkids 0\n"
	check("a point/line-only helper is not held to render precision", _convert(body.replace("kids 1","kids 2") + line_marker).ok)
	check("a two-corner polygon helper is not held to render precision", _convert(body.replace("kids 1","kids 2") + line_marker.replace("SURF 0x32","SURF 0x30")).ok)
	var repeated := line_marker.replace("SURF 0x32\nmat 0\nrefs 2\n0 0 0\n1 0 0","SURF 0x20\nmat 0\nrefs 4\n0 0 0\n1 0 0\n0 0 0\n1 0 0")
	check("a four-reference face over two points (E-starter COORD_TWHEEL) renders nothing", _convert(body.replace("kids 1","kids 2") + repeated).ok)
	# Real downloads (RN Buccaneer): a 14.5 mm aerial 5 m from its origin rounds invisibly in float32.
	var aerial := "OBJECT poly\nname \"AerialFwd\"\nnumvert 3\n-4.94334 2.04405 -0.00759996\n-4.92884 2.04405 -0.00759996\n-4.94334 2.04905 -0.00759996\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n"
	var antenna := _convert(body.replace("kids 1","kids 2") + aerial)
	if not antenna.ok:
		printerr("Aerial: ", antenna)
	check("a small part far from its origin keeps sub-micron float32 rounding", antenna.ok and antenna.value.source.triangle_count() == 2)
	# Real downloads (SU-31 Matador): the model names a .bmp, the ZIP ships the same image as .png/.jpg.
	var png_paint := Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,PackedByteArray([255,0,0,255])).save_png_to_buffer()
	var renamed := _convert(body.replace("name \"wing\"", "name \"wing\"\ntexture \"paint.bmp\""), png_paint)
	check("unique same-named texture substitutes a missing reference", renamed.ok
		and renamed.diagnostics.any(func(d: Dictionary) -> bool: return d.message == Converter.SUBSTITUTED_NOTE and d.arguments == ["paint.bmp","paint.png"]))
	var params5 := "verNumber 5\nmodelType 1\nmodelName body.ac\n".to_ascii_buffer()
	var twice := Package.inspect_bytes(Fixture._zip_bytes([["Plane/params.txt",params5],
		["Plane/data/body.ac",body.replace("name \"wing\"", "name \"wing\"\ntexture \"paint.bmp\"").to_ascii_buffer()],
		["Plane/data/paint.png",png_paint],["Plane/data/paint.gif",PackedByteArray([71,73,70,56,57,97])]]))
	check("ambiguous same-named textures keep the missing-file refusal", twice.ok and not Converter.convert(twice.value,"Plane").ok)
	# Real downloads (GP Cap 232, Twist 3D, Hawker Hunter): AC3D subdivision is reported, not refused.
	var subdivided := _convert(body.replace("name \"wing\"", "name \"wing\"\nsubdiv 2"))
	check("subdivided part converts with its control shape", subdivided.ok and subdivided.value.source.triangle_count() == 1
		and subdivided.value.receipt.unsubdivided_parts == 1)
	check("subdivision reported at import and after reopening", subdivided.ok
		and subdivided.diagnostics.any(func(d: Dictionary) -> bool: return d.message == Converter.UNSUBDIVIDED_NOTE and d.severity == "warning")
		and Converter.source_notes(subdivided.value.source).any(func(d: Dictionary) -> bool: return d.message == Converter.UNSUBDIVIDED_NOTE))
	check("subdiv 0 changes nothing", _convert(body.replace("name \"wing\"", "name \"wing\"\nsubdiv 0")).ok
		and not _convert(body.replace("name \"wing\"", "name \"wing\"\nsubdiv 0")).value.receipt.has("unsubdivided_parts"))
	# Real downloads: a quad whose two consecutive corners coincide is a triangle (Ascent Park Glider).
	var coincident := body.replace("numvert 3\n0 0 0\n1 0 0\n0 1 1", "numvert 4\n0 0 0\n1 0 0\n1 0 0\n0 1 1").replace("refs 3\n0 0 0\n1 1 0\n2 0 1", "refs 4\n0 0 0\n1 1 0\n2 1 0.5\n3 0 1")
	var collapsed := _convert(coincident)
	check("coincident consecutive corners collapse to the same shape", collapsed.ok and collapsed.value.source.triangle_count() == 1
		and not collapsed.value.receipt.has("omitted_self_intersecting_surfaces"))
	var closing := body.replace("numvert 3\n0 0 0\n1 0 0\n0 1 1", "numvert 4\n0 0 0\n1 0 0\n0 1 1\n0 0 0").replace("refs 3\n0 0 0\n1 1 0\n2 0 1", "refs 4\n0 0 0\n1 1 0\n2 0 1\n3 0 0")
	check("a repeated closing corner collapses too", _convert(closing).ok and _convert(closing).value.source.triangle_count() == 1)
	# A genuine (non-cancelling) bow-tie has no interior: omitted and reported, never fanned (MC 300S).
	var sliver := "OBJECT poly\nname \"sliver\"\nnumvert 4\n0 0 0\n4 2 0\n4 0 0\n0 4 0\nnumsurf %d\n"
	var crossed := sliver % 1 + "SURF 0x30\nmat 0\nrefs 4\n0 0 0\n1 0 0\n2 0 0\n3 0 0\nkids 0\n"
	result = _convert(body.replace("kids 1","kids 2") + crossed)
	check("self-intersecting surface omitted and counted", result.ok and result.value.source.triangle_count() == 1
		and result.value.receipt.omitted_self_intersecting_surfaces == 1)
	check("omission reported at import", result.ok and result.diagnostics.any(func(d: Dictionary) -> bool:
		return d.message == Converter.SELF_INTERSECTING_NOTE and d.arguments == ["1"]))
	check("omission reported after reopening", result.ok and Converter.source_notes(result.value.source).any(func(d: Dictionary) -> bool:
		return d.message == Converter.SELF_INTERSECTING_NOTE and d.arguments == ["1"]))
	var many_crossed := sliver % (Converter.MAX_SELF_INTERSECTING + 1)
	for face: int in Converter.MAX_SELF_INTERSECTING + 1:
		many_crossed += "SURF 0x30\nmat 0\nrefs 4\n0 0 0\n1 0 0\n2 0 0\n3 0 0\n"
	refused = _convert(body.replace("kids 1","kids 2") + many_crossed + "kids 0\n")
	check("too many self-intersecting surfaces refuse the model", not refused.ok and refused.diagnostics[0].code == "SOURCE_INVALID")
	# Real downloads (Bellanca C-27 rudder): collinear outline corners make a zero-area ear.
	var outline := "OBJECT poly\nname \"rudder\"\nnumvert 5\n0 0 0\n0 0 1\n0 0 2\n0 0 3\n2 0 1.5\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 5\n0 0 0\n1 0 0.3\n2 0 0.6\n3 0 1\n4 1 0.5\nkids 0\n"
	var straight := _convert(body.replace("kids 1","kids 2") + outline)
	if not straight.ok:
		printerr("Collinear outline: ", straight)
	# One fixture triangle plus at most three non-degenerate rudder triangles; never a refusal.
	check("collinear outline corners keep the shape without a zero-area triangle", straight.ok
		and straight.value.source.triangle_count() >= 2 and straight.value.source.triangle_count() <= 4)
	check("unchanged models carry no new receipt field", not _convert(body).value.receipt.has("omitted_self_intersecting_surfaces"))
	var large := body.replace("0 0 0\n1 0 0\n0 1 1", "100000000 0 0\n100000001 0 1\n100000000 1 1")
	check("render quantization cannot silently erase detail", not _convert(large).ok)
	var collapse := body.replace("0 0 0\n1 0 0\n0 1 1", "100000000 0 0\n100000001 0 0\n100000096 100000000 100000000")
	check("a wide bound cannot hide a collapsed float32 edge", not _convert(collapse).ok)
	for texture: PackedByteArray in [Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,PackedByteArray([255,0,0,128])).save_png_to_buffer(), _indexed_png()]:
		result = _convert(body.replace("name \"wing\"", "name \"wing\"\ntexture \"paint.png\""), texture)
		check("textured model admitted", result.ok)
		if result.ok:
			document = _document(result.value.source.source_bytes())
			check("PNG transparency renders with blending", document.materials[0].alphaMode == "BLEND")
	var v5 := "verNumber 5\nmodelType 1\nmodelName body.ac\n".to_ascii_buffer()
	var packed := Package.inspect_bytes(Fixture._zip_bytes([["params.txt","unrelated 1\n".to_ascii_buffer()],["Plane/params.txt",v5],["Plane/data/body.ac",body.to_ascii_buffer()]]))
	check("invalid parent does not hide a valid child", packed.ok and packed.value.models().size() == 2 and packed.value.models()[1].ok)
	var invalid := Package.inspect_bytes(Fixture._zip_bytes([["Plane/params.txt","verNumber 9\n".to_ascii_buffer()]]))
	check("invalid-only package reports its actual model error", not invalid.ok and invalid.diagnostics[0].message == "ClearView model %s: %s")
	invalid = Package.inspect_bytes(Fixture._zip_bytes([["Plane/params.txt",v5]]))
	check("missing-visual package reports its dependency", not invalid.ok and invalid.diagnostics[0].code == "DEPENDENCY_MISSING")
	var hinted := Fixture._zip_bytes([["Plane/",PackedByteArray()],["Plane/params.txt",v5],["Plane/data/BODY.AC",body.to_ascii_buffer()]])
	var directory := hinted.decode_u32(hinted.size() - 6)
	hinted.encode_u32(22,472)
	hinted.encode_u32(directory + 24,472)
	hinted.encode_u32(directory + 38,16)
	packed = Package.inspect_bytes(hinted)
	result = Converter.convert(packed.value,"Plane") if packed.ok else packed
	check("visual case match remains in saved receipt", result.ok and result.value.receipt.members[1].case_adjusted)
	check("directory explanation survives reopening", result.ok and Converter.source_notes(result.value.source).size() == result.diagnostics.size())

## Owner-download round 3: helicopters, VTOL dialects, the mesh-limit exception and edge cases.
func _helicopters_and_limits() -> void:
	var body := Fixture._ac_fixture()
	# CVHeliPak: v3, modelType 0, no modelName -> data/body.ac, visual only.
	var heli := _convert(body, PackedByteArray(), "verNumber 3.0\nmodelType 0.0\n")
	check("pre-v5 helicopter converts from the default body.ac", heli.ok)
	if heli.ok:
		var source: InspectedSource = heli.value.source
		check("helicopter GLB carries the rotorcraft tag", Installation.rotorcraft(source)
			and _document(source.source_bytes()).asset.extras.has(Converter.ROTORCRAFT_NAMESPACE))
		var doc := Authoring.new()
		doc.set_source(source)
		check("helicopter gets no airplane configuration", doc.source_installation_proposal().is_empty() and doc.needs_source_installation())
		var chosen := doc.choose_source_installation({}, doc.revision, true)
		check("helicopter configuration choice is refused with its own reason", not chosen.ok and chosen.diagnostics[0].message == Installation.ROTORCRAFT)
		check("helicopter issues and compile name the rotorcraft limit", doc.issues().any(func(d: Dictionary) -> bool: return d.message == Installation.ROTORCRAFT)
			and not doc.compile().ok and doc.compile().diagnostics[0].message == Installation.ROTORCRAFT)
	var plane := _convert(body)
	check("airplanes carry no rotorcraft tag", plane.ok and not Installation.rotorcraft(plane.value.source))
	# Harrier / VJ-101: flat v0 airplanes with a model name.
	check("flat v0 airplane converts", _convert(body, PackedByteArray(), "verNumber 0.0\nmodelType 1.0\nmodelName body.ac\n").ok)
	# Wee Jock: more leaf parts than the Creator mesh limit -> static leaves merged per parent.
	var count := Limits.GLB_MESHES + 2
	var many := ""
	for index: int in count:
		many += "OBJECT poly\nname \"leaf%d\"\nloc %d 0 0\nnumvert 3\n0 0 0\n1 0 0\n0 1 1\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n" % [index, index]
	many += "OBJECT poly\nname \"rotor.blade\"\nnumvert 3\n0 0 0\n1 0 0\n0 1 1\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n"
	var crowded := _convert(body.replace("kids 1", "kids %d" % (count + 2)) + many)
	if not crowded.ok:
		printerr("Merge: ", crowded)
	check("over the mesh limit, static leaves merge and the model converts", crowded.ok and crowded.value.receipt.merged_static_parts == count + 1
		and crowded.value.source.triangle_count() == count + 2)
	if crowded.ok:
		var document := _document(crowded.value.source.source_bytes())
		check("merged model fits the mesh limit", document.meshes.size() <= Limits.GLB_MESHES)
		var dotted: bool = document.nodes.any(func(n: Dictionary) -> bool: return n.name == "rotor.blade" and n.has("mesh"))
		check("group-style dotted parts stay separate and bindable", dotted)
		var widest := -INF
		for mesh: Dictionary in document.meshes:
			if str(mesh.name).ends_with("merged parts"):
				widest = maxf(widest, float(document.accessors[mesh.primitives[0].attributes.POSITION].max[0]))
		check("merged geometry keeps each part's own transform (baked in float64)", widest == float(count - 1) + 1.0)
		check("merge reported at import and after reopening", crowded.diagnostics.any(func(d: Dictionary) -> bool: return d.message == Converter.MERGED_NOTE)
			and Converter.source_notes(crowded.value.source).any(func(d: Dictionary) -> bool: return d.message == Converter.MERGED_NOTE))
	check("models under the limit are never merged", not _convert(body).value.receipt.has("merged_static_parts"))
	# Merging is decided by meshes actually emitted, not by nodes that merely look renderable.
	var near_limit := ""
	var parts := Limits.GLB_MESHES + 2
	for index: int in parts:
		var corners := "0 0 0\n1 0 0\n2 0 0" if index < 5 else "0 0 0\n1 0 0\n0 1 1"
		near_limit += "OBJECT poly\nname \"p%d\"\nloc %d 0 0\nnumvert 3\n%s\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n" % [index, index, corners]
	var fitted := _convert(body.replace("kids 1", "kids %d" % (parts + 1)) + near_limit)
	check("collinear parts that emit nothing do not trigger a merge", fitted.ok and not fitted.value.receipt.has("merged_static_parts"))
	# Cobra: a texture referenced by an absolute path on the author's PC.
	var outside := _convert(body.replace("name \"wing\"", "name \"wing\"\ntexture \"C:/Program Files/SVKSystems/ClearView/models/x/data/mapping.jpg\""))
	check("absent external texture leaves the plain colour with a warning", outside.ok
		and outside.diagnostics.any(func(d: Dictionary) -> bool: return d.message == Converter.EXTERNAL_NOTE and d.arguments == ["mapping.jpg"]))
	var paint := Image.create_from_data(1,1,false,Image.FORMAT_RGBA8,PackedByteArray([0,255,0,255])).save_png_to_buffer()
	var local := _convert(body.replace("name \"wing\"", "name \"wing\"\ntexture \"C:\\\\models\\\\x\\\\paint.png\""), paint)
	check("external texture found by name in the model's own folder", local.ok and _document(local.value.source.source_bytes()).has("images"))
	check("a relative missing texture still refuses", not _convert(body.replace("name \"wing\"", "name \"wing\"\ntexture \"absent.png\"")).ok)
	# Honey Bee: two corners 1e-9 m apart project to one render point -> zero-length edge, dropped.
	var near := "OBJECT poly\nname \"paddle\"\nnumvert 3\n0.05032362 -0.0134834 0\n0.050323621 -0.0134834 0\n0.2 0.3 0\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n2 0 0\n0 1 0\n1 0 1\nkids 0\n"
	var bee := _convert(body.replace("kids 1","kids 2") + near)
	if not bee.ok:
		printerr("Near corners: ", bee)
	check("corners merged by render precision collapse instead of refusing", bee.ok and bee.value.receipt.dropped_degenerate_surfaces == 1)
	# Blade mSR: a 1.6 mm part whose vertices sit 6 m from its node origin.
	var tiny := "OBJECT poly\nname \"cylinder\"\nloc -0.0241133 0.000587732 6.02181\nnumvert 3\n0.000755638 0.00466838 -6.03181\n0.002 0.00466838 -6.03181\n0.000755638 0.006 -6.03181\nnumsurf 1\nSURF 0x30\nmat 0\nrefs 3\n0 0 0\n1 1 0\n2 0 1\nkids 0\n"
	check("sub-micron rounding on a tiny distant part is accepted", _convert(body.replace("kids 1","kids 2") + tiny).ok)

static func _convert(body: String, texture := PackedByteArray(), parameters := "verNumber 5\nmodelType 1\nmodelName body.ac\n") -> Dictionary:
	var params := parameters.to_ascii_buffer()
	var files: Array = [["Plane/params.txt",params],["Plane/data/body.ac",body.to_ascii_buffer()]]
	if not texture.is_empty():
		files.append(["Plane/data/paint.png",texture])
	var package := Package.inspect_bytes(Fixture._zip_bytes(files))
	if not package.ok:
		return package
	return Converter.convert(package.value,"Plane")

static func _document(bytes: PackedByteArray) -> Dictionary:
	return JSON.parse_string(bytes.slice(20,20 + bytes.decode_u32(12)).get_string_from_utf8())

static func _with_receipt(bytes: PackedByteArray, receipt: Dictionary) -> PackedByteArray:
	var document := _document(bytes)
	document.asset.extras.openrc_clearview = receipt
	var json := JSON.stringify(document,"",true,true).to_utf8_buffer()
	while json.size() % 4:
		json.append(32)
	var output := bytes.slice(0,20)
	output.encode_u32(12,json.size())
	output.append_array(json)
	output.append_array(bytes.slice(20 + bytes.decode_u32(12)))
	output.encode_u32(8,output.size())
	return output

static func _indexed_png() -> PackedByteArray:
	var bytes := PackedByteArray(PngCheck.SIGNATURE)
	var head := PackedByteArray([0,0,0,1,0,0,0,1,8,3,0,0,0])
	for entry: Array in [["IHDR",head],["PLTE",PackedByteArray([255,0,0])],["tRNS",PackedByteArray([128])],["IDAT",PackedByteArray([0,0]).compress(FileAccess.COMPRESSION_DEFLATE)],["IEND",PackedByteArray()]]:
		var kind: PackedByteArray = str(entry[0]).to_ascii_buffer()
		var data: PackedByteArray = entry[1]
		var chunk := PackedByteArray()
		chunk.resize(4)
		chunk.encode_u32(0,_swap(data.size()))
		chunk.append_array(kind)
		chunk.append_array(data)
		var crc := PackedByteArray()
		crc.resize(4)
		crc.encode_u32(0,_swap(PngCheck.crc32(kind + data)))
		chunk.append_array(crc)
		bytes.append_array(chunk)
	return bytes

static func _swap(value: int) -> int:
	return ((value & 255) << 24) | ((value & 65280) << 8) | ((value >> 8) & 65280) | ((value >> 24) & 255)
