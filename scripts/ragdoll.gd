extends Node3D
## Physics ragdoll built from the humanoid's current pose. Each joint node
## becomes a RigidBody3D that drives the model's bones, linked by cone-twist
## joints, and launched with the runner's velocity so momentum carries over.

const LAYER := 4  # ragdoll parts don't collide with each other
# joint name -> [shape, size, offset, mass]
const PARTS := {
	"spine": ["box", Vector3(0.42, 0.66, 0.34), Vector3(0, 0.3, 0.04), 3.0],
	"neck": ["sphere", Vector3(0.2, 0, 0), Vector3(0, 0.16, 0), 1.0],
	"sh_l": ["capsule", Vector3(0.08, 0.36, 0), Vector3(0, -0.15, 0), 0.5],
	"sh_r": ["capsule", Vector3(0.08, 0.36, 0), Vector3(0, -0.15, 0), 0.5],
	"el_l": ["capsule", Vector3(0.08, 0.42, 0), Vector3(0, -0.17, 0), 0.4],
	"el_r": ["capsule", Vector3(0.08, 0.42, 0), Vector3(0, -0.17, 0), 0.4],
	"hip_l": ["capsule", Vector3(0.1, 0.46, 0), Vector3(0, -0.2, 0), 0.8],
	"hip_r": ["capsule", Vector3(0.1, 0.46, 0), Vector3(0, -0.2, 0), 0.8],
	"kn_l": ["capsule", Vector3(0.09, 0.52, 0), Vector3(0, -0.22, 0), 0.6],
	"kn_r": ["capsule", Vector3(0.09, 0.52, 0), Vector3(0, -0.22, 0), 0.6],
}
# child -> [parent, swing span deg, twist span deg]
const LINKS := {
	"neck": ["spine", 40.0, 30.0],
	"sh_l": ["spine", 80.0, 40.0],
	"sh_r": ["spine", 80.0, 40.0],
	"el_l": ["sh_l", 70.0, 10.0],
	"el_r": ["sh_r", 70.0, 10.0],
	"hip_l": ["spine", 60.0, 20.0],
	"hip_r": ["spine", 60.0, 20.0],
	"kn_l": ["hip_l", 70.0, 10.0],
	"kn_r": ["hip_r", 70.0, 10.0],
}

var bodies := {}


## grippy: wings were open on impact, so the body flops and drags to a stop.
func build(h: Node3D, vel: Vector3, grippy: bool) -> void:
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0 if grippy else 0.55
	pm.bounce = 0.05 if grippy else 0.3

	var spin := vel.cross(Vector3.UP).normalized() * -minf(vel.length() * 0.3, 8.0)
	for n in PARTS:
		var spec: Array = PARTS[n]
		var j: Node3D = h.joints[n]
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER
		rb.collision_mask = 1
		rb.mass = spec[3]
		rb.physics_material_override = pm
		rb.continuous_cd = true
		rb.linear_damp = 0.35 if grippy else 0.05
		rb.angular_damp = 1.5 if grippy else 0.6
		add_child(rb)
		rb.global_transform = j.global_transform.orthonormalized()

		var cs := CollisionShape3D.new()
		cs.position = spec[2]
		var size: Vector3 = spec[1]
		match spec[0]:
			"box":
				var s := BoxShape3D.new()
				s.size = size
				cs.shape = s
			"sphere":
				var s := SphereShape3D.new()
				s.radius = size.x
				cs.shape = s
			_:
				var s := CapsuleShape3D.new()
				s.radius = size.x
				s.height = size.y
				cs.shape = s
		rb.add_child(cs)
		rb.linear_velocity = vel
		rb.angular_velocity = spin
		bodies[n] = rb

	for n in LINKS:
		var link: Array = LINKS[n]
		var child: RigidBody3D = bodies[n]
		var parent: RigidBody3D = bodies[link[0]]
		var jt := ConeTwistJoint3D.new()
		add_child(jt)
		# Cone-twist's twist axis is X; limbs run along their local -Y.
		jt.global_transform = Transform3D(child.global_basis * Basis(Vector3.BACK, -PI / 2), child.global_position)
		jt.node_a = jt.get_path_to(parent)
		jt.node_b = jt.get_path_to(child)
		jt.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(link[1]))
		jt.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(link[2]))
	h.follow = bodies


## Stops the body dead where it lies.
func pin() -> void:
	for n in bodies:
		(bodies[n] as RigidBody3D).freeze = true


func torso() -> RigidBody3D:
	return bodies["spine"]


func focus() -> Vector3:
	var t := torso()
	return t.global_transform * Vector3(0, 0.3, 0)


func max_speed() -> float:
	var m := 0.0
	for n in bodies:
		m = maxf(m, (bodies[n] as RigidBody3D).linear_velocity.length())
	return m
