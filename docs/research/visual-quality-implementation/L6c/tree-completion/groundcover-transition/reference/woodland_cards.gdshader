shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D impostor_atlas : source_color, filter_linear, repeat_disable;
uniform sampler2D plain_atlas : source_color, filter_linear, repeat_disable;
uniform sampler2D fern_atlas : source_color, filter_linear, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.32;
uniform float atlas_frames = 4.0;

varying float selected_frame;
varying float species;
varying vec3 plant_tint;

void vertex() {
	species = INSTANCE_CUSTOM.y;
	plant_tint = COLOR.rgb;
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	vec3 to_camera = CAMERA_POSITION_WORLD - instance_origin;
	to_camera.y = 0.0;
	if (length(to_camera) < 0.0001) {
		to_camera = vec3(1.0, 0.0, 0.0);
	}
	vec3 toward_camera = normalize(to_camera);
	float local_yaw = INSTANCE_CUSTOM.x * TAU;
	float source_view_angle = mod(atan(toward_camera.z, toward_camera.x) + local_yaw + TAU, TAU);
	selected_frame = mod(floor(source_view_angle / (TAU / atlas_frames) + 0.5), atlas_frames);

	vec3 right = cross(vec3(0.0, 1.0, 0.0), toward_camera);
	if (length(right) < 0.0001) {
		right = vec3(0.0, 0.0, 1.0);
	}
	right = normalize(right);
	vec3 model_x = normalize(MODEL_MATRIX[0].xyz);
	vec3 model_z = normalize(MODEL_MATRIX[2].xyz);
	// The source cards use only a yaw rotation and uniform instance scale.
	// Project the world-facing billboard right vector into that local basis;
	// this avoids an inverse-matrix builtin that Godot's shader language lacks.
	VERTEX = vec3(
		dot(right, model_x) * VERTEX.x,
		VERTEX.y,
		dot(right, model_z) * VERTEX.x
	);
}

void fragment() {
	vec2 atlas_dimensions = vec2(textureSize(impostor_atlas, 0));
	float frame_width_px = atlas_dimensions.x / atlas_frames;
	float local_u = clamp(UV.x, 0.5 / frame_width_px, 1.0 - 0.5 / frame_width_px);
	float local_v = clamp(UV.y, 0.5 / atlas_dimensions.y, 1.0 - 0.5 / atlas_dimensions.y);
	vec2 atlas_uv = vec2((selected_frame + local_u) / atlas_frames, local_v);
	vec4 leaf_sample;
	if (species < 0.5) { leaf_sample = texture(plain_atlas, atlas_uv); }
	else if (species > 1.5) { leaf_sample = texture(fern_atlas, atlas_uv); }
	else { leaf_sample = texture(impostor_atlas, atlas_uv); }
	ALBEDO = leaf_sample.rgb * plant_tint;
	// The downloaded atlas contains source albedo, with no baked light. Let the world light its canopy.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = leaf_sample.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
