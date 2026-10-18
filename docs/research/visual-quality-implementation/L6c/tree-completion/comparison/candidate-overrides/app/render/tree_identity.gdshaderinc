// L6b/L7 identity: quarter-metre pilot-relative N/E lattice; integer-only hash.
// Mirrored in treeline.gd and checked with rendered GPU readback. No frame/time seed.
// Keep L6b's +2400 hash coordinates; south/west positions outside that range use +8192.
uint tree_hash(vec2 north_east) {
    ivec2 signed_q = ivec2(round(north_east * 4.0));
    ivec2 hash_offset = any(lessThan(signed_q, ivec2(-2400))) ? ivec2(8192) : ivec2(2400);
    uvec2 q = uvec2(signed_q + hash_offset);
    uint h = (q.x * 7381u + q.y * 19391u + 6113u) % 65521u;
    return (h * 25173u + 13849u) % 65521u;
}
vec3 tree_identity(vec2 north_east) {
    uint h = tree_hash(north_east);
    uint r = (h * 25173u + 13849u) % 65521u;
    return vec3(float(h % 3u), 12.0 + 13.0 * float(h % 1024u) / 1023.0,
                6.28318530718 * float(r) / 65521.0);
}

// A slowly interpolated world-space value field supplies a shared forest patch
// tint. Cell coordinates are offset before uint conversion so negative N/E
// positions hash identically on every renderer without signed-overflow rules.
const float TREE_PATCH_SPACING_M = 180.0;
float tree_patch_value(ivec2 cell) {
    uvec2 q = uvec2(cell + ivec2(32768));
    uint h = (q.x * 7381u + q.y * 19391u + 6113u) % 65521u;
    h = (h * 25173u + 13849u) % 65521u;
    return float(h % 997u) / 498.0 - 1.0;
}
float tree_patch_noise(vec2 world_north_east) {
    vec2 grid = world_north_east / TREE_PATCH_SPACING_M;
    ivec2 cell = ivec2(floor(grid));
    vec2 blend = fract(grid);
    blend = blend * blend * (3.0 - 2.0 * blend);
    float lower = mix(tree_patch_value(cell), tree_patch_value(cell + ivec2(1, 0)), blend.x);
    float upper = mix(tree_patch_value(cell + ivec2(0, 1)), tree_patch_value(cell + ivec2(1, 1)), blend.x);
    return mix(lower, upper, blend.y);
}

// Four exact integer bytes survive Compatibility's float16 instance-data packing.
// +8192 represents pilot-relative coordinates from -2,048m through +14,335.75m.
vec2 tree_position(vec4 packed_position) {
    return (vec2(packed_position.x * 256.0 + packed_position.y,
                 packed_position.z * 256.0 + packed_position.w) - vec2(8192.0)) / 4.0;
}
