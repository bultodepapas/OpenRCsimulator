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

// Four exact integer bytes survive Compatibility's float16 instance-data packing.
// +8192 represents pilot-relative coordinates from -2,048m through +14,335.75m.
vec2 tree_position(vec4 packed_position) {
    return (vec2(packed_position.x * 256.0 + packed_position.y,
                 packed_position.z * 256.0 + packed_position.w) - vec2(8192.0)) / 4.0;
}
