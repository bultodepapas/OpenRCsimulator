## LENS-08 (docs/plans/lens-screen-effects.md §6.4): water drops on a lens, simulated on the CPU in a bounded pool.
## Screen space: x in [0, aspect], y in [0, 1] downward, lengths in screen heights. Presentation only, not replay
## identical: arrivals follow the active camera and motion advances per rendered frame (§4.2).
##
## Forces per drop with ρ = r / R0 (mass ∝ ρ³): gravity ρ³·g (g = gravity projected on the image plane), air shear
## ρ²·A·a (a grows with airspeed², pointing away from the focus of expansion) and a pinning threshold ρ·P (contact
## angle hysteresis). Small beads stick, large ones run, and at speed the air wins; blown beads streak off the glass.
## Overlapping drops merge with volume and momentum conserved; a running drop sheds micro-beads (its track).
extends RefCounted

const R0 := 0.01
const GRAVITY_FORCE := 1.0
const AIR_FORCE := 2.5
const PIN_FORCE := 1.8
const ACCELERATION := 1.2
const DAMPING := 3.0
const MIN_RADIUS := 0.0015
const MAX_RADIUS := 0.045
const TRAIL_STEP := 0.012
const TRAIL_SHARE := 0.28
const BLOW_OFF_AIR := 0.6
const BLOW_OFF_RHO := 0.65
const FADE_IN_S := 0.08
const LINGER_S := 40.0
const FADE_OUT_S := 18.0
const MERGE_SHARE := 0.85
const CELL := 0.1
const SURFACE_CELL := 0.035
const PIN_PATCH_MIN := 0.55
const PIN_PATCH_SPAN := 0.9
const GRID_SLOTS := 256
## MultiMesh buffer floats per 2D instance with custom data: 8 transform + 4 custom.
const BUFFER_STRIDE := 12

const X := 0
const Y := 1
const R := 2
const VX := 3
const VY := 4
const AGE := 5
const TRAIL := 6
const SEED := 7
const STRIDE := 8

var capacity := 0
var count := 0
var trails := true
var _data := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _grid_head := PackedInt32Array()
var _grid_next := PackedInt32Array()
var _gone := PackedByteArray()
## Set whenever a drop changed; write() skips the MultiMesh upload otherwise (paused or empty frames).
var _dirty := true
var _written_height := -1.0
var _buffer := PackedFloat32Array()
var _surface_seed := 0


func configure(max_drops: int, stream: int, with_trails: bool) -> void:
	capacity = maxi(max_drops, 0)
	trails = with_trails
	count = 0
	_data.resize(capacity * STRIDE)
	_data.fill(0.0)
	_rng.seed = stream
	_surface_seed = posmod(stream, 65521)
	_grid_head.resize(GRID_SLOTS)
	_grid_next.resize(capacity)
	_gone.resize(capacity)
	_dirty = true


func clear() -> void:
	count = 0
	_dirty = true


## Adds a drop; a full pool replaces its smallest drop when the new one is larger.
func spawn(x: float, y: float, radius: float) -> void:
	if capacity <= 0:
		return
	radius = clampf(radius, MIN_RADIUS, MAX_RADIUS)
	var slot := count
	if count >= capacity:
		slot = -1
		var smallest := radius
		for i in count:
			if _data[i * STRIDE + R] < smallest:
				smallest = _data[i * STRIDE + R]
				slot = i
		if slot < 0:
			return
	else:
		count += 1
	_dirty = true
	var base := slot * STRIDE
	_data[base + X] = x
	_data[base + Y] = y
	_data[base + R] = radius
	_data[base + VX] = 0.0
	_data[base + VY] = 0.0
	_data[base + AGE] = 0.0
	_data[base + TRAIL] = 0.0
	_data[base + SEED] = _rng.randf()


## Uniform random position on the screen.
func spawn_random(aspect: float, radius: float) -> void:
	spawn(_rng.randf() * aspect, _rng.randf(), radius)


func random() -> float:
	return _rng.randf()


## Poisson count for an expected number of arrivals this frame (Knuth for small means, normal approximation above).
func poisson(mean: float) -> int:
	if not (mean > 0.0):
		return 0
	if mean > 12.0:
		return maxi(0, int(round(_rng.randfn(mean, sqrt(mean)))))
	var limit := exp(-mean)
	var product := _rng.randf()
	var k := 0
	while product > limit and k < 64:
		product *= _rng.randf()
		k += 1
	return k


