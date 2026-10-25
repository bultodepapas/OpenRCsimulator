shader_type canvas_item;
render_mode unshaded;

uniform float clock = 0.0;
uniform vec2 viewport_size = vec2(1920.0, 1080.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV - vec2(0.5, 0.48);
	p.x *= viewport_size.x / viewport_size.y;
	float arrival = smoothstep(0.0, 2.8, clock);
	vec3 color = vec3(0.003, 0.006, 0.012);
	// Broad atmospheric pools, with a restrained anamorphic horizon below the mark.
	color += vec3(0.005, 0.062, 0.095) * exp(-length(p * vec2(1.25, 2.8)) * 3.1) * arrival;
	color += vec3(0.0, 0.035, 0.043) * exp(-length((p - vec2(0.35, 0.05)) * vec2(2.5, 5.0)) * 2.0) * arrival;
	// One blue ignition breath as the contours become solid; never a full-screen flash.
	float ignition = exp(-pow((clock - 2.35) * 1.5, 2.0));
	color += vec3(0.005, 0.10, 0.16) * exp(-length(p * vec2(1.0, 3.8)) * 2.3) * ignition;
	float beam = exp(-pow((p.x + p.y * 0.65 - (clock - 2.4) * 0.55) * 8.0, 2.0));
	color += vec3(0.0, 0.038, 0.065) * beam * exp(-abs(p.y) * 5.0) * ignition;
	float horizon = p.y - 0.19;
	float spread = exp(-abs(p.x) * 3.0);
	color += vec3(0.02, 0.18, 0.24) * exp(-abs(horizon) * 180.0) * spread * arrival * 0.8;
	color += vec3(0.0, 0.025, 0.04) * exp(-abs(horizon) * 20.0) * spread * arrival;
	// Almost invisible optical rings, confined to the horizon rather than a HUD.
	float radius = length(vec2(p.x * 0.65, (p.y - 0.2) * 3.8));
	float ring = pow(max(0.0, cos(radius * 28.0 - clock * 0.24)), 44.0);
	color += vec3(0.005, 0.023, 0.03) * ring * exp(-radius * 4.0) * arrival;
	// Sparse floating dust: bounded single grid, no particles or persistent nodes.
	vec2 dust = p * vec2(65.0, 40.0) + vec2(clock * 0.12, -clock * 0.15);
	vec2 cell = floor(dust);
	float seed = hash(cell);
	vec2 local = fract(dust) - vec2(hash(cell + 2.0), hash(cell + 7.0));
	float mote = exp(-dot(local, local) * 850.0) * step(0.95, seed);
	color += vec3(0.23, 0.48, 0.55) * mote * (0.4 + 0.3 * sin(clock + seed * 40.0)) * arrival;
	float vignette = 1.0 - smoothstep(0.3, 1.15, length(p));
	color *= 0.5 + vignette * 0.5;
	float grain = (hash(FRAGCOORD.xy + floor(clock * 12.0)) - 0.5) / 900.0;
	COLOR = vec4(max(vec3(0.0), color + grain), 1.0);
}
