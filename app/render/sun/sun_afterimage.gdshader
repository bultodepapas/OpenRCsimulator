// SUN-03 (docs/plans/sun.md). Ours, MIT. The eye's bleached patches in the pilot view: screen-fixed (the camera is the
// pilot's gaze), drawn on a canvas layer over the 3D image and under the interface. A bleached patch has lost its
// acuity (photostress: the eye cannot read a chart there for tens of seconds), so the patch shows the image blurred
// over its own size, which removes a model inside it; once the sun's light has left it, it is also the negative
// afterimage, darker and violet. Display space: the screen texture is the finished 3D image.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 patches[8];                          // centre (screen uv), radius (share of the screen height), masking
uniform float lit[8];                             // 1 while the sun's image is still on the patch: blur, no darkening
uniform vec3 tint = vec3(0.62, 0.58, 0.80);       // SunOptics.AFTER_TINT: the negative afterimage of a white sun

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float clear = 1.0;
	float lod = 0.0;
	vec3 shade = vec3(0.0);
	float weight = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 p = patches[i];
		if (p.w <= 0.0) {
			continue;
		}
		float x = length((SCREEN_UV - p.xy) * vec2(aspect, 1.0)) / max(p.z, 1e-4);
		float m = p.w * exp(-0.5 * x * x * x * x);
		clear *= 1.0 - m;
		// Blur over twice the patch's radius in pixels (screen mipmaps), fading out beyond it: a model as large as the
		// patch is washed out, not just softened.
		lod = max(lod, (log2(max(p.z / SCREEN_PIXEL_SIZE.y, 1.0)) + 1.0) * (1.0 - smoothstep(1.0, 2.0, x)));
		shade += mix(tint, vec3(1.0), clamp(lit[i], 0.0, 1.0)) * m;
		weight += m;
	}
	float alpha = 1.0 - clear;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, lod).rgb;
	COLOR = vec4(blurred * (weight > 0.0 ? shade / weight : vec3(1.0)), alpha);
}
