extends SceneTree
const Jpeg := preload("res://workshop/creator/clearview/jpeg_check.gd")
const Images := preload("res://workshop/creator/clearview/images.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	for bytes: PackedByteArray in [_jpeg(1,1,PackedByteArray([3,255,217])), _jpeg(1,1,PackedByteArray([0,15,255,217]),true), _jpeg(16,8,PackedByteArray([3,255,208,3,255,217]),false,1)]:
		check("independent coefficient-zero JPEG accepted", Jpeg.inspect(bytes,200).ok)
		var normalized := Images.normalize(bytes)
		check("validated JPEG normalized", normalized.ok)
		if normalized.ok:
			var image := Image.new()
			check("PNG decode", image.load_png_from_buffer(normalized.value.png) == OK)
			var pixel := image.get_pixel(0,0)
			# IDCT of zero coefficients plus the 128 level shift is exactly neutral RGB 128.
			check("independent pixel oracle", pixel.is_equal_approx(Color(128.0/255.0,128.0/255.0,128.0/255.0)))
	var valid := _jpeg(1,1,PackedByteArray([3,255,217]))
	for size: int in valid.size():
		check("every truncated prefix refused", not Jpeg.inspect(valid.slice(0,size),200).ok)
	check("non-one padding refused", not Jpeg.inspect(_jpeg(1,1,PackedByteArray([2,255,217])),200).ok)
	check("extra entropy refused", not Jpeg.inspect(_jpeg(1,1,PackedByteArray([3,0,255,217])),200).ok)
	check("unescaped FF refused", not Jpeg.inspect(_jpeg(1,1,PackedByteArray([255,217])),200).ok)
	check("wrong restart refused", not Jpeg.inspect(_jpeg(16,8,PackedByteArray([3,255,209,3,255,217]),false,1),200).ok)
	check("missing restart refused", not Jpeg.inspect(_jpeg(16,8,PackedByteArray([3,3,255,217]),false,1),200).ok)
	check("trailing data refused", not Jpeg.inspect(valid + PackedByteArray([0]),200).ok)
	check("pixel limit before decode", not Jpeg.inspect(valid,0).ok)
	check("JPEG cancellation", not Jpeg.inspect(valid,200,func() -> bool: return true).ok)
	var image := Image.create(32,32,false,Image.FORMAT_RGB8)
	for y: int in 32:
		for x: int in 32:
			image.set_pixel(x,y,Color(float(x)/31.0,float(y)/31.0,float((x+y)%32)/31.0))
	var native := image.save_jpg_to_buffer(0.9)
	check("independent native-encoder coefficients", Jpeg.inspect(native,32*32).ok)
	check("native-encoder image normalized", Images.normalize(native).ok)
	var positions: Array[int] = []
	for at: int in mini(native.size(),512):
		positions.append(at)
	var start := _entropy_start(native)
	check("native entropy located", start > 0 and start < native.size() - 2)
	for at: int in range(start,native.size() - 2,3):
		positions.append(at)
	for at: int in positions:
		var mutated := native.duplicate()
		mutated[at] ^= 0x80
		var checked := Jpeg.inspect(mutated,32*32)
		# A valid mutation may change pixels. Only validated streams reach the native decoder.
		if checked.ok:
			check("accepted mutation also decodes", Images.normalize(mutated).ok)
	var zrl := _jpeg(1,1,PackedByteArray([0x54,0x54,0x54,255,217]),false,0,0,1)
	check("three zero runs and EOB per block", Jpeg.inspect(zrl,1).ok and Images.normalize(zrl).ok)
	check("zero run overflow refused", not Jpeg.inspect(_jpeg(1,1,PackedByteArray([0x55,0x7F,255,217]),false,0,0,1),1).ok)
	var bits := ""
	for component: int in 3:
		bits += "0" # zero DC
		for coefficient: int in 63:
			bits += "0" + "1".repeat(10) # AC category 10, +1023; no EOB after coefficient 63
	var stuffed := _pack_entropy(bits)
	check("stuffing fixture contains FF00", stuffed.count(255) > 0)
	var full := _jpeg(1,1,stuffed + PackedByteArray([255,217]),false,0,0,2)
	check("amplitudes and FF00 stuffing accepted", Jpeg.inspect(full,1).ok and Images.normalize(full).ok)
	var restart_bits := ("0" + "1".repeat(10) + "0").repeat(3)
	var interval := _pack_entropy(restart_bits)
	var reset := _jpeg(16,8,interval + PackedByteArray([255,208]) + interval + PackedByteArray([255,217]),false,1,10)
	check("DC predictors reset at restart", Jpeg.inspect(reset,128).ok and Images.normalize(reset).ok)
	_metadata(valid, native)
	print("ClearView JPEG: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ",label)

## Real ClearView textures carry EXIF (APP1), ICC (APP2) and Photoshop (APP13) segments.
func _metadata(valid: PackedByteArray, native: PackedByteArray) -> void:
	var plain := Jpeg.inspect(valid,200)
	check("metadata-free JPEG has no metadata note", plain.ok and not plain.diagnostics.any(func(d: Dictionary) -> bool: return d.message == Jpeg.METADATA_NOTE))
	for marker: int in [0xE1,0xE2,0xED,0xEF]:
		var tagged := _with_segments(valid,[_segment(marker,PackedByteArray([69,120,105,102,0,0,73,73,42]))])
		var checked := Jpeg.inspect(tagged,200)
		check("APP%d metadata skipped" % (marker - 0xE0), checked.ok and checked.diagnostics.size() == 1
			and checked.diagnostics[0].message == Jpeg.METADATA_NOTE)
		check("APP%d image still decodes to the oracle" % (marker - 0xE0), Images.normalize(tagged).ok)
	var stacked := _with_segments(native,[_segment(0xE1,PackedByteArray([1,2,3])),_segment(0xE2,PackedByteArray([4])),_segment(0xED,PackedByteArray())])
	check("stacked metadata over a native image", Jpeg.inspect(stacked,32*32).ok and Images.normalize(stacked).ok)
	var filler := PackedByteArray()
	filler.resize(65533)
	var segments: Array = []
	for index: int in 17:
		segments.append(_segment(0xE1,filler))
	var oversized := Jpeg.inspect(_with_segments(valid,segments),200)
	check("metadata total is bounded", not oversized.ok and oversized.diagnostics[0].code == "SOURCE_LIMIT")
	var truncated := _with_segments(valid,[PackedByteArray([255,0xE1,0,200,1,2])])
	check("metadata length beyond the file refused", not Jpeg.inspect(truncated,200).ok)
	# Real downloads (Mig-15, Parkzone Vapor): Adobe APP14 with encoder-hint flags 0x8000/0xC000.
	for flags: int in [0x80, 0xC0]:
		var adobe := _with_segments(valid,[_segment(0xEE,PackedByteArray([65,100,111,98,101,0,100,flags,0,0,0,1]))])
		check("Adobe encoder-hint flags 0x%X00 accepted" % flags, Jpeg.inspect(adobe,200).ok and Images.normalize(adobe).ok)
	# Real downloads (EF-Sabre): 4:2:2 luma sampling, in both orientations.
	for sampling: int in [0x21, 0x12]:
		var base := _jpeg(1,1,PackedByteArray([0,255,217]),true)
		var at := 0
		for index: int in base.size() - 2:
			if base[index] == 3 and base[index + 1] == 1 and base[index + 2] == 0x22:
				at = index + 2
		base[at] = sampling
		check("4:2:2 sampling 0x%X validated and decoded" % sampling, at > 0 and Jpeg.inspect(base,200).ok and Images.normalize(base).ok)
		var short := base.slice(0, base.size() - 3) + PackedByteArray([255,217])
		check("4:2:2 sampling 0x%X still checks every block" % sampling, not Jpeg.inspect(short,200).ok)
	var ycck := _with_segments(valid,[_segment(0xEE,PackedByteArray([65,100,111,98,101,0,100,0,0,0,0,2]))])
	check("Adobe YCCK transform still refused", not Jpeg.inspect(ycck,200).ok)
	check("progressive coding still refused", not Jpeg.inspect(_with_segments(valid,[]).slice(0,2) + _segment(0xC2,PackedByteArray([8,0,1,0,1,3,1,0x11,0,2,0x11,0,3,0x11,0])),200).ok)

## Insert segments after SOI and any leading JFIF APP0, as real files order them.
static func _with_segments(jpeg: PackedByteArray, segments: Array) -> PackedByteArray:
	var at := 2
	if jpeg.size() > 6 and jpeg[2] == 255 and jpeg[3] == 0xE0:
		at = 4 + ((jpeg[4] << 8) | jpeg[5])
	var bytes := jpeg.slice(0,at)
	for segment: PackedByteArray in segments:
		bytes += segment
	return bytes + jpeg.slice(at)

static func _segment(marker: int, payload: PackedByteArray) -> PackedByteArray:
	var length := payload.size() + 2
	return PackedByteArray([255,marker,length >> 8,length & 255]) + payload

static func _jpeg(width: int, height: int, entropy: PackedByteArray, subsampled := false, restart := 0, dc_category := 0, ac_mode := 0) -> PackedByteArray:
	var bytes := PackedByteArray([255,216])
	var q := PackedByteArray([0])
	for index: int in 64:
		q.append(1)
	bytes += _segment(0xDB,q)
	var h := PackedByteArray()
	for kind: int in [0,16]:
		h.append(kind)
		h.append(1)
		for index: int in 15:
			h.append(1 if kind == 16 and ac_mode == 1 and index == 0 else 0)
		h.append(dc_category if kind == 0 else (10 if ac_mode == 2 else 0))
		if kind == 16 and ac_mode == 1:
			h.append(0xF0)
	bytes += _segment(0xC4,h)
	bytes += _segment(0xC0,PackedByteArray([8,height >> 8,height & 255,width >> 8,width & 255,3,1,0x22 if subsampled else 0x11,0,2,0x11,0,3,0x11,0]))
	if restart > 0:
		bytes += _segment(0xDD,PackedByteArray([restart >> 8,restart & 255]))
	bytes += _segment(0xDA,PackedByteArray([3,1,0,2,0,3,0,0,63,0]))
	return bytes + entropy

static func _pack_entropy(bits: String) -> PackedByteArray:
	while bits.length() % 8:
		bits += "1"
	var result := PackedByteArray()
	for at: int in range(0,bits.length(),8):
		var value := 0
		for bit: int in 8:
			value = (value << 1) | (1 if bits[at + bit] == "1" else 0)
		result.append(value)
		if value == 255:
			result.append(0)
	return result

static func _entropy_start(bytes: PackedByteArray) -> int:
	var at := 2
	while at + 4 <= bytes.size():
		if bytes[at] != 255:
			return -1
		var marker: int = bytes[at + 1]
		var length: int = (bytes[at + 2] << 8) | bytes[at + 3]
		at += 2 + length
		if marker == 0xDA:
			return at
	return -1
