extends CanvasLayer
## Welcome page, pause menu and controls panel. Runs while the tree is paused.

const FONT := preload("res://assets/fonts/DelaGothicOne-Regular.ttf")
const CRIMSON := Color(0.78, 0.05, 0.13)
const INK := Color(0.05, 0.06, 0.1)
const DIM_TITLE := 0.35
const DIM_PAUSE := 0.6
## Action, keyboard, gamepad. {names} fill in from the connected pad.
const CONTROLS := [
	["Push / speed up", "W or UP", "Stick or D-pad up"],
	["Steer / roll", "A D or LEFT RIGHT", "Stick or D-pad left, right"],
	["Pull up (hold to loop)", "S or DOWN", "Stick or D-pad down"],
	["Wings", "SPACE", "{wings} or shoulder buttons"],
	["Skip / next", "ENTER or SPACE", "{next}"],
	["Change flier", "C", "{flier}"],
	["Retry round", "R", "{retry}"],
	["Pause", "ESC or P", "{pause}"],
]

var game: Node
var hud: Node
var _dim: ColorRect
var _title: Control
var _title_list: VBoxContainer
var _pause: Control
var _pause_list: VBoxContainer
var _retry: Button
var _controls: PanelContainer
var _grid: GridContainer
var _back: Button
var _notice: Label
var _return_focus: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Theme.new()
	root.theme.default_font = FONT
	add_child(root)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(INK, DIM_TITLE)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dim)

	_title = _screen(root)
	_label(_title, "GLIDER", 132, Color.WHITE, 22)
	_rule(_title)
	_title_list = _list(_title)
	_button(_title_list, "START", _on_start)
	_button(_title_list, "CONTROLS", _open_controls)
	_quit_button(_title_list)

	_pause = _screen(root)
	_label(_pause, "PAUSED", 76, Color.WHITE, 16)
	_rule(_pause)
	_pause_list = _list(_pause)
	_button(_pause_list, "RESUME", resume)
	_retry = _button(_pause_list, "RETRY ROUND", _on_retry)
	_button(_pause_list, "CONTROLS", _open_controls)
	_button(_pause_list, "QUIT TO TITLE", game.quit_to_title)
	_quit_button(_pause_list)

	_build_controls(root)

	_notice = Label.new()
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice.offset_bottom = -56.0
	_notice.add_theme_font_size_override("font_size", 20)
	_notice.add_theme_color_override("font_outline_color", INK)
	_notice.add_theme_constant_override("outline_size", 8)
	_notice.modulate.a = 0.0
	root.add_child(_notice)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		_on_joy_connection_changed(device, true)
	_show(null)


func _input(event: InputEvent) -> void:
	# The HUD sleeps with the tree, but prompts must still follow the player.
	if get_tree().paused:
		hud._input(event)
	if event.is_echo():
		return
	if _controls.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			_close_controls()
			get_viewport().set_input_as_handled()
	elif _title.visible:
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
			_on_start()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		if get_tree().paused:
			resume()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func show_title() -> void:
	_dim.color.a = DIM_TITLE
	_show(_title)
	_title_list.get_child(0).grab_focus()


func resume() -> void:
	get_tree().paused = false
	_show(null)


func _open_pause() -> void:
	get_tree().paused = true
	_dim.color.a = DIM_PAUSE
	_retry.visible = game.can_retry()
	_show(_pause)
	_pause_list.get_child(0).grab_focus()


func _on_start() -> void:
	_show(null)
	game.start_game()


func _on_retry() -> void:
	resume()
	game._start_round(false)


func _open_controls() -> void:
	_return_focus = get_viewport().gui_get_focus_owner() as Button
	_fill_controls()
	_controls.visible = true
	_title.visible = false
	_pause.visible = false
	_back.grab_focus()


func _close_controls() -> void:
	_controls.visible = false
	_show(_pause if get_tree().paused else _title)
	if _return_focus:
		_return_focus.grab_focus()


func _show(screen: Control) -> void:
	_title.visible = screen == _title
	_pause.visible = screen == _pause
	_controls.visible = false
	_dim.visible = screen != null


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected or Input.is_joy_known(device):
		return
	_notice.text = "Unrecognised controller: buttons may differ. See Controls in the menu."
	_notice.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(5.0)
	t.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _fill_controls() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var names: Dictionary = hud.pad_names()
	var pad_on: bool = hud.gamepad
	_cell("", Color.WHITE)
	_cell("KEYBOARD", Color(1, 0.95, 0.4) if not pad_on else Color(0.7, 0.72, 0.78))
	_cell("GAMEPAD", Color(1, 0.95, 0.4) if pad_on else Color(0.7, 0.72, 0.78))
	for row: Array in CONTROLS:
		_cell(row[0], Color.WHITE)
		_cell(row[1], Color.WHITE if not pad_on else Color(0.7, 0.72, 0.78))
		_cell(row[2].format(names), Color.WHITE if pad_on else Color(0.7, 0.72, 0.78))


func _cell(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	_grid.add_child(l)


func _build_controls(root: Control) -> void:
	_controls = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(INK, 0.94)
	box.border_color = CRIMSON
	box.set_border_width_all(4)
	box.set_content_margin_all(28)
	_controls.add_theme_stylebox_override("panel", box)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_controls.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_controls)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	_controls.add_child(stack)
	_label(stack, "CONTROLS", 40, Color.WHITE, 10)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 36)
	_grid.add_theme_constant_override("v_separation", 8)
	stack.add_child(_grid)
	_back = _button(stack, "BACK", _close_controls)


func _screen(root: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	root.add_child(v)
	return v


func _list(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	return v


func _label(parent: Control, text: String, size: int, color: Color, outline: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", CRIMSON)
	l.add_theme_constant_override("outline_size", outline)
	parent.add_child(l)


func _rule(parent: Control) -> void:
	var r := ColorRect.new()
	r.color = CRIMSON
	r.custom_minimum_size = Vector2(0, 6)
	parent.add_child(r)


func _button(parent: Control, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 54)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_stylebox_override("normal", _button_box(Color(INK, 0.8)))
	b.add_theme_stylebox_override("hover", _button_box(Color(CRIMSON, 0.7)))
	b.add_theme_stylebox_override("pressed", _button_box(CRIMSON))
	b.add_theme_stylebox_override("focus", _button_box(CRIMSON))
	b.pressed.connect(pressed)
	parent.add_child(b)
	return b


func _button_box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.skew = Vector2(0.2, 0)
	return s


func _quit_button(parent: Control) -> void:
	if not OS.has_feature("web"):
		_button(parent, "QUIT GAME", get_tree().quit)
