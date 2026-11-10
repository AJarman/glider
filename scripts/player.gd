extends CharacterBody3D
## The winged runner. A hidden sphere does the ramp physics (so it rolls and
## keeps momentum like a rolling ball); in the air a full 3D glider model takes
## over, and on touchdown the humanoid becomes a ragdoll.

signal launched
signal touched_down(collider: Object)
signal settled
signal splashed
signal skimmed
signal wings_changed(open: bool)
signal crashed(at: Vector3, normal: Vector3, vel: Vector3)

const HumanoidScript := preload("res://scripts/humanoid.gd")
const RagdollScript := preload("res://scripts/ragdoll.gd")

enum Mode { FROZEN, GROUND, AIR, RAGDOLL, SINK }

@export_group("Ramp")
@export var gravity := 12.0
@export var ramp_friction := 1.0
@export var ramp_push := 4.0
@export var ramp_steer := 9.0

@export_group("Glide")
@export var lift_k := 0.028
@export var cd0 := 0.03
@export var cdi := 0.08
@export var stall_aoa := 16.0
@export var trim_aoa := 5.5
@export var roll_rate := 200.0
@export var pitch_stability := 12.0
@export var yaw_stability := 6.0
@export var max_g := 5.0
## Extra lift while pulling back (flaps), so loops work from cruise speed.
@export var pull_boost := 1.0
@export var air_drag_closed := 0.001
## Body lift in the swan dive, as a fraction of gravity in level flight.
@export var swan_lift := 0.15
## How quickly the nose follows the flight path with the wings closed.
@export var swan_pitch := 1.5
## Stick control with the wings closed: pitch and roll cost speed through drag.
@export var swan_stick_pitch := 2.5
@export var swan_max_aoa := 45.0
@export var swan_roll_rate := 120.0
## Extra drag multiplier with the body flat to the airflow.
@export var swan_drag := 8.0
@export var swan_body_lift := 0.008
@export var wind_factor := 0.25

@export_group("Water")
## Ground effect starts at skim_speed and is full strength 15 m/s above it.
@export var skim_speed := 25.0
@export var ground_effect_height := 6.0
@export var ground_effect_lift := 0.8
@export var ground_effect_drag := 0.6
## Slowest speed and steepest descent (rise/run) that bounce off the water.
@export var skim_min_speed := 28.0
@export var skim_max_slope := 0.36
@export var skim_keep := 0.85
@export var skim_rebound := 0.5
@export var sink_speed := 9.0
## Slowest impact that draws blood.
@export var crash_speed := 25.0

@export_group("Mines")
@export var blast_force := 16.0
@export var bump_limit := 9.0
## Speed gained from a mine's shockwave at point-blank range.
@export var shock_push := 26.0

const RADIUS := 0.45

var mode := Mode.FROZEN
var wings_open := false
var has_launched := false
var has_landed := false
var ramp_body: StaticBody3D
var wind := Vector3.ZERO
var input_override = null  # Vector2 from autopilot, or null
## Glider attitude; -Z is the nose, +Y the belly-to-back "up".
var att := Basis.IDENTITY
var aoa := 0.0
var bank := 0.0
var air_time := 0.0
## Current strength of the lift cushion over the water, 0 to 1.
var ground_effect := 0.0
## Magnet modifier: the first touch on a target is where you stay.
var sticky := false
## A mine has blown the wings off; they're back next attempt.
var wings_lost := false
var ragdoll: Node3D

var body: Node3D
var visual_root: Node3D
var _shape: CollisionShape3D
var _off_floor := 0.0
var _settle_time := 0.0
var _stuck := false
var _rest_time := 0.0
var _last_fwd := Vector3.FORWARD
var _prone := 0.0
var _on_floor := false
var _floor_normal := Vector3.UP
var _hit: Object = null
var _debris: Array[Node3D] = []
var _hit_pos := Vector3.ZERO
var _hit_normal := Vector3.UP
var _bubbles: CPUParticles3D


func _ready() -> void:
	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	_shape.shape = sphere
	add_child(_shape)

	# Godot's move_and_slide strips vertical speed on slopes, which kills ramp
	# momentum, so movement and floor detection are done manually in _move().
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	visual_root = Node3D.new()
	# Rotated every frame in _process, so it must not be physics-interpolated.
	visual_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(visual_root)
	body = HumanoidScript.new()
	visual_root.add_child(body)

	_bubbles = CPUParticles3D.new()
	_bubbles.emitting = false
	_bubbles.local_coords = false
	_bubbles.amount = 24
	_bubbles.lifetime = 2.0
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = 0.5
	_bubbles.gravity = Vector3(0, 7, 0)
	_bubbles.mesh = _droplet(0.07, Color(0.85, 0.95, 1.0))
	add_child(_bubbles)


