## DT-MAC-13d1a: isolated RenderingDevice triangle-query fixture.
## Run each --case in a fresh Metal process; the Python runner validates diagnostics.
extends SceneTree

const PREFIX := "METAL_TRIANGLE_QUERY "
const SENTINEL := 0x5a5aa5a5
const SHADER := """
#version 460
#extension GL_EXT_ray_query : require
layout(local_size_x = 4, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform accelerationStructureEXT world_as;
layout(set = 0, binding = 1, std430) buffer Output { uvec4 result[]; } output_data;
void main() {
    uint i = gl_GlobalInvocationID.x;
    vec3 origin = i == 1 ? vec3(10.0, 1.0, 0.0) :
                  i == 2 ? vec3(2.0, 4.0, 0.0) : vec3(2.0, 1.0, 0.0);
    float maximum = i == 3 ? 4.9 : 100.0;
    rayQueryEXT query;
    rayQueryInitializeEXT(query, world_as, gl_RayFlagsOpaqueEXT, 0xff,
                          origin, 0.01, vec3(0.0, 0.0, -1.0), maximum);
    while (rayQueryProceedEXT(query)) { }
    uint hit = rayQueryGetIntersectionTypeEXT(query, true);
    if (hit == gl_RayQueryCommittedIntersectionTriangleEXT) {
        output_data.result[i] = uvec4(1u,
            rayQueryGetIntersectionPrimitiveIndexEXT(query, true),
            rayQueryGetIntersectionInstanceCustomIndexEXT(query, true),
            floatBitsToUint(rayQueryGetIntersectionTEXT(query, true)));
    } else {
        output_data.result[i] = uvec4(0u, 0u, 0u, 0u);
    }
}
"""

