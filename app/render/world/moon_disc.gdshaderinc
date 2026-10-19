// FW-MOON-03/05 (docs/plans/moon.md): the moon's disc, one implementation for every surface that draws it. Ours, MIT.
// FW-MOON-05: the NASA SVS CGI Moon Kit albedo and a LOLA-derived normal map (tools/world/moon_texture.py), oriented
// by the IAU rotation model through moon_render_to_body (libration, axis tilt and the turn of the face through the
// night); refraction squashes a low disc vertically. Map convention: u = lon/360° + 0.5 (east longitude, 0° at the
// centre), v = 0.5 − lat/180°; the normal map stores (east, north, up) as 0.5 + 0.5·n.
// Photometry: lunar-Lambert (McEwen 1991, Icarus 92:298), r = 2L·μ0/(μ0 + μ) + (1 − L)·μ0, which is flat at full moon
// (Lommel-Seeliger) and Lambert-like at large phase; moon_phase_k scales it so the disc-integrated brightness follows
// the Krisciunas & Schaefer (1991) phase law (sky_state.gd computes L and K). Earthshine lights the whole visible
// hemisphere almost from the observer's side, so it is flat (moon_earthshine, sky_state.gd). The terminator follows
// the true direction from the moon to the sun; the edge is antialiased to about one pixel.
// All inputs are linear and come from the CPU (no TIME): captures repeat.

uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);     // toward the moon's centre
uniform vec3 moon_lin = vec3(0.0);                // full-moon surface radiance × atmospheric transmittance; 0 = no moon
uniform vec3 moon_sun_dir = vec3(0.0, 1.0, 0.0);  // from the moon toward the sun
uniform float moon_radius = 0.0045379;            // rad: angular semidiameter (mean 0.26°)
uniform float moon_phase_l = 1.0;                 // McEwen L(α), clamped to [0, 1]
uniform float moon_phase_k = 1.0;                 // phase-law normalisation K(α)
uniform vec3 moon_earthshine = vec3(0.0);         // earthlight/sunlight irradiance at the moon × bluish tint
// The eye's local adaptation (sky_state.gd): scale and exponent on the illumination; 1, 1 = physical (by day).
uniform float moon_display_scale = 1.0;
uniform float moon_display_gamma = 1.0;
uniform bool moon_textured = false;
uniform sampler2D moon_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moon_normal : filter_linear_mipmap, repeat_enable;
uniform mat3 moon_render_to_body = mat3(1.0);    // render-frame direction -> Moon-fixed (x: 0° E, z: north)
uniform float moon_albedo_scale = 1.0;           // 1 / near-side mean linear luminance of the albedo map
uniform float moon_squash = 1.0;                 // apparent / true vertical size (refraction; 1 above ~10°)

vec3 moon_disc(vec3 d) {
	float c = dot(d, moon_dir);
	// Offset from the centre on the plane of the sky; undo the refraction squash along the local vertical first.
	vec3 o = d - moon_dir * c;
	vec3 up_sky = vec3(0.0, 1.0, 0.0) - moon_dir * moon_dir.y;
	float up_len = length(up_sky);
	if (up_len > 1e-4) {
		up_sky /= up_len;
		o += up_sky * (dot(o, up_sky) * (1.0 / moon_squash - 1.0));
	}
	// Radial position in disc radii and its screen derivative, taken before any branch (derivatives need uniform flow).
	float rr = length(o) / sin(moon_radius);
	float aa = max(fwidth(rr), 1e-4);
	if (c <= 0.0 || rr > 1.0 + 2.0 * aa || dot(moon_lin, vec3(1.0)) <= 0.0) {
		return vec3(0.0);
	}
	float edge = clamp((1.0 - rr) / aa + 0.5, 0.0, 1.0);
	vec3 offset = o / sin(moon_radius);
	float r = min(rr, 1.0);
	float mu = sqrt(max(1.0 - r * r, 0.0));                // cos(emission): the normal against the view
	vec3 normal = offset / max(rr, 1e-6) * r - moon_dir * mu; // the sphere's normal on the side facing the observer
	vec3 albedo = vec3(1.0);
	if (moon_textured) {
		vec3 p = moon_render_to_body * normal;
		float lon = atan(p.y, p.x);
		float lat = asin(clamp(p.z, -1.0, 1.0));
		vec2 uv = vec2(lon * 0.159154943 + 0.5, 0.5 - lat * 0.318309886);
		// Explicit level of detail from the disc's size on screen: the 2048-texel map spans the visible hemisphere's
		// diameter with 1024 texels, so 512·aa texels per pixel at the centre, more toward the foreshortened limb.
		// No screen derivatives of uv, hence no seam at ±180°.
		float lod = log2(max(512.0 * aa / max(mu, 0.0625), 1.0));
		albedo = textureLod(moon_albedo, uv, lod).rgb * moon_albedo_scale;
		vec3 nm = textureLod(moon_normal, uv, max(lod - 1.0, 0.0)).rgb * 2.0 - 1.0; // half-resolution map
		vec3 east = vec3(-sin(lon), cos(lon), 0.0);
		vec3 north = cross(p, east);
		normal = transpose(moon_render_to_body) * normalize(east * nm.x + north * nm.y + p * nm.z);
		mu = clamp(dot(normal, -d), 0.0, 1.0);
	}
	float mu0 = max(dot(normal, moon_sun_dir), 0.0);       // cos(incidence)
	float lit = 2.0 * moon_phase_l * mu0 / max(mu0 + mu, 1e-4) + (1.0 - moon_phase_l) * mu0;
	vec3 light = vec3(moon_phase_k * lit) + moon_earthshine; // relative to the flat full moon
	float level = max(dot(light, vec3(0.2126, 0.7152, 0.0722)), 1e-12);
	vec3 seen = light / level * pow(level, moon_display_gamma) * moon_display_scale; // hue kept, level compressed
	return moon_lin * edge * seen * albedo;
}
