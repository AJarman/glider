shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// A unit cylinder bent into a trumpet of churning cloud. Height runs 0 at the sea
// to 1 at the top, and the whole column snakes about as it spins.

uniform sampler2D churn : repeat_enable, filter_linear_mipmap;
uniform float height = 170.0;
uniform float neck = 6.0;
uniform float mouth = 80.0;
uniform float spin = 0.5;
uniform vec3 dark : source_color = vec3(0.1, 0.11, 0.15);
uniform vec3 light : source_color = vec3(0.5, 0.5, 0.56);

varying float level;

void vertex() {
	level = VERTEX.y + 0.5;
	float radius = mix(neck, mouth, pow(level, 2.4));
	vec2 snake = vec2(sin(level * 5.0 + TIME * 0.9), cos(level * 3.7 + TIME * 0.7)) * 10.0 * sin(level * 3.14);
	VERTEX = vec3(VERTEX.x * 2.0 * radius + snake.x, level * height, VERTEX.z * 2.0 * radius + snake.y);
}

void fragment() {
	vec2 uv = UV * vec2(4.0, 1.5) + vec2(TIME * spin + UV.y * 2.5, -TIME * 0.2);
	float n = texture(churn, uv).r;
	float n2 = texture(churn, uv * 2.3 + vec2(TIME * spin, 0.0)).r;
	float cloud = clamp(n * 0.7 + n2 * 0.5, 0.0, 1.0);
	ALBEDO = mix(dark, light, smoothstep(0.3, 0.75, cloud));
	float ends = smoothstep(0.0, 0.05, level) * (1.0 - smoothstep(0.82, 1.0, level));
	ALPHA = smoothstep(0.25, 0.6, cloud) * 0.92 * ends;
}
