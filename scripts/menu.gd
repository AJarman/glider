extends CanvasLayer
## Welcome page, pause menu and controls panel. Runs while the tree is paused.

const FONT := preload("res://assets/fonts/DelaGothicOne-Regular.ttf")
const HumanoidScript := preload("res://scripts/humanoid.gd")
const MAX_PLAYERS := 4
const NAME_LENGTH := 10
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
	["Choose spins (score x1 to x5)", "A D or LEFT RIGHT", "Stick or D-pad left, right"],
	["Skip / next / spin", "ENTER or SPACE", "{next}"],
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
var _setup: Control
var _rows: VBoxContainer
var _add: Button
var _go: Button
## Who's playing, kept between games: [{"name", "look"}].
var _roster: Array = [{"name": "PLAYER 1", "look": 0}]
var _results: Control
var _results_grid: GridContainer
var _again: Button


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

	_build_setup(root)
	_build_results(root)
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
	elif _setup.visible:
		if event.is_action_pressed("ui_cancel"):
			show_title()
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
			_on_go()
			get_viewport().set_input_as_handled()
	elif _results.visible:
		pass
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
	_dim.color.a = DIM_TITLE
	_fill_rows()
	_show(_setup)
	_go.grab_focus()


func _on_go() -> void:
	for i in _roster.size():
		if _roster[i].name.strip_edges() == "":
			_roster[i].name = "PLAYER %d" % (i + 1)
	_show(null)
	game.start_game(_roster)


## Shows the final standings, best first. rows: [{"name", "total", "code"}].
func show_results(rows: Array) -> void:
	for c in _results_grid.get_children():
		_results_grid.remove_child(c)
		c.queue_free()
	for h in ["", "PLAYER", "SCORE", "CODE"]:
		_cell(h, Color(0.7, 0.72, 0.78), _results_grid)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var col := Color(1, 0.95, 0.4) if i == 0 else Color.WHITE
		_cell("#%d" % (i + 1), col, _results_grid, 26)
		_cell(r.name, col, _results_grid, 26)
		_cell(str(r.total), col, _results_grid, 26)
		_cell(r.code, Color(0.6, 0.95, 1.0), _results_grid, 26)
	_dim.color.a = DIM_PAUSE
	_show(_results)
	_again.grab_focus()


func _build_setup(root: Control) -> void:
	_setup = _screen(root)
	_label(_setup, "WHO'S FLYING?", 60, Color.WHITE, 14)
	_rule(_setup)
	_rows = _list(_setup)
	var list := _list(_setup)
	_add = _button(list, "ADD PLAYER", _add_player)
	_go = _button(list, "GO!", _on_go)
	_button(list, "BACK", show_title)


func _fill_rows() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for i in _roster.size():
		var p: Dictionary = _roster[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rows.add_child(row)
		var edit := LineEdit.new()
		edit.text = p.name
		edit.max_length = NAME_LENGTH
		edit.custom_minimum_size = Vector2(260, 50)
		edit.add_theme_font_size_override("font_size", 24)
		edit.add_theme_stylebox_override("normal", _button_box(Color(INK, 0.8)))
		edit.add_theme_stylebox_override("focus", _button_box(CRIMSON))
		edit.select_all_on_focus = true
		edit.text_changed.connect(_on_name_changed.bind(edit, p))
		row.add_child(edit)
		var look := _small_button(row, "", Callable())
		look.custom_minimum_size.x = 170
		look.text = _look_text(p.look)
		look.pressed.connect(_cycle_look.bind(p, look, 1))
		look.gui_input.connect(_on_look_input.bind(p, look))
		look.focus_entered.connect(func() -> void: game.player.body.set_look(p.look))
		if _roster.size() > 1:
			_small_button(row, "X", _remove_player.bind(i)).custom_minimum_size.x = 54
	_add.visible = _roster.size() < MAX_PLAYERS


func _on_name_changed(text: String, edit: LineEdit, p: Dictionary) -> void:
	var caret := edit.caret_column
	edit.text = text.to_upper()
	edit.caret_column = caret
	p.name = edit.text


## Left and right flick through the fliers without leaving the button.
func _on_look_input(e: InputEvent, p: Dictionary, button: Button) -> void:
	if e.is_action_pressed("ui_left"):
		_cycle_look(p, button, -1)
		button.accept_event()
	elif e.is_action_pressed("ui_right"):
		_cycle_look(p, button, 1)
		button.accept_event()


func _look_text(look: int) -> String:
	return "< %s >" % String(HumanoidScript.LOOKS[look].name).to_upper()


func _cycle_look(p: Dictionary, button: Button, step: int) -> void:
	p.look = posmod(p.look + step, HumanoidScript.LOOKS.size())
	button.text = _look_text(p.look)
	game.player.body.set_look(p.look)


func _add_player() -> void:
	var n := _roster.size()
	_roster.append({"name": "PLAYER %d" % (n + 1), "look": n % HumanoidScript.LOOKS.size()})
	_fill_rows()
	if _add.visible:
		_add.grab_focus()
	else:
		_go.grab_focus()


func _remove_player(i: int) -> void:
	_roster.remove_at(i)
	_fill_rows()
	_go.grab_focus()


func _build_results(root: Control) -> void:
	_results = _screen(root)
	_label(_results, "RESULTS", 76, Color.WHITE, 16)
	_rule(_results)
	_results_grid = GridContainer.new()
	_results_grid.columns = 4
	_results_grid.add_theme_constant_override("h_separation", 36)
	_results_grid.add_theme_constant_override("v_separation", 8)
	_results.add_child(_results_grid)
	_label(_results, "Keep your code: it proves your score", 18, Color(0.85, 0.87, 0.92), 6)
	var list := _list(_results)
	_again = _button(list, "PLAY AGAIN", _play_again)
	_button(list, "CHANGE PLAYERS", _on_start)
	_button(list, "QUIT TO TITLE", game.quit_to_title)


func _play_again() -> void:
	_show(null)
	game.start_game(_roster, false)


func _small_button(parent: Control, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_stylebox_override("normal", _button_box(Color(INK, 0.8)))
	b.add_theme_stylebox_override("hover", _button_box(Color(CRIMSON, 0.7)))
	b.add_theme_stylebox_override("pressed", _button_box(CRIMSON))
	b.add_theme_stylebox_override("focus", _button_box(CRIMSON))
	if pressed.is_valid():
		b.pressed.connect(pressed)
	parent.add_child(b)
	return b


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
	_setup.visible = screen == _setup
	_results.visible = screen == _results
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


func _cell(text: String, color: Color, grid: GridContainer = null, size := 20) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	(grid if grid else _grid).add_child(l)


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
