extends RefCounted
## Short, checkable high-score codes, ready for a score table later.
##
## 50 bits: minutes since 2026-01-01 UTC (24, good for ~31 years), the score
## (18, up to 262,143), the game length (2: 3, 5 or 10 rounds, so each length
## gets its own table) and a 6-bit check over all of it plus the player's name.
## Written as ten Crockford base-32 characters: XXXXX-XXXXX.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const EPOCH := 1767225600  # 2026-01-01T00:00:00Z
const TIME_BITS := 24
const SCORE_BITS := 18
const ROUNDS_BITS := 2
const CHECK_BITS := 6
## The game lengths on offer; the code stores the index.
const ROUND_OPTIONS := [3, 5, 10]


static func encode(score: int, player_name: String, rounds: int, unix_time := -1) -> String:
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	var minutes := clampi((unix_time - EPOCH) / 60, 0, (1 << TIME_BITS) - 1)
	score = clampi(score, 0, (1 << SCORE_BITS) - 1)
	var mode := maxi(ROUND_OPTIONS.find(rounds), 0)
	var bits := minutes
	bits = (bits << SCORE_BITS) | score
	bits = (bits << ROUNDS_BITS) | mode
	bits = (bits << CHECK_BITS) | _check(minutes, score, mode, player_name)
	var out := ""
	for i in 10:
		out = ALPHABET[bits & 31] + out
		bits >>= 5
	return out.substr(0, 5) + "-" + out.substr(5)


## {"score", "rounds", "unix_time"} if the code is genuine for this name, else {}.
static func decode(code: String, player_name: String) -> Dictionary:
	var clean := code.to_upper().replace("-", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if clean.length() != 10:
		return {}
	var bits := 0
	for ch in clean:
		var v := ALPHABET.find(ch)
		if v < 0:
			return {}
		bits = (bits << 5) | v
	var check := bits & ((1 << CHECK_BITS) - 1)
	bits >>= CHECK_BITS
	var mode := bits & ((1 << ROUNDS_BITS) - 1)
	bits >>= ROUNDS_BITS
	var score := bits & ((1 << SCORE_BITS) - 1)
	var minutes := bits >> SCORE_BITS
	if mode >= ROUND_OPTIONS.size() or check != _check(minutes, score, mode, player_name):
		return {}
	return {"score": score, "rounds": ROUND_OPTIONS[mode], "unix_time": EPOCH + minutes * 60}


static func _check(minutes: int, score: int, mode: int, player_name: String) -> int:
	var h := ("%d:%d:%d:%s:glider" % [minutes, score, mode, player_name.strip_edges().to_upper()]).hash()
	return (h ^ (h >> 6) ^ (h >> 12)) & ((1 << CHECK_BITS) - 1)
