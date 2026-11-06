extends Node3D
## Round modifiers: rolls the roulette result and owns everything each modifier
## puts in the world, from air mines to weather.

signal detonated
## A fragment struck the flier; impact is its velocity relative to them.
signal shrapnel_hit(impact: Vector3)
## A slow fragment knocked the flier without doing real damage.
signal shrapnel_bump(impact: Vector3)
## The tornado's core took hold of the flier.
signal sucked_in
## The tornado spat the flier out of its top.
signal flung
## The pressure wave reached the flier; strength runs from 0 to 1.
signal shockwave(strength: float)
## A proximity beep; closeness runs from 0 at the edge of range to 1 at the mine.
signal beeped(closeness: float)

enum Mod { MINES, CLOUD, HURRICANE, REVERSE, TORNADO }

const NAMES := {
	Mod.MINES: "AIR MINES",
	Mod.CLOUD: "THICK CLOUD",
	Mod.HURRICANE: "HURRICANE",
	Mod.REVERSE: "REVERSE CONTROLS",
	Mod.TORNADO: "TORNADO",
}
const BLURBS := {
	Mod.MINES: "Open wings are a target",
	Mod.CLOUD: "Trust your instruments",
	Mod.HURRICANE: "Hold on to something",
	Mod.REVERSE: "Everything's backwards",
	Mod.TORNADO: "Ride it or run",
}
const ALL_CHANCE := 0.1
const ANY_CHANCE := 1.0 / 3.0
const TWISTER_REACH := 130.0
const TWISTER_CORE := 11.0
const TWISTER_TOP := 170.0
## The spiralling airflow, in m/s, and how hard it grips (per second, at the core).
const TWISTER_SWIRL := 38.0
const TWISTER_INFLOW := 34.0
const TWISTER_LIFT := 14.0
const TWISTER_DRAG := 5.0
const TWISTER_HOME := Vector3(0, 0, -280)
## Debris per kind: planks, crates, logs and scrap.
const DEBRIS_EACH := 26
const DEBRIS_COLORS := [
	Color(0.5, 0.33, 0.18), Color(0.34, 0.24, 0.15), Color(0.6, 0.55, 0.45),
	Color(0.3, 0.32, 0.36), Color(0.7, 0.2, 0.15),
]
## Crates and logs (kinds 1 and 2) hit like big shards; planks and scrap only bump.
const DEBRIS_HEAVY := [false, true, true, false]
const DEBRIS_HIT_SCALE := 1.1
const DEBRIS_RESPAWN := 5.0
## Wandering: it's shoved at random, carries its momentum and turns back near the edge.
const TWISTER_ROAM := 140.0
const TWISTER_MAX_SPEED := 18.0
const TWISTER_MOMENTUM_LOSS := 0.12
## Open wings are a sail: the funnel grabs them harder, hauls them up faster and
## hurls them much further. Tucked in, it's a slower ride and a straighter exit.
const OPEN_GRIP := 1.5
const CLIMB_OPEN := 62.0
const CLIMB_CLOSED := 36.0
const EJECT_UP_OPEN := 170.0
const EJECT_UP_CLOSED := 70.0
const EJECT_OUT_OPEN := 48.0
const EJECT_OUT_CLOSED := 16.0
const RIDE_SPEED := 40.0
const MINE_COUNT := 14
const MINE_SCALE := 3.0
## Each mine has its own fuse, somewhere in this range.
const FUSE_MIN := 22.0
const FUSE_MAX := 45.0
const SHOCK_SPEED := 90.0
const SHOCK_RANGE := 95.0
const SHARD_COUNT := 120
## Only these big chunks can take the wings; the rest of the junk just bumps.
const HEAVY_SHARDS := 24
const SHAPE_COUNT := 6
const PER_SHAPE := SHARD_COUNT / SHAPE_COUNT
const BUFFER_STRIDE := 16  # 12 for the transform, 4 for the colour.
const SHARD_COLORS := [
	Color(0.85, 0.12, 0.1), Color(1.0, 0.75, 0.1), Color(0.1, 0.7, 0.75), Color(0.95, 0.3, 0.7),
	Color(0.35, 0.8, 0.3), Color(0.25, 0.35, 0.9), Color(0.92, 0.92, 0.95), Color(0.3, 0.3, 0.34),
]
const SHARD_SPEED_MIN := 28.0
const SHARD_SPEED_MAX := 58.0
const SHARD_LIFE := 4.5
## Tumbling is only refreshed one frame in this many, per shard, to save time.
const SPIN_EVERY := 6
const SHARD_DRAG := 0.35
const SHARD_GRAVITY := 12.0  # Same as the flier's.
## Impacts slower than this (relative to the flier, m/s) only bump.
const BUMP_SPEED := 65.0
## How close a fragment must pass. Open wings make a far bigger target.
const HIT_RADIUS_OPEN := 3.6
const HIT_RADIUS_CLOSED := 2.0
const BEEP_RANGE := 130.0

