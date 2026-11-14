// DT-MAC-12a/F07: bounded, synthetic Metal 3 frame-interpolation experiment.
// This has no drawable, presenter, engine integration, FPS claim, or real-game inputs.
// API contract: https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase
// Motion direction: https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase/motionvectorscalex
// Background reference: https://github.com/apple/game-porting-toolkit/tree/main/game-porting-skills/skills/using-metalfx-frame-interpolation
// Build against SDK 26+; optional matrix controls use SDK 27 and macOS 27.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <simd/simd.h>
#include <AvailabilityMacros.h>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

static constexpr NSUInteger INPUT_W = 1280, INPUT_H = 720;
static constexpr NSUInteger OUTPUT_W = 1920, OUTPUT_H = 1080;
static constexpr NSUInteger ROW_BYTES = OUTPUT_W * 8; // RGBA16Float, 256-byte aligned
static constexpr float OUTPUT_SHIFT = 24.0f;

struct FixtureOptions {
    uint32_t extraStaticEncodes = 0; // --warmup-static: three after the reset encode
    bool matrices27 = false;
    bool singleEdge = false;
    float outputShift = OUTPUT_SHIFT;
};

static NSString *const shaderSource = @R"METAL(
#include <metal_stdlib>
using namespace metal;
struct ColorArgs { float shift; uint uniform; uint single_edge; };
kernel void make_color(texture2d<float, access::write> image [[texture(0)]],
                       constant ColorArgs &args [[buffer(0)]], uint2 p [[thread_position_in_grid]]) {
    if (p.x >= image.get_width() || p.y >= image.get_height()) return;
    if (args.uniform == 1) { image.write(float4(0.25, 0.5, 0.75, 1.0), p); return; }
    if (args.uniform == 2) { image.write(float4(1.0, 0.0, 1.0, 1.0), p); return; }
    // The default repeating hard edges reproduce R2. The optional single edge
    // changes only this synthetic plane, for a smaller-displacement control.
    float x = float(p.x) + 0.5 - args.shift;
    float y = float(p.y) + 0.5;
    float stripe = args.single_edge ? (x >= 960.0 ? 1.0 : 0.0)
                                    : (fract((x + 32.0) / 160.0) < 0.4 ? 1.0 : 0.0);
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

struct ColorArgs { float shift; uint32_t uniform; uint32_t singleEdge; };

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
                      id<MTLTexture> texture, float shift, uint32_t uniform, BOOL singleEdge) {
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (!encoder) return NO;
    ColorArgs args = {shift, uniform, uint32_t(singleEdge)};
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

// The macOS 27 properties are an independent opt-in experiment. SDK 26
// builds compile without referencing the later symbols and never fake success.
static NSString *setOptionalMatrices(id<MTLFXFrameInterpolator> fx, BOOL requested) API_AVAILABLE(macos(26.0)) {
    if (!requested) return nil;
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
    if (@available(macOS 27.0, *)) {
        constexpr float nearZ = 0.1f, farZ = 1000.0f;
        float y = 1.0f / std::tan(60.0f * 3.14159265358979323846f / 360.0f);
        float x = y / (float(OUTPUT_W) / float(OUTPUT_H));
        float z = farZ / (nearZ - farZ), t = nearZ * farZ / (nearZ - farZ);
        simd_float4x4 projection;
        projection.columns[0] = simd_make_float4(x, 0, 0, 0);
        projection.columns[1] = simd_make_float4(0, y, 0, 0);
        projection.columns[2] = simd_make_float4(0, 0, z, -1);
        projection.columns[3] = simd_make_float4(0, 0, t, 0);
        fx.worldToViewMatrix = matrix_identity_float4x4;
        fx.viewToClipMatrix = projection; // right-handed, Metal z in [0,1]
        return nil;
    }
    return @"matrix_control_requires_macos_27";
#else
    (void)fx;
    return @"matrix_control_requires_sdk_27_build";
#endif
}

static NSDictionary *encodeRecord(NSUInteger serial, BOOL reset, NSString *current) {
    return @{ @"serial": @(serial), @"simulated_time_seconds": @(double(serial) / 60.0),
              @"delta_time_seconds": @(1.0 / 60.0), @"reset": @(reset),
              @"color": current, @"previous_color": @"A" };
}

static NSDictionary *runCase(id<MTLDevice> device, id<MTLCommandQueue> queue,
                             id<MTLComputePipelineState> colorPipeline,
                             id<MTLComputePipelineState> motionPipeline,
                             id<MTLComputePipelineState> crossfadePipeline,
                             BOOL moving, float motionX, BOOL crossfadeOnly,
                             FixtureOptions options) API_AVAILABLE(macos(26.0)) {
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
    NSString *matrixFailure = setOptionalMatrices(fx, options.matrices27);
    if (matrixFailure) return @{ @"status": matrixFailure };

    // Seed: reset history with a real first color. The output is not interpreted.
    id<MTLCommandBuffer> first = [queue commandBuffer];
    uint32_t mode = moving ? 0 : 1;
    if (!first || !makeColor(first, colorPipeline, previous, 0.0f, mode, options.singleEdge) ||
        !makeColor(first, colorPipeline, current, moving ? options.outputShift : 0.0f, mode, options.singleEdge) ||
        !makeColor(first, colorPipeline, midpoint, moving ? options.outputShift * 0.5f : 0.0f, mode, options.singleEdge) ||
        !makeColor(first, colorPipeline, output, 0.0f, 2, options.singleEdge) ||
        !makeMotion(first, motionPipeline, motion, 0.0f) || !clearDepth(first, depth))
        return @{ @"status": @"input_encoding_failed" };
    NSMutableArray *encodeSequence = [NSMutableArray array];
    fx.colorTexture = previous;
    fx.prevColorTexture = previous;
    fx.shouldResetHistory = YES;
    if (!crossfadeOnly) [fx encodeToCommandBuffer:first];
    NSString *failure = nil;
    if (!waitForBuffer(first, &failure))
        return @{ @"status": @"first_encode_failed", @"detail": failure, @"encodes_completed": encodeSequence };
    if (!crossfadeOnly) {
        [encodeSequence addObject:encodeRecord(0, YES, @"A")];
        // Repeat A after the reset with zero motion; the previous texture is
        // always exactly the color from the preceding successful encode.
        for (uint32_t i = 0; i < options.extraStaticEncodes; ++i) {
            id<MTLCommandBuffer> warmup = [queue commandBuffer];
            if (!warmup || !makeMotion(warmup, motionPipeline, motion, 0.0f))
                return @{ @"status": @"warmup_input_encoding_failed", @"encodes_completed": encodeSequence };
            fx.colorTexture = previous;
            fx.prevColorTexture = previous;
            fx.shouldResetHistory = NO;
            [fx encodeToCommandBuffer:warmup];
            if (!waitForBuffer(warmup, &failure))
                return @{ @"status": @"warmup_encode_failed", @"detail": failure, @"encodes_completed": encodeSequence };
            [encodeSequence addObject:encodeRecord(i + 1, NO, @"A")];
        }
    }

    // Second encode uses the exact color from the prior encode as previous.
    // Poison output first so a missing second write is observable.
    id<MTLCommandBuffer> second = [queue commandBuffer];
    if (!second || !makeColor(second, colorPipeline, output, 0.0f, 2, options.singleEdge) ||
        !makeMotion(second, motionPipeline, motion, moving ? motionX : 0.0f))
        return @{ @"status": @"second_input_encoding_failed", @"encodes_completed": encodeSequence };
    fx.colorTexture = current;
    fx.prevColorTexture = previous;
    fx.shouldResetHistory = NO;
    if (crossfadeOnly) {
        if (!makeCrossfade(second, crossfadePipeline, previous, current, output))
            return @{ @"status": @"crossfade_encoding_failed", @"encodes_completed": encodeSequence };
    } else {
        [fx encodeToCommandBuffer:second];
    }
    id<MTLBlitCommandEncoder> blit = [second blitCommandEncoder];
    BOOL copied = copyTexture(blit, output, outBytes) && copyTexture(blit, midpoint, midBytes) &&
                  copyTexture(blit, previous, prevBytes) && copyTexture(blit, current, currBytes);
    if (!copied) return @{ @"status": @"readback_encoding_failed", @"encodes_completed": encodeSequence };
    [blit endEncoding];
    if (!waitForBuffer(second, &failure))
        return @{ @"status": @"second_encode_failed", @"detail": failure, @"encodes_completed": encodeSequence };
    if (!crossfadeOnly)
        [encodeSequence addObject:encodeRecord(options.extraStaticEncodes + 1, NO, moving ? @"B" : @"A_equivalent")];

    const _Float16 *out = static_cast<const _Float16 *>(outBytes.contents);
    const _Float16 *mid = static_cast<const _Float16 *>(midBytes.contents);
    const _Float16 *prev = static_cast<const _Float16 *>(prevBytes.contents);
    const _Float16 *curr = static_cast<const _Float16 *>(currBytes.contents);
    if (!out || !mid || !prev || !curr) return @{ @"status": @"readback_unavailable" };
    double outMid = 0.0, prevMid = 0.0, currMid = 0.0, blendMid = 0.0, outBlend = 0.0;
    double outPrev = 0.0, outCurr = 0.0;
    double maxError = 0.0, maxBlendError = 0.0;
    const uint16_t *prevBits = reinterpret_cast<const uint16_t *>(prev);
    const uint16_t *currBits = reinterpret_cast<const uint16_t *>(curr);
    const uint16_t *midBits = reinterpret_cast<const uint16_t *>(mid);
    uint64_t inputFingerprint = UINT64_C(14695981039346656037);
    uint64_t samples = 0;
    bool finite = true;
    NSUInteger left = moving ? (options.singleEdge ? OUTPUT_W / 2 - 64 : 64) : 0;
    NSUInteger right = moving ? (options.singleEdge ? OUTPUT_W / 2 + 64 : OUTPUT_W - 64) : OUTPUT_W;
    NSUInteger top = moving ? 32 : 0;
    NSUInteger bottom = moving ? OUTPUT_H - 32 : OUTPUT_H;
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
                if (x < left || x >= right || y < top || y >= bottom) continue;
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
                    outPrev += std::fabs(double(a) - double(c));
                    outCurr += std::fabs(double(a) - double(e));
                    ++samples;
                }
            }
        }
    }
    if (!finite || samples == 0) return @{ @"status": @"nonfinite_readback", @"finite": @NO };
    outMid /= double(samples); prevMid /= double(samples); currMid /= double(samples);
    blendMid /= double(samples); outBlend /= double(samples);
    outPrev /= double(samples); outCurr /= double(samples);
    NSString *status = moving ? (crossfadeOnly ? (maxBlendError < 0.001 ? @"crossfade_control_verified" : @"crossfade_mismatch")
                                               : @"motion_readback_complete")
                              : (maxError < 0.025 ? @"uniform_verified" : @"uniform_mismatch");
    return @{ @"status": status,
              @"finite": @YES, @"sampled_rgb_components": @(samples),
              @"mean_error_to_analytic_midpoint": @(outMid), @"max_component_error": @(maxError),
              @"previous_to_midpoint_mean_error": @(prevMid), @"current_to_midpoint_mean_error": @(currMid),
              @"output_to_previous_mean_error": @(outPrev), @"output_to_current_mean_error": @(outCurr),
              @"crossfade_to_midpoint_mean_error": @(blendMid), @"output_to_crossfade_mean_error": @(outBlend),
              @"output_to_crossfade_max_error": @(maxBlendError),
              @"comparison_region": @[@(left), @(top), @(right - left), @(bottom - top)],
              @"motion_texture_x": @(moving ? motionX : 0.0f),
              @"input_fingerprint_fnv64": [NSString stringWithFormat:@"%016llx", (unsigned long long)inputFingerprint],
              @"interpolator_encoded": @(!crossfadeOnly), @"encode_sequence": encodeSequence,
              @"static_warmup_encodes_requested": @(options.extraStaticEncodes),
              @"static_warmup_encodes_completed": @(crossfadeOnly ? 0 : options.extraStaticEncodes),
              @"convention_claim_from_this_case": @NO };
}

