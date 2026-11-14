// DT-MAC-13d: standalone Metal3 ray tracing -> MetalFX Denoising witness.
// API patterns: https://developer.apple.com/videos/play/wwdc2020/10012/
// Denoiser semantics: https://developer.apple.com/videos/play/wwdc2025/211/
// This is not Godot integration, a ray-traced flight scene, or a benchmark.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <dispatch/dispatch.h>
#import <simd/simd.h>
#include <algorithm>
#include <cstdint>
#include <cmath>
#include <cstdio>

static constexpr NSUInteger IW = 1280, IH = 720, OW = 1920, OH = 1080;
static constexpr NSUInteger FRAMES = 4;
static NSDictionary *pipeline_diagnostics = nil;

static NSDictionary *failure(NSString *stage, NSString *detail) {
    NSMutableDictionary *result = [@{ @"status": stage ?: @"unknown_failure", @"detail": detail ?: @"",
        @"scope": @"standalone Metal3 RT producer and denoiser; not Godot or performance qualification" } mutableCopy];
    if (pipeline_diagnostics) result[@"producer_pipelines"] = pipeline_diagnostics;
    return result;
}

static bool finish(id<MTLCommandBuffer> command, NSString **why) {
    if (!command) { *why = @"nil command buffer"; return false; }
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [command addCompletedHandler:^(id<MTLCommandBuffer> unused) { dispatch_semaphore_signal(done); }];
    [command commit];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC))) {
        *why = @"GPU command buffer did not complete within 20 seconds"; return false;
    }
    if (command.status != MTLCommandBufferStatusCompleted) {
        *why = command.error.localizedDescription ?: @"GPU command buffer failed"; return false;
    }
    return true;
}

static id<MTLTexture> texture(id<MTLDevice> device, MTLPixelFormat format, NSUInteger w, NSUInteger h,
                              MTLTextureUsage required) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
        width:w height:h mipmapped:NO];
    d.storageMode = MTLStorageModePrivate;
    d.usage = required;
    return [device newTextureWithDescriptor:d];
}

static bool expected_hit(double x, double y) {
    return y >= -0.8 && y <= 0.8 && std::fabs(x) <= (0.8 - y) * 0.5;
}

