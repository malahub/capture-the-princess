// Silhouette for a unit hidden behind a wall, tree or hill.
// Drawn without depth testing so it reads through the structure, but the
// alpha is driven by a fresnel term so it appears as a glowing outline with a
// faint body rather than a solid slab.
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.22, 1.0);
uniform float body_alpha = 0.26;
uniform float edge_alpha = 1.0;

void fragment() {
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = smoothstep(0.30, 0.88, rim);
	ALBEDO = tint.rgb * (0.65 + 0.75 * edge);
	ALPHA = mix(body_alpha, edge_alpha, edge);
}
