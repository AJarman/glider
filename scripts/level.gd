extends Node3D
## Builds the launch ramp, the sea, the target field and the islands.

const TargetScript := preload("res://scripts/target.gd")

const LIP := Vector3(0, 55, 0)
## Length of each slice of the ramp's centreline.
const SEG := 2.6
const RAMP_WIDTH := 8.0
const RAIL_H := 1.2
const TARGET_TOP := 2.5
const RIPPLES := 24
const WATER_REACH := 3500.0
## The tiny far-off jackpot target.
const PINPRICK_AT := Vector3(30, 0, -760)

var ramp_body: StaticBody3D
var ramp_pts := PackedVector3Array()
var start_position := Vector3.ZERO
var targets: Array = []
var _water: MeshInstance3D
var _petals: CPUParticles3D
var _water_mat: ShaderMaterial
var _ripples := PackedVector4Array()
var _ripple_next := 0
var _sim_time := 0.0


func _ready() -> void:
	_build_water()
	_build_ramp()
	_build_targets()
	_build_scenery()
	_build_landmarks()


func _build_water() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var chop := NoiseTexture2D.new()
	chop.width = 512
	chop.height = 512
	chop.seamless = true
	chop.as_normal_map = true
	chop.bump_strength = 6.0
	chop.noise = noise
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = preload("res://scripts/water.gdshader")
	_water_mat.set_shader_parameter("chop", chop)
	_ripples.resize(RIPPLES)
	_water = MeshInstance3D.new()
	_water.mesh = _water_mesh()
	_water.custom_aabb = AABB(Vector3(-WATER_REACH, -4, -WATER_REACH), Vector3(WATER_REACH * 2.0, 8, WATER_REACH * 2.0))
	_water.material_override = _water_mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.layers = 2  # Keeps blood decals off the sea.
	add_child(_water)