// A candidate is a useful witness only when it beats a literal half-blend, a
// zero vector, and the same-magnitude reversed vector by a fixed margin. Even
// then this one planar scene does not establish a production motion convention.
static NSDictionary *compareCases(NSDictionary *cases) {
    NSArray *names = @[@"crossfade", @"zero", @"reverse-color", @"reverse-input", @"color-pixels", @"input-pixels"];
    NSDictionary *uniform = cases[@"uniform"];
    if (![uniform isKindOfClass:[NSDictionary class]] || ![uniform[@"status"] isEqual:@"uniform_verified"])
        return @{ @"status": @"control_missing_or_failed", @"detail": @"uniform" };
    NSString *fingerprint = nil;
    for (NSString *name in names) {
        NSDictionary *entry = cases[name];
        NSString *expected = [name isEqual:@"crossfade"] ? @"crossfade_control_verified" : @"motion_readback_complete";
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"status"] isEqual:expected] ||
            ![entry[@"mean_error_to_analytic_midpoint"] isKindOfClass:[NSNumber class]] ||
            ![entry[@"output_to_crossfade_mean_error"] isKindOfClass:[NSNumber class]] ||
            ![entry[@"input_fingerprint_fnv64"] isKindOfClass:[NSString class]])
            return @{ @"status": @"control_missing_or_failed", @"detail": name };
        if (!fingerprint) fingerprint = entry[@"input_fingerprint_fnv64"];
        else if (![fingerprint isEqual:entry[@"input_fingerprint_fnv64"]])
            return @{ @"status": @"input_fingerprint_mismatch", @"detail": name };
    }
    double blend = [cases[@"crossfade"][@"mean_error_to_analytic_midpoint"] doubleValue];
    double zero = [cases[@"zero"][@"mean_error_to_analytic_midpoint"] doubleValue];
    double wrongColor = [cases[@"reverse-color"][@"mean_error_to_analytic_midpoint"] doubleValue];
    double wrongInput = [cases[@"reverse-input"][@"mean_error_to_analytic_midpoint"] doubleValue];
    double color = [cases[@"color-pixels"][@"mean_error_to_analytic_midpoint"] doubleValue];
    double input = [cases[@"input-pixels"][@"mean_error_to_analytic_midpoint"] doubleValue];
    double colorBlendDistance = [cases[@"color-pixels"][@"output_to_crossfade_mean_error"] doubleValue];
    double inputBlendDistance = [cases[@"input-pixels"][@"output_to_crossfade_mean_error"] doubleValue];
    constexpr double margin = 0.005;
    BOOL colorWitness = color + margin < std::fmin(blend, std::fmin(zero, wrongColor)) && colorBlendDistance > margin;
    BOOL inputWitness = input + margin < std::fmin(blend, std::fmin(zero, wrongInput)) && inputBlendDistance > margin;
    return @{ @"status": (colorWitness || inputWitness) ? @"synthetic_motion_distinguished" : @"synthetic_motion_inconclusive",
              @"color_pixel_candidate_distinguished": @(colorWitness),
              @"input_pixel_candidate_distinguished": @(inputWitness),
              @"required_mean_error_margin": @(margin), @"crossfade_mean_error": @(blend),
              @"zero_motion_mean_error": @(zero), @"reversed_color_mean_error": @(wrongColor),
              @"reversed_input_mean_error": @(wrongInput), @"color_candidate_mean_error": @(color),
              @"input_candidate_mean_error": @(input), @"input_fingerprint_fnv64": fingerprint,
              @"convention_claim": @NO,
              @"scope": @"one_synthetic_planar_witness_not_production_motion_or_presentation" };
}

