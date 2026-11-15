extends AnimatableBody3D
## A floating target. Discs score by ring; the mover slides about, the splitter
## bursts into six wedges and closes up again, the pyramid scores by ledge (with
## slopes between them to slide off) and the pinprick is a tiny, far-off jackpot.

enum Kind { DISC, MOVER, SPLITTER, PYRAMID, PINPRICK }

const FRACS := [1.0, 0.76, 0.52, 0.3, 0.11]
## Cool to hot, so a points value looks the same on every target.
const SCORE_COLORS := {
	10: Color(0.15, 0.3, 0.85),
	20: Color(0.1, 0.55, 0.95),
	30: Color(0.1, 0.8, 0.85),
	50: Color(0.2, 0.8, 0.3),
	60: Color(0.55, 0.85, 0.2),
	80: Color(0.8, 0.9, 0.15),
	100: Color(1.0, 0.85, 0.1),
	120: Color(1.0, 0.68, 0.1),
	150: Color(1.0, 0.5, 0.1),
	200: Color(1.0, 0.32, 0.12),
	250: Color(0.95, 0.15, 0.15),
	300: Color(0.9, 0.15, 0.6),
	400: Color(0.8, 0.15, 0.8),
	500: Color(0.6, 0.2, 0.95),
	1000: Color(1.0, 0.95, 0.5),
}
const RIM := 0.5
const BASE_H := 1.2
## A body counts as on a surface from just under it to this far above it.
const ABOVE := 2.5
const BELOW := 0.5
const MOVER_SWING := 22.0
const MOVER_PERIOD := 11.0
const SPLIT_GAP := 7.0  # How far each wedge slides out from the middle.
const SPLIT_PERIOD := 9.0
const SPLIT_PIECES := 6
const TIER_H := 2.5
## How far each pyramid slope reaches out over the ledge below, as a share of
## the step between tiers; what's left is flat, scoring ledge.
const SLOPE_SHARE := 0.62

var kind := Kind.DISC
var radius := 15.0
var scores: Array = [10, 20, 30, 50, 100]
var title := "TARGET"
## Moving targets hold still while a landing is being scored.
var frozen := false
var _home := Vector3.ZERO
var _time := 0.0
## The splitter's wedges.
var _halves: Array[AnimatableBody3D] = []


func setup(k: Kind, r: float, s: Array, t: String) -> void:
	kind = k
	radius = r
	scores = s
	title = t


func top_score() -> int:
	return scores.max()


func _ready() -> void:
	add_to_group("target")
	_home = position
	match kind:
		Kind.SPLITTER:
			_build_splitter()
		Kind.PYRAMID:
			_build_pyramid()
		_:
			_build_disc()
	if kind == Kind.PINPRICK:
		_build_beacon()


func _physics_process(delta: float) -> void:
	if frozen:
		set_meta("vel", Vector3.ZERO)
		for h in _halves:
			h.set_meta("vel", Vector3.ZERO)
		return
	_time += delta
	match kind:
		Kind.MOVER:
			var a := _time * TAU / MOVER_PERIOD
			_move_to(self, _home + Vector3(sin(a) * MOVER_SWING, 0, sin(a * 0.5) * MOVER_SWING * 0.35), delta)
		Kind.SPLITTER:
			var open := _split_amount(fmod(_time, SPLIT_PERIOD) / SPLIT_PERIOD)
			for h in _halves:
				_move_to(h, h.get_meta("dir") * SPLIT_GAP * open, delta)


## Moves a deck and notes its velocity (meta "vel"), so a body lying on it can
## tell resting from riding.
func _move_to(deck: Node3D, to: Vector3, delta: float) -> void:
	deck.set_meta("vel", (to - deck.position) / delta)
	deck.position = to


## 0 closed to 1 fully apart: shut, slide open, hang open, slide shut.
func _split_amount(phase: float) -> float:
	if phase < 0.3:
		return 0.0
	if phase < 0.45:
		return smoothstep(0.3, 0.45, phase)
	if phase < 0.75:
		return 1.0
	if phase < 0.9:
		return 1.0 - smoothstep(0.75, 0.9, phase)
	return 0.0