## A grid that's dense at the middle and stretches out to the horizon. It
## follows the camera, so the detail is always where it's being looked at.
func _water_mesh() -> ArrayMesh:
	var cells := 280
	var coords := PackedFloat32Array()
	for i in cells + 1:
		var u := float(i) / cells * 2.0 - 1.0
		coords.append(signf(u) * (absf(u) * 0.04 + pow(absf(u), 3.0) * 0.96) * WATER_REACH)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in cells + 1:
		for x in cells + 1:
			verts.append(Vector3(coords[x], 0, coords[z]))
			normals.append(Vector3.UP)
	for z in cells:
		for x in cells:
			var i := z * (cells + 1) + x
			indices.append_array([i, i + 1, i + cells + 1, i + 1, i + cells + 2, i + cells + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	_sim_time += delta
	_water_mat.set_shader_parameter("sim_time", _sim_time)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var c := cam.global_position.snappedf(16.0)
		_water.position = Vector3(c.x, 0, c.z)
		_petals.global_position = cam.global_position


func set_storm(amount: float) -> void:
	_water_mat.set_shader_parameter("storm", amount)


func add_ripple(at: Vector3, strength: float) -> void:
	_ripples[_ripple_next] = Vector4(at.x, at.z, _sim_time, strength)
	_ripple_next = (_ripple_next + 1) % RIPPLES
	_water_mat.set_shader_parameter("ripples", _ripples)


func _build_ramp() -> void:
	# Integrate a curved centreline: a flat start that eases over into a steep
	# drop, flattening out, then a steep kicker that throws the flier up.
	# Forward is -Z.
	var pts := PackedVector3Array()
	var p := Vector3.ZERO
	pts.append(p)
	var n := 90
	for i in n:
		var t := float(i) / float(n - 1)
		var ang: float
		if t < 0.12:
			ang = lerpf(0.0, -8.0, smoothstep(0.0, 0.12, t))  # Flat start, easing over.
		elif t < 0.3:
			ang = lerpf(-8.0, -55.0, smoothstep(0.12, 0.3, t))
		elif t < 0.8:
			ang = lerpf(-55.0, -5.0, smoothstep(0.3, 0.8, t))
		else:
			ang = lerpf(-5.0, 45.0, smoothstep(0.82, 1.0, t))  # A steep kicker.
		var r := deg_to_rad(ang)
		p += Vector3(0, sin(r), -cos(r)) * SEG
		pts.append(p)
	var off := LIP - pts[pts.size() - 1]
	for i in pts.size():
		pts[i] += off
	ramp_pts = pts

	ramp_body = StaticBody3D.new()
	add_child(ramp_body)
	var hw := RAMP_WIDTH * 0.5
	_build_deck(hw)
	_build_girder(hw)
	_build_railings(hw)
	_build_supports(hw)
	_build_start_deck()

	# Thick box per segment so a fast body can't tunnel through the deck.
	for i in pts.size() - 1:
		var a := pts[i]
		var c := pts[i + 1]
		var f := (c - a).normalized()
		var nrm := Vector3.RIGHT.cross(f).normalized()
		var basis := Basis.looking_at(f, nrm)
		var seg_len := a.distance_to(c) + 0.15
		var mid := (a + c) * 0.5
		_box_shape(Vector3(RAMP_WIDTH + 1.0, 2.0, seg_len), Transform3D(basis, mid - nrm * 1.0))
		for sx in [-1.0, 1.0]:
			_box_shape(Vector3(0.4, RAIL_H * 2.0, seg_len), Transform3D(basis, mid + Vector3(sx * (hw + 0.2), 0, 0)))

	var f0 := (pts[2] - pts[1]).normalized()
	start_position = pts[1] + Vector3.RIGHT.cross(f0).normalized() * 0.5


func _segment_normal(i: int) -> Vector3:
	return Vector3.RIGHT.cross((ramp_pts[i + 1] - ramp_pts[i]).normalized()).normalized()


## Plank deck, with racing kerbs down both edges and a painted launch zone.
func _build_deck(hw: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := 0.45
	var edges := [-hw, -hw + kerb, hw - kerb, hw]
	var count := ramp_pts.size() - 1
	var dist := 0.0
	for i in count:
		var a := ramp_pts[i]
		var b := ramp_pts[i + 1]
		var nrm := _segment_normal(i)
		var len := a.distance_to(b)
		var launch := i >= count - 4
		for k in 3:
			var col := Color.WHITE
			if k != 1:
				col = Color(0.9, 0.12, 0.1) if i % 2 == 0 else Color(0.97, 0.97, 0.97)
			elif launch:
				col = Color(1.0, 0.8, 0.15)
			var x0: float = edges[k]
			var x1: float = edges[k + 1]
			_quad_uv(st, a + Vector3(x0, 0, 0), b + Vector3(x0, 0, 0), b + Vector3(x1, 0, 0), a + Vector3(x1, 0, 0), nrm, col,
				Rect2(x0 / 4.0, dist / 4.0, (x1 - x0) / 4.0, len / 4.0))
		dist += len
	st.generate_tangents()
	var mat := _textured("plank_flooring_02")
	mat.vertex_color_use_as_albedo = true
	_ramp_mesh(st, mat)


func _build_girder(hw: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth := 0.7
	var L := Vector3(-hw - 0.1, 0, 0)
	var R := Vector3(hw + 0.1, 0, 0)
	var col := Color(0.62, 0.66, 0.72)
	var dist := 0.0
	for i in ramp_pts.size() - 1:
		var a := ramp_pts[i]
		var b := ramp_pts[i + 1]
		var nrm := _segment_normal(i)
		var len := a.distance_to(b)
		var uv := Rect2(0, dist / 3.0, 1.0, len / 3.0)
		var drop := nrm * depth
		_quad_uv(st, a + L - drop, b + L - drop, b + R - drop, a + R - drop, -nrm, col, Rect2(0, dist / 3.0, 3.0, len / 3.0))
		_quad_uv(st, a + L, b + L, b + L - drop, a + L - drop, Vector3.LEFT, col, uv)
		_quad_uv(st, a + R, b + R, b + R - drop, a + R - drop, Vector3.RIGHT, col, uv)
		dist += len
	st.generate_tangents()
	var mat := _textured("metal_plate")
	mat.vertex_color_use_as_albedo = true
	_ramp_mesh(st, mat)


## Glass panels between steel posts, under a continuous top rail.
func _build_railings(hw: float) -> void:
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.85, 0.88, 0.92)
	var up := Vector3.UP * RAIL_H
	var t := 0.07
	for i in ramp_pts.size() - 1:
		var a := ramp_pts[i]
		var b := ramp_pts[i + 1]
		for sx in [-1.0, 1.0]:
			var o := Vector3(sx * (hw + 0.02), 0, 0)
			_quad_uv(glass, a + o, b + o, b + o + up, a + o + up, Vector3.RIGHT * -sx, Color.WHITE, Rect2(0, 0, 1, 1))
			# Top rail: a square tube along the panels.
			var top := o + up
			var side := Vector3(t, 0, 0)
			var rise := Vector3(0, t, 0)
			var uv := Rect2(0, 0, 0.1, 0.5)
			_quad_uv(steel, a + top - side + rise, b + top - side + rise, b + top + side + rise, a + top + side + rise, Vector3.UP, col, uv)
			_quad_uv(steel, a + top - side - rise, b + top - side - rise, b + top - side + rise, a + top - side + rise, Vector3.LEFT, col, uv)
			_quad_uv(steel, a + top + side - rise, b + top + side - rise, b + top + side + rise, a + top + side + rise, Vector3.RIGHT, col, uv)
			_quad_uv(steel, a + top - side - rise, b + top - side - rise, b + top + side - rise, a + top + side - rise, Vector3.DOWN, col, uv)
			if i % 3 == 0:
				_box_verts(steel, a + o + up * 0.5, Vector3(t * 1.4, RAIL_H, t * 1.4), col)
	var steel_mat := _textured("metal_plate")
	steel_mat.vertex_color_use_as_albedo = true
	steel.generate_tangents()
	_ramp_mesh(steel, steel_mat)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.22)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.05
	glass_mat.metallic_specular = 0.8
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := _ramp_mesh(glass, glass_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Steel bents: paired columns on concrete footings, cross-braced and tied
## together along the ramp.
func _build_supports(hw: float) -> void:
	var steel := _textured("metal_plate")
	steel.albedo_color = Color(0.55, 0.6, 0.68)
	steel.metallic = 0.6
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.68, 0.67, 0.63)
	concrete.roughness = 0.9
	var x := hw - 0.8
	var prev_tops: Array = []
	for i in range(4, ramp_pts.size() - 2, 8):
		var top := ramp_pts[i] + Vector3.DOWN * 0.7
		if top.y < 2.0:
			continue
		var tops: Array = []
		for sx in [-1.0, 1.0]:
			var head := Vector3(sx * x, top.y, top.z)
			var foot := Vector3(sx * (x + top.y * 0.05), -4.0, top.z)
			_beam(foot, head, 0.34, steel)
			tops.append(head)
			var pad := CylinderMesh.new()
			pad.top_radius = 1.0
			pad.bottom_radius = 1.5
			pad.height = 5.0
			var pm := MeshInstance3D.new()
			pm.mesh = pad
			pm.material_override = concrete
			pm.position = Vector3(foot.x, -1.0, foot.z)
			add_child(pm)
		# X-brace each storey of the bent.
		var storeys := maxi(int(top.y / 9.0), 1)
		var left: Vector3 = tops[0]
		var right: Vector3 = tops[1]
		for s in storeys:
			var y0 := top.y * float(s) / storeys
			var y1 := top.y * float(s + 1) / storeys
			var l0 := Vector3(left.x, y0, top.z)
			var r0 := Vector3(right.x, y0, top.z)
			var l1 := Vector3(left.x, y1, top.z)
			var r1 := Vector3(right.x, y1, top.z)
			_beam(l0, r1, 0.14, steel)
			_beam(r0, l1, 0.14, steel)
			_beam(l1, r1, 0.2, steel)
		if prev_tops.size() == 2:
			for k in 2:
				_beam(prev_tops[k], tops[k], 0.2, steel)
		prev_tops = tops


## Level platform behind the start, so the top of the ramp isn't an open end.
func _build_start_deck() -> void:
	var length := 12.0
	var top := ramp_pts[0]
	var deck := BoxMesh.new()
	deck.size = Vector3(RAMP_WIDTH + 0.2, 0.7, length)
	var planks := _textured("plank_flooring_02")
	planks.uv1_scale = Vector3(3, 2, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = deck
	mi.material_override = planks
	mi.position = top + Vector3(0, -0.35, length * 0.5 + 0.1)
	add_child(mi)
	var steel := _textured("metal_plate")
	steel.albedo_color = Color(0.55, 0.6, 0.68)
	var x := RAMP_WIDTH * 0.5 - 0.8
	for sx in [-1.0, 1.0]:
		var head := Vector3(sx * x, top.y - 0.7, top.z + length - 1.0)
		_beam(Vector3(sx * (x + top.y * 0.05), -4.0, head.z), head, 0.34, steel)


func _beam(from: Vector3, to: Vector3, thick: float, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(thick, thick, from.distance_to(to))
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	add_child(mi)
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.BACK
	mi.global_transform = Transform3D(Basis.looking_at(to - from, up), (from + to) * 0.5)


func _ramp_mesh(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	ramp_body.add_child(mi)
	return mi


func _textured(tex: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/%s_diff.jpg" % tex)
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/%s_nor.jpg" % tex)
	mat.roughness_texture = load("res://assets/textures/%s_rough.jpg" % tex)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _box_shape(size: Vector3, xf: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	ramp_body.add_child(cs)


func _quad_uv(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color, uv: Rect2) -> void:
	var uvs := [uv.position, uv.position + Vector2(0, uv.size.y), uv.end, uv.position + Vector2(uv.size.x, 0)]
	var ps := [p0, p1, p2, p3]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_color(col)
		st.set_uv(uvs[k])
		st.add_vertex(ps[k])


func _box_verts(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var uv := Rect2(0, 0, 0.1, 0.3)
	for n: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var side := n.cross(Vector3.UP)
		var p0 := c + n * h + side * h - Vector3(0, h.y, 0)
		var p1 := c + n * h - side * h - Vector3(0, h.y, 0)
		_quad_uv(st, p0, p1, p1 + Vector3(0, size.y, 0), p0 + Vector3(0, size.y, 0), n, col, uv)


func _build_targets() -> void:
	var K := TargetScript.Kind
	var defs := [
		[Vector3(0, 0, -240), K.DISC, 20.0, [10, 20, 30, 50, 100], "THE BIG ONE"],
		[Vector3(-80, 0, -350), K.MOVER, 13.0, [20, 50, 80, 120, 200], "THE DRIFTER"],
		[Vector3(75, 0, -370), K.SPLITTER, 14.0, [30, 60, 100, 150, 250], "THE SPLITTER"],
		[Vector3(0, 0, -500), K.PYRAMID, 14.0, [50, 100, 200, 300, 500], "THE PYRAMID"],
		[Vector3(-140, 0, -210), K.DISC, 9.0, [30, 60, 100, 150, 250], "LEFT FLANK"],
		[Vector3(140, 0, -240), K.DISC, 9.0, [30, 60, 100, 150, 250], "RIGHT FLANK"],
		[PINPRICK_AT, K.PINPRICK, 2.5, [1000], "THE PINPRICK"],
	]
	for d in defs:
		var t := TargetScript.new()
		t.setup(d[1], d[2], d[3], d[4])
		t.position = d[0] + Vector3(0, TARGET_TOP, 0)
		add_child(t)
		targets.append(t)


func _build_scenery() -> void:
	var rng_s := RandomNumberGenerator.new()
	rng_s.seed = 20240611
	var spots := [
		Vector3(-240, 0, -400), Vector3(250, 0, -120), Vector3(-180, 0, 40),
		Vector3(190, 0, -600), Vector3(-90, 0, -700), Vector3(300, 0, -420),
	]
	var plants := {
		"Pine_1": [], "Pine_3": [], "CommonTree_1": [], "CommonTree_3": [],
		"Bush_Common": [], "Fern_1": [], "Grass_Common_Tall": [],
	}
	var rock_mat := _island_rock_material()
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.86, 0.78, 0.58)
	sand.roughness = 0.95
	for i in spots.size():
		var island := Node3D.new()
		island.position = spots[i]
		island.rotation.y = rng_s.randf() * TAU
		add_child(island)
		var main_scale := 11.0 + 3.0 * (i % 3)
		_add_beach(island, main_scale * 2.5, sand)
		_torii(island, Vector3(main_scale * 1.75, 0.5, 0), 0.9, PI / 2)
		var main := _add_rock(island, "Rock_Medium_%d" % (i % 3 + 1), Vector3(0, -main_scale * 0.25, 0), main_scale, rng_s.randf() * TAU, rock_mat)
		for k in 3:
			var ang := rng_s.randf() * TAU
			var pos := Vector3(cos(ang), 0, sin(ang)) * main_scale * rng_s.randf_range(1.5, 2.1)
			var s := main_scale * rng_s.randf_range(0.28, 0.45)
			_add_rock(island, "Rock_Medium_%d" % (k % 3 + 1), pos + Vector3(0, -s * 0.3, 0), s, rng_s.randf() * TAU, rock_mat)
		_scatter(main, plants, rng_s)
	for name in plants:
		_add_plants(name, plants[name])


func _add_beach(parent: Node3D, radius: float, mat: Material) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = radius * 0.72
	cone.bottom_radius = radius
	cone.height = 6.0
	cone.radial_segments = 64
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.position.y = -2.3
	parent.add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.8
	shape.height = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.position.y = -0.3
	body.add_child(cs)
	parent.add_child(body)


func _island_rock_material() -> StandardMaterial3D:
	# Triplanar, so the small rock texture stays fine on rocks scaled up to islands.
	var src: StandardMaterial3D = _nature_mesh("Rock_Medium_1").surface_get_material(0)
	var mat: StandardMaterial3D = src.duplicate()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.12
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return mat


func _add_rock(parent: Node3D, name: String, pos: Vector3, s: float, yaw: float, mat: Material) -> MeshInstance3D:
	var mesh := _nature_mesh(name)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * s
	parent.add_child(mi)
	# Collision shapes can't be scaled, so bake the scale into the faces.
	var body := StaticBody3D.new()
	parent.add_child(body)
	var faces := mesh.get_faces()
	for i in faces.size():
		faces[i] = mi.transform * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return mi


## Picks spots on the rock's upward faces for trees and undergrowth.
func _scatter(rock: MeshInstance3D, plants: Dictionary, rng_s: RandomNumberGenerator) -> void:
	var faces := rock.mesh.get_faces()
	var xf := rock.global_transform
	var tops: Array = []
	for i in range(0, faces.size(), 3):
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		var n := (b - a).cross(c - a).normalized()
		if absf(n.y) > 0.7 and (a + b + c).y / 3.0 > 3.0:
			tops.append([a, b, c])
	if tops.is_empty():
		return
	var names: Array = plants.keys()
	for i in 34:
		var name: String = names[0 if i < 3 else 1 if i < 5 else 2 if i < 7 else 3 if i < 8 else 4 + i % 3]
		var tri: Array = tops[rng_s.randi_range(0, tops.size() - 1)]
		var u := sqrt(rng_s.randf())
		var v := rng_s.randf()
		var p: Vector3 = tri[0] * (1.0 - u) + tri[1] * (u * (1.0 - v)) + tri[2] * (u * v)
		var s := rng_s.randf_range(1.4, 2.2) if i < 8 else rng_s.randf_range(1.5, 2.8)
		plants[name].append(Transform3D(Basis(Vector3.UP, rng_s.randf() * TAU).scaled(Vector3.ONE * s), p + Vector3.DOWN * 0.2))


func _add_plants(name: String, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _sakura(_nature_mesh(name)) if name.begins_with("CommonTree") else _nature_mesh(name)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)


## Blossom-pink copy of a tree, keeping the shape of its leaf cards.
func _sakura(mesh: Mesh) -> Mesh:
	var src: StandardMaterial3D = mesh.surface_get_material(1)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_toon;
uniform sampler2D leaves : source_color, filter_linear_mipmap;
void fragment() {
	vec4 t = texture(leaves, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = vec3(1.0, 0.62, 0.74) * (0.65 + 0.9 * dot(t.rgb, vec3(0.333)));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("leaves", src.albedo_texture)
	var copy: Mesh = mesh.duplicate()
	copy.surface_set_material(1, mat)
	return copy


func _build_landmarks() -> void:
	# Gates over the ramp: one to start, one at the launch.
	var last := ramp_pts.size() - 1
	_torii(self, ramp_pts[5], 1.75, 0.0)
	_torii(self, ramp_pts[last - 3], 1.75, 0.0)

	# Paper lanterns along the rails.
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(1.0, 0.25, 0.12)
	paper.emission_enabled = true
	paper.emission = Color(1.0, 0.35, 0.1)
	paper.emission_energy_multiplier = 1.4
	var lamp := SphereMesh.new()
	lamp.radius = 0.28
	lamp.height = 0.7
	lamp.radial_segments = 12
	lamp.rings = 6
	for i in range(3, ramp_pts.size() - 1, 9):
		for sx in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = lamp
			mi.material_override = paper
			mi.position = ramp_pts[i] + Vector3(sx * (RAMP_WIDTH * 0.5 + 0.02), RAIL_H + 0.45, 0)
			add_child(mi)

	# A snow-capped volcano on the horizon.
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.34, 0.42, 0.62)
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.97, 0.97, 1.0)
	var cap_height := 150.0
	var height := 620.0
	var top := 60.0
	var base := 1500.0
	var cap_base := lerpf(top, base, cap_height / height)
	for part in [[height - cap_height, top + (base - top) * cap_height / height, base, rock, (height - cap_height) * 0.5],
			[cap_height, top, cap_base, snow, height - cap_height * 0.5]]:
		var cone := CylinderMesh.new()
		cone.height = part[0]
		cone.top_radius = part[1]
		cone.bottom_radius = part[2]
		cone.radial_segments = 48
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = part[3]
		mi.position = Vector3(180, part[4] - 5.0, -3000)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# Cherry blossom drifting past the camera.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.12)
	var petal := StandardMaterial3D.new()
	petal.albedo_color = Color(1.0, 0.72, 0.82)
	petal.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	petal.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = petal
	_petals = CPUParticles3D.new()
	_petals.amount = 90
	_petals.lifetime = 6.0
	_petals.preprocess = 6.0
	_petals.local_coords = false
	_petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_petals.emission_box_extents = Vector3(28, 14, 28)
	_petals.direction = Vector3(0.6, -1, 0.2)
	_petals.spread = 25.0
	_petals.initial_velocity_min = 0.8
	_petals.initial_velocity_max = 2.2
	_petals.gravity = Vector3.ZERO
	_petals.angular_velocity_min = -200.0
	_petals.angular_velocity_max = 200.0
	_petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_petals.mesh = quad
	add_child(_petals)


func _torii(parent: Node3D, pos: Vector3, s: float, yaw: float) -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.86, 0.1, 0.08)
	red.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.07, 0.06, 0.08)
	var gate := Node3D.new()
	gate.position = pos
	gate.rotation.y = yaw
	gate.scale = Vector3.ONE * s
	parent.add_child(gate)
	var post := CylinderMesh.new()
	post.top_radius = 0.2
	post.bottom_radius = 0.27
	post.height = 6.0
	for sx in [-1.0, 1.0]:
		_gate_part(gate, post, red, Vector3(sx * 2.45, 3.0, 0))
	_gate_part(gate, _gate_bar(Vector3(5.9, 0.28, 0.26)), red, Vector3(0, 4.8, 0))
	_gate_part(gate, _gate_bar(Vector3(7.0, 0.38, 0.5)), red, Vector3(0, 5.75, 0))
	_gate_part(gate, _gate_bar(Vector3(7.5, 0.22, 0.6)), black, Vector3(0, 6.05, 0))
	_gate_part(gate, _gate_bar(Vector3(0.3, 0.9, 0.18)), black, Vector3(0, 5.25, 0))


func _gate_bar(size: Vector3) -> BoxMesh:
	var bar := BoxMesh.new()
	bar.size = size
	return bar


func _gate_part(gate: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	gate.add_child(mi)


func _nature_mesh(name: String) -> Mesh:
	var scene: Node = load("res://assets/nature/%s.gltf" % name).instantiate()
	var mesh: Mesh = (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	scene.free()
	return mesh
