// DT-MAC-12a/F07: bounded, synthetic Metal 3 frame-interpolation experiment.
// This has no drawable, presenter, engine integration, FPS claim, or real-game inputs.
// API contract: https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase
// Motion direction: https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase/motionvectorscalex
// Background reference: https://github.com/apple/game-porting-toolkit/tree/main/game-porting-skills/skills/using-metalfx-frame-interpolation
// Build against SDK 26+; only the macOS 26 Metal 3 properties are used.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static constexpr NSUInteger INPUT_W = 1280, INPUT_H = 720;
static constexpr NSUInteger OUTPUT_W = 1920, OUTPUT_H = 1080;
static constexpr NSUInteger ROW_BYTES = OUTPUT_W * 8; // RGBA16Float, 256-byte aligned
static constexpr float OUTPUT_SHIFT = 24.0f;
// The header describes current-to-previous displacement in color pixels. At
// unequal input/output sizes, also measure the lower-resolution interpretation;
// neither is treated as verified without the analytic midpoint comparison.
static constexpr float OUTPUT_MOTION_X = -OUTPUT_SHIFT;
static constexpr float INPUT_MOTION_X = -OUTPUT_SHIFT * float(INPUT_W) / float(OUTPUT_W);

static NSString *const shaderSource = @R"METAL(
#include <metal_stdlib>
using namespace metal;
struct ColorArgs { float shift; uint uniform; };
kernel void make_color(texture2d<float, access::write> image [[texture(0)]],
                       constant ColorArgs &args [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (p.x >= image.get_width() || p.y >= image.get_height()) return;
    if (args.uniform == 1) { image.write(float4(0.25, 0.5, 0.75, 1.0), p); return; }
    if (args.uniform == 2) { image.write(float4(1.0, 0.0, 1.0, 1.0), p); return; }
    // An opaque textured plane translates by 24 output pixels: its repeating
    // hard edges make a crossfade leave two ghosts instead of a true midpoint.
    float x = float(p.x) + 0.5 - args.shift;
    float y = float(p.y) + 0.5;
    float stripe = fract((x + 32.0) / 160.0) < 0.4 ? 1.0 : 0.0;
    float detail = 0.025 * sin(y * 0.013);
    float3 dark = float3(0.06, 0.09, 0.16) + detail;
    float3 bright = float3(0.94, 0.87, 0.72) + detail;
    image.write(float4(mix(dark, bright, stripe), 1.0), p);
}
kernel void make_motion(texture2d<float, access::write> image [[texture(0)]],
                        constant float &x [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (p.x < image.get_width() && p.y < image.get_height())
        image.write(float4(x, 0.0, 0.0, 0.0), p);
}
kernel void make_crossfade(texture2d<float, access::read> previous [[texture(0)]],
                           texture2d<float, access::read> current [[texture(1)]],
                           texture2d<float, access::write> output [[texture(2)]],
                           uint2 p [[thread_position_in_grid]]) {
    if (p.x < output.get_width() && p.y < output.get_height())
        output.write(0.5 * (previous.read(p) + current.read(p)), p);
}
)METAL";

struct ColorArgs { float shift; uint32_t uniform; };

static id<MTLTexture> makeTexture(id<MTLDevice> device, MTLPixelFormat format,
                                  NSUInteger w, NSUInteger h, MTLTextureUsage usage) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
        width:w height:h mipmapped:NO];
    d.storageMode = MTLStorageModePrivate;
    d.usage = usage;
    return [device newTextureWithDescriptor:d];
}

static BOOL waitForBuffer(id<MTLCommandBuffer> buffer, NSString **failure) {
    if (!buffer) { *failure = @"command_buffer_allocation_failed"; return NO; }
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> unused) { (void)unused; dispatch_semaphore_signal(finished); }];
    [buffer commit];
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC))) {
        *failure = @"gpu_timeout";
        return NO;
    }
    if (buffer.status != MTLCommandBufferStatusCompleted) {
        *failure = buffer.error.localizedDescription ?: @"gpu_command_failed";
        return NO;
    }
    return YES;
}

static BOOL makeColor(id<MTLCommandBuffer> buffer, id<MTLComputePipelineState> pipeline,
                      id<MTLTexture> texture, float shift, uint32_t uniform) {
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (!encoder) return NO;
    ColorArgs args = {shift, uniform};
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:texture atIndex:0];
    [encoder setBytes:&args length:sizeof(args) atIndex:0];
    [encoder dispatchThreads:MTLSizeMake(texture.width, texture.height, 1)
        threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
    [encoder endEncoding];
    return YES;
}

