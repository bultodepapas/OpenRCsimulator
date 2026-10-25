// SPDX-License-Identifier: MIT
// Derived from Godot Engine's motion_vector_decode.glsl (Godot Engine contributors).

#[compute]

#version 450

#VERSION_DEFINES

#extension GL_EXT_samplerless_texture_functions : require

#include "motion_vector_inc.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rg16f, set = 0, binding = 0) uniform restrict image2D velocity_buffer;
layout(r8, set = 0, binding = 1) uniform restrict writeonly image2D reactive_mask_output;
layout(set = 1, binding = 0) uniform texture2D depth_buffer;

#if defined(FSR3_PREPARE_REACTIVE)
layout(set = 1, binding = 1) uniform texture2D reactive_buffer;
#endif

layout(push_constant, std430) uniform Params {
	vec4 resolution;
	mat4 reprojection;
}
params;

void main() {
	const ivec2 screen_pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(screen_pos, ivec2(params.resolution.xy)))) {
		return;
	}

	vec2 velocity = imageLoad(velocity_buffer, screen_pos).rg;
	bool is_invalid_motion_vector = all(lessThanEqual(velocity, vec2(-1.0f, -1.0f)));
	if (is_invalid_motion_vector) {
		float depth_value = texelFetch(depth_buffer, screen_pos, 0).r;
		vec2 uv = (vec2(screen_pos) + vec2(0.5)) / params.resolution.xy;
		velocity = derive_motion_vector(uv, depth_value, params.reprojection);
	}
	imageStore(velocity_buffer, screen_pos, vec4(velocity, 0.0f, 0.0f));

#if defined(FSR3_PREPARE_REACTIVE)
	float reactive = texelFetch(reactive_buffer, screen_pos, 0).r;
#else
	float reactive = 0.0f;
#endif
	imageStore(reactive_mask_output, screen_pos, vec4(reactive, 0.0f, 0.0f, 0.0f));
}
