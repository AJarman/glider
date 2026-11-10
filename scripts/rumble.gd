extends RefCounted
## Controller (and phone) vibration. Every pad that's plugged in shakes, so
## hotseat players can pass one pad round or each hold their own.

const SETTINGS := "user://settings.cfg"

static var enabled := true
static var _loaded := false


static func load_setting() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		enabled = cfg.get_value("input", "vibration", true)


static func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		stop()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("input", "vibration", on)
	cfg.save(SETTINGS)


## A one-off kick. weak is the light, buzzy motor; strong the heavy thump.
static func pulse(weak: float, strong: float, duration: float) -> void:
	if not enabled:
		return
	weak = clampf(weak, 0.0, 1.0)
	strong = clampf(strong, 0.0, 1.0)
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, weak, strong, duration)
	if _handheld() and strong + weak > 0.3:
		Input.vibrate_handheld(int(duration * 1000.0), maxf(weak, strong))


## A steady rumble, called every frame; pads only, as phones can't hold it
## smoothly.
static func hum(weak: float, strong: float) -> void:
	if not enabled:
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), 0.12)


static func stop() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)


static func _handheld() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
