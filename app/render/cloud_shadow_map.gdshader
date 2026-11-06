// DT-MAC-06b C2: one periodic tile of the shared cloud noise for ground cloud shadows. Ours, MIT.
// The base deck repeats every CLOUD_FIELD_PERIOD cells, so a single tile covers the infinite field;
// drift, sun direction, scale, coverage and cluster strength stay per pixel in the consumer.
// Rendered into a half-float target and kept as RG16F: R = five-octave fbm (C2 ground shadows), G = the
// unnormalized sum of octaves 0-2 (C5b relief; consumers add octaves 3-4 per pixel). The 16-cell cluster
// noise is evaluated per pixel by consumers. 8-bit readback was not bit-exact (±1-2 LSB), hence floats.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://render/cloud_field.gdshaderinc"

uniform uint seed = 1253u;

void fragment() {
	vec2 cells = UV * float(CLOUD_FIELD_PERIOD);
	float noise = cloud_field_fbm(cells, seed, vec2(1.0));
	float low = 0.0;
	for (int octave = 0; octave < 3; octave++) {
		float scale = exp2(float(octave));
		vec2 period = vec2(float(CLOUD_FIELD_PERIOD) * scale);
		low += 0.5 / scale * cloud_field_value_noise(mod(cells * scale, period), ivec2(floor(period + vec2(0.5))),
			seed + uint(octave) * 7919u);
	}
	COLOR = vec4(noise, low, 0.0, 1.0);
}
