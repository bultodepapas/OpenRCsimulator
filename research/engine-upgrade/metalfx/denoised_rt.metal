// DT-MAC-13d: isolated ray-traced inputs for MetalFX Denoising, not Godot.
// API pattern: https://developer.apple.com/videos/play/wwdc2020/10012/
// Denoiser inputs: https://developer.apple.com/videos/play/wwdc2025/211/
#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace raytracing;

constant uint W = 1280, H = 720;

static uint hash32(uint v) {
    v ^= v >> 16; v *= 0x7feb352dU; v ^= v >> 15;
    v *= 0x846ca68bU; v ^= v >> 16; return v;
}

// The RT scene is static: an orthographic +Z camera at z=0 sees a triangle at
// z=2. Its reflected -Z ray hits a larger triangle at z=-2. Normals are world
// space, linear roughness is 0.5, depth is z/4 in Metal [0,1] clip space,
// motion/jitter are zero, and reflection distance is in scene units.
// For hits, cosine-weighted hemisphere sampling of a 2*cos(theta) environment
// has expectation 4/3. The 0.04 specular contribution is conditioned on the
// actual secondary intersection. Background is a constant unlit color.
kernel void trace_scene(
    primitive_acceleration_structure scene [[buffer(0)]],
    device float4 *witness [[buffer(1)]], constant uint &frame [[buffer(2)]],
    texture2d<float, access::write> color [[texture(0)]],
    texture2d<float, access::write> depth_value [[texture(1)]],
    texture2d<float, access::write> motion [[texture(2)]],
    texture2d<float, access::write> diffuse [[texture(3)]],
    texture2d<float, access::write> specular [[texture(4)]],
    texture2d<float, access::write> normal [[texture(5)]],
    texture2d<float, access::write> roughness [[texture(6)]],
    texture2d<float, access::write> spec_distance [[texture(7)]],
    texture2d<float, access::write> denoise_mask [[texture(8)]],
    uint2 p [[thread_position_in_grid]]) {
    if (p.x >= W || p.y >= H) return;
    float x = 2.0f * (float(p.x) + 0.5f) / float(W) - 1.0f;
    float y = 1.0f - 2.0f * (float(p.y) + 0.5f) / float(H);
    ray primary;
    primary.origin = float3(x, y, 0.0f); primary.direction = float3(0, 0, 1);
    primary.min_distance = 0.001f; primary.max_distance = 10.0f;
    intersector<triangle_data> intersect;
    auto hit = intersect.intersect(primary, scene);
    bool front = hit.type != intersection_type::none;
    float distance = 0.0f;
    if (front) {
        ray reflected;
        reflected.origin = float3(x, y, 2.0f - 0.001f);
        reflected.direction = float3(0, 0, -1);
        reflected.min_distance = 0.001f; reflected.max_distance = 10.0f;
        auto reflected_hit = intersect.intersect(reflected, scene);
        if (reflected_hit.type != intersection_type::none) distance = reflected_hit.distance + 0.001f;
    }
    uint index = p.y * W + p.x;
    float u = (float(hash32(index ^ (frame * 0x9e3779b9U)) & 65535U) + 0.5f) / 65536.0f;
    float3 base = float3(0.24f, 0.36f, 0.48f);
    float3 c = front ? base * (2.0f * sqrt(u)) + (distance > 0.0f ? 0.04f : 0.0f)
                     : float3(0.06f, 0.10f, 0.16f);
    color.write(float4(c, 1), p);
    depth_value.write(float4(front ? 0.5f : 1.0f), p);
    motion.write(float4(0), p);
    diffuse.write(float4(front ? base : float3(0), 1), p);
    specular.write(float4(front ? float3(0.04f) : float3(0), 1), p);
    normal.write(float4(0, 0, -1, 1), p);
    roughness.write(float4(0.5f), p);
    spec_distance.write(float4(distance), p);
    // Uniform zero: the SDK header says 1 means ignored; WWDC prose differs.
    // No claim is made that a particular mask value produced the quality result.
    denoise_mask.write(float4(0), p);
    witness[index] = float4(front ? 1.0f : 0.0f, front ? hit.distance : 0.0f, distance, u);
}

struct RasterVertex { float4 position [[position]]; };
vertex RasterVertex depth_vertex(uint id [[vertex_id]]) {
    const float2 positions[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    return {float4(positions[id], 0, 1)};
}
struct DepthResult { float depth [[depth(any)]]; };
fragment DepthResult depth_fragment(RasterVertex in [[stage_in]],
                                    texture2d<float, access::read> values [[texture(0)]]) {
    return {values.read(uint2(in.position.xy)).r};
}

kernel void clear_output(texture2d<float, access::write> output [[texture(0)]],
                         uint2 p [[thread_position_in_grid]]) {
    if (p.x < output.get_width() && p.y < output.get_height())
        output.write(float4(7.0f, 7.0f, 7.0f, 7.0f), p);
}
