class_name Terrain
extends RefCounted
## The world: rolling ground, two castle plateaus, a river through the middle and
## three bridges. Everything that stands on the ground asks this file where
## the ground is.

const HALF_X := 88.0
const HALF_Z := 58.0
const CASTLE_X := 56.0
const PLATEAU_H := 1.35

const RIVER_CARVE := 4.4
const RIVER_EDGE := 8.2          # |x| where the carve reaches zero
const WATER_HALF := 6.4          # |x| that counts as water
const WATER_Y := -0.85

const DECK_H := 1.15
const BRIDGE_Z := [-32.0, 0.0, 32.0]
const BRIDGE_HALF_Z := 3.9
const BRIDGE_SPAN := 8.2
const RAMP_X := 52.0          # centre of the assault hill, |x|
const RAMP_Z := 21.0          # just outside the castle side wall
const RAMP_H := 8.0           # enough to top the 4.62 m battlements
const STEP_UP := 0.9
const STEP_DOWN := 1.1     # stops archers walking off the battlements

const GRASS := Color("4a6f37")
const GRASS_LIGHT := Color("5e8843")
const GRASS_DARK := Color("35502a")
const SAND := Color("a8965f")
const ROCK := Color("767b80")
const DIRT := Color("7d6242")

static var _noise_seed := 1337
static var ground_node: MeshInstance3D = null
## Raised walkable surfaces built by the castles (wall walks, stairs). Each entry
## is {r: Rect2, h: float}. The terrain mesh ignores these; movement uses them.
static var decks: Array = []


# ================================================================== height
static func _bump(x: float, z: float, cx: float, cz: float, radius: float, height: float) -> float:
	var d := Vector2(x - cx, z - cz).length()
	if d > radius:
		return 0.0
	var t: float = 1.0 - d / radius
	return height * t * t * (3.0 - 2.0 * t)


## Raw ground, ignoring bridges. Used to build the mesh and to place props.
static func h_terrain(x: float, z: float) -> float:
	var y := 0.85 * sin(x * 0.043) * cos(z * 0.05) - 0.35
	y += 0.55 * sin((x * 0.9 + z) * 0.027) * cos(z * 0.017)
	y += _bump(x, z, -26.0, -30.0, 15.0, 8.0)
	y += _bump(x, z, 26.0, 30.0, 15.0, 8.0)
	y += _bump(x, z, 0.0, 37.0, 13.0, 4.6)
	# knolls you actually fight over: steep enough to hide a soldier's legs
	y += _bump(x, z, -22.0, 17.0, 10.0, 4.4)
	y += _bump(x, z, 22.0, -17.0, 10.0, 4.4)
	y += _bump(x, z, -34.0, -12.0, 9.0, 3.0)
	y += _bump(x, z, 34.0, 13.0, 9.0, 3.0)
	y += _bump(x, z, -48.0, 34.0, 14.0, 4.4)
	y += _bump(x, z, 48.0, -34.0, 14.0, 4.4)
	y = _plateau(y, x, z, -CASTLE_X)
	y = _plateau(y, x, z, CASTLE_X)
	y -= _carve(x)
	# the ramps go on last: a castle plateau must not flatten the way in
	return y + h_ramp(x, z)


## The assault ramp: a shoulder of ground outside each castle's side wall that
## rises above the battlements, so an army can climb and drop into the courtyard
## instead of battering the gate. Mirrored per side.
static func h_ramp(x: float, z: float) -> float:
	var out := 0.0
	# 24 m radius keeps the worst gradient (~0.5 m per metre) inside the step
	# rule; at 16 m the mid-slope was too steep to walk, only to jump onto
	out += _bump(x, z, -RAMP_X, RAMP_Z, 24.0, RAMP_H)
	out += _bump(x, z, RAMP_X, -RAMP_Z, 24.0, RAMP_H)
	# clipped at the wall line: the courtyard stays flat, the bank outside stays
	# tall, and the join hides inside the 3.6 m thickness of the wall
	return out * smoothstep(15.0, 18.6, absf(z))


## Flattens the ground under a castle, then ramps back to open terrain.
static func _plateau(y: float, x: float, z: float, cx: float) -> float:
	var dx: float = absf(x - cx) / 16.5
	var dz: float = absf(z) / 19.5
	var d: float = maxf(dx, dz)
	var w: float = 1.0 - smoothstep(0.82, 1.30, d)
	return lerpf(y, PLATEAU_H, w)


static func _carve(x: float) -> float:
	var d: float = absf(x)
	if d > RIVER_EDGE:
		return 0.0
	var t: float = d / RIVER_EDGE
	return RIVER_CARVE * (1.0 - smoothstep(0.30, 1.0, t))


