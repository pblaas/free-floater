shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled;

uniform vec4 rim_color : source_color = vec4(0.55, 0.07, 0.1, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.14;
uniform float pulse_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float rim = smoothstep(0.5, 1.0, r);
	ALBEDO = rim_color.rgb;
	ALPHA = clamp(rim * (base_alpha + pulse_alpha * pulse), 0.0, 1.0);
}
