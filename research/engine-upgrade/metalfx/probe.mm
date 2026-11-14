// DT-MAC-11a/F03: native Metal3 API intake, not a game performance benchmark.
// Build with SDK 26+; availability checks preserve the macOS 13 deployment floor.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#include <cmath>
#include <cstdio>
#include <limits>

static constexpr NSUInteger OUTPUT_W = 1920, OUTPUT_H = 1080;
static constexpr NSUInteger INPUT_W = 1280, INPUT_H = 720;

static id<MTLTexture> texture(id<MTLDevice> device, MTLPixelFormat format,
                             NSUInteger width, NSUInteger height, MTLTextureUsage usage) {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
        width:width height:height mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = usage;
    return [device newTextureWithDescriptor:descriptor];
}

static NSDictionary *spatial(id<MTLDevice> device) {
    if (@available(macOS 13.0, *)) {
        if (![MTLFXSpatialScalerDescriptor supportsDevice:device])
            return @{ @"supported": @NO, @"status": @"device_unsupported" };
        MTLFXSpatialScalerDescriptor *descriptor = [MTLFXSpatialScalerDescriptor new];
        descriptor.inputWidth = INPUT_W; descriptor.inputHeight = INPUT_H;
        descriptor.outputWidth = OUTPUT_W; descriptor.outputHeight = OUTPUT_H;
        descriptor.colorTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.outputTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.colorProcessingMode = MTLFXSpatialScalerColorProcessingModeLinear;
        id<MTLFXSpatialScaler> scaler = [descriptor newSpatialScalerWithDevice:device];
        if (!scaler) return @{ @"supported": @YES, @"status": @"allocation_failed" };
        scaler.colorTexture = texture(device, descriptor.colorTextureFormat, INPUT_W, INPUT_H,
                                       scaler.colorTextureUsage | MTLTextureUsageRenderTarget);
        scaler.outputTexture = texture(device, descriptor.outputTextureFormat, OUTPUT_W, OUTPUT_H,
                                        scaler.outputTextureUsage);
        const NSUInteger bytes_per_row = OUTPUT_W * 8;
        id<MTLBuffer> readback = [device newBufferWithLength:bytes_per_row * OUTPUT_H
                                                    options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> buffer = [queue commandBuffer];
        if (!scaler.colorTexture || !scaler.outputTexture || !readback || !buffer)
            return @{ @"supported": @YES, @"status": @"resource_allocation_failed" };
        // Uniform linear color is an intentionally narrow output witness. It
        // cannot qualify moving edges, ghosts, image quality or production FPS.
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = scaler.colorTexture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.5, 0.75, 1.0);
        [[buffer renderCommandEncoderWithDescriptor:pass] endEncoding];
        [scaler encodeToCommandBuffer:buffer];
        id<MTLBlitCommandEncoder> copy = [buffer blitCommandEncoder];
        [copy copyFromTexture:scaler.outputTexture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
            sourceSize:MTLSizeMake(OUTPUT_W, OUTPUT_H, 1) toBuffer:readback destinationOffset:0
            destinationBytesPerRow:bytes_per_row destinationBytesPerImage:bytes_per_row * OUTPUT_H];
        [copy endEncoding];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) { dispatch_semaphore_signal(done); }];
        [buffer commit];
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)))
            return @{ @"supported": @YES, @"status": @"gpu_timeout" };
        if (buffer.status != MTLCommandBufferStatusCompleted)
            return @{ @"supported": @YES, @"status": @"gpu_error",
                      @"error": buffer.error.localizedDescription ?: @"unknown" };
        const _Float16 *pixels = static_cast<const _Float16 *>(readback.contents);
        double maximum_error = 0.0;
        const float expected[4] = {0.25f, 0.5f, 0.75f, 1.0f};
        bool finite = true;
        for (NSUInteger i = 0; i < OUTPUT_W * OUTPUT_H * 4; ++i) {
            float value = static_cast<float>(pixels[i]);
            finite &= std::isfinite(value);
            maximum_error = std::fmax(maximum_error, std::fabs(value - expected[i % 4]));
        }
        return @{ @"supported": @YES, @"status": finite && maximum_error < 0.025 ? @"output_verified" : @"output_mismatch",
                  @"maximum_absolute_error": @(maximum_error), @"finite": @(finite),
                  @"gpu_seconds": @(buffer.GPUEndTime - buffer.GPUStartTime),
                  @"witness": @"single_uniform_linear_frame_not_a_benchmark" };
    }
    return @{ @"status": @"os_unavailable" };
}

