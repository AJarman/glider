shader_type canvas_item;
// Smears the 3D view along the lines radiating from the point being flown
// towards, so the world streaks past while the flier at the centre stays sharp.

const int SAMPLES = 14;

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform vec2 focus = vec2(0.5);
uniform float amount = 0.0;

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float keep = smoothstep(0.07, 0.24, length((SCREEN_UV - 0.5) * aspect));
	vec2 stride = (focus - SCREEN_UV) * amount * keep / float(SAMPLES);
	// Per-pixel noise hides the banding of so few samples.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	vec3 sum = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		sum += texture(screen, SCREEN_UV + stride * (float(i) + jitter)).rgb;
	}
	COLOR = vec4(sum / float(SAMPLES), 1.0);
}
