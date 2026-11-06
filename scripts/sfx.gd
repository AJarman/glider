extends Node
## Plays the synthesised effects in assets/sfx, two wind loops and quiet music.

const VOICES := 10
const MUSIC := ["midnight_cruiser", "empty_stretch", "detour"]
const MUSIC_VOLUME := 0.14
const SOUNDS := [
	"tick", "step", "taiko", "ready", "yoo", "go", "launch", "wings", "skim", "splash",
	"crash", "boom", "beep", "score", "perfect", "miss", "modifier", "kira",
]

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}
var _music: AudioStreamPlayer
var _track := 0


func _ready() -> void:
	for n in SOUNDS:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	for n in ["rush", "storm"]:
		var s: AudioStreamWAV = load("res://assets/sfx/%s.wav" % n)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_linear = 0.0
		add_child(p)
		p.play()
		_loops[n] = p
	_music = AudioStreamPlayer.new()
	_music.volume_linear = MUSIC_VOLUME
	_music.finished.connect(_next_track)
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_track = randi() % MUSIC.size()
	_next_track()


func _next_track() -> void:
	_track = (_track + 1) % MUSIC.size()
	_music.stream = load("res://assets/music/%s.mp3" % MUSIC[_track])
	_music.play()


func play(sound: String, wobble := 0.0, gain := 1.0) -> void:
	var p := _voices[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.pitch_scale = 1.0 + randf_range(-wobble, wobble)
	p.volume_linear = gain
	p.play()


func set_loop_pitch(sound: String, pitch: float) -> void:
	(_loops[sound] as AudioStreamPlayer).pitch_scale = pitch


## Eases a wind loop toward a volume from 0 to 1.
func set_loop(sound: String, volume: float, delta: float) -> void:
	var p: AudioStreamPlayer = _loops[sound]
	p.volume_linear = lerpf(p.volume_linear, volume, 1.0 - exp(-6.0 * delta))