func reset(pos: Vector3) -> void:
	_clear_ragdoll()
	for piece in _debris:
		piece.queue_free()
	_debris.clear()
	global_position = pos
	velocity = Vector3.ZERO
	mode = Mode.FROZEN
	has_launched = false
	has_landed = false
	att = Basis.IDENTITY
	aoa = 0.0
	bank = 0.0
	air_time = 0.0
	wings_lost = false
	_off_floor = 0.0
	_settle_time = 0.0
	_stuck = false
	_last_fwd = Vector3.FORWARD
	_prone = 0.0
	_on_floor = false
	_shape.disabled = false
	_bubbles.emitting = false
	body.visible = true
	body.restore_wings()
	wings_open = false
	body.set_pose("stand")
	visual_root.quaternion = Quaternion.IDENTITY
	reset_physics_interpolation()


func release() -> void:
	mode = Mode.GROUND
	velocity = Vector3.FORWARD * 3.0


func set_wings(open: bool) -> void:
	if has_landed or wings_lost:
		open = false
	if open and not wings_open and velocity.length() > 1.0:
		# Point the nose along the flight path, keeping the current roll.
		var vd := velocity.normalized()
		var up := att.y if absf(att.y.dot(vd)) < 0.95 else Vector3.UP
		if absf(up.dot(vd)) > 0.95:
			up = Vector3.BACK
		att = Basis.looking_at(vd, up)
	if open != wings_open:
		wings_changed.emit(open)
	wings_open = open
	body.set_wings(open)


## Hit by shrapnel: knocks the flier off course and rips the wings off.
func blast(from: Vector3) -> void:
	var away := (global_position - from).normalized()
	velocity += (away + Vector3.UP * 0.3).normalized() * blast_force
	set_wings(false)
	if wings_lost:
		return
	wings_lost = true
	for wing: Node3D in body.detach_wings():
		_throw_wing(wing, away)


## A mine's pressure wave throws the flier off course and rolls them over.
func shove(from: Vector3, strength: float) -> void:
	var away := (global_position - from).normalized()
	velocity += (away + Vector3.UP * 0.25).normalized() * shock_push * strength
	att = (att * Basis(Vector3.BACK, randf_range(-1.6, 1.6) * strength)).orthonormalized()


## A slow fragment knocks the flier off line without doing damage.
func bump(impact: Vector3) -> void:
	velocity += impact.limit_length(bump_limit)


## Sends a torn-off wing spinning away as its own physics object.
func _throw_wing(wing: Node3D, away: Vector3) -> void:
	var piece := RigidBody3D.new()
	piece.collision_layer = 4
	piece.collision_mask = 1
	piece.mass = 2.0
	piece.angular_damp = 0.3
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 0.1, 0.4)
	var shape := CollisionShape3D.new()
	shape.shape = box
	piece.add_child(shape)
	var xf := wing.global_transform
	get_parent().add_child(piece)
	piece.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var copy: Node3D = wing.duplicate()
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	piece.add_child(copy)
	var side := (xf.origin - global_position).normalized()
	piece.linear_velocity = velocity + (side + away).normalized() * randf_range(14.0, 22.0) + Vector3.UP * 8.0
	piece.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
	_debris.append(piece)


## Where the camera and scoring should look: the ragdoll torso once landed.
func focus() -> Vector3:
	if ragdoll:
		return ragdoll.focus()
	return get_global_transform_interpolated().origin


func focus_velocity() -> Vector3:
	if ragdoll:
		return ragdoll.torso().linear_velocity
	return velocity


func _get_input() -> Vector2:
	if input_override != null:
		return input_override
	if mode == Mode.FROZEN:
		return Vector2.ZERO
	var stick := Input.get_vector("left", "right", "up", "down")
	return stick


