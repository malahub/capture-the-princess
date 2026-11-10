class_name Nav
extends RefCounted
## Grid A* over the heightfield.
##
## The old router walked straight at a goal and, when that failed, sidestepped at
## random — which is why bodies piled up on doorway corners. This samples the
## actual walkable surface (terrain, decks, bridge ramps, castle floors) into a
## grid once per match, and searches it with the same step rule the movement code
## uses, so a stair the unit can't climb is an edge that doesn't exist either.

const CELL := 1.2

static var w := 0
static var h := 0
static var cells := PackedByteArray()      # 1 = walkable
static var heights := PackedFloat32Array() # surface height at the cell centre
static var built := false


static func _walkable(x: float, z: float, sol: Array) -> bool:
	if absf(x) > Terrain.HALF_X - 1.0 or absf(z) > Terrain.HALF_Z - 1.0:
		return false
	if not Terrain.walkable(x, z):
		return false
	for s in sol:
		var tag: String = String(s.get("tag", ""))
		if tag.begins_with("gate"):
			continue                     # the gate is a door: the path goes through it
		var rr: Rect2 = s["r"]
		if rr.has_point(Vector2(x, z)) and float(s["top"]) > Terrain.h(x, z) + 0.25:
			return false
	return true


static func build(sol: Array) -> void:
	w = int(ceil(Terrain.HALF_X * 2.0 / CELL))
	h = int(ceil(Terrain.HALF_Z * 2.0 / CELL))
	cells = PackedByteArray()
	cells.resize(w * h)
	heights = PackedFloat32Array()
	heights.resize(w * h)
	for iz in h:
		for ix in w:
			var x := -Terrain.HALF_X + (float(ix) + 0.5) * CELL
			var z := -Terrain.HALF_Z + (float(iz) + 0.5) * CELL
			var i := iz * w + ix
			heights[i] = Terrain.h(x, z)
			cells[i] = 1 if _walkable(x, z, sol) else 0
	built = true


static func cell_of(p: Vector3) -> int:
	var ix := int((p.x + Terrain.HALF_X) / CELL)
	var iz := int((p.z + Terrain.HALF_Z) / CELL)
	ix = clampi(ix, 0, w - 1)
	iz = clampi(iz, 0, h - 1)
	return iz * w + ix


static func centre(i: int) -> Vector3:
	var ix := i % w
	var iz := i / w
	return Vector3(-Terrain.HALF_X + (float(ix) + 0.5) * CELL, 0.0, -Terrain.HALF_Z + (float(iz) + 0.5) * CELL)


## Nearest walkable cell to a point, spiralling outwards — goals are often inside
## a wall's footprint or a hair off-mesh.
static func snap(p: Vector3) -> int:
	var start := cell_of(p)
	if cells[start] == 1:
		return start
	var sx := start % w
	var sz := start / w
	for r in range(1, 9):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var ix := sx + dx
				var iz := sz + dz
				if ix < 0 or iz < 0 or ix >= w or iz >= h:
					continue
				var i := iz * w + ix
				if cells[i] == 1 and absf(heights[i] - Terrain.h(p.x, p.z)) < Terrain.STEP_UP:
					return i
	return -1


static func _step_ok(a: int, b: int) -> bool:
	if cells[b] != 1:
		return false
	# Sample the leg rather than comparing cell centres: a stair tread is
	# shallower than a cell is wide, so centre-to-centre heights lie about it.
	var pa := centre(a)
	var pb := centre(b)
	var dist := pa.distance_to(pb)
	var steps := maxi(1, int(dist / 0.25))
	var prev := Terrain.h(pa.x, pa.z)
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var x := pa.x + (pb.x - pa.x) * t
		var z := pa.z + (pb.z - pa.z) * t
		var hh := Terrain.h(x, z)
		if absf(hh - prev) > Terrain.STEP_UP:
			return false
		prev = hh
	return true