var player: Node3D
var level: Node3D
var active: Array = []
var _mines: Array[Node3D] = []
var _lamps := {}  # mine -> its own lamp material
var _fuses := {}  # mine -> distance it bursts at
var _shocks: Array[Dictionary] = []
var _warning: OmniLight3D
var _beep_wait := 0.0
var _flash := 0.0
var _weather: Array[CPUParticles3D] = []
var _time := 0.0
var _twister: Node3D
var _debris: Array[MultiMesh] = []
var _debris_back := PackedFloat32Array()  # When each struck piece returns.
var _twister_pos := Vector3.ZERO
var _twister_vel := Vector3.ZERO
var _twister_shove := Vector3.ZERO
var _shove_wait := 0.0
var _twister_spray: CPUParticles3D
var _fling_wait := 0.0
var _ride_angle := 0.0
var _ripple_wait := 0.0
## How close the flier is to the funnel, from 0 to 1.
var tornado_closeness := 0.0
var _clouds: Array[ShardCloud] = []


## One mine's real fragments: every shard you see can actually hit you.
class ShardCloud:
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := 0.0
	var frame := 0
	var size := PackedFloat32Array()
	var dead := PackedByteArray()
	var meshes: Array[MultiMeshInstance3D] = []
	## Every shard's transform and colour, sent to the GPU in one go each frame.
	var buffer := PackedFloat32Array()

	func slot(i: int) -> int:
		return (i % SHAPE_COUNT * PER_SHAPE + i / SHAPE_COUNT) * BUFFER_STRIDE

	func place(i: int, xf: Transform3D) -> void:
		var o := slot(i)
		var b := xf.basis
		buffer[o] = b.x.x
		buffer[o + 1] = b.y.x
		buffer[o + 2] = b.z.x
		buffer[o + 3] = xf.origin.x
		buffer[o + 4] = b.x.y
		buffer[o + 5] = b.y.y
		buffer[o + 6] = b.z.y
		buffer[o + 7] = xf.origin.y
		buffer[o + 8] = b.x.z
		buffer[o + 9] = b.y.z
		buffer[o + 10] = b.z.z
		buffer[o + 11] = xf.origin.z

	func move(i: int, at: Vector3) -> void:
		var o := slot(i)
		buffer[o + 3] = at.x
		buffer[o + 7] = at.y
		buffer[o + 11] = at.z

	func paint(i: int, color: Color) -> void:
		var o := slot(i) + 12
		buffer[o] = color.r
		buffer[o + 1] = color.g
		buffer[o + 2] = color.b
		buffer[o + 3] = color.a

	func upload() -> void:
		var span := PER_SHAPE * BUFFER_STRIDE
		for k in SHAPE_COUNT:
			meshes[k].multimesh.buffer = buffer.slice(k * span, (k + 1) * span)

	func free_meshes() -> void:
		for m in meshes:
			m.queue_free()