## 0..1: how much of the bridge deck we are standing on (1 in the middle).
static func bridge_zone(x: float, z: float) -> float:
	if absf(x) > BRIDGE_SPAN:
		return 0.0
	for bz in BRIDGE_Z:
		var dz: float = absf(z - bz)
		if dz > BRIDGE_HALF_Z:
			continue
		var ramp: float = clampf((BRIDGE_SPAN - absf(x)) / 2.6, 0.0, 1.0)
		var edge: float = clampf((BRIDGE_HALF_Z - dz) / 0.18, 0.0, 1.0)
		return minf(ramp, edge)
	return 0.0


## Walkable surface: terrain, bridges, or a castle walkway/stairs.
static func h(x: float, z: float) -> float:
	var y := h_terrain(x, z)
	var bz := bridge_zone(x, z)
	if bz > 0.0:
		y = lerpf(y, DECK_H, bz)
	if not decks.is_empty():
		var dh := deck_height(x, z)
		if dh > y:
			y = dh
	return y


static func on_bridge(x: float, z: float) -> bool:
	return bridge_zone(x, z) > 0.06


static func in_water(x: float, z: float) -> bool:
	return absf(x) < WATER_HALF and not on_bridge(x, z)


static func walkable(x: float, z: float) -> bool:
	if absf(x) > HALF_X - 1.0 or absf(z) > HALF_Z - 1.0:
		return false
	if on_bridge(x, z):
		return true
	if absf(x) < WATER_HALF:
		# bridge decks are elevated; ask the heightfield instead of the footprint
		# band, or the deck edges read as water and A* refuses to start there
		return h(x, z) > WATER_Y + 0.30
	return true


static func slope(x: float, z: float) -> float:
	var e := 0.9
	var hx := h_terrain(x + e, z) - h_terrain(x - e, z)
	var hz := h_terrain(x, z + e) - h_terrain(x, z - e)
	return Vector2(hx, hz).length() / (2.0 * e)


# ================================================================== bridges
## The bridge a unit is standing on (or right next to), or a huge number.
static func current_bridge_z(from: Vector3) -> float:
	for bz in BRIDGE_Z:
		if absf(from.z - bz) < BRIDGE_HALF_Z + 1.4 and absf(from.x) < BRIDGE_SPAN + 1.6:
			return bz
	return 1e9


static func needs_bridge(from: Vector3, to: Vector3) -> bool:
	# already on the goal's bank: never walk back onto the deck
	if signf(from.x) == signf(to.x) and absf(from.x) >= WATER_HALF:
		return false
	# mid-crossing: stay on the deck line until the bank
	if current_bridge_z(from) < 1e8:
		return absf(to.x) > WATER_HALF
	return signf(from.x) != signf(to.x) and absf(from.x) > WATER_HALF and absf(to.x) > WATER_HALF


static func nearest_bridge_z(from_z: float, to_z: float) -> float:
	var best: float = BRIDGE_Z[0]
	var bd := 1e9
	for bz in BRIDGE_Z:
		var d: float = absf(from_z - bz) + absf(to_z - bz) * 0.45
		if d < bd:
			bd = d
			best = bz
	return best


## Near mouth first, then the far one: nobody walks into their own bank forever.
static func bridge_step(from: Vector3, to: Vector3) -> Vector3:
	var bz := current_bridge_z(from)
	if bz >= 1e8:
		bz = nearest_bridge_z(from.z, to.z)
		return Vector3(signf(from.x) * (BRIDGE_SPAN + 0.6), 0.0, bz)
	return Vector3(signf(to.x) * (BRIDGE_SPAN + 0.6), 0.0, bz)


# ================================================================== build
static func clear_decks() -> void:
	decks.clear()


static func add_deck(r: Rect2, h: float) -> void:
	decks.append({"r": r, "h": h})


static func deck_height(x: float, z: float) -> float:
	var best := -1e9
	for d in decks:
		var r: Rect2 = d["r"]
		if r.has_point(Vector2(x, z)):
			best = maxf(best, float(d["h"]))
	return best


static func build(root: Node3D) -> void:
	_make_ground_mesh(root)
	_make_water(root)
	for bz in BRIDGE_Z:
		_make_bridge(root, bz)


static func _vertex_color(x: float, z: float) -> Color:
	var y := h_terrain(x, z)
	var sl := slope(x, z)
	var c := GRASS.lerp(GRASS_LIGHT, clampf(y * 0.085 + 0.38, 0.0, 1.0))
	# slow colour drift so the ground is never one flat green
	var drift: float = sin(x * 0.19 + z * 0.07) * cos(z * 0.23 - x * 0.05)
	c = c.lerp(GRASS_DARK, clampf(0.16 + drift * 0.16, 0.0, 0.4))
	if y < -0.2:
		c = c.lerp(SAND, clampf((-y - 0.2) * 0.55, 0.0, 0.85))
	if sl > 0.35:
		c = c.lerp(ROCK, clampf((sl - 0.35) * 1.1, 0.0, 0.92))
	# the assault bank is rock, so the way in is obvious from a distance
	var ramp_h := h_ramp(x, z)
	if ramp_h > 1.2:
		c = c.lerp(ROCK.lerp(DIRT, 0.30), clampf((ramp_h - 1.2) / 3.6, 0.0, 0.8))
	# the road follows the land between the bridge and each castle
	if absf(z) < 4.2 and absf(x) > 8.0:
		c = c.lerp(DIRT, 0.55 * clampf((4.2 - absf(z)) / 4.2, 0.0, 1.0))
	return c


