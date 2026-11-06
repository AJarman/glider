extends Node3D
## Rigged flier in a flight suit, with procedural poses and pop-out wings. Plain
## joint nodes hold the pose and the model's skeleton follows them, so a ragdoll
## can drive the same bones. Local origin is the hip; forward is -Z.

const SUIT_SHADER := preload("res://scripts/flight_suit.gdshader")
const OUTLINE_SHADER := preload("res://scripts/outline.gdshader")
const WING := Color(0.93, 0.94, 0.97)
const WING_TRIM := Color(0.2, 0.25, 0.3)
const WING_TIP := Color(0.9, 0.15, 0.15)

const WING_FOLD_Z := 1.45
const MODEL_SCALE := 0.88
## Joint name -> skeleton bone, parents first.
const BONES := {
	"spine": "spine_01", "neck": "neck_01",
	"sh_l": "upperarm_l", "el_l": "lowerarm_l", "sh_r": "upperarm_r", "el_r": "lowerarm_r",
	"hip_l": "thigh_l", "kn_l": "calf_l", "hip_r": "thigh_r", "kn_r": "calf_r",
}
const JOINT_PARENTS := {"neck": "spine", "sh_l": "spine", "sh_r": "spine", "el_l": "sh_l", "el_r": "sh_r", "kn_l": "hip_l", "kn_r": "hip_r"}
const CHAR_DIR := "res://assets/characters/"
const LOOKS := [
	{"name": "Nova", "base": "Female", "skin": "T_Superhero_Female_Light_BaseColor.png", "hair": "Hair_Long",
		"hair_color": Color(1.0, 0.75, 0.45), "suit": Color(0.1, 0.45, 0.85), "trim": Color(1.0, 0.8, 0.15)},
	{"name": "Dash", "base": "Male", "skin": "T_Superhero_Male_Dark.png", "hair": "Hair_Buzzed",
		"hair_color": Color(0.35, 0.28, 0.25), "suit": Color(0.85, 0.2, 0.15), "trim": Color(0.95, 0.95, 0.97)},
	{"name": "Sol", "base": "Female", "skin": "T_Superhero_Female_Dark_BaseColor.png", "hair": "Hair_Buns",
		"hair_color": Color(0.45, 0.3, 0.25), "suit": Color(0.1, 0.65, 0.5), "trim": Color(1.0, 0.45, 0.2)},
	{"name": "Finn", "base": "Male", "skin": "T_Superhero_Male_Ligh.png", "hair": "Hair_SimpleParted",
		"hair_color": Color(0.8, 0.5, 0.25), "suit": Color(0.45, 0.2, 0.7), "trim": Color(0.3, 0.95, 0.75)},
]

var joints := {}
## Bodies that drive the bones instead of the joints, while ragdolling.
var follow := {}
var look := 0
var poses := {}
var pose := "stand"
var height := 0.42
## Stride speed in radians per second while the "run" pose is active.
var run_rate := 8.0
var wing_l: Node3D
var wing_r: Node3D
var wings_open := false
var _wing_tween: Tween
var _run_phase := 0.0
var _model: Node3D
var _skeleton: Skeleton3D
var _bone_ids := {}
## Joint frame -> bone frame, so an unposed joint means arms at the sides.
var _bone_offsets := {}
var _pelvis_bone := -1
## Spine bone frame -> pelvis, which has to travel with a ragdoll's torso.
var _pelvis_offset := Transform3D.IDENTITY


func _ready() -> void:
	for n in BONES:
		var j := Node3D.new()
		j.name = n
		joints[n] = j
	for n in BONES:
		(joints[JOINT_PARENTS[n]] if JOINT_PARENTS.has(n) else self).add_child(joints[n])
	_build_poses()
	set_look(look)


func _process(delta: float) -> void:
	if pose == "run":
		_update_run(delta)
	var p: Dictionary = poses[pose]
	# Strides are too quick for the usual pose smoothing to keep up with.
	var k := 1.0 - exp((-90.0 if pose == "run" else -12.0) * delta)
	for name in joints:
		var j: Node3D = joints[name]
		var target: Vector3 = p.get(name, Vector3.ZERO)
		j.rotation = j.rotation.lerp(target, k)
	height = lerpf(height, p.get("height", 0.42), k)
	_sync_bones()