func score_at(p: Vector3) -> int:
	match kind:
		Kind.SPLITTER:
			var best := 0
			for h in _halves:
				var c := h.global_position
				var rel := Vector2(p.x - c.x, p.z - c.z)
				var off := absf(angle_difference(rel.angle(), h.get_meta("angle")))
				var inside := rel.length() < 1.0 or off <= PI / SPLIT_PIECES + 0.05
				if inside and _on_surface(p, c.y):
					best = maxi(best, _ring_score(p, c))
			return best
		Kind.PYRAMID:
			# Only the flat ledges score: a body on a slope counts for the ledge
			# it's sliding down to, if it's low enough to be on it.
			var y := global_position.y
			var d := p - global_position
			for i in range(scores.size() - 1, -1, -1):
				var half := _tier_half(i) + 0.3
				if absf(d.x) <= half and absf(d.z) <= half and _on_surface(p, y + i * TIER_H):
					return scores[i]
			return 0
	if not _on_surface(p, global_position.y):
		return 0
	return _ring_score(p, global_position)


func _on_surface(p: Vector3, top: float) -> bool:
	return p.y > top - BELOW and p.y < top + ABOVE


func _ring_score(p: Vector3, centre: Vector3) -> int:
	var d := Vector2(p.x - centre.x, p.z - centre.z).length()
	for i in range(scores.size() - 1, -1, -1):
		if d <= radius * _frac(i):
			return scores[i]
	if d <= radius + RIM + 0.3:
		return scores[0]
	return 0


func _frac(i: int) -> float:
	return 1.0 if scores.size() == 1 else FRACS[i]


func _build_disc() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius + RIM
	shape.height = BASE_H
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -BASE_H * 0.5
	add_child(cs)

	var base := CylinderMesh.new()
	base.top_radius = radius + RIM
	base.bottom_radius = radius + RIM
	base.height = BASE_H
	base.radial_segments = 64
	_mesh(self, base, Vector3(0, -BASE_H * 0.5, 0), _mat(Color(0.95, 0.95, 0.97)))

	for i in scores.size():
		var ring := CylinderMesh.new()
		ring.top_radius = radius * _frac(i)
		ring.bottom_radius = ring.top_radius
		ring.height = 0.04
		ring.radial_segments = 64
		_mesh(self, ring, Vector3(0, 0.01 * (i + 1), 0), _mat(SCORE_COLORS[scores[i]]))
		_ring_label(self, i, Vector3.BACK)

	if kind == Kind.MOVER:
		# A raft hull riding on the sea, so it reads as something that sails.
		var hull := CylinderMesh.new()
		hull.top_radius = radius * 0.75
		hull.bottom_radius = radius * 0.6
		hull.height = 1.6
		hull.radial_segments = 32
		_mesh(self, hull, Vector3(0, -position.y + 0.3, 0), _mat(Color(0.75, 0.3, 0.15)))
		for k in 3:
			var a := TAU * k / 3.0
			var leg := CylinderMesh.new()
			leg.top_radius = 0.6
			leg.bottom_radius = 0.8
			leg.height = position.y - 1.0
			_mesh(self, leg, Vector3(cos(a), 0, sin(a)) * radius * 0.45 + Vector3(0, -BASE_H - leg.height * 0.5 + 0.2, 0), _mat(Color(0.5, 0.5, 0.55)))
	else:
		_legs(self, radius * 0.6, 4)


