extends Node3D
## Round flow for the game.

const LevelScript := preload("res://scripts/level.gd")
const PlayerScript := preload("res://scripts/player.gd")
const CameraScript := preload("res://scripts/camera_rig.gd")
const HudScript := preload("res://scripts/hud.gd")
const BloodScript := preload("res://scripts/blood.gd")
const ModifiersScript := preload("res://scripts/modifiers.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const MotionBlurScript := preload("res://scripts/motion_blur.gd")
const TargetScript := preload("res://scripts/target.gd")

const ROUNDS := 10
const RIPPLE_GAP := 0.1
const SPIN_TIME := 2.5
const SPIN_HOLD := 0.9
const STEP_GAP := 0.24

enum State { READY, RAMP, FLIGHT, LANDED, RESULT, GAME_OVER, ROULETTE }

var state := State.READY
var round_num := 1
var total := 0
var state_time := 0.0
var autoplay := false
var wind := Vector3.ZERO
var rng := RandomNumberGenerator.new()

var level: LevelScript
var player: PlayerScript
var cam: CameraScript
var hud: HudScript
var blood: BloodScript
var mods: ModifiersScript
var sfx: SfxScript
var blur: MotionBlurScript
var sun: DirectionalLight3D
var marker: MeshInstance3D
var env: Environment
var _auto_dropping := false
var _auto_target: Node3D
var _ripple_wait := 0.0
var _pending_mods: Array = []
var _spin_stopped := false
## Set by --mods=mines,cloud,hurricane,reverse to fix every roulette result.
var _forced_mods = null
var _stride := 0.0
var _step_wait := 0.0
var _bleeding := false
var _trail_last := Vector3.ZERO


func _ready() -> void:
	rng.randomize()
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	_read_forced_mods()
	_setup_input()
	_setup_environment()

	level = LevelScript.new()
	add_child(level)

	player = PlayerScript.new()
	add_child(player)
	player.ramp_body = level.ramp_body
	player.launched.connect(_on_launched)
	player.touched_down.connect(_on_touched_down)
	player.settled.connect(_on_settled)
	player.splashed.connect(_on_splashed)
	player.skimmed.connect(_on_skimmed)
	player.crashed.connect(_on_crashed)

	cam = CameraScript.new()
	cam.player = player
	cam.far = 4000.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.make_current()

	hud = HudScript.new()
	add_child(hud)

	blood = BloodScript.new()
	add_child(blood)

	mods = ModifiersScript.new()
	mods.player = player
	mods.level = level
	mods.detonated.connect(_on_mine_detonated)
	mods.beeped.connect(_on_mine_beeped)
	mods.shrapnel_hit.connect(_on_shrapnel_hit)
	mods.shrapnel_bump.connect(_on_shrapnel_bump)
	mods.shockwave.connect(_on_shockwave)
	mods.flung.connect(_on_flung)
	mods.sucked_in.connect(_on_sucked_in)
	add_child(mods)

	blur = MotionBlurScript.new()
	add_child(blur)

	sfx = SfxScript.new()
	add_child(sfx)
	hud.wheel.ticked.connect(sfx.play.bind("tick", 0.03))
	player.wings_changed.connect(_on_wings_changed)

	marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 1.0
	marker.mesh = torus
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.2, 0.3)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mm
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(marker)

	_start_round()


func _read_forced_mods() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mods="):
			_forced_mods = []
			for mod_name in arg.trim_prefix("--mods=").split(",", false):
				_forced_mods.append(ModifiersScript.Mod[mod_name.to_upper()])