static func roll(rng: RandomNumberGenerator) -> Array:
	var r := rng.randf()
	if r < ALL_CHANCE:
		return Mod.values()
	if r < ANY_CHANCE:
		return [rng.randi_range(0, Mod.size() - 1)]
	return []


func has(m: int) -> bool:
	return m in active


func apply(mods: Array, rng: RandomNumberGenerator) -> void:
	clear()
	active = mods
	player.reverse_controls = has(Mod.REVERSE)
	level.set_storm(1.0 if has(Mod.HURRICANE) else 0.0)
	if has(Mod.MINES):
		_spawn_mines(rng)
	if has(Mod.CLOUD):
		_add_clouds()
	if has(Mod.TORNADO):
		_add_twister()


func clear() -> void:
	active = []
	player.reverse_controls = false
	level.set_storm(0.0)
	for m in _mines:
		m.queue_free()
	_mines.clear()
	_lamps.clear()
	_fuses.clear()
	for sh in _shocks:
		sh.mesh.queue_free()
	_shocks.clear()
	for c in _clouds:
		c.free_meshes()
	_clouds.clear()
	if _warning:
		_warning.queue_free()
		_warning = null
	for w in _weather:
		w.queue_free()
	_weather.clear()
	if _twister:
		_twister.queue_free()
		_twister = null
	tornado_closeness = 0.0
	player.riding_twister = false


## Hurricane wind for the round, and the rain blown along it.
func start_storm(wind: Vector3) -> void:
	_add_rain(wind)


func update(delta: float, cam_pos: Vector3) -> void:
	_time += delta
	for w in _weather:
		w.global_position = cam_pos
	_update_clouds(delta)
	_update_shocks(delta)
	if _twister:
		_update_twister(delta)
	if _mines.is_empty():
		return
	var armed: bool = player.mode == player.Mode.AIR and player.has_launched
	var nearest: Node3D = null
	var near_dist := INF
	for i in _mines.size():
		var m := _mines[i]
		m.position.y += sin(_time * 1.3 + i) * 0.4 * delta
		m.rotate_y(0.5 * delta)
		_lamps[m].emission_energy_multiplier = 1.5 + 3.5 * maxf(sin(_time * 4.0 + i), 0.0)
		var d := m.global_position.distance_to(player.global_position)
		if d < near_dist:
			near_dist = d
			nearest = m
	_flash *= exp(-12.0 * delta)
	_warning.light_energy = 0.0
	if not armed or near_dist > BEEP_RANGE:
		return
	if near_dist < _fuses[nearest]:
		_detonate(nearest)
		return

	# Like a parking sensor: the closer the nearest mine, the faster it shrieks.
	var closeness := clampf(1.0 - (near_dist - FUSE_MIN) / (BEEP_RANGE - FUSE_MIN), 0.0, 1.0)
	_beep_wait -= delta
	if _beep_wait <= 0.0:
		_beep_wait = lerpf(0.75, 0.07, closeness * closeness)
		_flash = 1.0
		beeped.emit(closeness)
	_lamps[nearest].emission_energy_multiplier = 3.0 + 22.0 * _flash
	_warning.global_position = nearest.global_position
	_warning.light_energy = 12.0 * _flash


func _detonate(mine: Node3D) -> void:
	_mines.erase(mine)
	_lamps.erase(mine)
	_fuses.erase(mine)
	_explosion(mine.global_position)
	_start_shock(mine.global_position)
	mine.queue_free()
	detonated.emit()


