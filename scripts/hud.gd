extends CanvasLayer
## On-screen info in a loud anime style: round, score, flight readouts, wind,
## slammed banners, speed lines and manga sound-effect text.

const FONT := preload("res://assets/fonts/DelaGothicOne-Regular.ttf")
const CRIMSON := Color(0.78, 0.05, 0.13)
## Banners sit this far above centre, to leave the flier in view.
const BANNER_LIFT := 150.0

class WindArrow extends Control:
	var dir := Vector2.ZERO
	var strength := 0.0

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 36.0, Color(0, 0, 0, 0.35))
		draw_arc(c, 36.0, 0, TAU, 48, Color(1, 1, 1, 0.6), 2.0)
		if strength < 0.2:
			draw_circle(c, 5.0, Color.WHITE)
			return
		var d := dir.normalized()
		var length := 10.0 + minf(strength, 8.0) * 3.0
		var tip := c + d * length
		var tail := c - d * length * 0.7
		var perp := Vector2(-d.y, d.x)
		draw_line(tail, tip - d * 6.0, Color.WHITE, 4.0)
		draw_colored_polygon(PackedVector2Array([tip + d * 4.0, tip - d * 8.0 + perp * 8.0, tip - d * 8.0 - perp * 8.0]), Color.WHITE)


const KEYBOARD_HELP := "Ramp: W push · A/D steer      Air: SPACE wings · S pull up (hold to loop) · W push · A/D roll      R retry"
const GAMEPAD_HELP := "Left stick: up push · left/right steer · down pull up (hold to loop)      A wings      OPTIONS retry"
const KEYBOARD_NAMES := {"wings": "SPACE", "next": "ENTER", "flier": "C"}
const GAMEPAD_NAMES := {"wings": "A", "next": "MENU", "flier": "Y"}

class VelocityGimbal extends Control:
	const RADIUS := 62.0
	const MAX_SPEED := 60.0
	const SKY := Color(0.3, 0.6, 0.95, 0.85)
	const SEA := Color(0.05, 0.3, 0.45, 0.9)
	const SKIM := Color(0.4, 0.95, 1.0)

	var speed := 0.0
	var climb := 0.0
	var roll := 0.0
	var heading := 0.0
	var skim_ready := false

	func _draw() -> void:
		var c := size * 0.5
		var circle := PackedVector2Array()
		for i in 48:
			circle.append(c + Vector2.from_angle(TAU * i / 48.0) * RADIUS)
		draw_colored_polygon(circle, SKY)

		# The horizon drops as you climb and tilts against your roll.
		var along := Vector2.from_angle(deg_to_rad(-roll))
		var down := -along.orthogonal()
		var drop := clampf(climb / 90.0, -0.95, 0.95) * RADIUS
		var mid := c + down * drop
		var sea := PackedVector2Array([mid - along * 200.0, mid + along * 200.0,
			mid + along * 200.0 + down * 200.0, mid - along * 200.0 + down * 200.0])
		for poly in Geometry2D.intersect_polygons(circle, sea):
			draw_colored_polygon(poly, SEA)
		var half := sqrt(RADIUS * RADIUS - drop * drop)
		draw_line(mid - along * half, mid + along * half, Color.WHITE, 2.0, true)
		draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.8), 2.0, true)

		# Speed arc: fills clockwise, and turns cyan when fast enough to skim.
		var start := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		draw_arc(c, RADIUS + 8.0, start, start + sweep, 48, Color(0, 0, 0, 0.4), 6.0, true)
		if speed > 0.5:
			var fill := minf(speed / MAX_SPEED, 1.0)
			draw_arc(c, RADIUS + 8.0, start, start + sweep * fill, 48, SKIM if skim_ready else Color.WHITE, 6.0, true)

		# Arrow: travel direction seen from the camera, up being straight ahead.
		if speed < 1.0:
			draw_circle(c, 5.0, Color.WHITE)
			return
		var d := Vector2.from_angle(heading - PI / 2.0)
		var perp := Vector2(-d.y, d.x)
		var tip := c + d * (RADIUS - 8.0)
		var outline := Color(0, 0, 0, 0.7)
		draw_line(c - d * 14.0, tip - d * 10.0, outline, 8.0, true)
		draw_line(c - d * 14.0, tip - d * 10.0, Color(1, 0.9, 0.3), 5.0, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 16.0 + perp * 11.0, tip - d * 16.0 - perp * 11.0]), Color(1, 0.9, 0.3))


