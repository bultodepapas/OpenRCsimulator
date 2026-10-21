// MeshKit colors and Color-hex Multimesh tints are sRGB-encoded on the
// Forward+/Mobile shader path. Compatibility already supplies them in linear
// space, so return the same linear values there without a second conversion.
vec3 vertex_color_to_linear(vec3 color) {
	if (!OUTPUT_IS_SRGB) {
		vec3 linear_color = mix(
				pow((color + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)),
				color * (1.0 / 12.92),
				lessThan(color, vec3(0.04045)));
		// Palette endpoints also carry exact roof/slab tags. Do not let the
		// transfer-function arithmetic turn an encoded 1.0 into 0.99999994.
		return mix(linear_color, color, equal(color, vec3(1.0)));
	}
	return color;
}