## Six pie wedges. Each wedge's origin is the full disc's centre, so its rings
## are measured from where its own paint is centred.
func _build_splitter() -> void:
	var span := TAU / SPLIT_PIECES
	for k in SPLIT_PIECES:
		var a0 := span * k
		var a1 := a0 + span
		var mid := a0 + span * 0.5
		var dir := Vector3(cos(mid), 0, sin(mid))
		var wedge := AnimatableBody3D.new()
		wedge.add_to_group("target")
		wedge.set_meta("dir", dir)
		wedge.set_meta("angle", mid)
		add_child(wedge)
		_halves.append(wedge)
		var pts := PackedVector3Array()
		for y in [0.0, -BASE_H]:
			pts.append(Vector3(0, y, 0))
			for j in 9:
				var a := lerpf(a0, a1, j / 8.0)
				pts.append(Vector3(cos(a), 0, sin(a)) * (radius + RIM) + Vector3(0, y, 0))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		wedge.add_child(cs)
		_mesh(wedge, _wedge(radius + RIM, BASE_H, a0, a1), Vector3.ZERO, _mat(Color(0.95, 0.95, 0.97)))
		for i in scores.size():
			_mesh(wedge, _wedge(radius * _frac(i), 0.04, a0, a1), Vector3(0, 0.01 * (i + 1) + 0.04, 0), _mat(SCORE_COLORS[scores[i]]))
			# Numbers on the wedge facing the ramp and the one facing away.
			if k == 1 or k == 4:
				_ring_label(wedge, i, dir)
		_leg(wedge, dir * radius * 0.55, maxf(radius * 0.08, 0.6))