func _physics_process(delta: float) -> void:
	match mode:
		Mode.FROZEN:
			return
		Mode.RAGDOLL:
			_ragdoll_step(delta)
			return
		Mode.SINK:
			_sink_step(delta)
			return
	if mode == Mode.AIR and input_override == null and Input.is_action_just_pressed("wings"):
		set_wings(not wings_open)

	var inp := _get_input()
	var pre_vel := velocity
	if mode == Mode.GROUND:
		_ground_step(delta, inp)
	else:
		_air_step(delta, inp)
	_move(delta)
	_post_move(delta, pre_vel)

	if mode != Mode.RAGDOLL and global_position.y < 0.4:
		if _can_skim():
			_skim()
		else:
			_splash(global_position)


func _ground_step(delta: float, inp: Vector2) -> void:
	var v := velocity + Vector3.DOWN * gravity * delta
	if _on_floor:
		# Gravity's normal part is removed by the collision slide, leaving
		# only the downhill component, just like a rolling ball.
		var n := _floor_normal
		# Lean forward to speed up, sideways to steer.
		var hv := Vector3(v.x, 0, v.z)
		var f := hv.normalized() if hv.length() > 0.5 else Vector3.FORWARD
		var ft := (f - n * f.dot(n)).normalized()
		var r := ft.cross(n).normalized()
		v += ft * (-inp.y) * ramp_push * delta
		v += r * inp.x * ramp_steer * delta
		var sp := v.length()
		if sp > 0.0001:
			v *= maxf(sp - ramp_friction * delta, 0.0) / sp
	velocity = v


func _cl(a: float) -> float:
	# Symmetric lift curve, so inverted flight works with negative angle of attack.
	var m := absf(a)
	var c := m * 0.115 if m <= stall_aoa else maxf(stall_aoa * 0.115 - (m - stall_aoa) * 0.09, 0.4)
	return c * signf(a)


func _air_step(delta: float, inp: Vector2) -> void:
	var v := velocity
	var sp := v.length()
	v += Vector3.DOWN * gravity * delta

	if sp > 0.5:
		# Angle of attack and sideslip from the airflow in the body frame.
		var lv := att.transposed() * v
		var a := atan2(-lv.y, -lv.z)
		var beta := atan2(lv.x, -lv.z)
		aoa = rad_to_deg(a)

		# Stick rotates the glider about its own axes (so loops and rolls are
		# free); aerodynamic stability weathervanes the nose back to the airflow.
		var stab := clampf(sp / 15.0, 0.2, 1.0)
		var rate := Vector3.ZERO
		if wings_open:
			# Stick commands angle of attack: full pull sits just under the
			# stall for maximum lift (loops), full push mirrors it (inverted).
			var cmd := trim_aoa + inp.y * ((stall_aoa - 1.0 - trim_aoa) if inp.y > 0.0 else (trim_aoa + 6.0))
			rate.x = -pitch_stability * stab * (a - deg_to_rad(cmd))
			rate.z = deg_to_rad(-inp.x * roll_rate)
		else:
			# Swan dive: hands off, the shoulders level and the nose eases down the
			# flight path; the stick holds a body angle or rolls.
			var stick := inp if has_launched else Vector2.ZERO
			rate.x = -(swan_pitch + swan_stick_pitch * absf(stick.y)) * (a - deg_to_rad(stick.y * swan_max_aoa))
			rate.z = deg_to_rad(-stick.x * swan_roll_rate) if absf(stick.x) > 0.1 else deg_to_rad(bank) * 2.0
		rate.y = -yaw_stability * stab * beta
		att = (att * Basis.from_euler(rate * delta)).orthonormalized()

	var ge := _ground_effect(sp)
	ground_effect = ge
	if wings_open and sp > 0.5:
		var vd := v.normalized()
		var lift_dir := att.y - vd * att.y.dot(vd)
		if lift_dir.length() > 0.01:
			lift_dir = lift_dir.normalized()
		var cl := _cl(aoa) * (1.0 + pull_boost * maxf(inp.y, 0.0))
		var q := lift_k * sp * sp
		# A headwind adds to the air over the wings, so it adds lift but not drag.
		var air_sp := sp + maxf(-vd.dot(wind), 0.0)
		var lift := clampf(lift_k * air_sp * air_sp * cl * (1.0 + ground_effect_lift * ge), -max_g * gravity, max_g * gravity)
		v += lift_dir * lift * delta
		v -= vd * q * (cd0 + cdi * cl * cl) * (1.0 - ground_effect_drag * ge) * delta
		v += wind * wind_factor * delta
	elif sp > 0.0:
		var a := deg_to_rad(aoa)
		var flat := sin(a) * sin(a)
		v -= v / sp * air_drag_closed * (1.0 + swan_drag * flat) * sp * sp * delta
		v += wind * wind_factor * 0.4 * delta
		if has_launched:
			# Lift acts through the back, so rolling turns; the base part fades as
			# the dive steepens and the rest comes from the body's angle to the air.
			var vd := v.normalized()
			var lift_dir := att.y - vd * att.y.dot(vd)
			if lift_dir.length() > 0.01:
				var base := gravity * swan_lift * (1.0 + 0.5 * ge) * minf(sp / skim_speed, 1.0) * sqrt(maxf(1.0 - vd.y * vd.y, 0.0))
				var body_lift := clampf(swan_body_lift * sp * sp * sin(2.0 * a), -2.0 * gravity, 2.0 * gravity)
				v += lift_dir.normalized() * (base + body_lift) * delta
	bank = rad_to_deg(atan2(-att.x.y, att.y.y))
	velocity = v


