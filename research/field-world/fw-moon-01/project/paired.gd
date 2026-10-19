# FW-MOON-01 paired bench: the small effects measured inside ONE process, configurations interleaved in blocks so
# the shared VM's load drift hits every configuration alike. Each cycle runs one block per configuration
# (order rotated per cycle); a block discards SETTLE frames after the switch and records the rest.
# Paired estimate per cycle: block median(config) - block median(static). Run: run.sh OUT paired (scene paired.tscn).
# User args: --cycles=25 --block=30 --warmup=120 --out=<json>
extends "res://bench.gd"

const CONFIGS := ["static", "uniform", "mesh_disc", "light2"]
const SETTLE := 6

var cycles := 25
var block := 30
var warm := 120
var cfg_index := 0
var in_block := 0
var cycle := 0
var paired_frame := 0
var paired_last := 0
var current := ""
var block_wall := PackedFloat64Array()
var block_cpu := PackedFloat64Array()
var block_gpu := PackedFloat64Array()
var blocks := []
var all := {}


func _ready() -> void:
	super._ready()
	cycles = int(args.get("cycles", "25"))
	block = int(args.get("block", "30"))
	warm = int(args.get("warmup", "120"))
	_add_light2(false)
	light2.visible = false
	for c: String in CONFIGS:
		all[c] = {wall = PackedFloat64Array(), cpu = PackedFloat64Array(), gpu = PackedFloat64Array()}
	_apply(CONFIGS[0])


func _apply(c: String) -> void:
	current = c
	var mesh := c == "mesh_disc"
	sky_mat.set_shader_parameter("moon_lin", Vector3.ZERO if mesh else Vector3(0.6, 0.6, 0.58))
	disc.visible = mesh
	light2.visible = c == "light2"


static func _median(v: PackedFloat64Array) -> float:
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2] if s.size() else NAN


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if current == "uniform" or current == "mesh_disc":
		moon_az += STEP_DEG_PER_FRAME
		var d := dir_from(moon_az, moon_el)
		(disc_mat if current == "mesh_disc" else sky_mat).set_shader_parameter("moon_dir", d)
	if paired_frame > warm and in_block >= SETTLE:
		var vp := get_viewport().get_viewport_rid()
		var w := float(now - paired_last) / 1000.0
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		block_wall.append(w)
		block_cpu.append(cpu)
		block_gpu.append(gpu)
		all[current].wall.append(w)
		all[current].cpu.append(cpu)
		all[current].gpu.append(gpu)
	paired_last = now
	paired_frame += 1
	in_block += 1
	if in_block < block:
		return
	# End of block: store it (after warm-up), then switch to the next configuration of the rotated cycle order.
	if paired_frame > warm and block_wall.size() > 0:
		blocks.append({cycle = cycle, config = current, wall = _median(block_wall), cpu = _median(block_cpu),
			gpu = _median(block_gpu), n = block_wall.size()})
	block_wall = PackedFloat64Array()
	block_cpu = PackedFloat64Array()
	block_gpu = PackedFloat64Array()
	in_block = 0
	cfg_index += 1
	if cfg_index >= CONFIGS.size():
		cfg_index = 0
		if paired_frame > warm:
			cycle += 1
	if cycle >= cycles:
		var per := {}
		for c: String in CONFIGS:
			per[c] = {wall = all[c].wall, cpu = all[c].cpu, gpu = all[c].gpu}
		_write({paired_blocks = blocks, paired_samples = per, block = block, settle = SETTLE, cycles = cycles})
		get_tree().quit()
		return
	_apply(CONFIGS[(cfg_index + cycle) % CONFIGS.size()])
