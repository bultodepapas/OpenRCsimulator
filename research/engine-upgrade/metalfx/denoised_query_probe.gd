## DT-MAC-13d1: experimental local RenderingDevice RT -> MetalFX witness.
## No presentation, quality or performance claim. Runs only on a patched Metal 3 engine.
extends SceneTree

const PREFIX := "METAL_DENOISED_RD "
const IW := 1280
const IH := 720
const OW := 1920
const OH := 1080
const COMPUTE := """
#version 460
#extension GL_EXT_ray_query : require
layout(local_size_x=8, local_size_y=8) in;
layout(set=0,binding=0) uniform accelerationStructureEXT scene;
layout(rgba16f,set=0,binding=1) uniform writeonly image2D color_img;
layout(r32f,set=0,binding=2) uniform writeonly image2D depth_value;
layout(rg16f,set=0,binding=3) uniform writeonly image2D motion_img;
layout(rgba16f,set=0,binding=4) uniform writeonly image2D diffuse_img;
layout(rgba16f,set=0,binding=5) uniform writeonly image2D specular_img;
layout(rgba16f,set=0,binding=6) uniform writeonly image2D normal_img;
layout(r16f,set=0,binding=7) uniform writeonly image2D rough_img;
layout(rgba16f,set=0,binding=8) uniform writeonly image2D output_img;
layout(set=0,binding=9,std430) buffer Witness { vec4 values[]; } witness;
layout(push_constant,std430) uniform Push { uint frame; } pc;
uint hash32(uint v) {
    v ^= v >> 16; v *= 0x7feb352du; v ^= v >> 15; v *= 0x846ca68bu; v ^= v >> 16; return v;
}
void main() {
    uvec2 p=gl_GlobalInvocationID.xy;
    if (p.x < 1920u && p.y < 1080u) imageStore(output_img,ivec2(p),vec4(7.0));
    if (p.x >= 1280u || p.y >= 720u) return;
    float x=2.0*(float(p.x)+0.5)/1280.0-1.0;
    float y=1.0-2.0*(float(p.y)+0.5)/720.0;
    rayQueryEXT q;
    rayQueryInitializeEXT(q,scene,gl_RayFlagsOpaqueEXT,0xff,vec3(x,y,0.0),0.001,vec3(0,0,1),10.0);
    while (rayQueryProceedEXT(q)) {}
    bool hit=rayQueryGetIntersectionTypeEXT(q,true)==gl_RayQueryCommittedIntersectionTriangleEXT;
    float t=hit ? rayQueryGetIntersectionTEXT(q,true) : 0.0;
    float reflected=0.0;
    if (hit) {
        rayQueryEXT r;
        rayQueryInitializeEXT(r,scene,gl_RayFlagsOpaqueEXT,0xff,vec3(x,y,1.999),0.001,vec3(0,0,-1),10.0);
        while (rayQueryProceedEXT(r)) {}
        if (rayQueryGetIntersectionTypeEXT(r,true)==gl_RayQueryCommittedIntersectionTriangleEXT)
            reflected=rayQueryGetIntersectionTEXT(r,true)+0.001;
    }
    uint index=p.y*1280u+p.x;
    float u=(float(hash32(index^(pc.frame*0x9e3779b9u))&65535u)+0.5)/65536.0;
    vec3 base=vec3(0.24,0.36,0.48);
    vec3 c=hit ? base*(2.0*sqrt(u))+(reflected>0.0 ? 0.04 : 0.0) : vec3(0.06,0.10,0.16);
    imageStore(color_img,ivec2(p),vec4(c,1)); imageStore(depth_value,ivec2(p),vec4(hit ? 0.5 : 1.0));
    imageStore(motion_img,ivec2(p),vec4(0)); imageStore(diffuse_img,ivec2(p),vec4(hit ? base : vec3(0),1));
    imageStore(specular_img,ivec2(p),vec4(hit ? vec3(0.04) : vec3(0),1));
    imageStore(normal_img,ivec2(p),vec4(0,0,-1,1)); imageStore(rough_img,ivec2(p),vec4(0.5));
    witness.values[index]=vec4(hit ? 1.0 : 0.0,t,reflected,u);
}
"""
const VERTEX := """
#version 450
void main() {
    vec2 pos[3]=vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));
    gl_Position=vec4(pos[gl_VertexIndex],0,1);
}
"""
const FRAGMENT := """
#version 450
layout(set=0,binding=0) uniform sampler2D depth_values;
void main() { gl_FragDepth=texelFetch(depth_values,ivec2(gl_FragCoord.xy),0).r; }
"""