func _setup_input() -> void:
	_action("up", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("down", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("wings", [KEY_SPACE], [JOY_BUTTON_A], [])
	_action("restart", [KEY_R], [JOY_BUTTON_BACK], [])
	_action("next", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START], [])
	_action("quit", [KEY_ESCAPE], [], [])
	_action("flier", [KEY_C], [JOY_BUTTON_Y], [])


func _action(n: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(n):
		return
	InputMap.add_action(n, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(n, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.device = -1
		e.button_index = b
		InputMap.action_add_event(n, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.device = -1
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(n, e)


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.12, 0.42, 0.95)
	psm.sky_horizon_color = Color(1.0, 0.84, 0.82)
	psm.ground_horizon_color = Color(0.72, 0.86, 1.0)
	psm.ground_bottom_color = Color(0.1, 0.3, 0.5)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if _web_renderer():
		env.tonemap_exposure = 0.62
		env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.86, 1.0)
	env.fog_density = 0.0006
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.light_energy = 1.1
	add_child(sun)


## A retry passes false: same modifiers, no spin, so it can't dodge a bad result.
## The Compatibility renderer, used on the web, lights the scene much brighter.
func _web_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


func _start_round(spin := true) -> void:
	state = State.READY
	state_time = 0.0
	_auto_dropping = false
	var strength := rng.randf_range(0.0, 1.5 + 0.5 * round_num)
	var ang := rng.randf_range(0.0, TAU)
	wind = Vector3(cos(ang), 0, sin(ang)) * strength
	player.wind = wind
	player.reset(level.start_position)
	player.input_override = null
	cam.snap()
	hud.set_status(round_num, ROUNDS, total)
	if autoplay:
		_auto_target = level.targets[rng.randi_range(0, 3)]
	if spin:
		_spin_roulette()
	else:
		_apply_modifiers(mods.active)


func _spin_roulette() -> void:
	mods.clear()
	hud.set_modifiers([])
	_pending_mods = ModifiersScript.roll(rng) if _forced_mods == null else _forced_mods
	_spin_stopped = false
	state = State.ROULETTE
	hud.spin_wheel("ROUND %d" % round_num, _wheel_slice(_pending_mods), SPIN_TIME)
	sfx.play("taiko")


func _wheel_slice(result: Array) -> int:
	if result.is_empty():
		return 0
	return result[0] + 1


func _roulette_title(result: Array) -> String:
	if result.is_empty():
		return "NO MODIFIER"
	return " + ".join(result.map(func(m: int) -> String: return ModifiersScript.NAMES[m]))


func _apply_modifiers(result: Array) -> void:
	mods.apply(result, rng)
	hud.set_modifiers(result.map(func(m: int) -> String: return ModifiersScript.NAMES[m]))
	if mods.has(ModifiersScript.Mod.HURRICANE):
		var ang := rng.randf_range(0.0, TAU)
		wind = Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(22.0, 30.0)
		player.wind = wind
		mods.start_storm(wind)
	if autoplay: print("modifiers %s" % [_roulette_title(result)])
	_show_round_banner()


func _show_round_banner() -> void:
	var active := mods.active
	if active.is_empty():
		hud.show_banner("ROUND %d" % round_num, "%s · {flier} to change flier" % player.body.look_name(), Color(1, 0.95, 0.4), 0.0)
	else:
		var blurb: String = "Good luck" if active.size() > 1 else ModifiersScript.BLURBS[active[0]]
		hud.show_banner(_roulette_title(active), blurb, Color(1, 0.8, 0.3), 0.0, 0.7)


func _process(delta: float) -> void:
	state_time += delta

	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart") and state != State.GAME_OVER and state != State.ROULETTE:
		_start_round(false)
		return

	match state:
		State.ROULETTE:
			_update_roulette()
		State.READY:
			if Input.is_action_just_pressed("flier"):
				player.body.set_look(player.body.look + 1)
				_show_round_banner()
			if state_time > 1.2 and state_time - delta <= 1.2:
				hud.show_banner("READY", "", Color(1, 0.95, 0.4), 0.0)
				sfx.play("ready")
			if state_time > 2.2:
				hud.show_banner("GO!", "", Color(1, 1, 1), 0.6, 0.8)
				sfx.play("go")
				player.release()
				state = State.RAMP
				state_time = 0.0
		State.RAMP:
			if state_time > 4.0 and player.velocity.length() < 0.5:
				_start_round(false)
				return
		State.RESULT:
			if state_time > 4.0 or Input.is_action_just_pressed("next") or Input.is_action_just_pressed("wings"):
				round_num += 1
				if round_num > ROUNDS:
					state = State.GAME_OVER
					state_time = 0.0
					mods.clear()
					hud.set_modifiers([])
					hud.show_banner("FINAL SCORE %d" % total, "Press {next} to play again", Color(1, 0.95, 0.4), 0.0, 1.0)
					sfx.play("perfect")
				else:
					_start_round()
		State.GAME_OVER:
			if Input.is_action_just_pressed("next") or (autoplay and state_time > 3.0):
				round_num = 1
				total = 0
				blood.clear()
				_start_round()

	if autoplay:
		_autopilot()
	_update_hud()
	_update_marker()
	_update_atmosphere()
	_update_ripples(delta)
	_update_gusts()
	mods.update(delta, cam.global_position)
	_update_audio(delta)
	blur.update(cam, player.focus_velocity(), delta)
	_update_blood_trail()


func _update_roulette() -> void:
	if Input.is_action_just_pressed("flier"):
		player.body.set_look(player.body.look + 1)
	var skip := autoplay or Input.is_action_just_pressed("wings") or Input.is_action_just_pressed("next")
	if not _spin_stopped and (skip or state_time >= SPIN_TIME):
		_spin_stopped = true
		state_time = SPIN_TIME
		hud.stop_wheel(_roulette_title(_pending_mods))
		sfx.play("taiko")
		if _pending_mods.is_empty():
			sfx.play("kira")
		else:
			sfx.play("modifier")
			sfx.play("yoo")
			hud.impact(0.8)
	elif _spin_stopped and (skip or state_time >= SPIN_TIME + SPIN_HOLD):
		hud.hide_wheel()
		state = State.READY
		state_time = 0.0
		_apply_modifiers(_pending_mods)


func _update_audio(delta: float) -> void:
	var airborne := player.mode == PlayerScript.Mode.AIR
	var rush := clampf((player.velocity.length() - 15.0) / 50.0, 0.0, 1.0) if airborne else 0.0
	sfx.set_loop("rush", rush * rush * 0.3, delta)
	sfx.set_loop_pitch("rush", 0.85 + rush * 0.35)
	var storm := 0.32 if mods.has(ModifiersScript.Mod.HURRICANE) else 0.0
	if mods.has(ModifiersScript.Mod.TORNADO):
		storm = maxf(storm, 0.12 + mods.tornado_closeness * 0.55)
	sfx.set_loop("storm", storm, delta)
	if mods.tornado_closeness > 0.35 and airborne:
		cam.shake((mods.tornado_closeness - 0.35) * 0.5)
	if player.mode == PlayerScript.Mode.GROUND:
		# One slap of the feet per half turn of the run cycle.
		_stride += player.body.run_rate * delta
		_step_wait -= delta
		if _stride >= PI:
			_stride = fmod(_stride, PI)
			# Feet blur past faster than you'd want to hear every one.
			if _step_wait <= 0.0:
				_step_wait = STEP_GAP
				sfx.play("step", 0.1, 0.16)


func _update_gusts() -> void:
	if mods.has(ModifiersScript.Mod.HURRICANE):
		player.wind = wind * (1.0 + 0.35 * sin(Time.get_ticks_msec() * 0.0013) * sin(Time.get_ticks_msec() * 0.0031))


func _update_ripples(delta: float) -> void:
	if player.mode != PlayerScript.Mode.AIR or player.ground_effect < 0.03:
		_ripple_wait = 0.0
		return
	_ripple_wait -= delta
	if _ripple_wait <= 0.0:
		_ripple_wait = RIPPLE_GAP
		level.add_ripple(player.global_position, clampf(player.ground_effect * 1.6, 0.25, 1.0))


## Smears the skid after a hard crash, for as long as the body keeps sliding.
func _update_blood_trail() -> void:
	if not _bleeding:
		return
	if player.mode != PlayerScript.Mode.RAGDOLL:
		_bleeding = false
		return
	var p := player.focus()
	var v := player.focus_velocity()
	if p.distance_to(_trail_last) < 1.4 or v.length() < 3.0:
		return
	_trail_last = p
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 2.0)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var s := randf_range(0.7, 1.4)
		blood.splat(hit.position, hit.normal, v, s * 2.0, s)


func _update_hud() -> void:
	hud.set_flight(player.global_position.y - level.TARGET_TOP,
		player.wings_open, player.mode == PlayerScript.Mode.AIR and not player.has_landed, player.wings_lost)
	var right := cam.global_basis.x
	right.y = 0
	var fwd := -cam.global_basis.z
	fwd.y = 0
	right = right.normalized()
	fwd = fwd.normalized()
	var w := Vector2(player.wind.dot(right), -player.wind.dot(fwd))
	hud.set_wind(w, player.wind.length())

	var v := player.focus_velocity()
	var speed := v.length()
	var climb := rad_to_deg(asin(clampf(v.y / speed, -1.0, 1.0))) if speed > 0.1 else 0.0
	var flying := player.mode == PlayerScript.Mode.AIR
	var skim_ready := flying and Vector2(v.x, v.z).length() >= player.skim_min_speed
	hud.set_velocity(speed, climb, player.bank if flying else 0.0, atan2(v.dot(right), v.dot(fwd)), skim_ready)


func _update_marker() -> void:
	var show := player.mode == PlayerScript.Mode.AIR and player.has_launched
	marker.visible = show
	if not show:
		return
	var from := player.get_global_transform_interpolated().origin
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 200.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3 = hit.position + Vector3.UP * 0.08 if hit else Vector3(from.x, 0.15, from.z)
	marker.global_position = p
	var s := clampf((from.y - p.y) * 0.04 + 0.6, 0.6, 2.5)
	marker.scale = Vector3(s, 1, s)


func _update_atmosphere() -> void:
	var color := Color(0.72, 0.86, 1.0)
	var density := 0.0006
	var sky := 0.0
	var light := 1.1
	if mods.has(ModifiersScript.Mod.HURRICANE):
		color = Color(0.42, 0.47, 0.53)
		density = 0.0035
		sky = 0.7
		light = 0.55
	if mods.has(ModifiersScript.Mod.TORNADO):
		color = Color(0.5, 0.53, 0.56)
		density = maxf(density, 0.0016)
		sky = 0.45
		light = 0.7
	if mods.has(ModifiersScript.Mod.CLOUD):
		color = Color(0.82, 0.85, 0.89)
		density = 0.012
		sky = 1.0
		light = 0.7
	if cam.global_position.y < 0.0:
		color = Color(0.03, 0.2, 0.34)
		density = 0.03
		sky = 1.0
	env.fog_light_color = color
	env.fog_density = density
	env.fog_sky_affect = sky
	sun.light_energy = light * (0.8 if _web_renderer() else 1.0)


func _on_launched() -> void:
	if autoplay: print("launch v=%.1f pos=%s" % [player.velocity.length(), player.global_position])
	state = State.FLIGHT
	state_time = 0.0
	hud.show_banner("FLY!", "{wings} to pop your wings", Color(1, 1, 1), 1.2, 0.9)
	sfx.play("launch")
	hud.pop("WHOOSH!", Color(0.6, 0.95, 1.0))


func _on_touched_down(_col: Object) -> void:
	if autoplay: print("touchdown v=%s flight=%.1fs" % [player.velocity, state_time])
	state = State.LANDED
	state_time = 0.0


func _on_mine_beeped(closeness: float) -> void:
	sfx.play("beep", 0.0, 0.2 + 0.5 * closeness)


func _on_mine_detonated() -> void:
	sfx.play("boom", 0.05, 0.8)
	hud.pop("KA-BOOM!", Color(1, 0.5, 0.2))


func _on_sucked_in() -> void:
	cam.shake(0.6)
	sfx.play("launch")
	hud.show_banner("SUCKED IN!", "Wings out to go higher", Color(1, 0.9, 0.5), 1.0, 0.7)


func _on_flung() -> void:
	cam.shake(1.0)
	hud.impact(1.1)
	sfx.play("yoo")
	sfx.play("launch")
	hud.show_banner("WHEEEE!", "Spat out of the top!", Color(0.7, 1.0, 0.8), 1.2)


func _on_shockwave(strength: float) -> void:
	cam.shake(strength * 3.5)
	hud.impact(strength * 1.6)
	sfx.play("crash", 0.1, 0.3 + strength * 0.7)


## Shrapnel drew blood: a jet from the struck side, and a stain on whatever is
## underneath.
func _bleed(impact: Vector3, severity: float) -> void:
	var at := player.global_position
	var struck := -impact.normalized()
	blood.spurt(player, at + struck * 0.5, struck, severity)
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 80.0)
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var s := 1.2 + severity * 2.5
		blood.splat(hit.position, hit.normal, player.velocity, s * 1.6, s)


func _on_shrapnel_hit(impact: Vector3) -> void:
	_bleed(impact, 0.8)
	cam.shake(1.3)
	sfx.play("crash")
	hud.show_banner("HIT!", "Your wings are gone!", Color(1, 0.8, 0.2), 1.1, 1.3)


func _on_shrapnel_bump(impact: Vector3) -> void:
	_bleed(impact, 0.25)
	cam.shake(0.4)
	sfx.play("crash", 0.1, 0.4)
	hud.pop("CLANG!", Color(1, 0.9, 0.5))


func _on_wings_changed(open: bool) -> void:
	if autoplay:
		return
	if open:
		sfx.play("wings")
		hud.pop("FWOOMP!", Color(1, 0.95, 0.5))
		hud.impact(0.45)
	else:
		sfx.play("kira", 0.0, 0.4)


func _on_crashed(at: Vector3, normal: Vector3, vel: Vector3) -> void:
	if autoplay: print("crash v=%.1f at=%s" % [vel.length(), at])
	var severity := clampf((vel.length() - player.crash_speed) / 35.0, 0.0, 1.0)
	blood.crash(at, normal, vel, severity)
	sfx.play("crash", 0.08)
	hud.impact(0.8 + severity * 0.8)
	cam.shake(0.25 + severity * 0.5)
	hud.pop("SPLAT!", Color(1, 0.3, 0.3))
	_bleeding = true
	_trail_last = at


func _on_settled() -> void:
	# Score where the ragdoll's torso came to rest.
	var p := player.focus()
	var score := 0
	for t in level.targets:
		var top: float = t.global_position.y
		if p.y > top - 0.5 and p.y < top + 2.5:
			score = maxi(score, t.score_at(p))
	if autoplay: print("settled score=%d pos=%s" % [score, p])
	total += score
	state = State.RESULT
	state_time = 0.0
	cam.orbit = true
	hud.set_status(round_num, ROUNDS, total)
	if score > 0:
		var praise := "Nice landing!" if score < 100 else "BULLSEYE!" if score >= 300 else "Great shot!"
		hud.show_banner("+%d" % score, praise, Color(1, 0.95, 0.4), 0.0, 0.9)
		sfx.play("perfect" if score >= 100 else "score")
	else:
		hud.show_banner("MISS", "Off target", Color(0.8, 0.85, 1.0), 0.0)
		sfx.play("miss")


func _on_splashed() -> void:
	if autoplay: print("splash pos=%s t=%.1f" % [player.global_position, state_time])
	level.add_ripple(player.global_position, 1.0)
	state = State.RESULT
	state_time = 0.0
	cam.orbit = true
	hud.show_banner("SPLASH!", "Into the drink…", Color(0.7, 0.92, 1.0), 1.5, 0.7)
	sfx.play("splash", 0.06)
	sfx.play("miss", 0.0, 0.7)


func _on_skimmed() -> void:
	if autoplay: print("skim v=%.1f pos=%s" % [player.velocity.length(), player.global_position])
	hud.show_banner("SKIM!", "", Color(0.7, 0.95, 1.0), 0.4, 0.5)
	sfx.play("skim", 0.08)
	hud.pop("BOING!", Color(0.6, 1.0, 0.8))
	level.add_ripple(player.global_position, 1.0)


func _autopilot() -> void:
	var inp := Vector2.ZERO
	match state:
		State.RAMP:
			inp.y = -1.0
		State.FLIGHT:
			var to := _auto_target.global_position - player.global_position
			to.y = 0
			var hv := Vector3(player.velocity.x, 0, player.velocity.z)
			if hv.length() > 1.0 and player.wings_open:
				var want := clampf(rad_to_deg(-hv.signed_angle_to(to, Vector3.UP)) * 2.0, -35.0, 35.0)
				inp.x = clampf((want - player.bank) / 20.0, -1.0, 1.0)
			if not _auto_dropping:
				if not player.wings_open and player.air_time > 0.4:
					player.set_wings(true)
				var alt := player.global_position.y - level.TARGET_TOP
				var t_fall := sqrt(2.0 * maxf(alt, 0.1) / (player.gravity * (1.0 - player.swan_lift)))
				if to.length() < hv.length() * t_fall * 0.7:
					player.set_wings(false)
					_auto_dropping = true
				elif alt < 6.0:
					player.set_wings(false)
					_auto_dropping = true
			elif not player.wings_open and player.global_position.y - level.TARGET_TOP < 5.0 and player.velocity.y < 0.0:
				player.set_wings(true)
	player.input_override = inp