## A pie slice of the given height whose top sits at y = 0, from angle a0 to a1.
func _wedge(r: float, h: float, a0: float, a1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var arc: Array[Vector3] = []
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		arc.append(Vector3(cos(a), 0, sin(a)) * r)
	var down := Vector3(0, -h, 0)
	for k in n:
		var a := arc[k]
		var b := arc[k + 1]
		_face(st, Vector3.ZERO, a, b, Vector3.UP)
		_face(st, down, a + down, b + down, Vector3.DOWN)
		var out := ((a + b) * 0.5).normalized()
		_face(st, a, a + down, b + down, out)
		_face(st, a, b + down, b, out)
	var middle := arc[n / 2]
	for edge in [arc[0], arc[n]]:
		var side: Vector3 = edge.cross(Vector3.UP).normalized()
		if side.dot(middle) > 0.0:
			side = -side
		_face(st, Vector3.ZERO, edge, edge + down, side)
		_face(st, Vector3.ZERO, edge + down, down, side)
	return st.commit()


## One triangle facing nrm, whichever order its corners come in.
func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> void:
	var pts := [a, b, c] if (b - a).cross(c - a).dot(nrm) < 0.0 else [a, c, b]
	for p in pts:
		st.set_normal(nrm)
		st.add_vertex(p)


## Stepped and square: the higher the tier, the smaller and the richer. Each
## tier above the base rises from a sloped skirt, so only a strip of each ledge
## is flat, and a short landing slides back down.
func _build_pyramid() -> void:
	var base := BoxShape3D.new()
	base.size = Vector3(_tier_half(0) * 2.0, BASE_H, _tier_half(0) * 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = base
	cs.position.y = -BASE_H * 0.5
	add_child(cs)
	var slab := BoxMesh.new()
	slab.size = base.size
	_mesh(self, slab, Vector3(0, -BASE_H * 0.5, 0), _mat(SCORE_COLORS[scores[0]].lerp(Color.WHITE, 0.15)))
	for i in range(1, scores.size()):
		var top := _tier_half(i)
		var foot := _slope_foot(i)
		var y0 := (i - 1) * TIER_H
		var y1 := i * TIER_H
		var pts := PackedVector3Array()
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pts.append(Vector3(c.x * foot, y0 - 0.05, c.y * foot))
			pts.append(Vector3(c.x * top, y1, c.y * top))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var tier := CollisionShape3D.new()
		tier.shape = shape
		add_child(tier)
		_mesh(self, _frustum(foot, top, y0, y1), Vector3.ZERO, _mat(SCORE_COLORS[scores[i]].lerp(Color.WHITE, 0.15)))
	for i in scores.size():
		var half := _tier_half(i)
		var lbl := _label(str(scores[i]), clampf(half * 0.004, 0.012, 0.03))
		var inner := _slope_foot(i + 1) if i + 1 < scores.size() else 0.0
		lbl.position = Vector3(0, i * TIER_H + 0.1, (half + inner) * 0.5)
		add_child(lbl)
	_legs(self, _tier_half(0) * 0.6, 4)


## Half width of the bottom of tier i's slope, out on the ledge below.
func _slope_foot(i: int) -> float:
	var top := _tier_half(i)
	return top + (_tier_half(i - 1) - top) * SLOPE_SHARE


## A square, flat-topped pyramid tier: sloped sides from foot (half width at
## y0) up to top (half width at y1), with a lid.
func _frustum(foot: float, top: float, y0: float, y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var c0: Vector2 = corners[k]
		var c1: Vector2 = corners[(k + 1) % 4]
		var b0 := Vector3(c0.x * foot, y0, c0.y * foot)
		var b1 := Vector3(c1.x * foot, y0, c1.y * foot)
		var t0 := Vector3(c0.x * top, y1, c0.y * top)
		var t1 := Vector3(c1.x * top, y1, c1.y * top)
		var nrm := (b1 - b0).cross(t0 - b0).normalized()
		if nrm.dot(Vector3(c0.x + c1.x, 0, c0.y + c1.y)) < 0.0:
			nrm = -nrm
		_face(st, b0, b1, t1, nrm)
		_face(st, b0, t1, t0, nrm)
	var lid: Array[Vector3] = []
	for c: Vector2 in corners:
		lid.append(Vector3(c.x * top, y1, c.y * top))
	_face(st, lid[0], lid[1], lid[2], Vector3.UP)
	_face(st, lid[0], lid[2], lid[3], Vector3.UP)
	return st.commit()


func _tier_half(i: int) -> float:
	return radius * lerpf(1.0, 0.22, float(i) / maxf(scores.size() - 1, 1))


## A pillar of light so the far-off jackpot can be found from the ramp.
func _build_beacon() -> void:
	var beam := CylinderMesh.new()
	beam.top_radius = radius * 1.2
	beam.bottom_radius = radius * 0.9
	beam.height = 260.0
	beam.cap_top = false
	beam.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.92, 0.4, 0.18)
	var mi := MeshInstance3D.new()
	mi.mesh = beam
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 132.0
	add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.9, 0.4)
	glow.light_energy = 4.0
	glow.omni_range = 18.0
	glow.position.y = 3.0
	add_child(glow)


func _legs(parent: Node3D, spread: float, count: int) -> void:
	for k in count:
		var a := TAU * k / count + PI / 4
		_leg(parent, Vector3(cos(a), 0, sin(a)) * spread, maxf(radius * 0.08, 0.6))


## A pontoon leg from under the deck down into the sea.
func _leg(parent: Node3D, at: Vector3, r: float) -> void:
	var depth := position.y + 2.0
	var leg := CylinderMesh.new()
	leg.top_radius = r
	leg.bottom_radius = r * 1.3
	leg.height = depth
	_mesh(parent, leg, at + Vector3(0, -BASE_H - depth * 0.5, 0), _mat(Color(0.5, 0.5, 0.55)))


## Each ring's value, laid flat midway across the ring along dir.
func _ring_label(parent: Node3D, i: int, dir: Vector3) -> void:
	var inner: float = _frac(i + 1) if i + 1 < scores.size() else 0.0
	var rmid: float = radius * (_frac(i) + inner) * 0.5
	var px := radius * 0.006 if scores.size() == 1 else clampf(radius * 0.0012, 0.01, 0.022)
	var lbl := _label(str(scores[i]), px)
	lbl.position = Vector3(0, 0.1, 0) + dir * rmid
	parent.add_child(lbl)


func _label(text: String, px: float) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.outline_size = 16
	lbl.pixel_size = px
	lbl.rotation.x = -PI / 2
	lbl.shaded = false
	return lbl


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _mat(c: Color, two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.6
	return m