var rd: RenderingDevice
var owned: Array[RID] = []
var failures: Array[String] = []
var result := {"scope": "local_rd_triangle_query_denoised", "input": [IW, IH], "output": [OW, OH], "frames": 5,
    "claim": "finite and loose analytic ROI sanity only; no quality or performance qualification"}

func _initialize() -> void:
    _run.call_deferred()

func _check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)

func _keep(id: RID) -> RID:
    if id.is_valid():
        owned.append(id)
    return id

func _finish() -> void:
    if rd != null:
        rd.submit()
        rd.sync()
        owned.reverse()
        for id in owned:
            rd.free_rid(id)
        rd.free()
    result["failures"] = failures
    result["ok"] = failures.is_empty()
    print(PREFIX + JSON.stringify(result))
    quit(0 if failures.is_empty() else 1)

func _texture(format: int, width: int, height: int, usage: int, initial: PackedByteArray = PackedByteArray()) -> RID:
    var desc := RDTextureFormat.new()
    desc.texture_type = RenderingDevice.TEXTURE_TYPE_2D
    desc.format = format
    desc.width = width
    desc.height = height
    desc.usage_bits = usage
    var data: Array[PackedByteArray] = []
    if not initial.is_empty():
        data.append(initial)
    return _keep(rd.texture_create(desc, RDTextureView.new(), data))

func _shader(compute: String, vertex: String = "", fragment: String = "", label: String = "") -> RID:
    var source := RDShaderSource.new()
    source.source_compute = compute
    source.source_vertex = vertex
    source.source_fragment = fragment
    var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(source, false)
    if spirv == null or not spirv.compile_error_compute.is_empty() or not spirv.compile_error_vertex.is_empty() or not spirv.compile_error_fragment.is_empty():
        failures.append("spirv_compile:" + label + (":" + spirv.compile_error_compute + spirv.compile_error_vertex + spirv.compile_error_fragment if spirv != null else ":null"))
        return RID()
    return _keep(rd.shader_create_from_spirv(spirv, label))

func _uniform(kind: int, binding: int, ids: Array[RID]) -> RDUniform:
    var uniform := RDUniform.new()
    uniform.uniform_type = kind
    uniform.binding = binding
    for id in ids:
        uniform.add_id(id)
    return uniform