## Advances the pool. `gravity` is gravity on the image plane (screen axes, |g| ≤ 1), `focus` the focus of expansion
## (screen space), `air` the shear strength (0 still, 1 ≈ 30 m/s), `lateral` a uniform sideways shear (screen axes),
## `raining` keeps drops from drying.
## `inertia` is the camera's acceleration felt by the glass, as a pseudo-gravity on the image plane (g units): a punch-out,
## a flip or a hard turn throws the drops against the motion, like gravity, in proportion to their mass.
func step(dt: float, aspect: float, gravity: Vector2, focus: Vector2, air: float, lateral: Vector2, raining: bool,
		inertia: Vector2 = Vector2.ZERO) -> void:
	if dt <= 0.0 or count == 0:
		return
	_dirty = true
	var i := 0
	while i < count:
		var base := i * STRIDE
		var r: float = _data[base + R]
		var rho := r / R0
		var position := Vector2(_data[base + X], _data[base + Y])
		var velocity := Vector2(_data[base + VX], _data[base + VY])
		var away := position - focus
		var radial := away.normalized() if away.length_squared() > 1e-8 else Vector2.ZERO
		var force := (gravity + inertia) * GRAVITY_FORCE * rho * rho * rho + (radial * air + lateral) * AIR_FORCE * rho * rho
		# Real glass is not uniform: dust and coating wear make the pinning patchy, so running drops stall and lurch
		# (stick-slip) instead of gliding at a constant speed.
		var pin := PIN_FORCE * rho * (PIN_PATCH_MIN + PIN_PATCH_SPAN * _surface(position))
		var magnitude := force.length()
		if magnitude > pin:
			var net := force * ((magnitude - pin) / magnitude)
			velocity += (net / (rho * rho * rho) * ACCELERATION - velocity * DAMPING) * dt
		else:
			velocity = velocity.move_toward(Vector2.ZERO, dt * 2.0)
		var travel := velocity * dt
		position += travel
		var age: float = _data[base + AGE] + dt
		# A blown bead leaves the glass.
		var removed := air > BLOW_OFF_AIR and rho < BLOW_OFF_RHO and _rng.randf() < dt * 3.0 * air
		if not raining and age > LINGER_S + FADE_OUT_S:
			removed = true
		if not raining:
			r -= dt * 0.00002
		removed = removed or r < MIN_RADIUS or position.x < -MAX_RADIUS or position.x > aspect + MAX_RADIUS \
			or position.y < -MAX_RADIUS or position.y > 1.0 + MAX_RADIUS
		if removed:
			_remove(i)
			continue
		_data[base + X] = position.x
		_data[base + Y] = position.y
		_data[base + R] = r
		_data[base + VX] = velocity.x
		_data[base + VY] = velocity.y
		_data[base + AGE] = age
		if trails and rho > 0.9:
			var trail: float = _data[base + TRAIL] + travel.length()
			if trail >= TRAIL_STEP:
				trail = 0.0
				var bead := r * TRAIL_SHARE
				# Volume moves from the runner to the bead it leaves behind.
				_data[base + R] = pow(maxf(r * r * r - bead * bead * bead, 0.0), 1.0 / 3.0)
				if count < capacity:
					var back := velocity.normalized() * r * 1.1
					spawn(position.x - back.x, position.y - back.y, bead)
			_data[base + TRAIL] = trail
		i += 1
	_merge()


## Opacity of drop `i` (fade in on arrival, fade out after the rain stops).
func alpha(i: int, raining: bool) -> float:
	var age: float = _data[i * STRIDE + AGE]
	var a := clampf(age / FADE_IN_S, 0.0, 1.0)
	if not raining:
		a *= clampf(1.0 - (age - LINGER_S) / FADE_OUT_S, 0.0, 1.0)
	return a


func drop_position(i: int) -> Vector2:
	return Vector2(_data[i * STRIDE + X], _data[i * STRIDE + Y])


func drop_radius(i: int) -> float:
	return _data[i * STRIDE + R]


func drop_velocity(i: int) -> Vector2:
	return Vector2(_data[i * STRIDE + VX], _data[i * STRIDE + VY])


func seed_of(i: int) -> float:
	return _data[i * STRIDE + SEED]


## Total water volume (Σ r³), for conservation tests.
func volume() -> float:
	var total := 0.0
	for i in count:
		var r: float = _data[i * STRIDE + R]
		total += r * r * r
	return total


## Writes the live drops into a 2D MultiMesh: a unit quad scaled to the drop, stretched and turned along its motion.
## Custom data: (elongation, opacity, seed, radius in pixels).
## `gravity` (screen axes): a large drop held by pinning still sags along it into a pear shape.
func write(mesh: MultiMesh, height_px: float, raining: bool, gravity: Vector2 = Vector2(0.0, 1.0)) -> void:
	if not _dirty and is_equal_approx(height_px, _written_height):
		return
	_dirty = false
	_written_height = height_px
	var n := mini(count, mesh.instance_count)
	# One buffer upload instead of two engine calls per drop. 2D layout per instance (no colours, custom data):
	# x.x, y.x, 0, origin.x, x.y, y.y, 0, origin.y, then custom r, g, b, a.
	if _buffer.size() != mesh.instance_count * BUFFER_STRIDE:
		_buffer.resize(mesh.instance_count * BUFFER_STRIDE)
		_buffer.fill(0.0)
	for i in n:
		var base := i * STRIDE
		var r: float = _data[base + R]
		var vx: float = _data[base + VX]
		var vy: float = _data[base + VY]
		var speed := sqrt(vx * vx + vy * vy)
		var elongation := clampf(speed * 4.0, 0.0, 1.6)
		var angle := atan2(vy, vx) if speed > 1e-4 else _data[base + SEED] * TAU
		var sag := clampf((r / R0 - 0.9) * 0.18, 0.0, 0.35) * clampf(gravity.length(), 0.0, 1.0)
		if sag > elongation and gravity.length_squared() > 0.01:
			# At rest a heavy drop hangs: its body slides a little down the glass, the head stays pinned.
			elongation = sag
			angle = gravity.angle()
		var diameter_px := 2.0 * r * height_px
		var sx := diameter_px * (1.0 + elongation)
		var c := cos(angle)
		var s := sin(angle)
		var o := i * BUFFER_STRIDE
		_buffer[o] = c * sx
		_buffer[o + 1] = -s * diameter_px
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = _data[base + X] * height_px
		_buffer[o + 4] = s * sx
		_buffer[o + 5] = c * diameter_px
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = _data[base + Y] * height_px
		_buffer[o + 8] = elongation
		_buffer[o + 9] = alpha(i, raining)
		_buffer[o + 10] = _data[base + SEED]
		_buffer[o + 11] = r * height_px
	mesh.buffer = _buffer
	mesh.visible_instance_count = n