func _spawn_mines(rng: RandomNumberGenerator) -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.1, 0.11, 0.13)
	shell.metallic = 0.7
	shell.roughness = 0.35
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.1, 0.05)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.1, 0.05)
	_warning = OmniLight3D.new()
	_warning.light_color = Color(1.0, 0.12, 0.05)
	_warning.omni_range = 40.0
	_warning.light_energy = 0.0
	add_child(_warning)
	var body := SphereMesh.new()
	body.radius = 1.3
	body.height = 2.6
	body.radial_segments = 16
	body.rings = 8
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.22
	spike.height = 0.8
	spike.radial_segments = 8
	var lamp := SphereMesh.new()
	lamp.radius = 0.35
	lamp.height = 0.7
	lamp.radial_segments = 10
	lamp.rings = 5
	for i in MINE_COUNT:
		var m := Node3D.new()
		add_child(m)
		m.global_position = Vector3(rng.randf_range(-60, 60), rng.randf_range(14, 55), rng.randf_range(-420, -60))
		m.scale = Vector3.ONE * MINE_SCALE
		_fuses[m] = rng.randf_range(FUSE_MIN, FUSE_MAX)
		_mesh(m, body, shell, Transform3D.IDENTITY)
		var light: StandardMaterial3D = lamp_mat.duplicate()
		_lamps[m] = light
		# Lamps all round, so one always faces you.
		for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			_mesh(m, lamp, light, Transform3D(Basis.IDENTITY, dir * 1.2))
		for k in 10:
			# Spread the spikes evenly over the sphere.
			var y := 1.0 - (k + 0.5) / 5.0
			var ang := k * 2.4
			var dir := Vector3(cos(ang), 0, sin(ang)) * sqrt(1.0 - y * y) + Vector3.UP * y
			var side := Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.BACK
			var x := side.cross(dir).normalized()
			_mesh(m, spike, shell, Transform3D(Basis(x, dir, x.cross(dir)), dir * 1.5))
		_mines.append(m)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)


func _add_twister() -> void:
	_twister = Node3D.new()
	add_child(_twister)
	_twister_pos = TWISTER_HOME + Vector3(randf_range(-80, 80), 0, randf_range(-120, 120))
	var heading := randf() * TAU
	_twister_vel = Vector3(cos(heading), 0, sin(heading)) * 7.0
	_shove_wait = 0.0
	_twister.global_position = _twister_pos
	_fling_wait = 0.0

	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var churn := NoiseTexture2D.new()
	churn.width = 256
	churn.height = 256
	churn.seamless = true
	churn.noise = noise
	var tube := CylinderMesh.new()
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	tube.radial_segments = 40
	tube.rings = 40
	tube.cap_top = false
	tube.cap_bottom = false
	for layer in [[80.0, 6.0, 0.55], [58.0, 3.5, 0.9]]:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/tornado.gdshader")
		mat.set_shader_parameter("churn", churn)
		mat.set_shader_parameter("height", TWISTER_TOP)
		mat.set_shader_parameter("mouth", layer[0])
		mat.set_shader_parameter("neck", layer[1])
		mat.set_shader_parameter("spin", layer[2])
		var mi := MeshInstance3D.new()
		mi.mesh = tube
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-110, 0, -110), Vector3(220, TWISTER_TOP + 10.0, 220))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_twister.add_child(mi)

	_debris.clear()
	_debris_back.resize(DEBRIS_EACH * 4)
	_debris_back.fill(0.0)
	var plank := BoxMesh.new()
	plank.size = Vector3(4.0, 0.25, 0.8)
	var crate := BoxMesh.new()
	crate.size = Vector3(1.8, 1.8, 1.8)
	var log_piece := CylinderMesh.new()
	log_piece.top_radius = 0.4
	log_piece.bottom_radius = 0.5
	log_piece.height = 4.5
	log_piece.radial_segments = 8
	log_piece.rings = 1
	var scrap := PrismMesh.new()
	scrap.size = Vector3(2.4, 2.8, 0.2)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	for shape: Mesh in [plank, crate, log_piece, scrap]:
		shape.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = shape
		mm.instance_count = DEBRIS_EACH
		for i in DEBRIS_EACH:
			mm.set_instance_color(i, DEBRIS_COLORS[randi() % DEBRIS_COLORS.size()])
		var bits := MultiMeshInstance3D.new()
		bits.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		bits.multimesh = mm
		bits.custom_aabb = AABB(Vector3(-110, 0, -110), Vector3(220, TWISTER_TOP + 10.0, 220))
		bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_twister.add_child(bits)
		_debris.append(mm)

	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.0
	drop.radial_segments = 6
	drop.rings = 3
	var spray_mat := StandardMaterial3D.new()
	spray_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.8)
	spray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = spray_mat
	_twister_spray = CPUParticles3D.new()
	_twister_spray.amount = 140
	_twister_spray.lifetime = 1.8
	_twister_spray.local_coords = false
	_twister_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_twister_spray.emission_ring_radius = 16.0
	_twister_spray.emission_ring_inner_radius = 8.0
	_twister_spray.emission_ring_height = 0.5
	_twister_spray.emission_ring_axis = Vector3.UP
	_twister_spray.direction = Vector3.UP
	_twister_spray.spread = 35.0
	_twister_spray.initial_velocity_min = 10.0
	_twister_spray.initial_velocity_max = 26.0
	_twister_spray.gravity = Vector3(0, -14, 0)
	_twister_spray.scale_amount_min = 0.6
	_twister_spray.scale_amount_max = 2.4
	_twister_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_twister_spray.mesh = drop
	_twister.add_child(_twister_spray)