## The radial lines manga uses for impact, redrawn on twos like limited animation.
class SpeedLines extends Control:
	var strength := 0.0:
		set(value):
			strength = value
			queue_redraw()
	var _wait := 0.0

	func _process(delta: float) -> void:
		_wait -= delta
		if strength > 0.01 and _wait <= 0.0:
			_wait = 1.0 / 12.0
			queue_redraw()

	func _draw() -> void:
		if strength <= 0.01:
			return
		var c := size * 0.5
		var reach := size.length() * 0.6
		for i in 80:
			var a := randf() * TAU
			var inner := randf_range(190.0, 340.0) * (1.4 - strength * 0.4)
			var w := randf_range(0.003, 0.02)
			draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(a) * inner,
				c + Vector2.from_angle(a - w) * reach, c + Vector2.from_angle(a + w) * reach]),
				Color(0.04, 0.02, 0.06, 0.85 * strength))


## Slanted HUD plates and the crimson slash behind banners.
class Deco extends Control:
	var stripe := 0.0:
		set(value):
			stripe = value
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var plate := Color(0.03, 0.02, 0.06, 0.62)
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(340, 0), Vector2(296, 112), Vector2(0, 112)]), plate)
		draw_line(Vector2(0, 112), Vector2(296, 112), CRIMSON, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(w - 300, 0), Vector2(w, 0), Vector2(w, 100), Vector2(w - 262, 100)]), plate)
		draw_line(Vector2(w - 262, 100), Vector2(w, 100), CRIMSON, 4.0)
		draw_rect(Rect2(0, h - 46, w, 46), plate)
		draw_line(Vector2(0, h - 46), Vector2(w, h - 46), CRIMSON, 3.0)
		if stripe <= 0.01:
			return
		var mid := h * 0.5 - BANNER_LIFT
		var half := 92.0 * stripe
		var slant := 60.0
		var quad := PackedVector2Array([Vector2(-slant, mid - half + slant * 0.4), Vector2(w + slant, mid - half - slant * 0.4),
			Vector2(w + slant, mid + half - slant * 0.4), Vector2(-slant, mid + half + slant * 0.4)])
		draw_colored_polygon(quad, Color(CRIMSON, 0.9))
		draw_line(quad[0], quad[1], Color.WHITE, 5.0, true)
		draw_line(quad[3], quad[2], Color.WHITE, 5.0, true)


class RouletteWheel extends Control:
	signal ticked

	const RADIUS := 200.0
	const TICK_ARC := TAU / 28.0
	# Slice sizes match the real odds, so the wheel never lies.
	const SLICES := [
		["NONE", 0.6667, Color(0.93, 0.52, 0.65)],
		["MINES", 0.0467, Color(0.78, 0.05, 0.13)],
		["CLOUD", 0.0467, Color(0.55, 0.6, 0.68)],
		["ALL", 0.1, Color(0.95, 0.72, 0.1)],
		["STORM", 0.0467, Color(0.15, 0.25, 0.65)],
		["REVERSE", 0.0466, Color(0.5, 0.2, 0.68)],
		["TORNADO", 0.0466, Color(0.2, 0.55, 0.4)],
	]

	var angle := 0.0:
		set(value):
			angle = value
			var tick := int(value / TICK_ARC)
			if tick != _tick:
				_tick = tick
				ticked.emit()
			queue_redraw()
	var _tick := 0

	func _draw() -> void:
		var c := size * 0.5
		var font := get_theme_default_font()
		draw_circle(c, RADIUS + 12.0, Color(0.05, 0.06, 0.1, 0.92), true, -1.0, true)
		var from := angle
		for s in SLICES:
			var sweep: float = TAU * s[1]
			var fan := PackedVector2Array([c])
			var steps := maxi(int(sweep * 24.0), 2)
			for i in steps + 1:
				fan.append(c + Vector2.from_angle(from + sweep * i / steps) * RADIUS)
			draw_colored_polygon(fan, s[2])
			draw_line(c, c + Vector2.from_angle(from) * RADIUS, Color(1, 1, 1, 0.8), 2.0, true)
			draw_set_transform(c, from + sweep * 0.5)
			draw_string_outline(font, Vector2(62, 8), s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(62, 8), s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
			draw_set_transform(Vector2.ZERO)
			from += sweep
		draw_arc(c, RADIUS, 0, TAU, 96, Color.WHITE, 4.0, true)
		draw_circle(c, 40.0, Color(0.05, 0.06, 0.1), true, -1.0, true)
		draw_arc(c, 40.0, 0, TAU, 40, Color.WHITE, 3.0, true)
		var tip := c + Vector2.UP * (RADIUS - 22.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-20, -44), tip + Vector2(20, -44)]), Color(1, 0.95, 0.4))

	## The final angle that puts a random spot in this slice under the pointer.
	func stop_angle(slice: int) -> float:
		var start := 0.0
		for i in slice:
			start += TAU * SLICES[i][1]
		var sweep: float = TAU * SLICES[slice][1]
		return -PI / 2.0 - start - sweep * randf_range(0.15, 0.85) + TAU * 6.0