static BOOL makeMotion(id<MTLCommandBuffer> buffer, id<MTLComputePipelineState> pipeline,
                       id<MTLTexture> texture, float x) {
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (!encoder) return NO;
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:texture atIndex:0];
    [encoder setBytes:&x length:sizeof(x) atIndex:0];
    [encoder dispatchThreads:MTLSizeMake(INPUT_W, INPUT_H, 1)
        threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
    [encoder endEncoding];
    return YES;
}

static BOOL makeCrossfade(id<MTLCommandBuffer> buffer, id<MTLComputePipelineState> pipeline,
                          id<MTLTexture> previous, id<MTLTexture> current, id<MTLTexture> output) {
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (!encoder) return NO;
    [encoder setComputePipelineState:pipeline];
    [encoder setTexture:previous atIndex:0];
    [encoder setTexture:current atIndex:1];
    [encoder setTexture:output atIndex:2];
    [encoder dispatchThreads:MTLSizeMake(OUTPUT_W, OUTPUT_H, 1)
        threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
    [encoder endEncoding];
    return YES;
}

static BOOL clearDepth(id<MTLCommandBuffer> buffer, id<MTLTexture> depth) {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.depthAttachment.texture = depth;
    pass.depthAttachment.loadAction = MTLLoadActionClear;
    pass.depthAttachment.storeAction = MTLStoreActionStore;
    pass.depthAttachment.clearDepth = 0.5; // normal 0-near, 1-far depth
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) return NO;
    [encoder endEncoding];
    return YES;
}

static BOOL copyTexture(id<MTLBlitCommandEncoder> blit, id<MTLTexture> texture, id<MTLBuffer> buffer) {
    if (!blit || !texture || !buffer) return NO;
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
        sourceSize:MTLSizeMake(OUTPUT_W, OUTPUT_H, 1) toBuffer:buffer destinationOffset:0
        destinationBytesPerRow:ROW_BYTES destinationBytesPerImage:ROW_BYTES * OUTPUT_H];
    return YES;
}