## The radius debris whirls at, for a height from 0 at the sea to 1 near the top.
func _debris_reach(climb: float) -> float:
	return lerpf(14.0, 66.0, pow(climb, 2.0))


## Random shoves on a heavy body, so it drifts and curves but never jerks.
func _roam_twister(delta: float) -> void:
	_shove_wait -= delta
	if _shove_wait <= 0.0:
		_shove_wait = randf_range(1.5, 4.0)
		var ang := randf() * TAU
		_twister_shove = Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, 6.0)
	var home := TWISTER_HOME - _twister_pos
	var turn_back := home.normalized() * maxf(home.length() - TWISTER_ROAM, 0.0) * 0.2
	_twister_vel += (_twister_shove + turn_back) * delta
	_twister_vel *= exp(-TWISTER_MOMENTUM_LOSS * delta)
	_twister_vel = _twister_vel.limit_length(TWISTER_MAX_SPEED)
	_twister_pos += _twister_vel * delta
	_twister.global_position = _twister_pos


func _update_twister(delta: float) -> void:
	_roam_twister(delta)
	var core := _twister.global_position
	var target: Vector3 = player.global_position
	var radius: float = (HIT_RADIUS_OPEN if player.wings_open else HIT_RADIUS_CLOSED) * DEBRIS_HIT_SCALE
	var armed: bool = player.mode == player.Mode.AIR and player.has_launched
	for k in _debris.size():
		for i in DEBRIS_EACH:
			var n := k * DEBRIS_EACH + i
			var climb := fmod(_time * 0.08 + n * 0.0917, 1.0)
			var reach := _debris_reach(climb) + sin(n * 1.7) * 4.0
			var whirl := 3.4 - climb * 2.4
			var ang := n * 2.4 - _time * whirl
			var at := Vector3(cos(ang) * reach, 3.0 + climb * TWISTER_TOP * 0.82, sin(ang) * reach)
			if _time < _debris_back[n]:
				_debris[k].set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), at))
				continue
			if armed and (core + at).distance_squared_to(target) < radius * radius:
				_debris_back[n] = _time + DEBRIS_RESPAWN
				var heavy: bool = DEBRIS_HEAVY[k]
				_strike(Vector3(sin(ang), 0, -cos(ang)) * whirl * reach + _twister_vel, heavy, 1.0 if heavy else 0.5)
			var tumble := Vector3(_time * (2.0 + fmod(n * 0.37, 3.0)), n, _time * (1.5 + fmod(n * 0.53, 2.5)))
			_debris[k].set_instance_transform(i, Transform3D(Basis.from_euler(tumble), at))
	_ripple_wait -= delta
	if _ripple_wait <= 0.0:
		_ripple_wait = 0.45
		level.add_ripple(core, 1.0)

	var offset: Vector3 = player.global_position - core
	offset.y = 0.0
	var r := offset.length()
	tornado_closeness = clampf(1.0 - r / TWISTER_REACH, 0.0, 1.0)
	_fling_wait = maxf(_fling_wait - delta, 0.0)
	player.tornado_pull = Vector3.ZERO
	var airborne: bool = player.mode == player.Mode.AIR and player.has_launched
	if player.riding_twister:
		if airborne:
			_ride(core, delta)
		else:
			player.riding_twister = false
		return
	var height: float = player.global_position.y
	if not airborne or height > TWISTER_TOP or _fling_wait > 0.0:
		return
	var f := tornado_closeness
	if f <= 0.0:
		return
	var out := offset / maxf(r, 0.1)
	var around := Vector3(-out.z, 0, out.x)
	if r < TWISTER_CORE:
		player.riding_twister = true
		_ride_angle = atan2(out.z, out.x)
		sucked_in.emit()
		return
	# The air itself is spiralling in and up, and it drags you along with it,
	# harder the deeper you go, so speed bleeds off and you're drawn to the core.
	var flow := around * TWISTER_SWIRL - out * TWISTER_INFLOW + Vector3.UP * TWISTER_LIFT
	var grip: float = TWISTER_DRAG * (OPEN_GRIP if player.wings_open else 1.0)
	player.tornado_pull = (flow - player.velocity) * grip * f * f + Vector3.UP * player.gravity * f


