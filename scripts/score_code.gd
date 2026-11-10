extends RefCounted
## Short, checkable high-score codes, ready for a score table later.
##
## 50 bits: minutes since 2026-01-01 UTC (24, good for ~31 years), the score
## (20, up to 1,048,575) and a 6-bit check over both plus the player's name.
## Written as ten Crockford base-32 characters: XXXXX-XXXXX.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const EPOCH := 1767225600  # 2026-01-01T00:00:00Z
const TIME_BITS := 24
const SCORE_BITS := 20
const CHECK_BITS := 6


static func encode(score: int, player_name: String, unix_time := -1) -> String:
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	var minutes := clampi((unix_time - EPOCH) / 60, 0, (1 << TIME_BITS) - 1)
	score = clampi(score, 0, (1 << SCORE_BITS) - 1)
	var bits := (minutes << (SCORE_BITS + CHECK_BITS)) | (score << CHECK_BITS) | _check(minutes, score, player_name)
	var out := ""
	for i in 10:
		out = ALPHABET[bits & 31] + out
		bits >>= 5
	return out.substr(0, 5) + "-" + out.substr(5)


## {"score", "unix_time"} if the code is genuine for this name, else {}.
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
	var score := (bits >> CHECK_BITS) & ((1 << SCORE_BITS) - 1)
	var minutes := bits >> (SCORE_BITS + CHECK_BITS)
	if check != _check(minutes, score, player_name):
		return {}
	return {"score": score, "unix_time": EPOCH + minutes * 60}


static func _check(minutes: int, score: int, player_name: String) -> int:
	var h := ("%d:%d:%s:glider" % [minutes, score, player_name.strip_edges().to_upper()]).hash()
	return (h ^ (h >> 6) ^ (h >> 12)) & ((1 << CHECK_BITS) - 1)