static NSDictionary *configuration(FixtureOptions options) {
    return @{ @"extra_static_encodes_after_reset": @(options.extraStaticEncodes),
              @"matrix_mode": options.matrices27 ? @"macos27_identity_view_and_metal_perspective" : @"sdk26_scalar_only",
              @"scene": options.singleEdge ? @"single_edge" : @"r2_repeating_edges",
              @"output_shift_pixels": @(options.outputShift) };
}

static NSDictionary *runFixture(NSString *mode, FixtureOptions options) {
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
            id<MTLFunction> crossfadeFunction = [library newFunctionWithName:@"make_crossfade"];
            if (!queue || !colorFunction || !motionFunction || !crossfadeFunction) return @{ @"status": @"pipeline_inputs_failed" };
            id<MTLComputePipelineState> colorPipeline = [device newComputePipelineStateWithFunction:colorFunction error:&error];
            if (!colorPipeline) return @{ @"status": @"color_pipeline_failed", @"detail": error.localizedDescription ?: @"unknown" };
            id<MTLComputePipelineState> motionPipeline = [device newComputePipelineStateWithFunction:motionFunction error:&error];
            if (!motionPipeline) return @{ @"status": @"motion_pipeline_failed", @"detail": error.localizedDescription ?: @"unknown" };
            id<MTLComputePipelineState> crossfadePipeline = [device newComputePipelineStateWithFunction:crossfadeFunction error:&error];
            if (!crossfadePipeline) return @{ @"status": @"crossfade_pipeline_failed", @"detail": error.localizedDescription ?: @"unknown" };
            BOOL all = [mode isEqual:@"all"];
            NSMutableDictionary *cases = [NSMutableDictionary dictionary];
            NSArray *names = @[@"uniform", @"crossfade", @"zero", @"reverse-color", @"reverse-input", @"color-pixels", @"input-pixels"];
            float outputMotion = -options.outputShift;
            float inputMotion = outputMotion * float(INPUT_W) / float(OUTPUT_W);
            for (NSString *name in names) {
                if (!all && ![mode isEqual:name]) continue;
                BOOL moving = ![name isEqual:@"uniform"];
                BOOL crossfadeOnly = [name isEqual:@"crossfade"];
                float motionX = 0.0f;
                if ([name isEqual:@"color-pixels"]) motionX = outputMotion;
                if ([name isEqual:@"input-pixels"]) motionX = inputMotion;
                if ([name isEqual:@"reverse-color"]) motionX = -outputMotion;
                if ([name isEqual:@"reverse-input"]) motionX = -inputMotion;
                NSDictionary *entry = runCase(device, queue, colorPipeline, motionPipeline, crossfadePipeline,
                                              moving, motionX, crossfadeOnly, options);
                cases[name] = entry;
                NSString *expected = !moving ? @"uniform_verified" : (crossfadeOnly ? @"crossfade_control_verified" : @"motion_readback_complete");
                if (![entry[@"status"] isEqual:expected])
                    return @{ @"status": @"case_failed", @"device": device.name, @"failed_case": name,
                              @"configuration": configuration(options), @"cases": cases };
            }
            NSDictionary *comparison = all ? compareCases(cases) : nil;
            return @{ @"status": all ? comparison[@"status"] : @"individual_case_complete",
                      @"device": device.name, @"requested_case": mode, @"cases": cases,
                      @"comparison": comparison ?: (id)[NSNull null],
                      @"configuration": configuration(options),
                      @"input_size": @[@(INPUT_W), @(INPUT_H)], @"color_and_output_size": @[@(OUTPUT_W), @(OUTPUT_H)],
                      @"output_translation_pixels": @(options.outputShift),
                      @"motion_units": @"current_to_previous_color_vs_input_pixel_candidates_scale_1",
                      @"reset_sequence": @"first_reset_optional_static_warmups_then_test_previous_is_prior_encoded_color",
                      @"camera": @"static_60_degree_vertical_fov_near_0.1_far_1000_depth_0.5_nonreversed",
                      @"color": @"synthetic_tonemapped_range_manual_exposure_1_no_scaler",
                      @"fixture_revision": @"hard_edges_warmup_matrix_controls_v3",
                      @"baseline_path": @"no_options_repeats_r2_sequence_and_scene",
                      @"purpose": @"synthetic_gpu_readback_not_production_or_presenter" };
        }
        return @{ @"status": @"os_unavailable" };
    }
}

