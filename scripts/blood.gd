extends Node3D
## Blood from hard crashes: a burst of droplets and decals that stay on the
## scenery until the next game. Only world geometry (layer 1) receives them.

const MAX_SPLATS := 150
const COLOR := Color(0.5, 0.02, 0.03, 0.95)

var _textures: Array[ImageTexture] = []
var _splats: Array[Node3D] = []


func _ready() -> void:
	for i in 3:
		_textures.append(_make_texture(i))


## A lumpy blob with droplets flung around it, cut from noise.
func _make_texture(seed_value: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value + 7
	noise.frequency = 0.045
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var specks := FastNoiseLite.new()
	specks.seed = seed_value + 31
	specks.frequency = 0.22
	for y in size:
		for x in size:
			var p := (Vector2(x, y) - Vector2.ONE * size * 0.5) / (size * 0.5)
			var r := p.length()
			var blob := 1.0 - r * 1.7 + noise.get_noise_2d(x, y) * 1.1
			var speck := specks.get_noise_2d(x, y) - 0.42 - r * 0.25
			var a := clampf(maxf(blob, speck * 6.0) * 6.0, 0.0, 1.0)
			a *= 1.0 - smoothstep(0.85, 1.0, r)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func splat(pos: Vector3, normal: Vector3, along: Vector3, length: float, width: float) -> void:
	var x := along - normal * along.dot(normal)
	if x.length() < 0.01:
		x = normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD)
	x = x.normalized()
	var mark := Transform3D(Basis(x, normal, x.cross(normal)), pos + normal * 0.12)
	var d: Node3D = _flat_splat(length, width) if RenderingServer.get_current_rendering_method() == "gl_compatibility" else _decal(length, width)
	add_child(d)
	d.global_transform = mark
	_splats.append(d)
	if _splats.size() > MAX_SPLATS:
		_splats.pop_front().queue_free()


## The Compatibility renderer has no decals, so the web build lays down a quad.
func _flat_splat(length: float, width: float) -> MeshInstance3D:
	var quad := PlaneMesh.new()
	quad.size = Vector2(length, width)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _textures[randi() % _textures.size()]
	mat.albedo_color = COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 1
	mat.no_depth_test = false
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _decal(length: float, width: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = _textures[randi() % _textures.size()]
	d.modulate = COLOR
	d.size = Vector3(length, 1.2, width)
	d.normal_fade = 0.4
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1
	return d


## The impact itself: a big smear along the skid, spatter thrown ahead of it.
func crash(pos: Vector3, normal: Vector3, vel: Vector3, severity: float) -> void:
	var dir := vel.normalized()
	var big := lerpf(2.5, 6.0, severity)
	splat(pos, normal, vel, big * 1.6, big)
	var ahead := dir - normal * dir.dot(normal)
	for i in 6 + int(severity * 10.0):
		var offset := ahead * randf_range(1.0, big * 2.2) + normal.cross(ahead) * randf_range(-1.0, 1.0) * big * 0.6
		var s := randf_range(0.3, 1.1)
		splat(pos + offset, normal, vel, s * 1.8, s)
	_burst(pos, normal, dir, severity)


## A wound in mid-air: a jet out of the impact point. It's parented to the flier
## so the spray stays in shot, not left behind at flight speed.
func spurt(flier: Node3D, at: Vector3, out: Vector3, severity: float) -> void:
	var p := _spray(at, out, severity)
	p.reparent(flier)
	p.local_coords = true
	p.spread = 28.0
	p.gravity = Vector3(0, -6, 0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0 + severity * 8.0
	p.emitting = true


func _burst(pos: Vector3, normal: Vector3, dir: Vector3, severity: float) -> void:
	_spray(pos + normal * 0.2, (normal + dir * 0.7).normalized(), severity).emitting = true


func _spray(pos: Vector3, direction: Vector3, severity: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 50 + int(severity * 70.0)
	p.lifetime = 1.1
	p.explosiveness = 0.95
	p.direction = direction
	p.spread = 45.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0 + severity * 8.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.02, 0.03)
	mat.roughness = 0.25
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	return p


func clear() -> void:
	for d in _splats:
		d.queue_free()
	_splats.clear()
