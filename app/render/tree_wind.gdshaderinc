// L15b: small whole-card lean. A rigid rotation keeps the interpolated trunk root
// fixed even though the atlas quad includes padding below ground. A nonlinear
// bend of its four corners would move that root. No leaf/detail bending on cards.
// Artistic estimates: <=0.24m centreline lean at 10m/s, speed squared below that,
// 0.20–0.50Hz by tree height, and a per-tree phase. Not a botanical dynamics model.
const float TREE_WIND_LEAN_M = 0.24;

vec3 tree_bend(vec3 point, vec2 wind, float height, uint identity_hash, float clock) {
    float speed_squared = dot(wind, wind);
    if (speed_squared == 0.0) {
        return point; // exact calm parity, including transparent atlas padding
    }
    vec2 direction = wind / sqrt(speed_squared);
    float height_weight = clamp((height - 12.0) / 13.0, 0.0, 1.0);
    float cycles = round(mix(512.0, 205.0, height_weight));
    float phase = fract(clock * (cycles / 1024.0) + float(identity_hash) / 65521.0);
    float sway = 0.75 + 0.25 * sin(6.28318530718 * phase);
    float angle = (TREE_WIND_LEAN_M / height) * min(speed_squared / 100.0, 1.0) * sway;
    vec3 axis = vec3(direction.y, 0.0, -direction.x);
    float c = cos(angle);
    float s = sin(angle);
    return point * c + cross(axis, point) * s + axis * dot(axis, point) * (1.0 - c);
}