static NSDictionary *run(id<MTLDevice> device, NSString *shader_path) {
    if (!device.supportsRaytracing) return failure(@"raytracing_unsupported", @"Metal reports no RT support");
    if (@available(macOS 26.0, *)) {
        if (![MTLFXTemporalDenoisedScalerDescriptor supportsDevice:device])
            return failure(@"denoiser_unsupported", @"descriptor supportsDevice returned false");
        NSError *error = nil;
        NSString *shader = [NSString stringWithContentsOfFile:shader_path encoding:NSUTF8StringEncoding error:&error];
        if (!shader || shader.length > 100000) return failure(@"shader_read_failed", error.localizedDescription);
        MTLCompileOptions *options = [MTLCompileOptions new];
        options.languageVersion = MTLLanguageVersion2_4;
        id<MTLLibrary> lib = [device newLibraryWithSource:shader options:options error:&error];
        if (!lib) return failure(@"shader_compile_failed", error.localizedDescription);
        id<MTLFunction> trace_fn = [lib newFunctionWithName:@"trace_scene"];
        id<MTLFunction> clear_fn = [lib newFunctionWithName:@"clear_output"];
        id<MTLFunction> vertex_fn = [lib newFunctionWithName:@"depth_vertex"];
        id<MTLFunction> fragment_fn = [lib newFunctionWithName:@"depth_fragment"];
        if (!trace_fn || !clear_fn || !vertex_fn || !fragment_fn)
            return failure(@"shader_entry_missing", @"one or more shader functions are nil");
        MTLComputePipelineDescriptor *trace_desc = [MTLComputePipelineDescriptor new];
        trace_desc.label = @"openrc-rt-trace"; trace_desc.computeFunction = trace_fn;
        id<MTLComputePipelineState> trace = [device newComputePipelineStateWithDescriptor:trace_desc
            options:MTLPipelineOptionNone reflection:nil error:&error];
        if (!trace) return failure(@"trace_pipeline_failed", error.localizedDescription);
        MTLComputePipelineDescriptor *clear_desc = [MTLComputePipelineDescriptor new];
        clear_desc.label = @"openrc-rt-clear"; clear_desc.computeFunction = clear_fn;
        id<MTLComputePipelineState> clear = [device newComputePipelineStateWithDescriptor:clear_desc
            options:MTLPipelineOptionNone reflection:nil error:&error];
        if (!clear) return failure(@"clear_pipeline_failed", error.localizedDescription);
        MTLRenderPipelineDescriptor *depth_desc = [MTLRenderPipelineDescriptor new];
        depth_desc.label = @"openrc-rt-depth";
        depth_desc.vertexFunction = vertex_fn; depth_desc.fragmentFunction = fragment_fn;
        depth_desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> depth_pipe = [device newRenderPipelineStateWithDescriptor:depth_desc error:&error];
        if (!depth_pipe) return failure(@"depth_pipeline_failed", error.localizedDescription);
        // These are queried pipeline-state properties, not a claim that MetalFX's
        // internal pipelines are instrumented or that validation found no faults.
        id trace_validation = [NSNull null], clear_validation = [NSNull null], depth_validation = [NSNull null];
        if (@available(macOS 15.0, *)) {
            trace_validation = @(trace.shaderValidation);
            clear_validation = @(clear.shaderValidation);
            depth_validation = @(depth_pipe.shaderValidation);
        }
        NSDictionary *environment = [NSProcessInfo processInfo].environment;
        MTLSize max_device = device.maxThreadsPerThreadgroup;
        pipeline_diagnostics = @{
            @"trace": @{ @"label": trace.label ?: (id)[NSNull null], @"shader_validation_raw": trace_validation,
                @"max_threads_per_threadgroup": @(trace.maxTotalThreadsPerThreadgroup),
                @"thread_execution_width": @(trace.threadExecutionWidth) },
            @"clear": @{ @"label": clear.label ?: (id)[NSNull null], @"shader_validation_raw": clear_validation,
                @"max_threads_per_threadgroup": @(clear.maxTotalThreadsPerThreadgroup),
                @"thread_execution_width": @(clear.threadExecutionWidth) },
            @"depth_vertex_fragment": @{ @"label": depth_pipe.label ?: (id)[NSNull null],
                @"shader_validation_raw": depth_validation,
                @"max_threads_per_threadgroup": @"not applicable to vertex/fragment rendering" },
            @"device_max_threads_per_threadgroup": @[@(max_device.width),@(max_device.height),@(max_device.depth)],
            @"compute_dispatch_threads_per_group": @[@8,@8,@1],
            @"environment": @{
                @"MTL_SHADER_VALIDATION": environment[@"MTL_SHADER_VALIDATION"] ?: (id)[NSNull null],
                @"MTL_SHADER_VALIDATION_DEFAULT_STATE": environment[@"MTL_SHADER_VALIDATION_DEFAULT_STATE"] ?: (id)[NSNull null],
                @"MTL_SHADER_VALIDATION_ENABLE_PIPELINES": environment[@"MTL_SHADER_VALIDATION_ENABLE_PIPELINES"] ?: (id)[NSNull null],
                @"MTL_SHADER_VALIDATION_DISABLE_PIPELINES": environment[@"MTL_SHADER_VALIDATION_DISABLE_PIPELINES"] ?: (id)[NSNull null],
                @"MTL_SHADER_VALIDATION_REPORT_TO_STDERR": environment[@"MTL_SHADER_VALIDATION_REPORT_TO_STDERR"] ?: (id)[NSNull null],
                @"MTL_SHADER_VALIDATION_ABORT_ON_FAULT": environment[@"MTL_SHADER_VALIDATION_ABORT_ON_FAULT"] ?: (id)[NSNull null],
                @"MTL_DEBUG_LAYER": environment[@"MTL_DEBUG_LAYER"] ?: (id)[NSNull null] },
            @"state_values": @"0=default, 1=enabled, 2=disabled; null=unavailable",
            @"scope": @"producer pipeline state only; MetalFX SDK internal pipelines are not covered" };
        MTLDepthStencilDescriptor *ds_desc = [MTLDepthStencilDescriptor new];
        ds_desc.depthWriteEnabled = YES; ds_desc.depthCompareFunction = MTLCompareFunctionAlways;
        id<MTLDepthStencilState> depth_state = [device newDepthStencilStateWithDescriptor:ds_desc];
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (!queue || !depth_state) return failure(@"queue_or_depth_state_failed", @"nil Metal object");

        // Packed float3, as required by the Metal triangle geometry descriptor.
        const float vertices[] = {
            -0.8f,-0.8f,2.0f,  0.8f,-0.8f,2.0f,  0.0f,0.8f,2.0f,
            -2.0f,-2.0f,-2.0f, 2.0f,-2.0f,-2.0f, 0.0f,2.0f,-2.0f
        };
        id<MTLBuffer> vertex_buffer = [device newBufferWithBytes:vertices length:sizeof(vertices)
                                                        options:MTLResourceStorageModeShared];
        if (!vertex_buffer) return failure(@"geometry_allocation_failed", @"nil vertex buffer");
        MTLAccelerationStructureTriangleGeometryDescriptor *geometry =
            [MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
        geometry.vertexBuffer = vertex_buffer; geometry.vertexStride = 3 * sizeof(float);
        geometry.vertexFormat = MTLAttributeFormatFloat3;
        geometry.triangleCount = 2;
        MTLPrimitiveAccelerationStructureDescriptor *accel_desc = [MTLPrimitiveAccelerationStructureDescriptor descriptor];
        accel_desc.geometryDescriptors = @[geometry];
        MTLAccelerationStructureSizes sizes = [device accelerationStructureSizesWithDescriptor:accel_desc];
        if (!sizes.accelerationStructureSize || !sizes.buildScratchBufferSize)
            return failure(@"acceleration_sizes_invalid", @"zero structure or scratch size");
        id<MTLAccelerationStructure> accel = [device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
        id<MTLBuffer> scratch = [device newBufferWithLength:sizes.buildScratchBufferSize options:MTLResourceStorageModePrivate];
        id<MTLCommandBuffer> build = [queue commandBuffer];
        id<MTLAccelerationStructureCommandEncoder> build_encoder = [build accelerationStructureCommandEncoder];
        if (!accel || !scratch || !build_encoder) return failure(@"acceleration_allocation_failed", @"nil RT object");
        [build_encoder buildAccelerationStructure:accel descriptor:accel_desc scratchBuffer:scratch scratchBufferOffset:0];
        [build_encoder endEncoding];
        NSString *why = nil;
        if (!finish(build, &why)) return failure(@"acceleration_build_failed", why);

        MTLFXTemporalDenoisedScalerDescriptor *d = [MTLFXTemporalDenoisedScalerDescriptor new];
        d.inputWidth = IW; d.inputHeight = IH; d.outputWidth = OW; d.outputHeight = OH;
        d.colorTextureFormat = MTLPixelFormatRGBA16Float; d.outputTextureFormat = MTLPixelFormatRGBA16Float;
        d.depthTextureFormat = MTLPixelFormatDepth32Float; d.motionTextureFormat = MTLPixelFormatRG16Float;
        d.diffuseAlbedoTextureFormat = MTLPixelFormatRGBA16Float; d.specularAlbedoTextureFormat = MTLPixelFormatRGBA16Float;
        d.normalTextureFormat = MTLPixelFormatRGBA16Float; d.roughnessTextureFormat = MTLPixelFormatR16Float;
        d.specularHitDistanceTextureFormat = MTLPixelFormatR16Float; d.specularHitDistanceTextureEnabled = YES;
        d.denoiseStrengthMaskTextureFormat = MTLPixelFormatR8Unorm; d.denoiseStrengthMaskTextureEnabled = YES;
        d.reactiveMaskTextureEnabled = NO; d.transparencyOverlayTextureEnabled = NO; d.autoExposureEnabled = YES;
        id<MTLFXTemporalDenoisedScaler> fx = [d newTemporalDenoisedScalerWithDevice:device];
        if (!fx) return failure(@"denoiser_allocation_failed", @"descriptor creation returned nil");
        MTLTextureUsage rw = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        id<MTLTexture> color = texture(device, d.colorTextureFormat, IW, IH, rw | fx.colorTextureUsage);
        id<MTLTexture> depth_value = texture(device, MTLPixelFormatR32Float, IW, IH, rw);
        id<MTLTexture> depth = texture(device, d.depthTextureFormat, IW, IH, MTLTextureUsageRenderTarget | fx.depthTextureUsage);
        id<MTLTexture> motion = texture(device, d.motionTextureFormat, IW, IH, rw | fx.motionTextureUsage);
        id<MTLTexture> diffuse = texture(device, d.diffuseAlbedoTextureFormat, IW, IH, rw | fx.diffuseAlbedoTextureUsage);
        id<MTLTexture> specular = texture(device, d.specularAlbedoTextureFormat, IW, IH, rw | fx.specularAlbedoTextureUsage);
        id<MTLTexture> normal = texture(device, d.normalTextureFormat, IW, IH, rw | fx.normalTextureUsage);
        id<MTLTexture> rough = texture(device, d.roughnessTextureFormat, IW, IH, rw | fx.roughnessTextureUsage);
        id<MTLTexture> hit_distance = texture(device, d.specularHitDistanceTextureFormat, IW, IH, rw | fx.specularHitDistanceTextureUsage);
        id<MTLTexture> mask = texture(device, d.denoiseStrengthMaskTextureFormat, IW, IH, rw | fx.denoiseStrengthMaskTextureUsage);
        id<MTLTexture> output = texture(device, d.outputTextureFormat, OW, OH, rw | fx.outputTextureUsage);
        const NSUInteger pixels = IW * IH;
        const NSUInteger depth_offset = 0, motion_offset = depth_offset + pixels * 4;
        const NSUInteger diffuse_offset = motion_offset + pixels * 4, specular_offset = diffuse_offset + pixels * 8;
        const NSUInteger normal_offset = specular_offset + pixels * 8, rough_offset = normal_offset + pixels * 8;
        const NSUInteger distance_offset = rough_offset + pixels * 2, mask_offset = distance_offset + pixels * 2;
        id<MTLBuffer> witness = [device newBufferWithLength:IW * IH * sizeof(simd_float4) options:MTLResourceStorageModeShared];
        id<MTLBuffer> input_read = [device newBufferWithLength:IW * IH * 8 options:MTLResourceStorageModeShared];
        id<MTLBuffer> aux_read = [device newBufferWithLength:mask_offset + pixels options:MTLResourceStorageModeShared];
        id<MTLBuffer> output_read = [device newBufferWithLength:OW * OH * 8 options:MTLResourceStorageModeShared];
        if (!color || !depth_value || !depth || !motion || !diffuse || !specular || !normal || !rough ||
            !hit_distance || !mask || !output || !witness || !input_read || !aux_read || !output_read)
            return failure(@"texture_allocation_failed", @"nil required texture or readback buffer");
        fx.colorTexture = color; fx.depthTexture = depth; fx.motionTexture = motion;
        fx.diffuseAlbedoTexture = diffuse; fx.specularAlbedoTexture = specular;
        fx.normalTexture = normal; fx.roughnessTexture = rough; fx.specularHitDistanceTexture = hit_distance;
        fx.denoiseStrengthMaskTexture = mask; fx.outputTexture = output;
        fx.preExposure = 1.0f; fx.depthReversed = NO;
        fx.jitterOffsetX = 0; fx.jitterOffsetY = 0; fx.motionVectorScaleX = 1; fx.motionVectorScaleY = 1;
        fx.worldToViewMatrix = matrix_identity_float4x4;
        matrix_float4x4 projection = matrix_identity_float4x4; projection.columns[2].z = 0.25f;
        fx.viewToClipMatrix = projection;

        NSUInteger compared = 0, hits = 0, hit_mismatch = 0, distance_mismatch = 0, sentinel = 0, nonfinite = 0;
        NSUInteger aux_samples = 0, aux_mismatch = 0;
        double noisy_error = 0, denoised_error = 0, max_producer_error = 0;
        NSUInteger input_n = 0, output_n = 0;
        const float reference[] = {0.36f, 0.52f, 0.68f};
        for (uint32_t frame = 0; frame < FRAMES; ++frame) {
            id<MTLCommandBuffer> command = [queue commandBuffer];
            id<MTLComputeCommandEncoder> compute = [command computeCommandEncoder];
            if (!compute) return failure(@"trace_encoder_failed", @"nil compute encoder");
            [compute setComputePipelineState:trace];
            [compute setAccelerationStructure:accel atBufferIndex:0];
            [compute setBuffer:witness offset:0 atIndex:1];
            [compute setBytes:&frame length:sizeof(frame) atIndex:2];
            NSArray<id<MTLTexture>> *inputs = @[color,depth_value,motion,diffuse,specular,normal,rough,hit_distance,mask];
            for (NSUInteger i = 0; i < inputs.count; ++i) [compute setTexture:inputs[i] atIndex:i];
            [compute dispatchThreads:MTLSizeMake(IW,IH,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
            [compute endEncoding];
            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = MTLLoadActionClear;
            pass.depthAttachment.clearDepth = 1.0; pass.depthAttachment.storeAction = MTLStoreActionStore;
            id<MTLRenderCommandEncoder> render = [command renderCommandEncoderWithDescriptor:pass];
            if (!render) return failure(@"depth_encoder_failed", @"nil render encoder");
            [render setRenderPipelineState:depth_pipe]; [render setDepthStencilState:depth_state];
            [render setFragmentTexture:depth_value atIndex:0];
            [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [render endEncoding];
            compute = [command computeCommandEncoder];
            if (!compute) return failure(@"sentinel_encoder_failed", @"nil compute encoder");
            [compute setComputePipelineState:clear]; [compute setTexture:output atIndex:0];
            [compute dispatchThreads:MTLSizeMake(OW,OH,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
            [compute endEncoding];
            fx.shouldResetHistory = frame == 0;
            [fx encodeToCommandBuffer:command];
            if (frame == FRAMES - 1) {
                id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
                if (!blit) return failure(@"readback_encoder_failed", @"nil blit encoder");
                [blit copyFromTexture:color sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                    sourceSize:MTLSizeMake(IW,IH,1) toBuffer:input_read destinationOffset:0
                    destinationBytesPerRow:IW*8 destinationBytesPerImage:IW*IH*8];
                NSArray<id<MTLTexture>> *aux = @[depth,motion,diffuse,specular,normal,rough,hit_distance,mask];
                const NSUInteger offsets[] = {depth_offset,motion_offset,diffuse_offset,specular_offset,
                                               normal_offset,rough_offset,distance_offset,mask_offset};
                const NSUInteger bytes_per_pixel[] = {4,4,8,8,8,2,2,1};
                for (NSUInteger i=0;i<aux.count;++i) {
                    [blit copyFromTexture:aux[i] sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                        sourceSize:MTLSizeMake(IW,IH,1) toBuffer:aux_read destinationOffset:offsets[i]
                        destinationBytesPerRow:IW*bytes_per_pixel[i] destinationBytesPerImage:pixels*bytes_per_pixel[i]];
                }
                [blit copyFromTexture:output sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
                    sourceSize:MTLSizeMake(OW,OH,1) toBuffer:output_read destinationOffset:0
                    destinationBytesPerRow:OW*8 destinationBytesPerImage:OW*OH*8];
                [blit endEncoding];
            }
            if (!finish(command, &why)) return failure(@"frame_gpu_failed", why);
            if (frame != FRAMES - 1) continue;
            const simd_float4 *rays = (const simd_float4 *)witness.contents;
            const _Float16 *input = (const _Float16 *)input_read.contents;
            const _Float16 *result = (const _Float16 *)output_read.contents;
            const uint8_t *raw = (const uint8_t *)aux_read.contents;
            const float *depth_values = (const float *)(raw + depth_offset);
            const _Float16 *motions = (const _Float16 *)(raw + motion_offset);
            const _Float16 *diffuses = (const _Float16 *)(raw + diffuse_offset);
            const _Float16 *speculars = (const _Float16 *)(raw + specular_offset);
            const _Float16 *normals = (const _Float16 *)(raw + normal_offset);
            const _Float16 *roughness_values = (const _Float16 *)(raw + rough_offset);
            const _Float16 *hit_distances = (const _Float16 *)(raw + distance_offset);
            const uint8_t *masks = raw + mask_offset;
            const float albedo[] = {0.24f,0.36f,0.48f};
            for (NSUInteger y = 0; y < IH; ++y) for (NSUInteger x = 0; x < IW; ++x) {
                double nx = 2.0 * (double(x)+0.5) / IW - 1.0, ny = 1.0 - 2.0 * (double(y)+0.5) / IH;
                const simd_float4 r = rays[y*IW+x];
                if (!std::isfinite(r.x) || !std::isfinite(r.y) || !std::isfinite(r.z) || !std::isfinite(r.w) ||
                    (r.x != 0.0f && r.x != 1.0f) || r.w <= 0 || r.w >= 1) { ++nonfinite; continue; }
                bool expected = expected_hit(nx, ny), observed = r.x == 1.0f;
                bool near_edge = std::fabs(ny+0.8)<0.003 || std::fabs(ny-0.8)<0.003 ||
                                 std::fabs(std::fabs(nx)-(0.8-ny)*0.5)<0.003;
                if (!near_edge) { ++compared; if (expected != observed) ++hit_mismatch; }
                if (observed) { ++hits; if (std::fabs(r.y-2.0f)>0.002f || std::fabs(r.z-4.0f)>0.003f) ++distance_mismatch; }
                else if (r.y != 0 || r.z != 0) ++distance_mismatch;
                if ((x % 4 == 0) && (y % 4 == 0)) {
                    const NSUInteger i=y*IW+x;
                    auto near = [](float a, float b) { return std::isfinite(a) && std::fabs(a-b)<0.01f; };
                    bool correct = near(depth_values[i],observed ? 0.5f : 1.0f) &&
                        near(float(motions[i*2]),0) && near(float(motions[i*2+1]),0) &&
                        near(float(roughness_values[i]),0.5f) && near(float(hit_distances[i]),observed ? 4.0f : 0.0f) &&
                        masks[i]==0 && near(float(normals[i*4]),0) && near(float(normals[i*4+1]),0) &&
                        near(float(normals[i*4+2]),-1.0f);
                    for (int c=0;c<3;++c)
                        correct = correct && near(float(diffuses[i*4+c]),observed ? albedo[c] : 0.0f) &&
                            near(float(speculars[i*4+c]),observed ? 0.04f : 0.0f);
                    ++aux_samples; if (!correct) ++aux_mismatch;
                }
                if (std::fabs(nx)<0.2 && ny>-0.3 && ny<0.1) {
                    for (int c=0;c<3;++c) {
                        float v = float(input[(y*IW+x)*4+c]);
                        if (!std::isfinite(v) || !std::isfinite(r.w)) { ++nonfinite; continue; }
                        max_producer_error = std::max(max_producer_error, double(std::fabs(v-(albedo[c]*2.0f*std::sqrt(r.w)+0.04f))));
                        noisy_error += std::fabs(v-reference[c]); ++input_n;
                    }
                }
            }
            for (NSUInteger y=0;y<OH;++y) for (NSUInteger x=0;x<OW;++x) {
                double nx=2.0*(double(x)+0.5)/OW-1.0, ny=1.0-2.0*(double(y)+0.5)/OH;
                for (int c=0;c<4;++c) {
                    float v=float(result[(y*OW+x)*4+c]);
                    if (!std::isfinite(v)) { ++nonfinite; continue; }
                    if (v==7.0f) ++sentinel;
                    if (c<3 && std::fabs(nx)<0.2 && ny>-0.3 && ny<0.1) {
                        denoised_error+=std::fabs(v-reference[c]); ++output_n;
                    }
                }
            }
        }
        if (!input_n || !output_n) return failure(@"empty_reference_region", @"CPU reference ROI was empty");
        const double output_mae = denoised_error / output_n;
        // A very loose analytic-ROI sanity bound rejects blank or unrelated
        // finite output; it is not an image-quality or denoising-benefit gate.
        bool good = compared > IW*IH/2 && hits > IW*IH/10 && hit_mismatch == 0 && distance_mismatch == 0 &&
                    nonfinite == 0 && sentinel == 0 && aux_samples > 0 && aux_mismatch == 0 &&
                    max_producer_error < 0.01 && output_mae < 0.4;
        return @{ @"status": good ? @"raytrace_and_output_verified" : @"witness_failed",
            @"device": device.name, @"raytracing_api_supported": @YES, @"denoiser_supports_device": @YES,
            @"dimensions": @{ @"input": @[@(IW),@(IH)], @"output": @[@(OW),@(OH)] },
            @"frames": @(FRAMES), @"warmup_frames": @(FRAMES-1), @"measured_frame_index": @(FRAMES-1),
            @"history_reset_frames": @[@0], @"compared_primary_rays": @(compared),
            @"primary_hits": @(hits), @"primary_hit_mismatches": @(hit_mismatch),
            @"secondary_distance_mismatches": @(distance_mismatch), @"max_input_producer_error": @(max_producer_error),
            @"nonfinite_components": @(nonfinite), @"unchanged_sentinel_components": @(sentinel),
            @"auxiliary_samples": @(aux_samples), @"auxiliary_mismatches": @(aux_mismatch),
            @"input_roi_mean_absolute_error": @(noisy_error/input_n),
            @"output_roi_mean_absolute_error": @(output_mae), @"output_roi_sanity_limit": @0.4,
            @"quality_note": @"loose analytic static ROI sanity only; output/input resolutions differ; no quality or speedup gate",
            @"conventions": @"orthographic +Z, depth z/4, world normals, linear albedo/roughness, zero motion and jitter, exposure automatic, reflected distance in scene units, uniform zero denoise mask",
            @"producer_pipelines": pipeline_diagnostics,
            @"scope": @"standalone Metal3 RT producer and denoiser; not Godot or performance qualification" };
    }
    return failure(@"os_unavailable", @"MetalFX denoising requires macOS 26 or later");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSDictionary *result = nil;
        @try {
            NSString *path = argc == 2 ? [NSString stringWithUTF8String:argv[1]] : nil;
            if (!path) result = failure(@"usage_error", @"pass the path to denoised_rt.metal");
            else {
                id<MTLDevice> device = MTLCreateSystemDefaultDevice();
                result = device ? run(device, path) : failure(@"device_unavailable", @"no native Metal device");
            }
        } @catch (NSException *exception) {
            result = failure(@"metal_exception", exception.reason);
        }
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&error];
        if (!json) { std::fputs("{\"status\":\"json_serialization_failed\"}\n", stdout); return 2; }
        std::fwrite(json.bytes, 1, json.length, stdout); std::fputc('\n', stdout);
        return [result[@"status"] isEqual:@"raytrace_and_output_verified"] ? 0 : 1;
    }
}