// Combine individually bounded runs without touching the GPU. A caller must
// separately retain matching source/binary hashes; these JSON checks cannot
// establish binary identity by themselves.
static NSDictionary *compareReports(NSArray<NSString *> *paths) {
    NSMutableDictionary *cases = [NSMutableDictionary dictionary];
    NSString *device = nil;
    NSNumber *apiValidation = nil, *shaderValidation = nil;
    NSDictionary *expectedConfiguration = nil;
    NSArray *names = @[@"uniform", @"crossfade", @"zero", @"reverse-color", @"reverse-input", @"color-pixels", @"input-pixels"];
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        id report = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![report isKindOfClass:[NSDictionary class]] ||
            ![report[@"schema"] isEqual:@"openrc-metalfx-frame-interpolation-fixture-v1"] ||
            ![report[@"fixture_revision"] isEqual:@"hard_edges_warmup_matrix_controls_v3"] ||
            ![report[@"status"] isEqual:@"individual_case_complete"] ||
            ![report[@"device"] isKindOfClass:[NSString class]] ||
            ![report[@"configuration"] isKindOfClass:[NSDictionary class]] ||
            ![report[@"api_validation_requested"] isKindOfClass:[NSNumber class]] ||
            ![report[@"shader_validation_requested"] isKindOfClass:[NSNumber class]])
            return @{ @"status": @"comparison_input_invalid", @"detail": path };
        NSString *name = report[@"requested_case"];
        NSDictionary *reportCases = report[@"cases"];
        if (![name isKindOfClass:[NSString class]] || ![names containsObject:name] ||
            ![reportCases isKindOfClass:[NSDictionary class]])
            return @{ @"status": @"comparison_case_missing_or_duplicate", @"detail": path };
        NSDictionary *entry = reportCases[name];
        if (cases[name] || ![entry isKindOfClass:[NSDictionary class]])
            return @{ @"status": @"comparison_case_missing_or_duplicate", @"detail": path };
        if (!device) {
            device = report[@"device"];
            apiValidation = report[@"api_validation_requested"];
            shaderValidation = report[@"shader_validation_requested"];
            expectedConfiguration = report[@"configuration"];
        } else if (![device isEqual:report[@"device"]] || ![apiValidation isEqual:report[@"api_validation_requested"]] ||
                   ![shaderValidation isEqual:report[@"shader_validation_requested"]] ||
                   ![expectedConfiguration isEqual:report[@"configuration"]]) {
            return @{ @"status": @"comparison_environment_mismatch", @"detail": path };
        }
        cases[name] = entry;
    }
    NSDictionary *comparison = compareCases(cases);
    return @{ @"status": comparison[@"status"], @"device": device ?: @"unknown", @"requested_case": @"compare",
              @"cases": cases, @"comparison": comparison, @"fixture_revision": @"hard_edges_warmup_matrix_controls_v3",
              @"configuration": expectedConfiguration ?: @{},
              @"source_and_binary_identity": @"verify_separately_using_retained_hash_receipts",
              @"compared_api_validation_requested": apiValidation ?: @NO,
              @"compared_shader_validation_requested": shaderValidation ?: @NO };
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc == 1 ? @"all" : [NSString stringWithUTF8String:argv[1]];
        NSArray *modes = @[@"all", @"uniform", @"crossfade", @"zero", @"reverse-color", @"reverse-input", @"color-pixels", @"input-pixels"];
        BOOL comparing = [mode isEqual:@"compare"];
        FixtureOptions options;
        BOOL valid = mode != nil && (comparing ? argc == 9 : [modes containsObject:mode]);
        NSMutableSet *seen = [NSMutableSet set];
        if (!comparing) for (int i = 2; i < argc; ++i) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if (!arg || [seen containsObject:arg]) { valid = NO; break; }
            [seen addObject:arg];
            if ([arg isEqual:@"--warmup-static=3"]) options.extraStaticEncodes = 3;
            else if ([arg isEqual:@"--matrices-27"]) options.matrices27 = true;
            else if ([arg isEqual:@"--single-edge"]) options.singleEdge = true;
            else if ([arg isEqual:@"--small-shift=4"]) options.outputShift = 4.0f;
            else valid = NO;
        }
        if (!valid) {
            std::fprintf(stderr, "usage: frame_interpolation [all|uniform|crossfade|zero|reverse-color|reverse-input|color-pixels|input-pixels]\n"
                                 "       [--warmup-static=3] [--matrices-27] [--single-edge] [--small-shift=4]\n"
                                 "       frame_interpolation compare <seven individual JSON files>\n");
            return 2;
        }
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        if (comparing) for (int i = 2; i < argc; ++i) [paths addObject:[NSString stringWithUTF8String:argv[i]]];
        // The outer deadline also bounds synchronous framework/shader compilation
        // calls; on timeout the process exits instead of waiting on its worker.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSDictionary *result = nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            result = comparing ? compareReports(paths) : runFixture(mode, options);
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
        return ([report[@"status"] isEqual:@"individual_case_complete"] ||
                [report[@"status"] isEqual:@"synthetic_motion_distinguished"]) ? 0 : 1;
    }
}
