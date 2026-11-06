shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
// Inverted hull: the anime ink line around the flier.

uniform float width = 0.011;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = vec3(0.05, 0.03, 0.07);
}
