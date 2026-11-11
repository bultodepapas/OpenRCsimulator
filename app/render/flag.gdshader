shader_type spatial;
render_mode cull_disabled;

uniform vec3 cloth_points[45];
uniform vec2 cloth_phase = vec2(0.0);
uniform float cloth_energy = 0.0;
uniform bool fine_fabric = false;
uniform sampler2D country_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D weave_texture : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D weave_color : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D weave_roughness : repeat_enable, filter_linear_mipmap;
uniform vec2 cloth_size = vec2(1.5, 0.9);

vec3 along_at(ivec2 i) {
	return cloth_points[i.y*9+min(i.x+1,8)]-cloth_points[i.y*9+max(i.x-1,0)];
}

vec3 down_at(ivec2 i) {
	return cloth_points[min(i.y+1,4)*9+i.x]-cloth_points[max(i.y-1,0)*9+i.x];
}

vec3 cloth(vec2 uv) {
	vec2 cell = clamp(uv, vec2(0.0), vec2(1.0)) * vec2(8.0, 4.0);
	ivec2 i = min(ivec2(floor(cell)), ivec2(7, 3));
	vec2 f = cell - vec2(i);
	int n = i.y * 9 + i.x;
	vec3 p = mix(mix(cloth_points[n], cloth_points[n+1], f.x),
		mix(cloth_points[n+9], cloth_points[n+10], f.x), f.y);
	// Small detail only; the 2D surface owns the silhouette and attachment.
	float clearance = smoothstep(0.065, 0.13, length(p.xz - vec2(-0.06, 0.0)));
	p.z += clearance * uv.x * uv.x * cloth_energy * 0.004 *
		(sin(uv.x*39.0 + uv.y*13.0 - cloth_phase.x) + 0.45*sin(uv.x*67.0-uv.y*17.0-cloth_phase.y));
	return p;
}

void vertex() {
	VERTEX = cloth(UV);
	// Smooth vertex normals derived from the deformed lattice, not the bind plane.
	// Interpolation avoids lighting bands at control-cell boundaries and saves
	// four extra evaluations of the wrinkle function for every rendered vertex.
	vec2 cell = clamp(UV,vec2(0.0),vec2(1.0))*vec2(8.0,4.0);
	ivec2 i = min(ivec2(floor(cell)),ivec2(7,3));
	vec2 f = cell-vec2(i);
	vec3 along = mix(mix(along_at(i),along_at(i+ivec2(1,0)),f.x),mix(along_at(i+ivec2(0,1)),along_at(i+ivec2(1,1)),f.x),f.y);
	vec3 down = mix(mix(down_at(i),down_at(i+ivec2(1,0)),f.x),mix(down_at(i+ivec2(0,1)),down_at(i+ivec2(1,1)),f.x),f.y);
	NORMAL = normalize(cross(down,along) + vec3(0.0,0.0,0.0000001));
	TANGENT = normalize(along + vec3(0.0000001,0.0,0.0));
	BINORMAL = normalize(cross(TANGENT,NORMAL));
}

void fragment() {
	// The back shows the mirrored print of the same physical sheet.
	ALBEDO = texture(country_texture,UV).rgb * 0.82;
	// Godot's cull_disabled side check already flips the back-face normal.
	ROUGHNESS = 0.88;
	SPECULAR = 0.22;
	if (fine_fabric) {
		vec2 metres = UV * cloth_size;
		vec2 weave = metres / vec2(0.72,1.02);
		float grain = dot(texture(weave_color,weave).rgb,vec3(0.2126,0.7152,0.0722));
		float edge = min(min(metres.x,cloth_size.x-metres.x),min(metres.y,cloth_size.y-metres.y));
		float hem = 1.0-smoothstep(0.008,0.008+max(fwidth(edge),0.001),edge);
		ALBEDO *= clamp(0.99+(grain-0.58)*0.16,0.90,1.05)*(1.0-0.14*hem);
		ROUGHNESS = clamp(0.78+texture(weave_roughness,weave).r*0.20,0.78,1.0);
		NORMAL_MAP = texture(weave_texture,weave).rgb;
		NORMAL_MAP_DEPTH = 0.35;
	}
}
