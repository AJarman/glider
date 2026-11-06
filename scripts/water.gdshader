shader_type spatial;
render_mode blend_mix, cull_disabled;
// Open sea: rolling Gerstner swells in the mesh, scrolling noise for chop, and
// foam on crests, around anything in the water and on passing ripples.

const int WAVE_COUNT = 6;
// Direction x, z, wavelength (m), height (m).
const vec4 WAVES[WAVE_COUNT] = vec4[WAVE_COUNT](
	vec4(0.80, 0.60, 74.0, 0.26),
	vec4(0.34, 0.94, 47.0, 0.18),
	vec4(-0.62, 0.78, 29.0, 0.12),
	vec4(0.96, -0.28, 17.0, 0.07),
	vec4(-0.20, -0.98, 10.0, 0.04),
	vec4(0.55, -0.83, 6.0, 0.025)
);
const float SWELL_MAX = 0.725;
const int RIPPLES = 24;

uniform vec4 ripples[RIPPLES]; // x, z, birth time, strength
uniform float sim_time = 0.0;
uniform float storm = 0.0;
uniform vec3 deep : source_color = vec3(0.01, 0.13, 0.3);
uniform vec3 mid : source_color = vec3(0.03, 0.32, 0.5);
uniform vec3 shallow : source_color = vec3(0.15, 0.68, 0.68);
uniform sampler2D chop : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;

varying vec2 base;
varying float swell;

// Height and slope of the swell at p, with the crests sharpened.
vec3 swell_at(vec2 p, float time) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		vec4 w = WAVES[i];
		float k = TAU / w.z;
		float phase = k * dot(w.xy, p) + sqrt(9.8 * k) * time + float(i) * 1.7;
		float crest = sin(phase) * 0.5 + 0.5;
		sum.x += w.w * (crest * crest * 2.0 - 1.0);
		sum.yz += w.xy * w.w * k * 2.0 * crest * cos(phase);
	}
	return sum;
}

// Height, slope and foam of the rings spreading from disturbances.
vec4 ripples_at(vec2 p) {
	vec4 sum = vec4(0.0);
	for (int i = 0; i < RIPPLES; i++) {
		vec4 r = ripples[i];
		float age = sim_time - r.z;
		if (r.w <= 0.0 || age > 2.4) {
			continue;
		}
		vec2 to = p - r.xy;
		float d = length(to) + 0.001;
		float front = d - 9.0 * age - 0.5;
		float env = exp(-front * front / 10.0 - age * 1.4) * r.w;
		sum.x += sin(front * 1.8) * env;
		sum.yz += to / d * cos(front * 1.8) * env;
		sum.w += max(sin(front * 1.8), 0.0) * env;
	}
	return sum;
}

void vertex() {
	base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float far = distance(base, CAMERA_POSITION_WORLD.xz);
	vec3 s = swell_at(base, TIME);
	swell = s.x / SWELL_MAX;
	VERTEX.y += s.x * (1.0 + storm * 0.25) * (1.0 - smoothstep(900.0, 2400.0, far));
	VERTEX.xz -= s.yz * 0.35;
	VERTEX.y += ripples_at(base).x * 0.28;
}

void fragment() {
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(120.0, 700.0, dist);
	vec2 p = base;

	// Slow patches of rougher and calmer water, like gusts crossing the sea.
	float gust = texture(chop, p / 620.0 + TIME * vec2(0.002, 0.0013)).r;
	float rough = mix(0.45, 1.35, smoothstep(0.42, 0.58, gust)) + storm;

	vec3 s = swell_at(p, TIME);
	vec2 a = texture(chop, p / 41.0 + TIME * vec2(0.012, 0.007)).rg * 2.0 - 1.0;
	vec2 b = texture(chop, p / 17.0 - TIME * vec2(0.021, 0.016)).rg * 2.0 - 1.0;
	vec2 c = texture(chop, p / 6.3 + TIME * vec2(-0.03, 0.044)).rg * 2.0 - 1.0;
	vec2 d = texture(chop, p / 2.3 + TIME * vec2(0.06, -0.05)).rg * 2.0 - 1.0;
	float close = 1.0 - smoothstep(25.0, 110.0, dist);
	vec2 slope = s.yz + (a * 0.12 + (b * 0.17 + c * 0.17) * near + d * 0.14 * close) * rough;
	vec4 ring = ripples_at(p);
	slope += ring.yz;

	NORMAL = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz) * (FRONT_FACING ? 1.0 : -1.0);

	// Distance from the surface to whatever is behind it, for the shoreline.
	float behind = 1000.0;
	if (FRONT_FACING) {
		float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		depth = depth * 2.0 - 1.0;
#endif
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		behind = max(-view.z / view.w + VERTEX.z, 0.0);
	}
	float shore = exp(-behind * 0.5);
	float surf = exp(-behind * 1.8);

	float height = clamp(swell * 0.5 + 0.5, 0.0, 1.0);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	vec3 water = mix(deep, mid, smoothstep(0.1, 0.9, height + (gust - 0.5) * 1.2));
	water = mix(water, shallow, clamp(smoothstep(0.62, 1.0, height) * 0.45 + shore * 0.8, 0.0, 1.0));
	water = mix(water, vec3(0.1, 0.16, 0.22), storm * 0.55);

	// Crests whiten where the sea is rough; a broken band hugs the shoreline.
	float grain = texture(chop, p / 8.0 + TIME * vec2(0.01, -0.02)).b * 0.5
		+ texture(chop, p / 2.7 - TIME * vec2(0.03, 0.01)).r * 0.5;
	float lace = texture(chop, p / 1.9 + TIME * vec2(0.05, 0.04)).g;
	float cap = smoothstep(0.84 - storm * 0.14, 0.92 - storm * 0.14, height) * smoothstep(0.5, 0.58, grain);
	cap *= max(smoothstep(0.48, 0.62, gust), storm) * smoothstep(0.46, 0.56, lace);
	float edge = smoothstep(0.5, 0.7, surf + (grain - 0.5) * 0.8 + sin(TIME * 0.9 + p.x * 0.07 + p.y * 0.05) * 0.12);
	float foam = clamp(cap * near + edge + ring.w, 0.0, 1.0);

	ALBEDO = mix(water, vec3(0.92, 0.97, 1.0), foam * 0.85);
	ROUGHNESS = mix(mix(0.2, 0.05, near), 0.7, foam);
	SPECULAR = 0.6;
	ALPHA = clamp(mix(mix(0.62, 0.92, fresnel) - shore * 0.3, 0.97, foam), 0.0, 1.0);
}
