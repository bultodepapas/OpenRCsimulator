# SUN-02: a CPU mirror of sky.gdshader toward one direction, read from the live sky material (weather tints, flow
# steps and FW-MOON-06d frames included).
# - background_luminance: the sky's gradient (haze with its sun scatter and horizon lobes, toward the zenith), without
#   the sun's own halo or aureole: the luminance a model near the sun is seen against, for the veil's E/B.
# - transmission: the cloud optical density, so the sun glare and the afterimage dose dim behind exactly the deck the
#   sky draws (the classic deck with its cirrus, or the layered appearance decks; the disc there is multiplied by
#   exp(−8·(density + cirrus))). The noise mirrors
# render/cloud_field.gdshaderinc with its 32-bit unsigned hash arithmetic emulated exactly. Cell coordinates are
# Vector2 (float32, as on the GPU), the octave sums float64: results differ from the shader only at the coverage
# threshold's edges. Read-only: it never writes the sky material.
extends RefCounted

const PERIOD := 64
const MASK32 := 0xFFFFFFFF
## sky.gdshader: the disc's optical thickness per unit of deck density.
const DISC_OPTICAL_SCALE := 8.0


## Luminance of the sky's gradient toward `dir` (render axes, unit), scene units (sky.gdshader haze() and the
## zenith mix; no disc, halo, aureole, moon or clouds).
static func background_luminance(sky: ShaderMaterial, dir: Vector3) -> float:
	var col := background_radiance(sky, dir)
	return 0.2126 * col.x + 0.7152 * col.y + 0.0722 * col.z


## The sky gradient's linear colour toward `dir`, pre-exposure (what background_luminance weighs): the colour a veil
## must never mix below (SUN-02).
static func background_radiance(sky: ShaderMaterial, dir: Vector3) -> Vector3:
	if sky == null or not dir.is_finite():
		return Vector3.ZERO
	var haze: Vector3 = _param(sky, &"haze_lin", Vector3(0.584, 0.768, 0.846))
	var zenith: Vector3 = _param(sky, &"zenith_lin", Vector3(0.076, 0.138, 0.287))
	var sun_dir: Vector3 = _param(sky, &"sun_dir", Vector3(0.0, 0.707, 0.707))
	var sun_lin: Vector3 = _param(sky, &"sun_lin", Vector3.ONE * PI)
	var scatter := float(_param(sky, &"sun_scatter", 0.0))
	var col := haze + sun_lin * pow(maxf(dir.dot(sun_dir), 0.0), 8.0) * scatter + _lobe(sky, dir, &"lobe_lin", &"lobe_dir",
		&"lobe_k", &"lobe_height") + _lobe(sky, dir, &"lobe2_lin", &"lobe2_dir", &"lobe2_k", &"lobe2_height")
	var y := maxf(dir.y, 0.0)
	return col.lerp(zenith, 1.0 - pow(1.0 - y, float(_param(sky, &"gradient_curve", 2.6))))


## sky.gdshader lobe_term() for one lobe.
static func _lobe(sky: ShaderMaterial, d: Vector3, lin_name: StringName, dir_name: StringName, k_name: StringName,
		height_name: StringName) -> Vector3:
	var lin: Vector3 = _param(sky, lin_name, Vector3.ZERO)
	if lin.x + lin.y + lin.z <= 0.0:
		return Vector3.ZERO
	var lobe_dir: Vector3 = _param(sky, dir_name, Vector3.RIGHT)
	var h := maxf(Vector2(d.x, d.z).length(), 1e-4)
	var toward := (Vector2(lobe_dir.x, lobe_dir.z) + Vector2(1e-6, 0.0)).normalized()
	var az := maxf((Vector2(d.x, d.z) / h).dot(toward), 0.0)
	return lin * pow(az, float(_param(sky, k_name, 8.0))) * exp(-maxf(asin(clampf(d.y, -1.0, 1.0)), 0.0) / float(_param(sky, height_name, 1.5708)))