## Up the inside of the funnel, whirling round the wall as it widens, then out of
## the top. Popping or tucking the wings on the way changes both the climb and exit.
func _ride(core: Vector3, delta: float) -> void:
	var open: bool = player.wings_open
	var pos: Vector3 = player.global_position
	var level_up := minf(pos.y + (CLIMB_OPEN if open else CLIMB_CLOSED) * delta, TWISTER_TOP)
	var rise := clampf(level_up / TWISTER_TOP, 0.0, 1.0)
	# Rides the wall, in among the debris, so the climb has to be survived.
	var reach := _debris_reach(rise) * 0.95
	_ride_angle += RIDE_SPEED / reach * delta
	var side := Vector3(cos(_ride_angle), 0, sin(_ride_angle))
	player.global_position = core + side * reach + Vector3.UP * level_up
	player.velocity = Vector3(-side.z, 0, side.x) * RIDE_SPEED + Vector3.UP * (CLIMB_OPEN if open else CLIMB_CLOSED)
	player.att = player.att.rotated(Vector3.UP, -RIDE_SPEED / reach * delta).orthonormalized()
	if level_up < TWISTER_TOP:
		return
	player.riding_twister = false
	_fling_wait = 8.0
	var spin_off := Vector3(-side.z, 0, side.x)
	var sideways: float = EJECT_OUT_OPEN if open else EJECT_OUT_CLOSED
	player.velocity = (side + spin_off).normalized() * sideways + Vector3.UP * (EJECT_UP_OPEN if open else EJECT_UP_CLOSED)
	player.att = Basis.looking_at(player.velocity.normalized(), Vector3.BACK)
	flung.emit()


## An expanding bubble of pressure: it hits when it reaches you, harder up close.
func _start_shock(at: Vector3) -> void:
	var bubble := SphereMesh.new()
	bubble.radius = 1.0
	bubble.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.75, 0.18)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = bubble
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.1
	add_child(mi)
	mi.global_position = at
	_shocks.append({"pos": at, "radius": 0.0, "mesh": mi, "mat": mat, "felt": false})