static func _make_ground_mesh(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.4
	var nx := int(HALF_X * 2.0 / step)
	var nz := int(HALF_Z * 2.0 / step)
	for ix in nx:
		for iz in nz:
			var x0 := -HALF_X + float(ix) * step
			var z0 := -HALF_Z + float(iz) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var p00 := Vector3(x0, h_terrain(x0, z0), z0)
			var p10 := Vector3(x1, h_terrain(x1, z0), z0)
			var p11 := Vector3(x1, h_terrain(x1, z1), z1)
			var p01 := Vector3(x0, h_terrain(x0, z1), z1)
			var c00 := _vertex_color(x0, z0)
			var c10 := _vertex_color(x1, z0)
			var c11 := _vertex_color(x1, z1)
			var c01 := _vertex_color(x0, z1)
			# Godot treats clockwise as front-facing: this winding faces up
			_tri(st, p00, p10, p11, c00, c10, c11)
			_tri(st, p00, p11, p01, c00, c11, c01)
	st.generate_normals()
	var built: ArrayMesh = st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = built
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	mi.material_override = mat
	mi.name = "Ground"
	mi.extra_cull_margin = 400.0
	ground_node = mi
	root.add_child(mi)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


static func _make_water(root: Node3D) -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(WATER_HALF * 2.0 + 0.6, HALF_Z * 2.0)
	pm.subdivide_width = 2
	pm.subdivide_depth = 2
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.42, 0.58, 0.86)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.metallic = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = m
	water.position = Vector3(0, WATER_Y, 0)
	water.name = "Water"
	root.add_child(water)

	# a lighter ribbon on top: reads as current without needing a texture
	var ripples := MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(WATER_HALF * 1.1, HALF_Z * 2.0)
	ripples.mesh = pm2
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = Color(0.55, 0.8, 0.9, 0.20)
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ripples.material_override = m2
	ripples.position = Vector3(0, WATER_Y + 0.04, 0)
	root.add_child(ripples)


static func _make_bridge(root: Node3D, bz: float) -> void:
	var n := Node3D.new()
	n.name = "Bridge%d" % int(bz)
	root.add_child(n)
	var planks := int(BRIDGE_SPAN * 2.0 / 0.85)
	for i in planks:
		var x := -BRIDGE_SPAN + 0.45 + float(i) * 0.85
		var shade := Core.WOOD if i % 2 == 0 else Core.WOOD.darkened(0.12)
		# the plank top follows the same surface the units walk on, so feet never
		# sink into the deck at the bridge mouths
		var top: float = h(x, bz)
		Core.box(n, Vector3(0.80, 0.16, BRIDGE_HALF_Z * 2.0 + 0.5), Vector3(x, top - 0.08, bz), shade, Vector3.ZERO, 0.85)
	# rails
	for side in [-1.0, 1.0]:
		var zz: float = bz + side * (BRIDGE_HALF_Z + 0.15)
		for i in 7:
			var x := -BRIDGE_SPAN + 1.2 + float(i) * (BRIDGE_SPAN * 2.0 - 2.4) / 6.0
			Core.cyl(n, 0.09, 0.11, 1.0, Vector3(x, DECK_H + 0.45, zz), Core.WOOD_DARK, Vector3.ZERO, 6)
		Core.box(n, Vector3(BRIDGE_SPAN * 2.0 - 1.6, 0.14, 0.16), Vector3(0, DECK_H + 0.95, zz), Core.WOOD, Vector3.ZERO, 0.8)
	# piles into the water
	for px in [-6.0, 0.0, 6.0]:
		for side in [-1.0, 1.0]:
			Core.cyl(n, 0.22, 0.26, 3.4, Vector3(px, h(px, bz) - 1.75, bz + side * 2.2), Core.WOOD_DARK, Vector3.ZERO, 6)
	# stone quays: a retaining wall at each mouth, so the bank reads as a drop
	for side in [-1.0, 1.0]:
		for i in 5:
			var qx: float = side * (BRIDGE_SPAN - 0.3)
			var qz: float = bz - BRIDGE_HALF_Z + 0.5 + float(i) * 1.9
			var top: float = DECK_H - 0.05
			Core.box(n, Vector3(0.9, 1.6, 1.85), Vector3(qx, top - 0.8, qz), Core.STONE_DARK, Vector3.ZERO, 0.9)
			Core.box(n, Vector3(1.05, 0.16, 1.95), Vector3(qx, top + 0.02, qz), Core.STONE, Vector3.ZERO, 0.9)