func _update_run(delta: float) -> void:
	_run_phase = fmod(_run_phase + run_rate * delta, TAU)
	var s := sin(_run_phase)
	var c := cos(_run_phase)
	var p: Dictionary = poses["run"]
	p["hip_l"] = Vector3(0.25 + 0.95 * s, 0, -0.05)
	p["hip_r"] = Vector3(0.25 - 0.95 * s, 0, 0.05)
	# The knee folds while that leg swings forward.
	p["kn_l"] = Vector3(-0.3 - 1.3 * maxf(c, 0.0), 0, 0)
	p["kn_r"] = Vector3(-0.3 - 1.3 * maxf(-c, 0.0), 0, 0)
	p["sh_l"] = Vector3(-0.9 * s, 0, -0.15)
	p["sh_r"] = Vector3(0.9 * s, 0, 0.15)
	p["height"] = 0.4 + 0.05 * absf(c)


func set_pose(p: String) -> void:
	if poses.has(p):
		pose = p


## Hides both wings and hands them over, unfolded, to be thrown away.
func detach_wings() -> Array[Node3D]:
	set_wings(true, true)
	wing_l.visible = false
	wing_r.visible = false
	wings_open = false
	return [wing_l, wing_r]


func restore_wings() -> void:
	wing_l.visible = true
	wing_r.visible = true
	set_wings(false, true)