func _update_shocks(delta: float) -> void:
	for sh: Dictionary in _shocks.duplicate():
		sh.radius += SHOCK_SPEED * delta
		sh.mesh.scale = Vector3.ONE * sh.radius
		sh.mat.albedo_color.a = 0.18 * (1.0 - sh.radius / SHOCK_RANGE)
		var d: float = sh.pos.distance_to(player.global_position)
		if not sh.felt and sh.radius >= d:
			sh.felt = true
			if player.mode == player.Mode.AIR:
				var strength := pow(clampf(1.0 - d / SHOCK_RANGE, 0.0, 1.0), 2.0)
				player.shove(sh.pos, strength)
				shockwave.emit(strength)
		if sh.radius >= SHOCK_RANGE:
			sh.mesh.queue_free()
			_shocks.erase(sh)


func _shard_meshes() -> Array[Mesh]:
	var plate := PrismMesh.new()
	plate.size = Vector3(1.3, 3.2, 0.45)
	var slab := BoxMesh.new()
	slab.size = Vector3(1.8, 0.35, 1.1)
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.3
	pipe.bottom_radius = 0.3
	pipe.height = 2.6
	pipe.radial_segments = 8
	pipe.rings = 1
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.55
	spike.height = 2.4
	spike.radial_segments = 6
	spike.rings = 1
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 1.05
	ring.rings = 12
	ring.ring_segments = 6
	var lump := SphereMesh.new()
	lump.radius = 0.8
	lump.height = 1.6
	lump.radial_segments = 6
	lump.rings = 3
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.45
	mat.roughness = 0.35
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var meshes: Array[Mesh] = [plate, slab, pipe, spike, ring, lump]
	for m in meshes:
		m.surface_set_material(0, mat)
	return meshes


func _throw_shards(at: Vector3) -> void:
	var cloud := ShardCloud.new()
	for shape in _shard_meshes():
		var mi := MultiMeshInstance3D.new()
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mi.multimesh = MultiMesh.new()
		mi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mi.multimesh.use_colors = true
		mi.multimesh.mesh = shape
		mi.multimesh.instance_count = PER_SHAPE
		mi.custom_aabb = AABB(Vector3.ONE * -2000.0, Vector3.ONE * 4000.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		cloud.meshes.append(mi)
	cloud.pos.resize(SHARD_COUNT)
	cloud.vel.resize(SHARD_COUNT)
	cloud.size.resize(SHARD_COUNT)
	cloud.dead.resize(SHARD_COUNT)
	cloud.dead.fill(0)
	cloud.buffer.resize(SHARD_COUNT * BUFFER_STRIDE)
	for i in SHARD_COUNT:
		# Uniform over the sphere, so the odds fall with distance squared.
		var y := randf_range(-1.0, 1.0)
		var ang := randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang)) * sqrt(1.0 - y * y) + Vector3.UP * y
		cloud.pos[i] = at
		cloud.vel[i] = dir * randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX)
		cloud.size[i] = randf_range(0.9, 1.1) if i < HEAVY_SHARDS else randf_range(0.25, 0.5)
		cloud.paint(i, SHARD_COLORS[randi() % SHARD_COLORS.size()])
	_clouds.append(cloud)