## 8-connected A*. Returns world points from (excluding) the start to the goal.
static func find_path(from: Vector3, to: Vector3) -> Array:
	if not built:
		return []
	var a := snap(from)
	var b := snap(to)
	if a < 0 or b < 0:
		return []
	if a == b:
		return [to]

	var n := w * h
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)

	# binary heap of (f, cell) — a linear scan here is what turned a replan into
	# a multi-second stall once every unit started asking for one
	var heap_f := PackedFloat32Array()
	var heap_i := PackedInt32Array()
	var push := func(f: float, idx: int) -> void:
		heap_f.append(f)
		heap_i.append(idx)
		var k := heap_i.size() - 1
		while k > 0:
			var parent := (k - 1) / 2
			if heap_f[parent] <= heap_f[k]:
				break
			var tf := heap_f[parent]
			var ti := heap_i[parent]
			heap_f[parent] = heap_f[k]
			heap_i[parent] = heap_i[k]
			heap_f[k] = tf
			heap_i[k] = ti
			k = parent
	var pop := func() -> int:
		var top := heap_i[0]
		var last := heap_i.size() - 1
		heap_f[0] = heap_f[last]
		heap_i[0] = heap_i[last]
		heap_f.resize(last)
		heap_i.resize(last)
		var k := 0
		while true:
			var l := k * 2 + 1
			var r := l + 1
			var small := k
			if l < heap_i.size() and heap_f[l] < heap_f[small]:
				small = l
			if r < heap_i.size() and heap_f[r] < heap_f[small]:
				small = r
			if small == k:
				break
			var tf := heap_f[small]
			var ti := heap_i[small]
			heap_f[small] = heap_f[k]
			heap_i[small] = heap_i[k]
			heap_f[k] = tf
			heap_i[k] = ti
			k = small
		return top

	var bx: int = b % w
	var bz: int = b / w
	var expanded := 0
	g[a] = 0.0
	push.call(0.0, a)

	while heap_i.size() > 0 and expanded < 9000:
		var cur: int = pop.call()
		expanded += 1
		if cur == b:
			break
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		var cx: int = cur % w
		var cz: int = cur / w
		for dz: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nx: int = cx + dx
				var nz: int = cz + dz
				if nx < 0 or nz < 0 or nx >= w or nz >= h:
					continue
				var ni: int = nz * w + nx
				if closed[ni] == 1 or cells[ni] != 1:
					continue
				if dx != 0 and dz != 0:
					if cells[cz * w + nx] != 1 or cells[nz * w + cx] != 1:
						continue
				var cost: float = g[cur] + (1.4142 if (dx != 0 and dz != 0) else 1.0)
				if cost >= g[ni]:
					continue
				if not _step_ok(cur, ni):
					continue
				g[ni] = cost
				came[ni] = cur
				var hx: int = absi(nx - bx)
				var hz: int = absi(nz - bz)
				var heur: float = float(maxi(hx, hz)) + 0.4142 * float(mini(hx, hz))
				push.call(cost + heur, ni)

	if came[b] < 0 and a != b:
		return []

	# walk it back
	var raw: Array = []
	var cur2 := b
	var steps := 0
	while cur2 != a and cur2 >= 0 and steps < 4000:
		raw.append(centre(cur2))
		cur2 = came[cur2]
		steps += 1
	raw.reverse()
	if raw.is_empty():
		return []
	# Only smooth paths that stay on one level. A stair or a ramp refuses
	# straight-line shortcuts — the grid path is the safe one, and cutting a
	# corner across a 3 m drop is exactly how units used to fall off stairs.
	var hmin := INF
	var hmax := -INF
	for wp in raw:
		var hh: float = Terrain.h(wp.x, wp.z)
		hmin = minf(hmin, hh)
		hmax = maxf(hmax, hh)
	raw[raw.size() - 1] = to
	if hmax - hmin > 1.0:
		return raw

	# string-pull: drop waypoints we can walk straight past
	var out: Array = []
	var i := 0
	while i < raw.size():
		var j := raw.size() - 1
		var keep := i
		while j > i:
			if _clear(raw[i] if not out.is_empty() else from, raw[j]):
				keep = j
				break
			j -= 1
		out.append(raw[keep])
		i = keep + 1
	return out


## Straight-line walkability, used to smooth the grid path.
static func _clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist := d.length()
	if dist < 0.001:
		return true
	var steps := int(dist / 0.3) + 1
	var prev_h := Terrain.h(a.x, a.z)
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var x := a.x + d.x * t
		var z := a.z + d.z * t
		if not Terrain.walkable(x, z):
			return false
		var hh := Terrain.h(x, z)
		if absf(hh - prev_h) > Terrain.STEP_UP:
			return false
		prev_h = hh
	return true