func _dispatch(frame: int, compute_pipeline: RID, compute_set: RID, depth_pipeline: RID, depth_set: RID, framebuffer: RID) -> void:
    var list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(list, compute_pipeline)
    rd.compute_list_bind_uniform_set(list, compute_set, 0)
    rd.compute_list_set_push_constant(list, PackedInt32Array([frame]).to_byte_array(), 4)
    rd.compute_list_dispatch(list, (OW + 7) / 8, (OH + 7) / 8, 1)
    rd.compute_list_end()
    var draw := rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_CLEAR_DEPTH)
    rd.draw_list_bind_render_pipeline(draw, depth_pipeline)
    rd.draw_list_bind_uniform_set(draw, depth_set, 0)
    rd.draw_list_draw(draw, false, 1, 3)
    rd.draw_list_end()

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
        failures.append("local_rd_unavailable")
        _finish()
        return
    result["capability"] = rd.metalfx_denoised_capability()
    _check(rd.has_feature(RenderingDevice.SUPPORTS_METAL_TRIANGLE_QUERY), "triangle_query_unavailable")
    _check(result.capability.status == "available", "denoiser_" + str(result.capability.status))
    if not failures.is_empty():
        _finish()
        return
    _check(rd.metalfx_denoised_create(Vector2i.ZERO, Vector2i(OW, OH)).status == "invalid_dimensions", "invalid_size_accepted")
    var created: Dictionary = rd.metalfx_denoised_create(Vector2i(IW, IH), Vector2i(OW, OH))
    result["factory"] = created.status
    if created.status != "created":
        failures.append("factory_" + str(created.status))
        _finish()
        return
    var context: RID = _keep(created.context)
    var other := RenderingServer.create_local_rendering_device()
    if other == null:
        failures.append("second_rd_unavailable")
    else:
        _check(other.metalfx_denoised_status(context).status == "invalid_context", "cross_device_context_accepted")
        other.free()
    var vertex_data := PackedFloat32Array([-0.8,-0.8,2, 0.8,-0.8,2, 0,0.8,2, -3,-3,-2, 3,-3,-2, 0,3,-2]).to_byte_array()
    var vertex := _keep(rd.vertex_buffer_create(vertex_data.size(), vertex_data, RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT))
    var geometry := RDAccelerationStructureGeometry.new()
    geometry.vertex_buffer = vertex
    geometry.vertex_stride = 12
    geometry.vertex_count = 6
    geometry.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
    geometry.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
    var blas := _keep(rd.blas_create([geometry], 0))
    var tlas := _keep(rd.tlas_create(1, 0))
    if not vertex.is_valid() or not blas.is_valid() or not tlas.is_valid():
        failures.append("acceleration_allocation")
        _finish()
        return
    var instance := RDAccelerationStructureInstance.new()
    instance.blas = blas
    instance.mask = 0xff
    _check(rd.blas_build(blas) == OK and rd.tlas_build(tlas, [instance]) == OK, "acceleration_build")
    var sample_storage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
    var color := _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, IW, IH, sample_storage)
    var depth_value := _texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, IW, IH, sample_storage)
    var depth := _texture(RenderingDevice.DATA_FORMAT_D32_SFLOAT, IW, IH, RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
    var motion := _texture(RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, IW, IH, sample_storage)
    var diffuse := _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, IW, IH, sample_storage)
    var specular := _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, IW, IH, sample_storage)
    var normal := _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, IW, IH, sample_storage)
    var roughness := _texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT, IW, IH, sample_storage)
    var exposure := _texture(RenderingDevice.DATA_FORMAT_R16_SFLOAT, 1, 1, RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT, PackedByteArray([0, 60]))
    var output := _texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, OW, OH,
        sample_storage | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT)
    var textures: Array[RID] = [color, depth, motion, diffuse, specular, normal, roughness, exposure, output]
    var compute_images: Array[RID] = [color, depth_value, motion, diffuse, specular, normal, roughness, output]
    for id in textures + [depth_value]:
        _check(id.is_valid(), "texture_allocation")
    if not failures.is_empty():
        _finish()
        return
    var identity := Projection()
    var projection := Projection()
    projection.z = Vector4(0, 0, 0.25, 0)
    _check(rd.metalfx_denoised_encode(context, [], identity, projection, 1.0, Vector2.ZERO, true).status == "invalid_texture_count", "texture_count_accepted")
    _check(rd.metalfx_denoised_encode(context, textures, identity, projection, 1.0, Vector2.ZERO, false).status == "invalid_frame", "initial_history_without_reset")
    _check(rd.metalfx_denoised_encode(context, textures, identity, projection, -1.0, Vector2.ZERO, true).status == "invalid_frame", "negative_exposure_accepted")
    var wrong: Array[RID] = textures.duplicate()
    wrong[4] = diffuse
    _check(rd.metalfx_denoised_encode(context, wrong, identity, projection, 1.0, Vector2.ZERO, true).status == "invalid_textures", "alias_accepted")
    var witness := _keep(rd.storage_buffer_create(IW * IH * 16))
    var compute_shader := _shader(COMPUTE, "", "", "openrc-denoised-rt")
    var depth_shader := _shader("", VERTEX, FRAGMENT, "openrc-denoised-depth")
    if not witness.is_valid() or not compute_shader.is_valid() or not depth_shader.is_valid():
        failures.append("shader_or_buffer")
        _finish()
        return
    var pipeline := _keep(rd.compute_pipeline_create(compute_shader))
    var uniforms: Array[RDUniform] = [_uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE, 0, [tlas])]
    for i in compute_images.size():
        uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, i + 1, [compute_images[i]]))
    uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 9, [witness]))
    var compute_set := _keep(rd.uniform_set_create(uniforms, compute_shader, 0))
    var framebuffer := _keep(rd.framebuffer_create([depth]))
    var depth_state := RDPipelineDepthStencilState.new()
    depth_state.enable_depth_test = true
    depth_state.enable_depth_write = true
    depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_ALWAYS
    var depth_pipeline := _keep(rd.render_pipeline_create(depth_shader, rd.framebuffer_get_format(framebuffer), -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
        RDPipelineRasterizationState.new(), RDPipelineMultisampleState.new(), depth_state, RDPipelineColorBlendState.new()))
    var sampler := _keep(rd.sampler_create(RDSamplerState.new()))
    var depth_set := _keep(rd.uniform_set_create([_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [sampler, depth_value])], depth_shader, 0))
    _check(pipeline.is_valid() and compute_set.is_valid() and framebuffer.is_valid() and depth_pipeline.is_valid() and depth_set.is_valid(), "pipeline_allocation")
    if not failures.is_empty():
        _finish()
        return
    for frame in 4:
        _dispatch(frame, pipeline, compute_set, depth_pipeline, depth_set, framebuffer)
        var submitted: Dictionary = rd.metalfx_denoised_encode(context, textures, identity, projection, 1.0, Vector2.ZERO, frame == 0)
        _check(submitted.status == "enqueued", "enqueue_" + str(frame) + "_" + str(submitted.status))
        rd.submit()
        rd.sync()
    # Populate and sync every input in one submission; the following denoiser
    # callback is the first operation in a fresh command graph and sees a
    # sentinel-filled output without a prior encoder creating the command buffer.
    _dispatch(4, pipeline, compute_set, depth_pipeline, depth_set, framebuffer)
    rd.submit()
    rd.sync()
    var fresh: Dictionary = rd.metalfx_denoised_encode(context, textures, identity, projection, 1.0, Vector2.ZERO, false)
    _check(fresh.status == "enqueued", "fresh_graph_enqueue_" + str(fresh.status))
    rd.submit()
    rd.sync()
    result["fresh_graph"] = rd.metalfx_denoised_status(context)
    result["status"] = result.fresh_graph
    _check(result.status.accepted == 5 and result.status.encoded == 5 and not result.status.gpu_completion_observed, "encode_receipt")
    _inspect(witness, color, depth, motion, diffuse, specular, normal, roughness, output)
    # A new generation is admitted, then retired before its queued callback executes.
    var replacement: Dictionary = rd.metalfx_denoised_create(Vector2i(IW, IH), Vector2i(OW, OH))
    _check(replacement.status == "created", "replacement_factory")
    if replacement.status == "created":
        var next: RID = replacement.context
        _dispatch(5, pipeline, compute_set, depth_pipeline, depth_set, framebuffer)
        _check(rd.metalfx_denoised_encode(next, textures, identity, projection, 1.0, Vector2.ZERO, true).status == "enqueued", "replacement_enqueue")
        rd.free_rid(next)
        _check(rd.metalfx_denoised_status(next).status == "invalid_context", "freed_context_accepted")
        rd.submit()
        rd.sync()
        var after := rd.texture_get_data(output, 0)
        if after.size() == OW * OH * 8:
            var retired_value := after.decode_half((OH / 2 * OW + OW / 2) * 8)
            _check(is_finite(retired_value) and retired_value != 7.0, "retired_context_output")
        else:
            failures.append("retired_context_readback_size")
    _finish()