func _update_clouds(delta: float) -> void:
	var target: Vector3 = player.global_position
	var radius: float = HIT_RADIUS_OPEN if player.wings_open else HIT_RADIUS_CLOSED
	var drag := exp(-SHARD_DRAG * delta)
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	for c: ShardCloud in _clouds.duplicate():
		c.age += delta
		c.frame += 1
		for i in SHARD_COUNT:
			if c.dead[i] == 1:
				continue
			var from := c.pos[i]
			var v := c.vel[i] * drag
			v.y -= SHARD_GRAVITY * delta
			var to := from + v * delta
			c.pos[i] = to
			c.vel[i] = v
			if to.y < 0.0:
				c.dead[i] = 1
				c.place(i, hidden)
				if i < HEAVY_SHARDS:
					level.add_ripple(to, 0.35)
				continue
			if (c.frame + i) % SPIN_EVERY == 0 or c.frame == 1:
				var spin := Basis.from_euler(Vector3(c.age * 5.0 + i, i, c.age * 3.0)).scaled(Vector3.ONE * c.size[i])
				c.place(i, Transform3D(spin, to))
			else:
				c.move(i, to)
			if from.distance_squared_to(target) > 900.0:
				continue
			var d := Geometry3D.get_closest_point_to_segment(target, from, to).distance_to(target)
			if d < radius * c.size[i]:
				c.dead[i] = 1
				c.place(i, hidden)
				_strike(v, i < HEAVY_SHARDS, c.size[i])
		c.upload()
		if c.age >= SHARD_LIFE or c.dead.count(1) == SHARD_COUNT:
			c.free_meshes()
			_clouds.erase(c)


## Hard hits from big chunks take open wings; everything else only shoves.
func _strike(shard_vel: Vector3, heavy: bool, shard_size: float) -> void:
	if player.mode != player.Mode.AIR:
		return
	var impact: Vector3 = shard_vel - player.velocity
	if not heavy or not player.wings_open or impact.length() < BUMP_SPEED:
		player.bump(impact * shard_size)
		shrapnel_bump.emit(impact)
	else:
		player.blast(player.global_position - impact.normalized())
		shrapnel_hit.emit(impact)


func _sparks(at: Vector3) -> void:
	# White-hot, and only for show: the shards are what can hurt you.
	var spark := BoxMesh.new()
	spark.size = Vector3(0.05, 1.3, 0.05)
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.8, 0.4)
	spark.material = hot
	var s := _burst(at, 40, 0.5, 20.0, 60.0, spark)
	s.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	s.gravity = Vector3(0, -10, 0)


func _burst(at: Vector3, amount: int, life: float, speed_min: float, speed_max: float, mesh: Mesh) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.mesh = mesh
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


func _explosion(at: Vector3) -> void:
	_throw_shards(at)
	_sparks(at)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 120
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 40.0
	p.damping_min = 12.0
	p.damping_max = 20.0
	p.gravity = Vector3(0, 2, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 0.95, 0.6), Color(1, 0.45, 0.1), Color(0.15, 0.13, 0.12, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	p.color_ramp = ramp
	var ball := SphereMesh.new()
	ball.radius = 0.45
	ball.height = 0.9
	ball.radial_segments = 8
	ball.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material = mat
	p.mesh = ball
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.65, 0.3)
	flash.light_energy = 24.0
	flash.omni_range = 70.0
	add_child(flash)
	flash.global_position = at
	var t := flash.create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.45)
	t.tween_callback(flash.queue_free)


func _add_clouds() -> void:
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var soft := GradientTexture2D.new()
	soft.gradient = fade
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = soft
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(26, 26)
	quad.material = mat
	var p := _weather_particles(70, 7.0)
	p.emission_box_extents = Vector3(70, 30, 70)
	p.spread = 180.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3.ZERO
	var alpha := Gradient.new()
	alpha.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.93, 0.95, 0.97, 0.3), Color(1, 1, 1, 0)])
	alpha.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = alpha
	p.mesh = quad


func _add_rain(wind: Vector3) -> void:
	var streak := BoxMesh.new()
	streak.size = Vector3(0.025, 2.2, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.88, 1.0, 0.4)
	streak.material = mat
	var p := _weather_particles(500, 1.0)
	p.emission_box_extents = Vector3(55, 30, 55)
	p.direction = (wind.normalized() * 1.6 + Vector3.DOWN).normalized()
	p.spread = 3.0
	p.initial_velocity_min = 42.0
	p.initial_velocity_max = 55.0
	p.gravity = Vector3.ZERO
	p.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	p.mesh = streak


func _weather_particles(amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_weather.append(p)
	return p