var gamepad := false
var round_label: Label
var score_label: Label
var velocity_label: Label
var path_label: Label
var gimbal: VelocityGimbal
var alt_label: Label
var wings_label: Label
var wind_label: Label
var banner: Label
var sub_banner: Label
var help: Label
var wind_arrow: WindArrow
var mods_label: Label
var lines: SpeedLines
var deco: Deco
var flash: ColorRect
var _hud_root: Control
var _slam_tween: Tween
var _impact_tween: Tween
var wheel: RouletteWheel
var wheel_title: Label
var wheel_result: Label
var _wheel_tween: Tween
var _wheel_stop := 0.0
var _banner_tween: Tween
var _sub_text := ""
var _banner_box: VBoxContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Theme.new()
	root.theme.default_font = FONT
	add_child(root)
	_hud_root = root

	deco = Deco.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(deco)
	lines = SpeedLines.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lines)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 1, 1, 0)
	root.add_child(flash)

	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 18)
	root.add_child(tl)
	round_label = _label(tl, 26)
	score_label = _label(tl, 36, Color(1, 0.9, 0.3))
	var vel := VBoxContainer.new()
	vel.custom_minimum_size.x = 170
	vel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tl.add_child(vel)
	gimbal = VelocityGimbal.new()
	gimbal.custom_minimum_size = Vector2(170, 150)
	gimbal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vel.add_child(gimbal)
	velocity_label = _label(vel, 30)
	path_label = _label(vel, 20)
	for l in [velocity_label, path_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var tr := VBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.offset_left = -320
	tr.offset_right = -24
	tr.offset_top = 18
	root.add_child(tr)
	alt_label = _label(tr, 30)
	wings_label = _label(tr, 26)
	mods_label = _label(tr, 24, Color(1, 0.6, 0.25))
	for l in [alt_label, wings_label, mods_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	wind_arrow = WindArrow.new()
	wind_arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wind_arrow.offset_left = -45
	wind_arrow.offset_right = 45
	wind_arrow.offset_top = 12
	wind_arrow.offset_bottom = 102
	root.add_child(wind_arrow)
	wind_label = _label(root, 20)
	wind_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wind_label.offset_left = -120
	wind_label.offset_right = 120
	wind_label.offset_top = 102
	wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -BANNER_LIFT * 2.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	_banner_box = col
	banner = _label(col, 84, Color(1, 0.95, 0.4))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_banner = _label(col, 28)
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	help = _label(root, 20, Color(1, 1, 1, 0.85))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -40
	help.offset_bottom = -12
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	wheel = RouletteWheel.new()
	wheel.set_anchors_preset(Control.PRESET_CENTER)
	wheel.offset_left = -230
	wheel.offset_right = 230
	wheel.offset_top = -218
	wheel.offset_bottom = 242
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.visible = false
	root.add_child(wheel)
	wheel_title = _label(wheel, 34, Color(1, 0.95, 0.4))
	wheel_title.position = Vector2(0, -44)
	wheel_title.size.x = 460
	wheel_result = _label(wheel, 34)
	wheel_result.position = Vector2(0, 450)
	wheel_result.size.x = 460
	for l in [wheel_title, wheel_result]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	gamepad = not Input.get_connected_joypads().is_empty()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh_prompts()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_set_gamepad(false)
	elif event is InputEventJoypadButton:
		_set_gamepad(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_set_gamepad(true)


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	_set_gamepad(connected or not Input.get_connected_joypads().is_empty())


func _set_gamepad(value: bool) -> void:
	if value == gamepad:
		return
	gamepad = value
	_refresh_prompts()


func _refresh_prompts() -> void:
	help.text = GAMEPAD_HELP if gamepad else KEYBOARD_HELP
	sub_banner.text = _sub_text.format(GAMEPAD_NAMES if gamepad else KEYBOARD_NAMES)


func _label(parent: Control, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(size / 5, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func set_status(round_num: int, rounds: int, total: int) -> void:
	round_label.text = "ROUND %d / %d" % [mini(round_num, rounds), rounds]
	score_label.text = "SCORE %d" % total


## A hit worth drawing attention to: speed lines, plus a white frame if hard enough.
func impact(strength: float) -> void:
	if _impact_tween:
		_impact_tween.kill()
	lines.strength = minf(strength, 1.0)
	flash.color.a = clampf(strength - 0.5, 0.0, 0.8)
	_impact_tween = create_tween().set_parallel(true)
	_impact_tween.tween_property(lines, "strength", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_impact_tween.tween_property(flash, "color:a", 0.0, 0.18)


## Comic sound-effect lettering stamped over the action.
func pop(text: String, color := Color.WHITE) -> void:
	var l := _label(_hud_root, 60, color)
	l.add_theme_constant_override("outline_size", 16)
	l.text = text
	var vp := _hud_root.size
	l.position = Vector2(vp.x * randf_range(0.15, 0.62), vp.y * randf_range(0.2, 0.62))
	l.rotation = randf_range(-0.3, 0.3)
	l.pivot_offset = l.get_minimum_size() * 0.5
	l.scale = Vector2.ONE * 2.2
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.45)
	t.tween_property(l, "modulate:a", 0.0, 0.2)
	t.tween_callback(l.queue_free)


func spin_wheel(title: String, slice: int, duration: float) -> void:
	show_banner("", "", Color.WHITE, 0.0)
	wheel.visible = true
	wind_arrow.visible = false
	wind_label.visible = false
	wheel_title.text = title
	wheel_result.text = ""
	wheel.angle = fposmod(wheel.angle, TAU)
	_wheel_stop = wheel.stop_angle(slice)
	_wheel_tween = create_tween()
	_wheel_tween.tween_property(wheel, "angle", _wheel_stop, duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func stop_wheel(result: String) -> void:
	if _wheel_tween:
		_wheel_tween.kill()
	wheel.angle = _wheel_stop
	wheel_result.text = result


func hide_wheel() -> void:
	wheel.visible = false
	wind_arrow.visible = true
	wind_label.visible = true


func set_modifiers(names: Array) -> void:
	mods_label.text = "\n".join(names)


func set_flight(alt: float, wings: bool, show_wings: bool, lost: bool) -> void:
	alt_label.text = "ALT %d m" % int(maxf(alt, 0.0))
	wings_label.text = ("WINGS GONE!" if lost else "WINGS OPEN" if wings else "wings closed") if show_wings else ""
	wings_label.add_theme_color_override("font_color", Color(1, 0.35, 0.25) if lost else Color(0.5, 1, 0.5) if wings else Color(0.8, 0.8, 0.8))


func set_velocity(speed: float, climb: float, roll: float, heading: float, skim_ready: bool) -> void:
	gimbal.speed = speed
	gimbal.climb = climb
	gimbal.roll = roll
	gimbal.heading = heading
	gimbal.skim_ready = skim_ready
	gimbal.queue_redraw()
	velocity_label.text = "%d km/h" % int(speed * 3.6)
	if speed < 1.0:
		path_label.text = "STOPPED"
	elif absf(climb) < 5.0:
		path_label.text = "LEVEL"
	else:
		path_label.text = "%s %d°" % ["CLIMBING" if climb > 0.0 else "DIVING", int(absf(climb))]


func set_wind(screen_dir: Vector2, strength: float) -> void:
	wind_arrow.dir = screen_dir
	wind_arrow.strength = strength
	wind_arrow.queue_redraw()
	wind_label.text = "WIND %.1f m/s" % strength


func show_banner(text: String, sub := "", color := Color(1, 0.95, 0.4), hold := 1.4, punch := 0.0) -> void:
	if _banner_tween:
		_banner_tween.kill()
	if _slam_tween:
		_slam_tween.kill()
	if punch > 0.0:
		impact(punch)
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	_sub_text = sub
	_refresh_prompts()
	banner.modulate.a = 1.0
	sub_banner.modulate.a = 1.0
	deco.stripe = 0.0
	if text != "":
		# Slams down: lands on the next frame, once the box knows its new size.
		_banner_box.scale = Vector2.ONE * 2.0
		_slam_tween = create_tween().set_parallel(true)
		_slam_tween.tween_property(_banner_box, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_slam_tween.tween_property(deco, "stripe", 1.0, 0.12)
		_center_banner_pivot.call_deferred()
	if hold > 0.0:
		_banner_tween = create_tween()
		_banner_tween.tween_interval(hold)
		_banner_tween.set_parallel(true)
		_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)
		_banner_tween.tween_property(sub_banner, "modulate:a", 0.0, 0.4)
		_banner_tween.tween_property(deco, "stripe", 0.0, 0.3)


func _center_banner_pivot() -> void:
	_banner_box.pivot_offset = _banner_box.size * 0.5