## The sky disc's transmission toward `dir` (render axes, unit) for the cloud uniforms on `sky`: 1 = clear.
static func transmission(sky: ShaderMaterial, dir: Vector3) -> float:
	return exp(-DISC_OPTICAL_SCALE * optical_density(sky, dir))


## density + cirrus amount at `dir`, as sky.gdshader accumulates them before the disc.
static func optical_density(sky: ShaderMaterial, dir: Vector3) -> float:
	if sky == null or not dir.is_finite() or dir.y <= 0.0:
		return 0.0
	if bool(_param(sky, &"layered_appearance", false)):
		return _layered(sky, dir)
	var coverage := float(_param(sky, &"cloud_coverage", 0.35))
	if coverage <= 0.0:
		return 0.0
	var deck := Vector2(dir.x, dir.z) / maxf(dir.y, 0.02)
	var offset: Vector2 = _param(sky, &"cloud_offset", Vector2.ZERO)
	var cells := (deck * float(_param(sky, &"cloud_scale", 6.0)) + offset).posmod(float(PERIOD))
	var seed := int(_param(sky, &"cloud_seed", 1)) & MASK32
	var body := cloud_density(cells, seed, coverage, float(_param(sky, &"cluster_strength", 0.0)))
	var density := body * smoothstep(0.03, 0.25, dir.y)
	var cirrus_strength := float(_param(sky, &"cirrus_strength", 0.0))
	var cirrus_amount := 0.0
	if cirrus_strength > 0.0:
		var cirrus := stretched_density(cells, (seed + 15485863) & MASK32, float(_param(sky, &"cirrus_coverage", 0.34)),
			Vector2(3.0, 51.0) / 64.0) * smoothstep(0.02, 0.18, dir.y)
		cirrus_amount = clampf(cirrus * clampf(cirrus_strength, 0.0, 0.12), 0.0, 0.12)
	return density + cirrus_amount


## The layered decks (weather profiles), upper first, composited as sky.gdshader and stars.gdshader do.
static func _layered(sky: ShaderMaterial, dir: Vector3) -> float:
	var count := int(_param(sky, &"appearance_layer_count", 0))
	var parameters: Variant = _param(sky, &"appearance_layer_parameters", [])
	var motion: Variant = _param(sky, &"appearance_layer_motion", [])
	var seeds: Variant = _param(sky, &"appearance_layer_seeds", [])
	var cloud_density_scale := clampf(float(_param(sky, &"appearance_cloud_density", 1.0)), 0.0, 1.0)
	count = mini(mini(count, 8), mini(mini(_size(parameters), _size(motion)), _size(seeds)))
	var total := 0.0
	var horizon_fade := smoothstep(0.03, 0.25, dir.y)
	for order in count:
		var index := count - 1 - order
		var layer: Vector4 = parameters[index]
		var layer_motion: Vector4 = motion[index]
		var layer_seed := maxi(int(seeds[index]), 0) & MASK32
		var deck := Vector2(dir.x, dir.z) / maxf(dir.y, 0.02) * (layer.x / maxf(layer.y, 1.0))
		var cells := (deck + Vector2(layer_motion.x, layer_motion.y)).posmod(float(PERIOD))
		var shape := int(floorf(layer_motion.w + 0.5))
		var body: float
		if shape == 1:
			body = stretched_density(cells, layer_seed, layer.z, Vector2(3.0, 51.0) / 64.0)
		elif shape == 2:
			body = stretched_density(cells, layer_seed, layer.z, Vector2(7.0, 45.0) / 64.0)
		else:
			body = cloud_density(cells, layer_seed, layer.z, layer_motion.z)
		if shape == 3:
			body = maxf(body, 0.90 * smoothstep(0.02, 0.13, dir.y) * smoothstep(0.52, 0.94, layer.z))
		var optical := clampf(layer.w, 0.0, 1.0) * cloud_density_scale
		var layer_horizon_fade := smoothstep(0.005, 0.11, dir.y) if shape == 3 else horizon_fade
		var tower_height := lerpf(0.68, 1.0, smoothstep(0.025, 0.52, dir.y)) if shape == 4 else 1.0
		var alpha := clampf(body * optical * layer_horizon_fade * tower_height, 0.0, 0.98)
		total = 1.0 - (1.0 - total) * (1.0 - alpha)
	return total