## 0 to 1: strongest at high speed right on the water.
func _ground_effect(sp: float) -> float:
	var near := clampf(1.0 - global_position.y / ground_effect_height, 0.0, 1.0)
	return near * near * clampf((sp - skim_speed) / 15.0, 0.0, 1.0)


func _post_move(delta: float, pre_vel: Vector3) -> void:
	match mode:
		Mode.GROUND:
			if _on_floor or (not has_launched and _snap_down()):
				_off_floor = 0.0
			else:
				_off_floor += delta
				if _off_floor > 0.12:
					mode = Mode.AIR
					air_time = 0.0
					if velocity.length() > 1.0:
						att = Basis.looking_at(velocity.normalized(), Vector3.UP)
					if not has_launched and velocity.length() > 5.0:
						has_launched = true
						launched.emit()
		Mode.AIR:
			air_time += delta
			if _hit != null and _hit != ramp_body and has_launched:
				_start_ragdoll(pre_vel, _hit)
			elif _on_floor:
				mode = Mode.GROUND
				_off_floor = 0.0


## Keeps the runner on the deck over the ramp's crest, where the straight
## segments would otherwise toss them off each joint. Past the lip there's
## nothing below to find, so the real launch is untouched.
func _snap_down() -> bool:
	var c := move_and_collide(-_floor_normal * 0.4, true)
	if c == null or c.get_collider() != ramp_body or c.get_normal().y <= 0.42:
		return false
	global_position += c.get_travel()
	var n := c.get_normal()
	var sp := velocity.length()
	velocity -= n * maxf(velocity.dot(n), 0.0)
	velocity = velocity.normalized() * sp
	_on_floor = true
	_floor_normal = n
	return true


func _move(delta: float) -> void:
	# Manual slide: remove only the into-surface part of velocity on contact,
	# so speed along the surface is preserved like a rolling ball.
	_on_floor = false
	_hit = null
	var motion := velocity * delta
	for i in 4:
		var c := move_and_collide(motion)
		if c == null:
			break
		var n := c.get_normal()
		if _hit == null:
			_hit = c.get_collider()
			_hit_pos = c.get_position()
			_hit_normal = n
		if n.y > 0.42:
			_on_floor = true
			_floor_normal = n
		var vn := velocity.dot(n)
		if vn < 0.0:
			velocity -= n * vn
		motion = c.get_remainder()
		var mn := motion.dot(n)
		if mn < 0.0:
			motion -= n * mn
		if motion.length() < 0.0001:
			break


func _start_ragdoll(vel: Vector3, col: Object) -> void:
	var grippy := wings_open
	mode = Mode.RAGDOLL
	has_landed = true
	_settle_time = 0.0
	_rest_time = 0.0
	_shape.set_deferred("disabled", true)
	_stuck = sticky and col is Node and (col as Node).is_in_group("target")
	ragdoll = RagdollScript.new()
	get_parent().add_child(ragdoll)
	ragdoll.build(body, vel, grippy, _stuck)
	if _stuck:
		ragdoll.stick_to(col)
	wings_open = false
	body.set_wings(false, true)
	touched_down.emit(col)
	if vel.length() >= crash_speed:
		crashed.emit(_hit_pos, _hit_normal, vel)