var failures: Array[String] = []
var case_name := "happy"
var result: Dictionary = {"scope": "local_rendering_device_compute_query", "cases": {}}
var rd: RenderingDevice
var vertex := RID()
var blas := RID()
var tlas := RID()
var output := RID()
var indirect := RID()
var shader := RID()
var pipeline := RID()
var uniform_set := RID()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_name = arg.trim_prefix("--case=")
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _finish() -> void:
	if rd != null:
		# Finish any queued build even in a negative case before destroying its inputs.
		rd.submit()
		rd.sync()
		if uniform_set.is_valid() and rd.uniform_set_is_valid(uniform_set):
			rd.free_rid(uniform_set)
		if pipeline.is_valid():
			rd.free_rid(pipeline)
		if shader.is_valid():
			rd.free_rid(shader)
		if tlas.is_valid():
			rd.free_rid(tlas)
		if blas.is_valid():
			rd.free_rid(blas)
		if vertex.is_valid():
			rd.free_rid(vertex)
		if output.is_valid():
			rd.free_rid(output)
		if indirect.is_valid():
			rd.free_rid(indirect)
		rd.free()
	result["case"] = case_name
	result["failures"] = failures
	result["ok"] = failures.is_empty()
	print(PREFIX + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _geometry() -> RDAccelerationStructureGeometry:
	var geometry := RDAccelerationStructureGeometry.new()
	geometry.vertex_buffer = vertex
	geometry.vertex_stride = 12
	geometry.vertex_count = 6
	geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
	return geometry

func _instance() -> RDAccelerationStructureInstance:
	var instance := RDAccelerationStructureInstance.new()
	instance.blas = blas
	instance.id = 0x234567
	instance.mask = 0xff
	instance.transform = Transform3D(Basis.from_scale(Vector3(2.0, 1.0, 1.0)), Vector3(2.0, 1.0, -5.0))
	return instance

func _dispatch(use_indirect: bool) -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	if use_indirect:
		rd.compute_list_dispatch_indirect(list, indirect, 0)
	else:
		rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

func _run() -> void:
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["display"] = DisplayServer.get_name()
	result["engine"] = Engine.get_version_info()
	if result.driver != "metal" or result.display == "headless":
		failures.append("requires_rendered_metal")
		_finish()
		return
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		failures.append("local_rendering_device_unavailable")
		_finish()
		return
	var available := rd.has_feature(RenderingDevice.SUPPORTS_METAL_TRIANGLE_QUERY)
	result["triangle_query"] = available
	_check(not rd.has_feature(RenderingDevice.SUPPORTS_RAY_QUERY), "full_ray_query_claimed")
	_check(not rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE), "ray_pipeline_claimed")
	if case_name not in ["off", "off_blas", "off_tlas", "happy", "bad_bounds", "bad_stride", "bad_offset", "bad_capacity", "bad_id", "bad_mask", "bad_transform", "bad_sbt", "bad_flags", "empty", "rebuild", "pipeline", "sbt", "ray_list", "stale_direct", "stale_indirect", "rebuild_stale"]:
		failures.append("unknown_case")
		_finish()
		return
	if case_name in ["off", "off_blas", "off_tlas"]:
		_check(not available, "default_must_be_off")
		if case_name == "off_blas":
			_check(not rd.blas_create([], 0).is_valid(), "disabled_blas_accepted")
		elif case_name == "off_tlas":
			_check(not rd.tlas_create(1, 0).is_valid(), "disabled_tlas_accepted")
		_finish()
		return
	if not available:
		failures.append("triangle_query_unavailable")
		_finish()
		return

	if case_name == "pipeline":
		_check(not rd.raytracing_pipeline_create([], [], [], 1).is_valid(), "ray_pipeline_accepted")
		_finish()
		return
	if case_name == "sbt":
		_check(not rd.hit_sbt_create(RID(), 1).is_valid(), "sbt_accepted")
		_finish()
		return
	if case_name == "ray_list":
		_check(rd.raytracing_list_begin() == -1, "ray_list_accepted")
		_finish()
		return

	var vertices := PackedFloat32Array([-1, -1, 0, 1, -1, 0, 0, 1, 0,
		3, -1, 0, 5, -1, 0, 4, 1, 0]).to_byte_array()
	vertex = rd.vertex_buffer_create(vertices.size(), vertices, RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT)
	_check(vertex.is_valid(), "vertex_buffer")
	if not vertex.is_valid():
		_finish()
		return
	var geometry := _geometry()
	if case_name == "bad_bounds":
		geometry.vertex_count = 9
		_check(not rd.blas_create([geometry], 0).is_valid(), "out_of_bounds_accepted")
		_finish()
		return
	if case_name == "bad_stride":
		geometry.vertex_stride = 10
		_check(not rd.blas_create([geometry], 0).is_valid(), "bad_stride_accepted")
		_finish()
		return
	if case_name == "bad_offset":
		geometry.vertex_offset = 4294967296
		_check(not rd.blas_create([geometry], 0).is_valid(), "wrapped_offset_accepted")
		_finish()
		return
	if case_name == "bad_capacity":
		_check(not rd.tlas_create(4294967297, 0).is_valid(), "wrapped_capacity_accepted")
		_finish()
		return
	blas = rd.blas_create([geometry], 0)
	tlas = rd.tlas_create(1, 0)
	_check(blas.is_valid() and tlas.is_valid(), "create_as")
	if not blas.is_valid() or not tlas.is_valid():
		_finish()
		return
	_check(rd.blas_build(blas) == OK, "build_blas")
	var instance := _instance()
	if case_name == "bad_id":
		instance.id = 0x1000000
		_check(rd.tlas_build(tlas, [instance]) != OK, "out_of_range_id_accepted")
		_finish()
		return
	if case_name == "bad_mask":
		instance.mask = 256
		_check(rd.tlas_build(tlas, [instance]) != OK, "out_of_range_mask_accepted")
		_finish()
		return
	if case_name in ["bad_transform", "bad_sbt", "bad_flags"]:
		if case_name == "bad_transform":
			instance.transform = Transform3D(Basis.from_scale(Vector3(0.0, 1.0, 1.0)), Vector3.ZERO)
		elif case_name == "bad_sbt":
			instance.hit_sbt_range = 1
		else:
			instance.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_FORCE_NO_OPAQUE_BIT
		_check(rd.tlas_build(tlas, [instance]) != OK, "invalid_instance_accepted")
		_finish()
		return
	if case_name == "empty":
		_check(rd.tlas_build(tlas, []) != OK, "empty_tlas_accepted")
		_finish()
		return
	_check(rd.tlas_build(tlas, [instance]) == OK, "build_tlas")
	if case_name == "rebuild":
		_check(rd.tlas_build(tlas, [instance]) != OK, "mutable_tlas_accepted")
		_finish()
		return
	var shader_source := RDShaderSource.new()
	shader_source.source_compute = SHADER
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source, false)
	if spirv == null or not spirv.compile_error_compute.is_empty():
		failures.append("spirv_compile:" + (spirv.compile_error_compute if spirv != null else "null"))
		_finish()
		return
	shader = rd.shader_create_from_spirv(spirv, "triangle_query_probe")
	_check(shader.is_valid(), "metal_shader")
	if not shader.is_valid():
		_finish()
		return
	pipeline = rd.compute_pipeline_create(shader)
	var initial := PackedInt32Array()
	initial.resize(16)
	initial.fill(SENTINEL)
	output = rd.storage_buffer_create(64, initial.to_byte_array())
	indirect = rd.storage_buffer_create(12, PackedInt32Array([1, 1, 1]).to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	var as_uniform := RDUniform.new()
	as_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE
	as_uniform.binding = 0
	as_uniform.add_id(tlas)
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output)
	uniform_set = rd.uniform_set_create([as_uniform, output_uniform], shader, 0)
	_check(pipeline.is_valid() and output.is_valid() and indirect.is_valid() and uniform_set.is_valid(), "compute_resources")
	if not failures.is_empty():
		_finish()
		return
	_dispatch(false)
	var data := rd.buffer_get_data(output)
	_check(data.size() == 64, "readback_size")
	if data.size() == 64:
		for i in 2:
			var offset := i * 16
			_check(data.decode_u32(offset) == 1 and data.decode_u32(offset + 4) == i and data.decode_u32(offset + 8) == 0x234567 and absf(data.decode_float(offset + 12) - 5.0) < 0.001, "hit_" + str(i))
		_check(data.decode_u32(32) == 0 and data.decode_u32(48) == 0, "miss_or_tmax")
		result.cases["readback"] = {"hit0_primitive": data.decode_u32(4), "hit1_primitive": data.decode_u32(20), "instance_id": data.decode_u32(8), "distance": data.decode_float(12), "miss": data.decode_u32(32), "bounded_miss": data.decode_u32(48)}
	if case_name in ["stale_direct", "stale_indirect", "rebuild_stale"]:
		if case_name == "rebuild_stale":
			_check(rd.tlas_build(tlas, [instance]) != OK, "tlas_rebuild_accepted")
		else:
			rd.free_rid(blas)
			blas = RID()
		_check(rd.buffer_update(output, 0, 64, initial.to_byte_array()) == OK, "reset_output")
		_dispatch(case_name == "stale_indirect")
		data = rd.buffer_get_data(output)
		_check(data.size() == 64 and data.decode_u32(0) == SENTINEL and data.decode_u32(48) == SENTINEL, "stale_dispatch_executed")
	elif case_name == "happy" and failures.is_empty():
		# Destroy the first generation after completion, then build and query a new one.
		rd.free_rid(uniform_set)
		uniform_set = RID()
		rd.free_rid(tlas)
		tlas = RID()
		rd.free_rid(blas)
		blas = rd.blas_create([geometry], 0)
		tlas = rd.tlas_create(1, 0)
		_check(blas.is_valid() and tlas.is_valid(), "recreate_as")
		if blas.is_valid() and tlas.is_valid():
			_check(rd.blas_build(blas) == OK, "rebuild_new_blas")
			instance = _instance()
			instance.id = 0x345678
			_check(rd.tlas_build(tlas, [instance]) == OK, "rebuild_new_tlas")
			as_uniform = RDUniform.new()
			as_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE
			as_uniform.binding = 0
			as_uniform.add_id(tlas)
			uniform_set = rd.uniform_set_create([as_uniform, output_uniform], shader, 0)
			_check(uniform_set.is_valid(), "rebuild_uniform_set")
			if uniform_set.is_valid() and failures.is_empty():
				_check(rd.buffer_update(output, 0, 64, initial.to_byte_array()) == OK, "rebuild_reset_output")
				_dispatch(true)
				data = rd.buffer_get_data(output)
				_check(data.size() == 64 and data.decode_u32(0) == 1 and data.decode_u32(8) == 0x345678 and data.decode_u32(20) == 1, "rebuild_readback")
				result.cases["rebuilt_instance_id"] = data.decode_u32(8) if data.size() == 64 else -1
	_finish()