## cloud_field.gdshaderinc cloud_density().
static func cloud_density(cells: Vector2, seed: int, coverage: float, cluster_strength: float) -> float:
	var bounded := clampf(coverage, 0.0, 1.0)
	if bounded <= 0.0:
		return 0.0
	var noise := fbm(cells, seed, Vector2.ONE)
	var strength := clampf(cluster_strength, 0.0, 1.0)
	var local := bounded
	if strength > 0.0:
		var coarse := cells.posmod(float(PERIOD)) / 16.0
		var cluster := smoothstep(0.2, 0.8, value_noise(coarse, Vector2i(4, 4), (seed + 104729) & MASK32))
		local = clampf(bounded + (cluster - 0.5) * 0.7 * strength, 0.0, 1.0)
	return _threshold(noise, local)


## cloud_field.gdshaderinc cloud_stretched_density().
static func stretched_density(cells: Vector2, seed: int, coverage: float, frequency: Vector2) -> float:
	return _threshold(fbm(cells, seed, frequency), coverage)


static func _threshold(noise: float, coverage: float) -> float:
	var c := clampf(coverage, 0.0, 1.0)
	return smoothstep(1.0 - c, 1.25 - c, noise)


## cloud_field_fbm(): five octaves of periodic value noise.
static func fbm(cells: Vector2, seed: int, frequency: Vector2) -> float:
	var p := cells * frequency
	var period := float(PERIOD) * frequency
	var total := 0.0
	var amp := 0.5
	for octave in 5:
		var q := Vector2(fposmod(p.x, period.x), fposmod(p.y, period.y))
		var lattice := Vector2i(int(floorf(period.x + 0.5)), int(floorf(period.y + 0.5)))
		total += amp * value_noise(q, lattice, (seed + octave * 7919) & MASK32)
		p *= 2.0
		period *= 2.0
		amp *= 0.5
	return total / 0.96875


## cloud_field_value_noise(): quintic value noise with independent axis periods.
static func value_noise(p: Vector2, period: Vector2i, seed: int) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * f * (f * (f * 6.0 - Vector2(15.0, 15.0)) + Vector2(10.0, 10.0))
	var x0 := posmod(int(i.x), period.x)
	var x1 := posmod(int(i.x) + 1, period.x)
	var y0 := posmod(int(i.y), period.y)
	var y1 := posmod(int(i.y) + 1, period.y)
	var a := hash2(x0, y0, seed)
	var b := hash2(x1, y0, seed)
	var d := hash2(x0, y1, seed)
	var e := hash2(x1, y1, seed)
	return lerpf(lerpf(a, b, u.x), lerpf(d, e, u.x), u.y)


## cloud_field_hash2(): uint arithmetic modulo 2³².
static func hash2(x: int, y: int, seed: int) -> float:
	var qx := mul32(x & MASK32, 1597334677)
	var qy := mul32(y & MASK32, 3812015801)
	var n := mul32(qx ^ qy ^ mul32(seed & MASK32, 2654435761), 1597334677)
	return float(n >> 8) * (1.0 / 16777216.0)


## a·b mod 2³² for a, b in [0, 2³²) without overflowing the 64-bit int.
static func mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK32


static func _param(sky: ShaderMaterial, uniform_name: StringName, fallback: Variant) -> Variant:
	var value: Variant = sky.get_shader_parameter(uniform_name)
	return fallback if value == null else value


static func _size(value: Variant) -> int:
	return value.size() if value is Array or value is PackedVector4Array or value is PackedInt32Array \
		or value is PackedInt64Array or value is PackedFloat32Array else 0
