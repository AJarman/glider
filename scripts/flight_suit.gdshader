shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Paints a flight suit over the bare base character. COLOR holds the rest-pose
// position (T-pose, metres), so the cut lines stay put while the body animates.

uniform sampler2D skin_tex : source_color;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D rough_tex : hint_default_white;
uniform vec3 suit : source_color = vec3(0.1, 0.45, 0.85);
uniform vec3 trim : source_color = vec3(1.0, 0.8, 0.15);
uniform float neck_y = 1.48;
uniform float wrist_x = 0.68;

void fragment() {
	vec3 p = vec3(COLOR.r * 2.0 - 1.0, COLOR.g * 2.0, COLOR.b * 2.0 - 1.0);
	float side = abs(p.x);
	// The shoulders rise above the collar, so only the neck and head stay bare.
	float covered = max(step(p.y, neck_y), step(0.11, side) * step(p.y, neck_y + 0.07));
	float glove = step(wrist_x, side) * step(0.4, p.y);
	float boot = step(p.y, 0.3);
	float collar = step(neck_y - 0.04, p.y) * step(p.y, neck_y) * step(side, 0.13);
	float chest = step(1.22, p.y) * step(p.y, 1.27) * step(side, 0.27);
	float belt = step(0.93, p.y) * step(p.y, 0.98) * step(side, 0.3);
	float accent = clamp(glove + boot + collar + chest + belt, 0.0, 1.0);

	vec3 skin = texture(skin_tex, UV).rgb;
	vec3 cloth = mix(suit, trim, accent) * (0.8 + 0.3 * dot(skin, vec3(0.333)));
	float rough = texture(rough_tex, UV).r;
	ALBEDO = mix(skin, cloth, covered);
	ROUGHNESS = mix(rough, 0.45, covered);
	SPECULAR = mix(0.4, 0.6, covered);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