static NSDictionary *temporal(id<MTLDevice> device) {
    if (@available(macOS 13.0, *)) {
        if (![MTLFXTemporalScalerDescriptor supportsDevice:device])
            return @{ @"supported": @NO, @"status": @"device_unsupported" };
        double native_min = 1.0, native_max = 3.0;
        NSString *origin = @"engine_macos13_assumption";
        if (@available(macOS 14.0, *)) {
            native_min = [MTLFXTemporalScalerDescriptor supportedInputContentMinScaleForDevice:device];
            native_max = [MTLFXTemporalScalerDescriptor supportedInputContentMaxScaleForDevice:device];
            origin = @"native_device_query";
        }
        if (!std::isfinite(native_min) || !std::isfinite(native_max) || native_min <= 0 || native_max < native_min)
            return @{ @"supported": @YES, @"status": @"invalid_scale_bounds" };
        // Mirrors the pinned RenderingDeviceDriverMetal reciprocal/uint64 limit encoding.
        double encoded_lower = 1.0 / native_max * 1000000.0;
        double encoded_upper = 1.0 / native_min * 1000000.0;
        if (!std::isfinite(encoded_lower) || !std::isfinite(encoded_upper) || encoded_lower < 1.0
            || encoded_upper >= double(std::numeric_limits<uint64_t>::max()) || encoded_upper < encoded_lower)
            return @{ @"supported": @YES, @"status": @"invalid_encoded_scale_bounds" };
        uint64_t lower = uint64_t(encoded_lower);
        uint64_t upper = uint64_t(encoded_upper);
        MTLFXTemporalScalerDescriptor *descriptor = [MTLFXTemporalScalerDescriptor new];
        descriptor.inputWidth = INPUT_W; descriptor.inputHeight = INPUT_H;
        descriptor.outputWidth = OUTPUT_W; descriptor.outputHeight = OUTPUT_H;
        descriptor.colorTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.outputTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.depthTextureFormat = MTLPixelFormatDepth32Float;
        descriptor.motionTextureFormat = MTLPixelFormatRG16Float;
        descriptor.autoExposureEnabled = NO; // Same exposure mode as the pinned Godot factory.
        id<MTLFXTemporalScaler> scaler = [descriptor newTemporalScalerWithDevice:device];
        return @{ @"supported": @YES, @"status": scaler ? @"allocated_not_encoded" : @"allocation_failed",
                  @"bounds_origin": origin, @"native_min": @(native_min), @"native_max": @(native_max),
                  @"godot_min_integer": @(lower), @"godot_max_integer": @(upper),
                  @"godot_min_scale": @(lower / 1000000.0), @"godot_max_scale": @(upper / 1000000.0) };
    }
    return @{ @"status": @"os_unavailable" };
}

static NSDictionary *interpolation(id<MTLDevice> device) {
    if (@available(macOS 26.0, *)) {
        if (![MTLFXFrameInterpolatorDescriptor supportsDevice:device])
            return @{ @"supported": @NO, @"status": @"device_unsupported" };
        MTLFXFrameInterpolatorDescriptor *descriptor = [MTLFXFrameInterpolatorDescriptor new];
        descriptor.inputWidth = INPUT_W; descriptor.inputHeight = INPUT_H;
        descriptor.outputWidth = OUTPUT_W; descriptor.outputHeight = OUTPUT_H;
        descriptor.colorTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.outputTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.depthTextureFormat = MTLPixelFormatDepth32Float;
        descriptor.motionTextureFormat = MTLPixelFormatRG16Float;
        id<MTLFXFrameInterpolator> effect = [descriptor newFrameInterpolatorWithDevice:device];
        return @{ @"supported": @YES, @"status": effect ? @"allocated_not_encoded" : @"allocation_failed",
                  @"presentation": @"not_integrated" };
    }
    return @{ @"status": @"os_unavailable" };
}

static NSDictionary *denoised(id<MTLDevice> device) {
    if (@available(macOS 26.0, *)) {
        if (![MTLFXTemporalDenoisedScalerDescriptor supportsDevice:device])
            return @{ @"supported": @NO, @"status": @"device_unsupported",
                      @"ray_traced_inputs": @"not_integrated" };
        MTLFXTemporalDenoisedScalerDescriptor *descriptor = [MTLFXTemporalDenoisedScalerDescriptor new];
        descriptor.inputWidth = INPUT_W; descriptor.inputHeight = INPUT_H;
        descriptor.outputWidth = OUTPUT_W; descriptor.outputHeight = OUTPUT_H;
        descriptor.colorTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.outputTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.depthTextureFormat = MTLPixelFormatDepth32Float;
        descriptor.motionTextureFormat = MTLPixelFormatRG16Float;
        descriptor.diffuseAlbedoTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.specularAlbedoTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.normalTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.roughnessTextureFormat = MTLPixelFormatR16Float;
        descriptor.specularHitDistanceTextureFormat = MTLPixelFormatR16Float;
        descriptor.denoiseStrengthMaskTextureFormat = MTLPixelFormatR8Unorm;
        descriptor.transparencyOverlayTextureFormat = MTLPixelFormatRGBA16Float;
        descriptor.autoExposureEnabled = YES;
        id<MTLFXTemporalDenoisedScaler> effect = [descriptor newTemporalDenoisedScalerWithDevice:device];
        // Allocation is not denoising execution. No synthetic G-buffer may be
        // presented as a real ray-traced producer or a production integration.
        return @{ @"supported": @YES, @"status": effect ? @"allocated_not_encoded" : @"allocation_failed",
                  @"ray_traced_inputs": @"not_integrated" };
    }
    return @{ @"status": @"os_unavailable" };
}

int main() {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { std::fprintf(stderr, "No native Metal device\n"); return 2; }
        NSDictionary *result = @{ @"schema": @"openrc-metalfx-api-probe-v1", @"device": device.name,
            @"apple7": @([device supportsFamily:MTLGPUFamilyApple7]),
            @"apple9": @([device supportsFamily:MTLGPUFamilyApple9]),
            @"raytracing_api_supported": @(device.supportsRaytracing),
            @"input": @[@(INPUT_W), @(INPUT_H)], @"output": @[@(OUTPUT_W), @(OUTPUT_H)],
            @"spatial": spatial(device), @"temporal": temporal(device),
            @"frame_interpolation": interpolation(device), @"temporal_denoised": denoised(device),
            @"production_qualification": @"not_run" };
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        std::fwrite(json.bytes, 1, json.length, stdout); std::fputc('\n', stdout);
        return [result[@"spatial"][@"status"] isEqual:@"output_verified"] ? 0 : 1;
    }
}