func _remove(i: int) -> void:
	count -= 1
	if i != count:
		for k in STRIDE:
			_data[i * STRIDE + k] = _data[count * STRIDE + k]


## Merges overlapping drops through a persistent hashed grid (head/next index lists): no allocation per frame.
## Hash collisions only add distance checks; they never merge drops that do not overlap.
func _merge() -> void:
	if count < 2:
		return
	_grid_head.fill(-1)
	if _grid_next.size() < capacity:
		_grid_next.resize(capacity)
	if _gone.size() < capacity:
		_gone.resize(capacity)
	for i in count:
		_gone[i] = 0
		var slot := _grid_slot(int(floorf(_data[i * STRIDE + X] / CELL)), int(floorf(_data[i * STRIDE + Y] / CELL)))
		_grid_next[i] = _grid_head[slot]
		_grid_head[slot] = i
	var merged := false
	for i in count:
		if _gone[i] != 0:
			continue
		var bi := i * STRIDE
		var cx := int(floorf(_data[bi + X] / CELL))
		var cy := int(floorf(_data[bi + Y] / CELL))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var j: int = _grid_head[_grid_slot(cx + dx, cy + dy)]
				while j >= 0:
					var next_j: int = _grid_next[j]
					if j > i and _gone[j] == 0:
						var bj := j * STRIDE
						var ri: float = _data[bi + R]
						var rj: float = _data[bj + R]
						var ddx: float = _data[bj + X] - _data[bi + X]
						var ddy: float = _data[bj + Y] - _data[bi + Y]
						if ddx * ddx + ddy * ddy <= _square((ri + rj) * MERGE_SHARE):
							var vi := ri * ri * ri
							var vj := rj * rj * rj
							var total := vi + vj
							_data[bi + X] = (_data[bi + X] * vi + _data[bj + X] * vj) / total
							_data[bi + Y] = (_data[bi + Y] * vi + _data[bj + Y] * vj) / total
							_data[bi + VX] = (_data[bi + VX] * vi + _data[bj + VX] * vj) / total
							_data[bi + VY] = (_data[bi + VY] * vi + _data[bj + VY] * vj) / total
							_data[bi + R] = minf(pow(total, 1.0 / 3.0), MAX_RADIUS)
							_data[bi + AGE] = maxf(_data[bi + AGE], _data[bj + AGE])
							_gone[j] = 1
							merged = true
					j = next_j
	if not merged:
		return
	# Remove from the end so swapped-in drops are never ones still marked.
	for j in range(count - 1, -1, -1):
		if _gone[j] != 0:
			_remove(j)


func _grid_slot(cx: int, cy: int) -> int:
	return posmod(cx * 73856093 ^ cy * 19349663, GRID_SLOTS)


## Smooth value noise in [0, 1] over the glass (cells of SURFACE_CELL screen heights), fixed per pool seed.
func _surface(at: Vector2) -> float:
	var gx := at.x / SURFACE_CELL
	var gy := at.y / SURFACE_CELL
	var ix := int(floorf(gx))
	var iy := int(floorf(gy))
	var fx := gx - float(ix)
	var fy := gy - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _cell_noise(ix, iy)
	var b := _cell_noise(ix + 1, iy)
	var c := _cell_noise(ix, iy + 1)
	var d := _cell_noise(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _cell_noise(ix: int, iy: int) -> float:
	var h := (ix * 374761393 + iy * 668265263 + _surface_seed * 1274126177) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return float(h & 0xFFFF) / 65535.0


## A drop striking the lens at speed breaks into a crown: a few satellite beads thrown around it.
func splash(x: float, y: float, radius: float, beads: int) -> void:
	for k in beads:
		var angle := _rng.randf() * TAU
		var distance := radius * _rng.randf_range(1.6, 3.2)
		spawn(x + cos(angle) * distance, y + sin(angle) * distance, radius * _rng.randf_range(0.18, 0.35))


static func _square(x: float) -> float:
	return x * x