func set_wings(open: bool, instant := false) -> void:
	if open == wings_open and not instant:
		return
	wings_open = open
	if _wing_tween:
		_wing_tween.kill()
	for pair in [[wing_l, -1.0], [wing_r, 1.0]]:
		var w: Node3D = pair[0]
		var s: float = pair[1]
		var rot := Vector3(0, -0.25 * s, 0.08 * s) if open else Vector3(0, 0, -WING_FOLD_Z * s)
		var scl := Vector3.ONE if open else Vector3(0.25, 1, 1)
		if instant:
			w.rotation = rot
			w.scale = scl
	if instant:
		return
	_wing_tween = create_tween().set_parallel(true)
	for pair in [[wing_l, -1.0], [wing_r, 1.0]]:
		var w: Node3D = pair[0]
		var s: float = pair[1]
		if open:
			# Buzz-style "pop": overshoot then settle.
			_wing_tween.tween_property(w, "rotation", Vector3(0, -0.25 * s, 0.08 * s), 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_wing_tween.tween_property(w, "scale", Vector3.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			_wing_tween.tween_property(w, "rotation", Vector3(0, 0, -WING_FOLD_Z * s), 0.15) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_wing_tween.tween_property(w, "scale", Vector3(0.25, 1, 1), 0.15)


# --- construction -----------------------------------------------------------

func look_name() -> String:
	return LOOKS[look]["name"]


func set_look(i: int) -> void:
	look = posmod(i, LOOKS.size())
	if _wing_tween:
		_wing_tween.kill()
	if _model:
		_model.queue_free()
	var l: Dictionary = LOOKS[look]
	var base: String = l["base"]
	_model = load(CHAR_DIR + "Superhero_%s_FullBody.gltf" % base).instantiate()
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.rotation.y = PI  # The model faces +Z.

	var rest := {}
	for n in BONES:
		_bone_ids[n] = _skeleton.find_bone(BONES[n])
		rest[n] = _skeleton.get_bone_global_rest(_bone_ids[n])
	_model.position = _model.basis * (rest["hip_l"].origin + rest["hip_r"].origin) * -0.5
	var at := func(n: String) -> Vector3: return _model.transform * rest[n].origin
	joints["spine"].position = at.call("spine")
	joints["neck"].position = at.call("neck") - at.call("spine")
	for s in ["l", "r"]:
		joints["sh_" + s].position = at.call("sh_" + s) - at.call("spine")
		joints["el_" + s].position = Vector3.DOWN * at.call("el_" + s).distance_to(at.call("sh_" + s))
		joints["hip_" + s].position = at.call("hip_" + s)
		joints["kn_" + s].position = Vector3.DOWN * at.call("kn_" + s).distance_to(at.call("hip_" + s))

	# The arms rest straight out, so turn them down to match an unposed joint.
	var turn := Basis(Vector3.UP, PI)
	for n in BONES:
		var aim := Basis.IDENTITY
		if n.begins_with("sh_") or n.begins_with("el_"):
			aim = Basis(Vector3.BACK, -PI / 2 if n.ends_with("_l") else PI / 2)
		_bone_offsets[n] = turn * aim * rest[n].basis

	_pelvis_bone = _skeleton.find_bone("pelvis")
	_pelvis_offset = rest["spine"].affine_inverse() * _skeleton.get_bone_global_rest(_pelvis_bone)

	var wrist: float = absf(_skeleton.get_bone_global_rest(_skeleton.find_bone("hand_l")).origin.x) - 0.02
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		m.extra_cull_margin = 500.0  # A ragdoll can fly far from this node.
		if m.name.begins_with("Superhero") or m.name.begins_with("SuperHero"):
			_dress(m, l, base, rest["neck"].origin.y, wrist)
	_attach_hair(l)
	_build_pack(rest)
	set_wings(wings_open, true)
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		m.layers = 2  # Keeps blood decals off the flier.
	_sync_bones()


## Stores each vertex's rest position in its colour, which the suit shader uses
## to cut clean collars, cuffs and boots per pixel.
func _dress(m: MeshInstance3D, l: Dictionary, base: String, neck: float, wrist: float) -> void:
	var src: Mesh = m.mesh
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		colors[i] = Color(v.x * 0.5 + 0.5, v.y * 0.5, v.z * 0.5 + 0.5)
	arrays[Mesh.ARRAY_COLOR] = colors
	for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[c] = null
	var flags := 0
	if (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() == verts.size() * 8:
		flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var dressed := ArrayMesh.new()
	dressed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	m.mesh = dressed
	var mat := ShaderMaterial.new()
	mat.shader = SUIT_SHADER
	mat.set_shader_parameter("skin_tex", load(CHAR_DIR + l["skin"]))
	mat.set_shader_parameter("normal_tex", load(CHAR_DIR + "T_Superhero_%s_Normal.png" % base))
	mat.set_shader_parameter("rough_tex", load(CHAR_DIR + "T_Superhero_%s_Roughness.png" % base))
	mat.set_shader_parameter("suit", l["suit"])
	mat.set_shader_parameter("trim", l["trim"])
	mat.set_shader_parameter("neck_y", neck - 0.03)
	mat.set_shader_parameter("wrist_x", wrist)
	mat.next_pass = _outline()
	m.material_override = mat


func _attach_hair(l: Dictionary) -> void:
	var hair: Node3D = load(CHAR_DIR + "hair/%s.gltf" % l["hair"]).instantiate()
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	_skeleton.add_child(head)
	head.add_child(hair)
	hair.transform = _skeleton.get_bone_global_rest(_skeleton.find_bone("Head")).affine_inverse()
	for m: MeshInstance3D in hair.find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = m.mesh.surface_get_material(0).duplicate()
		mat.albedo_color = l["hair_color"]
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
		mat.next_pass = _outline()
		m.material_override = mat


func _outline() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	return mat


func _build_pack(rest: Dictionary) -> void:
	var bone := "spine_03"
	var l_trim: Color = LOOKS[look]["suit"]
	var mount := BoneAttachment3D.new()
	mount.bone_name = bone
	_skeleton.add_child(mount)
	var pack := Node3D.new()
	mount.add_child(pack)
	var bone_rest := _skeleton.get_bone_global_rest(_skeleton.find_bone(bone))
	var turn := Basis(Vector3.UP, PI).scaled(Vector3.ONE / MODEL_SCALE)
	pack.transform = bone_rest.affine_inverse() * Transform3D(turn, bone_rest.origin + Vector3(0, 0.08, -0.14))
	_part(pack, _box(Vector3(0.24, 0.3, 0.1)), Vector3(0, 0, 0.05), l_trim)
	_part(pack, _box(Vector3(0.08, 0.22, 0.02)), Vector3(0, 0, 0.11), WING)
	wing_l = _wing(pack, -1.0)
	wing_r = _wing(pack, 1.0)


func _sync_bones() -> void:
	var src := joints if follow.is_empty() else follow
	var to_skel := _skeleton.global_transform.affine_inverse()
	if follow.is_empty():
		_skeleton.reset_bone_pose(_pelvis_bone)
	else:
		var torso := to_skel * (src["spine"] as Node3D).get_global_transform_interpolated()
		var spine := Transform3D(torso.basis.orthonormalized() * _bone_offsets["spine"], torso.origin)
		_skeleton.set_bone_global_pose(_pelvis_bone, spine * _pelvis_offset)
	for n in BONES:
		var body: Node3D = src[n]
		var x := to_skel * (body.get_global_transform_interpolated() if body is RigidBody3D else body.global_transform)
		_skeleton.set_bone_global_pose(_bone_ids[n], Transform3D(x.basis.orthonormalized() * _bone_offsets[n], x.origin))


func _wing(parent: Node3D, s: float) -> Node3D:
	var hinge := Node3D.new()
	hinge.position = Vector3(0.15 * s, 0.1, 0.1)
	parent.add_child(hinge)
	_part(hinge, _box(Vector3(1.1, 0.035, 0.32)), Vector3(0.6 * s, 0, 0.04), WING)
	_part(hinge, _box(Vector3(0.7, 0.04, 0.08)), Vector3(0.5 * s, 0.002, -0.06), WING_TRIM)
	_part(hinge, _box(Vector3(0.24, 0.05, 0.36)), Vector3(1.24 * s, 0, 0.08), WING_TIP)
	hinge.rotation = Vector3(0, 0, -WING_FOLD_Z * s)
	hinge.scale = Vector3(0.25, 1, 1)
	return hinge


func _build_poses() -> void:
	var sym := func(sh: Vector3, el: Vector3, hip: Vector3, kn: Vector3, spine: Vector3, neck: Vector3, h: float) -> Dictionary:
		return {
			"sh_l": Vector3(sh.x, sh.y, -sh.z), "sh_r": sh,
			"el_l": el, "el_r": el,
			"hip_l": Vector3(hip.x, hip.y, -hip.z), "hip_r": hip,
			"kn_l": kn, "kn_r": kn,
			"spine": spine, "neck": neck, "height": h,
		}
	poses["stand"] = sym.call(Vector3(0, 0, 0.12), Vector3(0.15, 0, 0), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.42)
	poses["run"] = sym.call(Vector3.ZERO, Vector3(1.4, 0, 0), Vector3.ZERO, Vector3.ZERO, Vector3(-0.3, 0, 0), Vector3(0.25, 0, 0), 0.42)
	poses["swan"] = sym.call(Vector3(-0.2, 0, 1.45), Vector3(0.1, 0, 0), Vector3(0, 0, 0.04), Vector3(-0.15, 0, 0), Vector3(0.25, 0, 0), Vector3(0.7, 0, 0), 0.42)
	poses["glide"] = sym.call(Vector3(3.0, 0, 0.25), Vector3.ZERO, Vector3(0, 0, 0.05), Vector3(-0.2, 0, 0), Vector3.ZERO, Vector3(0.7, 0, 0), 0.42)
	poses["tuck"] = sym.call(Vector3(1.3, 0, 0.3), Vector3(1.6, 0, 0), Vector3(1.9, 0, 0.1), Vector3(-2.3, 0, 0), Vector3(-0.7, 0, 0), Vector3(0.2, 0, 0), 0.0)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.45
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mi.material_override = m
	parent.add_child(mi)
	return mi


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m