func _ragdoll_step(delta: float) -> void:
	var p: Vector3 = ragdoll.focus()
	if p.y < 0.4:
		_splash(p)
		return
	# On a moving target, lying still means moving with it.
	var carrier := _deck_velocity(p)
	# A swaying deck keeps a loose body shuffling, so allow it more slack.
	var slack := 1.0 if carrier == Vector3.ZERO else 3.0
	var still: bool = (ragdoll.torso().linear_velocity - carrier).length() < 0.35 * slack and ragdoll.max_speed(carrier) < slack
	_settle_time = _settle_time + delta if still else 0.0
	_rest_time += delta
	var give_up := 12.0 if carrier == Vector3.ZERO else 5.0
	if _settle_time > 0.8 or _rest_time > give_up or (_stuck and _rest_time > 0.6):
		# Pinned here, so where the body lies is exactly what gets scored.
		mode = Mode.FROZEN
		ragdoll.pin()
		settled.emit()


## Landed with the Magnet: the body rides its target rather than resting on it.
func is_stuck() -> bool:
	return _stuck


## How fast the deck under a point is moving: targets record it as meta "vel".
func _deck_velocity(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 2.5)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Node:
		return (hit.collider as Node).get_meta("vel", Vector3.ZERO)
	return Vector3.ZERO


func _clear_ragdoll() -> void:
	if ragdoll:
		body.follow = {}
		ragdoll.queue_free()
		ragdoll = null


func _can_skim() -> bool:
	if mode != Mode.AIR or not has_launched:
		return false
	var hs := Vector2(velocity.x, velocity.z).length()
	return hs >= skim_min_speed and -velocity.y <= hs * skim_max_slope


func _skim() -> void:
	global_position.y = 0.4
	velocity = Vector3(velocity.x * skim_keep, maxf(absf(velocity.y) * skim_rebound, 2.0), velocity.z * skim_keep)
	_spray(global_position, 24, 4.0, 8.0)
	skimmed.emit()


func _splash(at: Vector3) -> void:
	if ragdoll:
		velocity = ragdoll.torso().linear_velocity
	_clear_ragdoll()
	mode = Mode.SINK
	has_landed = true
	wings_open = false
	body.set_wings(false, true)
	body.visible = true
	_shape.set_deferred("disabled", true)
	global_position = at
	reset_physics_interpolation()
	_bubbles.emitting = true
	_spray(at, 80, 6.0, 13.0)
	splashed.emit()


func _sink_step(delta: float) -> void:
	velocity = velocity.lerp(Vector3.DOWN * sink_speed, 1.0 - exp(-1.5 * delta))
	global_position += velocity * delta


func _spray(at: Vector3, amount: int, speed_min: float, speed_max: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.4
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = Vector3(0, -12, 0)
	p.mesh = _droplet(0.18, Color(0.9, 0.97, 1.0))
	get_parent().add_child(p)
	p.global_position = Vector3(at.x, 0.3, at.z)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _droplet(radius: float, color: Color) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material = mat
	return m


func _process(delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	var fwd := hv.normalized() if hv.length() > 0.5 else _last_fwd
	var up := Vector3.UP
	var prone := 0.0
	var target: Basis

	match mode:
		Mode.GROUND:
			if _on_floor:
				up = _floor_normal
			# Feet keep pace with the deck: strides lengthen with speed, into huge
			# leaps at full tilt, and the legs turn over to cover the ground.
			var speed := velocity.length()
			var stride := lerpf(2.2, 7.0, clampf(speed / 45.0, 0.0, 1.0))
			body.run_rate = maxf(TAU * speed / stride, 5.0)
			body.set_pose("run")
		Mode.AIR:
			if wings_open:
				prone = 1.0
				body.set_pose("glide")
			elif has_launched:
				prone = 1.0
				body.set_pose("swan")
			else:
				body.set_pose("run")
		Mode.SINK:
			body.set_pose("tuck")

	if prone > 0.0:
		target = att
	else:
		if Vector2(fwd.x, fwd.z).length() > 0.01:
			_last_fwd = Vector3(fwd.x, 0, fwd.z).normalized()
		var ft := fwd - up * fwd.dot(up)
		if ft.length() < 0.01:
			ft = _last_fwd
		target = Basis.looking_at(ft.normalized(), up)
	var k := 1.0 - exp(-16.0 * delta)
	visual_root.quaternion = visual_root.quaternion.slerp(Quaternion(target.orthonormalized()), k)

	_prone = lerpf(_prone, prone, 1.0 - exp(-10.0 * delta))
	body.rotation.x = -PI / 2 * _prone
	body.position.y = lerpf(body.height, -0.28, _prone)