static NSDictionary *runCase(id<MTLDevice> device, id<MTLCommandQueue> queue,
                             id<MTLComputePipelineState> colorPipeline,
                             id<MTLComputePipelineState> motionPipeline,
                             id<MTLComputePipelineState> crossfadePipeline,
                             BOOL moving, float motionX, BOOL crossfadeOnly) API_AVAILABLE(macos(26.0)) {
    MTLFXFrameInterpolatorDescriptor *d = [MTLFXFrameInterpolatorDescriptor new];
    d.inputWidth = INPUT_W; d.inputHeight = INPUT_H;
    d.outputWidth = OUTPUT_W; d.outputHeight = OUTPUT_H;
    d.colorTextureFormat = MTLPixelFormatRGBA16Float;
    d.outputTextureFormat = MTLPixelFormatRGBA16Float;
    d.depthTextureFormat = MTLPixelFormatDepth32Float;
    d.motionTextureFormat = MTLPixelFormatRG16Float;
    id<MTLFXFrameInterpolator> fx = [d newFrameInterpolatorWithDevice:device];
    if (!fx) return @{ @"status": @"allocation_failed" };

    MTLTextureUsage colorUsage = fx.colorTextureUsage | MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
    id<MTLTexture> previous = makeTexture(device, d.colorTextureFormat, OUTPUT_W, OUTPUT_H, colorUsage);
    id<MTLTexture> current = makeTexture(device, d.colorTextureFormat, OUTPUT_W, OUTPUT_H, colorUsage);
    id<MTLTexture> midpoint = makeTexture(device, d.colorTextureFormat, OUTPUT_W, OUTPUT_H,
                                           MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead);
    id<MTLTexture> output = makeTexture(device, d.outputTextureFormat, OUTPUT_W, OUTPUT_H,
                                        fx.outputTextureUsage | MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead);
    id<MTLTexture> depth = makeTexture(device, d.depthTextureFormat, INPUT_W, INPUT_H,
                                       fx.depthTextureUsage | MTLTextureUsageRenderTarget);
    id<MTLTexture> motion = makeTexture(device, d.motionTextureFormat, INPUT_W, INPUT_H,
                                        fx.motionTextureUsage | MTLTextureUsageShaderWrite);
    id<MTLBuffer> outBytes = [device newBufferWithLength:ROW_BYTES * OUTPUT_H options:MTLResourceStorageModeShared];
    id<MTLBuffer> midBytes = [device newBufferWithLength:ROW_BYTES * OUTPUT_H options:MTLResourceStorageModeShared];
    id<MTLBuffer> prevBytes = [device newBufferWithLength:ROW_BYTES * OUTPUT_H options:MTLResourceStorageModeShared];
    id<MTLBuffer> currBytes = [device newBufferWithLength:ROW_BYTES * OUTPUT_H options:MTLResourceStorageModeShared];
    if (!previous || !current || !midpoint || !output || !depth || !motion ||
        !outBytes || !midBytes || !prevBytes || !currBytes)
        return @{ @"status": @"resource_allocation_failed" };

    fx.depthTexture = depth;
    fx.motionTexture = motion;
    fx.outputTexture = output;
    fx.motionVectorScaleX = 1.0f; fx.motionVectorScaleY = 1.0f;
    fx.jitterOffsetX = 0.0f; fx.jitterOffsetY = 0.0f;
    fx.deltaTime = 1.0f / 60.0f;
    fx.nearPlane = 0.1f; fx.farPlane = 1000.0f;
    fx.fieldOfView = 60.0f; fx.aspectRatio = float(OUTPUT_W) / float(OUTPUT_H);
    [fx setDepthReversed:NO];
    fx.uiTexture = nil; // no UI or production composition in this fixture

    // Seed: reset history with a real first color. The output is not interpreted.
    id<MTLCommandBuffer> first = [queue commandBuffer];
    uint32_t mode = moving ? 0 : 1;
    if (!first || !makeColor(first, colorPipeline, previous, 0.0f, mode) ||
        !makeColor(first, colorPipeline, current, moving ? OUTPUT_SHIFT : 0.0f, mode) ||
        !makeColor(first, colorPipeline, midpoint, moving ? OUTPUT_SHIFT * 0.5f : 0.0f, mode) ||
        !makeColor(first, colorPipeline, output, 0.0f, 2) ||
        !makeMotion(first, motionPipeline, motion, 0.0f) || !clearDepth(first, depth))
        return @{ @"status": @"input_encoding_failed" };
    fx.colorTexture = previous;
    fx.prevColorTexture = previous;
    fx.shouldResetHistory = YES;
    if (!crossfadeOnly) [fx encodeToCommandBuffer:first];
    NSString *failure = nil;
    if (!waitForBuffer(first, &failure)) return @{ @"status": @"first_encode_failed", @"detail": failure };

    // Second encode uses the exact color from the prior encode as previous.
    // Poison output first so a missing second write is observable.
    id<MTLCommandBuffer> second = [queue commandBuffer];
    if (!second || !makeColor(second, colorPipeline, output, 0.0f, 2) ||
        !makeMotion(second, motionPipeline, motion, moving ? motionX : 0.0f))
        return @{ @"status": @"second_input_encoding_failed" };
    fx.colorTexture = current;
    fx.prevColorTexture = previous;
    fx.shouldResetHistory = NO;
    if (crossfadeOnly) {
        if (!makeCrossfade(second, crossfadePipeline, previous, current, output))
            return @{ @"status": @"crossfade_encoding_failed" };
    } else {
        [fx encodeToCommandBuffer:second];
    }
    id<MTLBlitCommandEncoder> blit = [second blitCommandEncoder];
    BOOL copied = copyTexture(blit, output, outBytes) && copyTexture(blit, midpoint, midBytes) &&
                  copyTexture(blit, previous, prevBytes) && copyTexture(blit, current, currBytes);
    if (!copied) return @{ @"status": @"readback_encoding_failed" };
    [blit endEncoding];
    if (!waitForBuffer(second, &failure)) return @{ @"status": @"second_encode_failed", @"detail": failure };

    const _Float16 *out = static_cast<const _Float16 *>(outBytes.contents);
    const _Float16 *mid = static_cast<const _Float16 *>(midBytes.contents);
    const _Float16 *prev = static_cast<const _Float16 *>(prevBytes.contents);
    const _Float16 *curr = static_cast<const _Float16 *>(currBytes.contents);
    if (!out || !mid || !prev || !curr) return @{ @"status": @"readback_unavailable" };
    double outMid = 0.0, prevMid = 0.0, currMid = 0.0, blendMid = 0.0, outBlend = 0.0;
    double maxError = 0.0, maxBlendError = 0.0;
    const uint16_t *prevBits = reinterpret_cast<const uint16_t *>(prev);
    const uint16_t *currBits = reinterpret_cast<const uint16_t *>(curr);
    const uint16_t *midBits = reinterpret_cast<const uint16_t *>(mid);
    uint64_t inputFingerprint = UINT64_C(14695981039346656037);
    uint64_t samples = 0;
    bool finite = true;
    // Read and check every pixel. Moving-image error excludes a border wider
    // than the displacement, where the synthetic pan exposes new content.
    for (NSUInteger y = 0; y < OUTPUT_H; ++y) {
        for (NSUInteger x = 0; x < OUTPUT_W; ++x) {
            NSUInteger i = (y * OUTPUT_W + x) * 4;
            for (NSUInteger channel = 0; channel < 4; ++channel) {
                uint64_t packed = uint64_t(prevBits[i + channel]) | (uint64_t(currBits[i + channel]) << 16) |
                                  (uint64_t(midBits[i + channel]) << 32);
                inputFingerprint = (inputFingerprint ^ packed) * UINT64_C(1099511628211);
                float a = float(out[i + channel]), b = float(mid[i + channel]);
                float c = float(prev[i + channel]), e = float(curr[i + channel]);
                if (!std::isfinite(a) || !std::isfinite(b) || !std::isfinite(c) || !std::isfinite(e)) {
                    finite = false;
                    continue;
                }
                if (moving && (x < 64 || x >= OUTPUT_W - 64 || y < 32 || y >= OUTPUT_H - 32)) continue;
                double error = std::fabs(double(a) - double(b));
                double blended = 0.5 * (double(c) + double(e));
                maxError = std::fmax(maxError, error);
                maxBlendError = std::fmax(maxBlendError, std::fabs(double(a) - blended));
                if (channel < 3) {
                    outMid += error;
                    prevMid += std::fabs(double(c) - double(b));
                    currMid += std::fabs(double(e) - double(b));
                    blendMid += std::fabs(blended - double(b));
                    outBlend += std::fabs(double(a) - blended);
                    ++samples;
                }
            }
        }
    }
    if (!finite || samples == 0) return @{ @"status": @"nonfinite_readback", @"finite": @NO };
    outMid /= double(samples); prevMid /= double(samples); currMid /= double(samples);
    blendMid /= double(samples); outBlend /= double(samples);
    NSString *status = moving ? (crossfadeOnly ? (maxBlendError < 0.001 ? @"crossfade_control_verified" : @"crossfade_mismatch")
                                               : @"motion_readback_complete")
                              : (maxError < 0.025 ? @"uniform_verified" : @"uniform_mismatch");
    return @{ @"status": status,
              @"finite": @YES, @"sampled_rgb_components": @(samples),
              @"mean_error_to_analytic_midpoint": @(outMid), @"max_component_error": @(maxError),
              @"previous_to_midpoint_mean_error": @(prevMid), @"current_to_midpoint_mean_error": @(currMid),
              @"crossfade_to_midpoint_mean_error": @(blendMid), @"output_to_crossfade_mean_error": @(outBlend),
              @"output_to_crossfade_max_error": @(maxBlendError),
              @"comparison_region": moving ? @[@64, @32, @(OUTPUT_W - 128), @(OUTPUT_H - 64)]
                                             : @[@0, @0, @(OUTPUT_W), @(OUTPUT_H)],
              @"motion_texture_x": @(moving ? motionX : 0.0f),
              @"input_fingerprint_fnv64": [NSString stringWithFormat:@"%016llx", (unsigned long long)inputFingerprint],
              @"interpolator_encoded": @(!crossfadeOnly), @"convention_claim_from_this_case": @NO };
}