func _near(value: float, expected: float, tolerance: float = 0.01) -> bool:
    return is_finite(value) and absf(value - expected) <= tolerance

func _inspect(witness: RID, color: RID, depth: RID, motion: RID, diffuse: RID, specular: RID, normal: RID, roughness: RID, output: RID) -> void:
    var w := rd.buffer_get_data(witness)
    var c := rd.texture_get_data(color, 0)
    var d := rd.texture_get_data(depth, 0)
    var m := rd.texture_get_data(motion, 0)
    var a := rd.texture_get_data(diffuse, 0)
    var s := rd.texture_get_data(specular, 0)
    var n := rd.texture_get_data(normal, 0)
    var r := rd.texture_get_data(roughness, 0)
    var out := rd.texture_get_data(output, 0)
    if w.size() != IW*IH*16 or c.size() != IW*IH*8 or d.size() != IW*IH*4 or m.size() != IW*IH*4 or a.size() != IW*IH*8 or s.size() != IW*IH*8 or n.size() != IW*IH*8 or r.size() != IW*IH*2 or out.size() != OW*OH*8:
        failures.append("readback_size")
        return
    var compared := 0
    var hits := 0
    var mismatch := 0
    for y in range(0, IH, 4):
        for x in range(0, IW, 4):
            var i := y*IW+x
            var nx := 2.0*(x+0.5)/IW-1.0
            var ny := 1.0-2.0*(y+0.5)/IH
            var expected := ny >= -0.8 and ny <= 0.8 and absf(nx) <= (0.8-ny)*0.5
            var hit_value := w.decode_float(i*16)
            if not is_finite(hit_value) or (hit_value != 0.0 and hit_value != 1.0):
                mismatch += 1
                continue
            var hit := hit_value == 1.0
            if absf(ny+0.8) > 0.004 and absf(ny-0.8) > 0.004 and absf(absf(nx)-(0.8-ny)*0.5) > 0.004:
                compared += 1
                if hit != expected:
                    mismatch += 1
            if hit:
                hits += 1
            if not _near(w.decode_float(i*16+4), 2.0 if hit else 0.0, 0.003) or not _near(w.decode_float(i*16+8), 4.0 if hit else 0.0, 0.004):
                mismatch += 1
            if not _near(d.decode_float(i*4), 0.5 if hit else 1.0) or not _near(m.decode_half(i*4), 0.0) or not _near(m.decode_half(i*4+2), 0.0) or not _near(n.decode_half(i*8), 0.0) or not _near(n.decode_half(i*8+2), 0.0) or not _near(n.decode_half(i*8+4), -1.0) or not _near(r.decode_half(i*2), 0.5):
                mismatch += 1
            var u := w.decode_float(i*16+12)
            if not is_finite(u) or u < 0.0 or u > 1.0:
                mismatch += 1
                continue
            for channel in 3:
                var base: float = [0.24,0.36,0.48][channel]
                var expected_color: float = base*2.0*sqrt(u)+0.04 if hit else [0.06,0.10,0.16][channel]
                if not _near(c.decode_half(i*8+channel*2), expected_color) or not _near(a.decode_half(i*8+channel*2), base if hit else 0.0) or not _near(s.decode_half(i*8+channel*2), 0.04 if hit else 0.0):
                    mismatch += 1
    var invalid := 0
    var sentinel := 0
    var error := 0.0
    var samples := 0
    for y in OH:
        for x in OW:
            var i := (y*OW+x)*8
            var nx := 2.0*(x+0.5)/OW-1.0
            var ny := 1.0-2.0*(y+0.5)/OH
            for channel in 3:
                var value := out.decode_half(i+channel*2)
                if not is_finite(value):
                    invalid += 1
                elif value == 7.0:
                    sentinel += 1
                elif absf(nx) < 0.2 and ny > -0.3 and ny < 0.1:
                    error += absf(value-[0.36,0.52,0.68][channel])
                    samples += 1
    result["producer_samples"] = compared
    result["primary_hits"] = hits
    result["producer_mismatches"] = mismatch
    result["nonfinite_rgb"] = invalid
    result["sentinel_rgb"] = sentinel
    result["roi_mean_absolute_error"] = error / samples if samples > 0 else -1.0
    _check(compared > 20000 and hits > 2000 and mismatch == 0, "producer_sanity")
    _check(invalid == 0 and sentinel == 0 and samples > 0 and error / samples < 0.4, "denoised_sanity")
