extends Camera3D
## Smoothed chase camera. Flat follow on the ramp and after landing; in glide
## it becomes a chase-plane cam that follows loops and rolls with the glider.

const PlayerScript := preload("res://scripts/player.gd")

var player: PlayerScript
var orbit := false
## Set by the intro flyby to [where to be, what to look at]; null follows the player.
var tour = null
var _tour_look := Vector3.ZERO
var dir := Vector3.FORWARD
var cam_up := Vector3.UP
var _dist := 7.0
var _height := 2.6
var _ahead := 4.0
var _target := Vector3.ZERO
var _slope := 0.0
var _shake := 0.0
var _wobble := 0.0


## Starts a tour from wherever the camera is now.
func start_tour(at: Vector3, look: Vector3) -> void:
	tour = [at, look]
	_tour_look = global_position + -global_basis.z * 20.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func snap() -> void:
	tour = null
	dir = Vector3.FORWARD
	cam_up = Vector3.UP
	orbit = false
	_dist = 7.0
	_height = 2.6
	_ahead = 4.0
	_target = player.global_position
	_slope = 0.45
	global_position = _desired()
	_look()


func _process(delta: float) -> void:
	if player == null:
		return
	if tour != null:
		global_position = global_position.lerp(tour[0], 1.0 - exp(-3.0 * delta))
		_tour_look = _tour_look.lerp(tour[1], 1.0 - exp(-4.5 * delta))
		h_offset = 0.0
		v_offset = 0.0
		if global_position.distance_to(_tour_look) > 0.5:
			look_at(_tour_look, Vector3.UP)
		return
	_target = player.focus()
	var v := player.focus_velocity()
	var hv := Vector3(v.x, 0, v.z)
	var gliding := player.mode == PlayerScript.Mode.AIR and player.wings_open
	var up_goal := Vector3.UP

	if orbit:
		dir = Vector3(dir.x, 0, dir.z).normalized().rotated(Vector3.UP, 0.35 * delta)
	elif gliding and v.length() > 2.0:
		dir = _turn(dir, v.normalized(), 3.0 * delta)
		up_goal = player.att.y
	elif hv.length() > 1.5:
		dir = _turn(dir, hv.normalized(), 2.5 * delta)
	elif dir.y != 0.0:
		dir = _turn(dir, Vector3(dir.x, 0, dir.z).normalized(), 2.5 * delta)
	cam_up = _turn(cam_up, up_goal, 3.0 * delta)

	var dist := 7.0
	var h := 2.6
	var ahead := 4.0
	match player.mode:
		PlayerScript.Mode.AIR:
			if gliding:
				dist = 9.0; h = 2.6; ahead = 12.0
			else:
				dist = 7.0; h = 7.0; ahead = 2.0
		PlayerScript.Mode.RAGDOLL:
			dist = 11.0; h = 6.0; ahead = 0.0
		PlayerScript.Mode.SINK:
			dist = 9.0; h = 2.0; ahead = 0.0
		PlayerScript.Mode.FROZEN:
			if player.has_landed or player.has_launched:
				dist = 9.0; h = 4.5; ahead = 0.0

	# On the ramp, rise with the slope so the camera never dips under the deck.
	var slope := 0.0
	if player.mode == PlayerScript.Mode.GROUND and hv.length() > 0.5:
		slope = maxf(-v.y / hv.length(), 0.0)
	_slope = lerpf(_slope, slope, 1.0 - exp(-4.0 * delta))

	var k := 1.0 - exp(-3.0 * delta)
	_dist = lerpf(_dist, dist, k)
	_height = lerpf(_height, h, k)
	_ahead = lerpf(_ahead, ahead, k)

	global_position = global_position.lerp(_desired(), 1.0 - exp(-8.0 * delta))
	if global_position.y < 1.5 and player.mode != PlayerScript.Mode.SINK:
		global_position.y = 1.5
	_look()
	fov = lerpf(fov, clampf(62.0 + v.length() * 0.55, 62.0, 90.0), 1.0 - exp(-2.0 * delta))
	_shake *= exp(-5.0 * delta)
	# Speed wobble: a fast, uneven shudder that builds as the speed climbs.
	var rattle := clampf((v.length() - 12.0) / 48.0, 0.0, 1.0)
	_wobble += delta * (8.0 + 14.0 * rattle)
	var sway := (sin(_wobble * 1.7) + sin(_wobble * 2.9) * 0.5) * 0.09 * rattle
	var bob := (sin(_wobble * 2.3 + 1.0) + sin(_wobble * 3.7) * 0.5) * 0.09 * rattle
	h_offset = randf_range(-_shake, _shake) + sway
	v_offset = randf_range(-_shake, _shake) + bob
	rotate_object_local(Vector3.FORWARD, sin(_wobble * 1.3) * 0.008 * rattle)


## Rotate unit vector a toward b, safe for (nearly) opposite vectors.
func _turn(a: Vector3, b: Vector3, rate: float) -> Vector3:
	var w := clampf(1.0 - exp(-rate), 0.0, 1.0)
	if a.dot(b) > 0.99999:
		return b  # Too close for slerp to find a rotation axis.
	if a.dot(b) < -0.98:
		var axis := a.cross(Vector3.UP)
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		return a.rotated(axis.normalized(), PI * w).normalized()
	return a.slerp(b, w).normalized()


func _desired() -> Vector3:
	return _target - dir * _dist + cam_up * _height + Vector3.UP * (_slope * _dist)


func _look() -> void:
	var t := _target + dir * _ahead + cam_up * 0.5
	var d := t - global_position
	if d.length() > 0.1 and absf(d.normalized().dot(cam_up)) < 0.99:
		look_at(t, cam_up)