static NSDictionary *runFixture(NSString *mode) {
    @autoreleasepool {
        if (@available(macOS 26.0, *)) {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (!device) return @{ @"status": @"no_device" };
            if (![MTLFXFrameInterpolatorDescriptor supportsDevice:device])
                return @{ @"status": @"device_unsupported", @"device": device.name ?: @"unknown" };
            id<MTLCommandQueue> queue = [device newCommandQueue];
            NSError *error = nil;
            id<MTLLibrary> library = [device newLibraryWithSource:shaderSource options:nil error:&error];
            if (!library) return @{ @"status": @"shader_compile_failed", @"detail": error.localizedDescription ?: @"unknown" };
            id<MTLFunction> colorFunction = [library newFunctionWithName:@"make_color"];
            id<MTLFunction> motionFunction = [library newFunctionWithName:@"make_motion"];
            if (!queue || !colorFunction || !motionFunction) return @{ @"status": @"pipeline_inputs_failed" };
            id<MTLComputePipelineState> colorPipeline = [device newComputePipelineStateWithFunction:colorFunction error:&error];
            if (!colorPipeline) return @{ @"status": @"color_pipeline_failed", @"detail": error.localizedDescription ?: @"unknown" };
            id<MTLComputePipelineState> motionPipeline = [device newComputePipelineStateWithFunction:motionFunction error:&error];
            if (!motionPipeline) return @{ @"status": @"motion_pipeline_failed", @"detail": error.localizedDescription ?: @"unknown" };
            BOOL all = [mode isEqual:@"all"];
            NSMutableDictionary *cases = [NSMutableDictionary dictionary];
            if (all || [mode isEqual:@"uniform"]) {
                NSDictionary *uniform = runCase(device, queue, colorPipeline, motionPipeline, NO, 0.0f);
                cases[@"uniform"] = uniform;
                if (![uniform[@"status"] isEqual:@"uniform_verified"])
                    return @{ @"status": @"uniform_control_failed", @"device": device.name, @"cases": cases };
            }
            BOOL colorPass = NO, inputPass = NO, executionOK = YES;
            if (all || [mode isEqual:@"color-pixels"]) {
                NSDictionary *candidate = runCase(device, queue, colorPipeline, motionPipeline, YES, OUTPUT_MOTION_X);
                cases[@"moving_color_pixel_units"] = candidate;
                colorPass = [candidate[@"status"] isEqual:@"midpoint_distinguished"];
                executionOK = executionOK && (colorPass || [candidate[@"status"] isEqual:@"midpoint_inconclusive"]);
            }
            if (all || [mode isEqual:@"input-pixels"]) {
                NSDictionary *candidate = runCase(device, queue, colorPipeline, motionPipeline, YES, INPUT_MOTION_X);
                cases[@"moving_input_pixel_units"] = candidate;
                inputPass = [candidate[@"status"] isEqual:@"midpoint_distinguished"];
                executionOK = executionOK && (inputPass || [candidate[@"status"] isEqual:@"midpoint_inconclusive"]);
            }
            BOOL pass = executionOK && ([mode isEqual:@"uniform"] || colorPass || inputPass);
            return @{ @"status": pass ? @"synthetic_checks_passed" : @"moving_check_inconclusive_or_failed",
                      @"device": device.name, @"requested_case": mode, @"cases": cases,
                      @"input_size": @[@(INPUT_W), @(INPUT_H)], @"color_and_output_size": @[@(OUTPUT_W), @(OUTPUT_H)],
                      @"output_translation_pixels": @(OUTPUT_SHIFT),
                      @"motion_units": @"current_to_previous_color_vs_input_pixel_candidates_scale_1",
                      @"reset_sequence": @"first_true_second_false_previous_is_prior_encoded_color",
                      @"camera": @"static_60_degree_vertical_fov_near_0.1_far_1000_depth_0.5_nonreversed",
                      @"color": @"synthetic_tonemapped_range_manual_exposure_1_no_scaler",
                      @"purpose": @"synthetic_gpu_readback_not_production_or_presenter" };
        }
        return @{ @"status": @"os_unavailable" };
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc == 1 ? @"all" : (argc == 2 ? [NSString stringWithUTF8String:argv[1]] : nil);
        if (!mode || ![@[@"all", @"uniform", @"color-pixels", @"input-pixels"] containsObject:mode]) {
            std::fprintf(stderr, "usage: frame_interpolation [all|uniform|color-pixels|input-pixels]\n");
            return 2;
        }
        // The outer deadline also bounds synchronous framework/shader compilation
        // calls; on timeout the process exits instead of waiting on its worker.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSDictionary *result = nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            result = runFixture(mode);
            dispatch_semaphore_signal(done);
        });
        bool timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) != 0;
        NSDictionary *selected = timedOut ? @{ @"status": @"cpu_or_gpu_timeout", @"timeout_seconds": @20 } : result;
        NSMutableDictionary *report = [selected mutableCopy];
        report[@"schema"] = @"openrc-metalfx-frame-interpolation-fixture-v1";
        report[@"api_validation_requested"] = @((std::getenv("MTL_DEBUG_LAYER") ?: "")[0] == '1');
        report[@"shader_validation_requested"] = @((std::getenv("MTL_SHADER_VALIDATION") ?: "")[0] == '1');
        report[@"validation_note"] = @"environment_request_only_inspect_stderr_for_validation_diagnostics";
        NSError *jsonError = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&jsonError];
        if (!json) { std::fprintf(stderr, "JSON serialization failed: %s\n", jsonError.localizedDescription.UTF8String); return 2; }
        std::fwrite(json.bytes, 1, json.length, stdout); std::fputc('\n', stdout);
        return [report[@"status"] isEqual:@"synthetic_checks_passed"] ? 0 : 1;
    }
}
