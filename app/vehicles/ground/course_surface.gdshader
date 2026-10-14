// Display texture only. Terrain displacement and contact normals come from Course.sample.
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.18, 0.19, 0.2, 1.0);
uniform float surface_roughness = 0.9;
uniform bool grass = false;
uniform bool survey_grid = false;
uniform sampler2D turf_data : filter_linear_mipmap, repeat_enable;
varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float tone = 1.0;
    if (grass) {
        // Reuse the repository's L9e turf data, channel B = centred tone multiplier.
        tone = mix(0.75, 1.25, texture(turf_data, world_position.xz / 2.0).b);
    }
    if (survey_grid) {
        vec2 grid_uv = world_position.xz * 2.0;
        vec2 width = max(fwidth(grid_uv), vec2(0.0001));
        vec2 d = abs(fract(grid_uv + 0.5) - 0.5) / width;
        float line = 1.0 - clamp(min(d.x, d.y), 0.0, 1.0);
        float fade = 1.0 - smoothstep(0.1, 0.5, max(width.x, width.y));
        tone += line * fade * 0.22;
    }
    // Painted elevation cue makes the small ramps legible at RC eye height.
    // It follows the sampled mesh exactly and never displaces the surface.
    float raised = survey_grid ? smoothstep(0.008, 0.035, world_position.y) : 0.0;
    vec3 surface_color = mix(base_color.rgb, vec3(0.34, 0.25, 0.12), raised * 0.7);
    ALBEDO = surface_color * tone;
    ROUGHNESS = surface_roughness;
}
