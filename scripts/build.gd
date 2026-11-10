class_name Bld
extends RefCounted
## Everything visible in Heavy Flag: the map, the castles, the characters.
## Built from primitives at runtime so the whole game ships as text.

const CX := 34.0            # castle centre in build-local space
const PLATEAU_HX := 16.5     # half-extent of a castle plateau (see Terrain._plateau)

const GATE_X := 20.0        # gate plane |x|, relative to the castle
# derived, so the castle can never drift off its plateau when the map grows
const CASTLE_SHIFT := Terrain.CASTLE_X - PLATEAU_HX - GATE_X - 0.6
const GATE_ABS := GATE_X + CASTLE_SHIFT   # |x| of the gate plane in world space
const BACK_X := 48.0        # back wall |x|
const SIDE_Z := 17.0        # side wall |z|
const THRONE_Z := 9.4
const WALL_H := 4.4
const WALL_T := 3.6
const WALK_H: float = Terrain.PLATEAU_H + WALL_H + 0.22
const MID_H := 2.15                       # middle storey: the shrine terrace
const DUNGEON_Z := -9.4
const HAT_Z := 9.0

static func team_col(t: int) -> Color:
	return Core.RED if t == 0 else Core.BLUE

static func team_dark(t: int) -> Color:
	return Core.RED_DARK if t == 0 else Core.BLUE_DARK

static func team_light(t: int) -> Color:
	return Core.RED_LIGHT if t == 0 else Core.BLUE_LIGHT

static func team_name(t: int) -> String:
	return "RED" if t == 0 else "BLUE"

## Mirrors a castle-local offset into world space. flip=+1 red, -1 blue.
static func wpt(flip: float, lx: float, lz: float) -> Vector3:
	return Vector3(-flip * (lx + CASTLE_SHIFT), 0.0, lz)

# ================================================================= world
static func make_env(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8fb2cf")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a8bed4")
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-33.0, -46.0, 0.0)
	sun.light_energy = 1.02
	sun.light_color = Color("fff3dd")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 150.0
	root.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, 145.0, 0.0)
	fill.light_energy = 0.14
	fill.light_color = Color("b9d0ff")
	fill.shadow_enabled = false
	root.add_child(fill)


static func ground(root: Node3D) -> void:
	Core.box(root, Vector3(112, 1.0, 72), Vector3(0, -0.5, 0), Core.GRASS)
	# Mottled grass patches: flat quads a hair above the plane, never z-fighting.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261110
	for i in 90:
		var p := Vector3(rng.randf_range(-54, 54), 0.012, rng.randf_range(-34, 34))
		if absf(p.x) > 17.0:
			continue
		var s := rng.randf_range(1.2, 4.0)
		Core.box(root, Vector3(s, 0.02, s * rng.randf_range(0.6, 1.2)), p,
				Core.GRASS.lerp(Core.GRASS_DARK, rng.randf() * 0.6))
	# Road between the gates.
	Core.box(root, Vector3(40, 0.03, 7.0), Vector3(0, 0.02, 0), Core.DIRT)
	Core.box(root, Vector3(40, 0.03, 6.2), Vector3(0, 0.035, 0), Core.DIRT.lerp(Core.GRASS, 0.25))
	for i in 26:
		var x := -20.0 + float(i) * 1.55
		Core.box(root, Vector3(1.1, 0.02, 1.0), Vector3(x, 0.05, rng.randf_range(-2.2, 2.2)),
				Core.DIRT.lerp(Core.STONE_DARK, rng.randf_range(0.0, 0.35)))


static func scatter(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77123
	var tries := 0
	var placed := 0
	while placed < 78 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(-80.0, 80.0), 0.0, rng.randf_range(-48.0, 48.0))
		if absf(p.x) < 11.0:
			continue                                    # river and its banks
		if absf(p.z) < 8.0:
			continue                                    # the road
		if Vector2(p.x + 52.0, p.z).length() < 18.0 or Vector2(p.x - 52.0, p.z).length() < 18.0:
			continue                                    # castle plateaus
		if Terrain.slope(p.x, p.z) > 0.75:
			continue                                    # too steep to stand a tree on
		p.y = Terrain.h_terrain(p.x, p.z)
		tree(root, p, rng.randf_range(0.85, 1.4))
		placed += 1
	tries = 0
	placed = 0
	while placed < 46 and tries < 3000:
		tries += 1
		var p := Vector3(rng.randf_range(-80.0, 80.0), 0.0, rng.randf_range(-48.0, 48.0))
		if absf(p.x) < 11.5 or absf(p.z) < 6.0:
			continue
		if Vector2(p.x + 52.0, p.z).length() < 15.0 or Vector2(p.x - 52.0, p.z).length() < 15.0:
			continue
		p.y = Terrain.h_terrain(p.x, p.z)
		rock(root, p, rng.randf_range(0.45, 1.0))
		placed += 1
	# boundary hedge, so the arena edge reads as an edge
	var stepx := 3.0
	var n := int(Terrain.HALF_X * 2.0 / stepx)
	for i in n:
		var x := -Terrain.HALF_X + float(i) * stepx
		hedge(root, Vector3(x, Terrain.h_terrain(x, -Terrain.HALF_Z + 1.5), -Terrain.HALF_Z + 1.5))
		hedge(root, Vector3(x, Terrain.h_terrain(x, Terrain.HALF_Z - 1.5), Terrain.HALF_Z - 1.5))
	var m := int(Terrain.HALF_Z * 2.0 / stepx)
	for i in m:
		var z := -Terrain.HALF_Z + float(i) * stepx
		hedge(root, Vector3(-Terrain.HALF_X + 1.5, Terrain.h_terrain(-Terrain.HALF_X + 1.5, z), z))
		hedge(root, Vector3(Terrain.HALF_X - 1.5, Terrain.h_terrain(Terrain.HALF_X - 1.5, z), z))


static func tree(root: Node3D, p: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = p
	root.add_child(n)
	Core.cyl(n, 0.16 * s, 0.24 * s, 1.5 * s, Vector3(0, 0.75 * s, 0), Core.WOOD_DARK, Vector3.ZERO, 8)
	Core.sphere(n, 1.05 * s, Vector3(0, 2.1 * s, 0), Core.GRASS_DARK, 0.95, 10)
	Core.sphere(n, 0.72 * s, Vector3(0.55 * s, 1.7 * s, 0.2 * s), Core.GRASS_DARK.lerp(Core.GRASS_LIGHT, 0.35), 0.95, 10)
	Core.sphere(n, 0.62 * s, Vector3(-0.5 * s, 1.85 * s, -0.3 * s), Core.GRASS_DARK.lerp(Core.GRASS_LIGHT, 0.2), 0.95, 10)
	Core.sphere(n, 0.9 * s, Vector3(-0.1 * s, 2.55 * s, 0.1 * s), Core.GRASS_LIGHT.lerp(Core.GRASS_DARK, 0.35), 0.9, 10)


static func rock(root: Node3D, p: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = p
	n.rotation_degrees.y = randf() * 360.0
	root.add_child(n)
	Core.sphere(n, s, Vector3(0, s * 0.45, 0), Core.STONE_DARK, 0.62, 7, 0.95)
	Core.sphere(n, s * 0.55, Vector3(s * 0.6, s * 0.2, s * 0.3), Core.STONE, 0.6, 6, 0.95)


static func hedge(root: Node3D, p: Vector3) -> void:
	var s := 1.0 + randf() * 0.25
	Core.box(root, Vector3(2.5, 1.6 * s, 1.3), p + Vector3(0, 0.8 * s, 0),
			Core.GRASS_DARK.lerp(Core.GRASS, randf()), Vector3(0, randf_range(-12, 12), 0))

# ================================================================= castle
## Builds one castle. Returns the gameplay points and appends wall rects to `solids`.
## Walls are thick enough to walk on: the top slab is registered as a deck, and the
## stairs register a deck per step, so units can climb and shoot from the parapet.
static func castle(root: Node3D, team: int, solids: Array) -> Dictionary:
	var flip := 1.0 if team == 0 else -1.0
	var col := team_col(team)
	var dark := team_dark(team)
	var light := team_light(team)
	var n := Node3D.new()
	n.name = "Castle%s" % team_name(team)
	n.position.y = Terrain.PLATEAU_H
	root.add_child(n)

	# Courtyard stone floor (flush with the plateau, so movement stays planar).
	Core.box(n, Vector3(28, 0.08, 34), wpt(flip, CX, 0) + Vector3(0, 0.04, 0), Color("4a4f56"))
	for ix in 10:
		for iz in 11:
			var lx := CX - 12.0 + float(ix) * 2.9
			var lz := -15.0 + float(iz) * 3.0
			var shade := Color("585e66").lerp(dark, 0.10).lerp(Color("6d747c"), 0.55 * absf(sin(float(ix) * 1.7 + float(iz) * 0.9)))
			Core.box(n, Vector3(2.7, 0.02, 2.8), wpt(flip, lx, lz) + Vector3(0, 0.085, 0), shade)

	# Team carpet from the gate to the throne.
	Core.box(n, Vector3(24, 0.03, 3.6), wpt(flip, GATE_X + 12.0, 2.0) + Vector3(0, 0.10, 0), dark)
	Core.box(n, Vector3(24, 0.03, 2.7), wpt(flip, GATE_X + 12.0, 2.0) + Vector3(0, 0.12, 0), col)

	# --- walls (walkable) ------------------------------------------------
	wall(n, wpt(flip, BACK_X, 0), Vector3(WALL_T, WALL_H, SIDE_Z * 2.0), col, dark, solids,
		Vector3(-flip, 0, 0))
	for sz in [-SIDE_Z, SIDE_Z]:
		wall(n, wpt(flip, (BACK_X + GATE_X) * 0.5, sz), Vector3(BACK_X - GATE_X, WALL_H, WALL_T),
			col, dark, solids, Vector3(0, 0, signf(sz)))
	# front wall, split around a 10-wide gate
	for fz in [-1.0, 1.0]:
		var seg_z: float = fz * ((SIDE_Z + 5.0) * 0.5 + 2.5)
		var seg_len: float = SIDE_Z - 5.0
		wall(n, wpt(flip, GATE_X, seg_z), Vector3(WALL_T, WALL_H, seg_len), col, dark, solids,
			Vector3(flip, 0, 0))
	# gate arch
	var gx: float = -flip * (GATE_X + CASTLE_SHIFT)
	for gz in [-5.4, 5.4]:
		Core.box(n, Vector3(1.6, 4.4, 1.6), Vector3(gx, 2.2, gz), Core.STONE_DARK)
		Core.box(n, Vector3(2.0, 0.4, 2.0), Vector3(gx, 4.5, gz), Core.STONE)
	Core.box(n, Vector3(1.8, 1.0, 12.4), Vector3(gx, 4.9, 0), dark)
	Core.box(n, Vector3(1.4, 0.4, 12.8), Vector3(gx, 5.5, 0), light)
	for i in 5:
		Core.box(n, Vector3(0.12, 1.2, 0.12), Vector3(gx + 0.5 * flip, 3.9, -4.4 + float(i) * 2.2), Color("2b2f36"))
	Core.box(n, Vector3(0.14, 0.14, 9.4), Vector3(gx + 0.5 * flip, 4.5, 0), Color("2b2f36"))
	Core.box(n, Vector3(0.12, 1.9, 2.2), Vector3(gx + 0.85 * flip, 3.2, 0), col)
	Core.box(n, Vector3(0.14, 0.26, 2.3), Vector3(gx + 0.88 * flip, 4.2, 0), Core.GOLD)
	Core.box(n, Vector3(0.14, 0.26, 2.3), Vector3(gx + 0.88 * flip, 2.2, 0), Core.GOLD)

	# corner towers
	for tx in [BACK_X - 0.6, GATE_X + 0.6]:
		for tz in [-SIDE_Z, SIDE_Z]:
			tower(n, wpt(flip, tx, tz), col, dark, light, solids, flip)

	# --- stairs onto the parapet ----------------------------------------
	var stair_x := BACK_X - 4.0
	for sz2 in [-1.0, 1.0]:
		stair_run(n, flip, stair_x, sz2, solids)

	# --- middle storey: a raised keep in the courtyard, holding the shrine
	var mx0: float = CX - 0.6
	var mx1: float = CX + 5.4
	var mz: float = 4.2
	var mcx: float = (mx0 + mx1) * 0.5
	Core.box(n, Vector3(mx1 - mx0, MID_H, mz * 2.0), wpt(flip, mcx, 0) + Vector3(0, MID_H * 0.5, 0),
		Core.STONE_DARK, Vector3.ZERO, 0.92)
	Core.box(n, Vector3(mx1 - mx0 + 0.4, 0.18, mz * 2.0 + 0.4), wpt(flip, mcx, 0) + Vector3(0, MID_H - 0.09, 0),
		Core.STONE, Vector3.ZERO, 0.9)
	Terrain.add_deck(rect_at(wpt(flip, mcx, 0), Vector2(mx1 - mx0 + 0.4, mz * 2.0 + 0.4)),
		Terrain.PLATEAU_H + MID_H)
	# three steps up, on the gate side
	for i in 3:
		var sh: float = MID_H * float(i + 1) / 3.0
		var sx: float = mx0 - 0.5 - float(2 - i) * 0.95
		Core.box(n, Vector3(1.05, sh, 3.6), wpt(flip, sx, 0) + Vector3(0, sh * 0.5, 0), Core.STONE_DARK, Vector3.ZERO, 0.9)
		Core.box(n, Vector3(1.1, 0.06, 3.66), wpt(flip, sx, 0) + Vector3(0, sh - 0.03, 0), Core.STONE, Vector3.ZERO, 0.9)
		Terrain.add_deck(rect_at(wpt(flip, sx, 0), Vector2(1.1, 3.66)), Terrain.PLATEAU_H + sh)
	# gold balustrade around the platform
	for i in 10:
		var bz2: float = -mz + 0.45 + float(i) * ((mz * 2.0 - 0.9) / 9.0)
		for side2 in [-1.0, 1.0]:
			Core.cyl(n, 0.07, 0.085, 0.8, wpt(flip, mcx + side2 * (mx1 - mx0) * 0.48, bz2) + Vector3(0, MID_H + 0.4, 0),
				Core.GOLD, Vector3.ZERO, 6, 0.35)
	for side3 in [-1.0, 1.0]:
		Core.box(n, Vector3(0.14, 0.11, mz * 2.0), wpt(flip, mcx + side3 * (mx1 - mx0) * 0.48, 0) + Vector3(0, MID_H + 0.82, 0),
			Core.GOLD, Vector3.ZERO, 0.35)

	# --- the shrine: three tiers, the key hangs above the top one --------
	var shrine_p := wpt(flip, mcx + 0.9, 0.0)
	Core.cyl(n, 1.15, 1.35, 0.40, shrine_p + Vector3(0, MID_H + 0.20, 0), Core.STONE_DARK, Vector3.ZERO, 16, 0.9)
	Core.cyl(n, 0.88, 0.98, 0.32, shrine_p + Vector3(0, MID_H + 0.53, 0), Core.STONE, Vector3.ZERO, 16, 0.85)
	Core.cyl(n, 0.60, 0.68, 0.26, shrine_p + Vector3(0, MID_H + 0.82, 0), Core.STONE_LIGHT, Vector3.ZERO, 16, 0.8)
	Core.torus(n, 0.46, 0.58, shrine_p + Vector3(0, MID_H + 0.97, 0), Core.GOLD)
	for i in 4:
		var a2 := TAU * float(i) / 4.0 + PI * 0.25
		Core.cyl(n, 0.05, 0.07, 2.1, shrine_p + Vector3(cos(a2) * 1.45, MID_H + 1.05, sin(a2) * 1.45),
			Core.WOOD_DARK, Vector3.ZERO, 6, 0.7)
	# no spire: the key above the altar must be visible from above

	# --- throne (where your princess must be delivered) ---------------
	var throne_p := wpt(flip, CX + 2.2, THRONE_Z)
	Core.cyl(n, 2.2, 2.6, 0.22, throne_p + Vector3(0, 0.19, 0), dark, Vector3.ZERO, 20)
	Core.cyl(n, 1.9, 2.0, 0.10, throne_p + Vector3(0, 0.33, 0), col, Vector3.ZERO, 20)
	for i in 6:
		var a := TAU * float(i) / 6.0
		Core.cyl(n, 0.10, 0.16, 0.9, throne_p + Vector3(cos(a) * 2.35, 0.45, sin(a) * 2.35), Core.GOLD, Vector3.ZERO, 8)
	Core.box(n, Vector3(1.5, 1.9, 0.35), throne_p + Vector3(-flip * 1.5, 0.95, 0), Core.WOOD_DARK, Vector3(0, 0, -flip * 8.0))
	Core.box(n, Vector3(1.4, 0.5, 0.9), throne_p + Vector3(-flip * 1.2, 0.6, 0), col)
	for bz in [-2.6, 2.6]:
		banner(n, throne_p + Vector3(-flip * 2.4, 0, bz), col, dark, flip)
	for cx2 in [-2.4, 2.4]:
		for cz2 in [-2.4, 2.4]:
			Core.cyl(n, 0.10, 0.10, 3.0, throne_p + Vector3(cx2, 1.5, cz2), Core.WOOD_DARK, Vector3.ZERO, 6)
			Core.sphere(n, 0.14, throne_p + Vector3(cx2, 3.0, cz2), Core.GOLD, 1.0, 6, 0.4)
	# no canopy: the throne has to stay readable from the iso camera
	for cx3 in [-2.4, 2.4]:
		for cz3 in [-2.4, 2.4]:
			Core.box(n, Vector3(0.14, 0.10, 0.14), throne_p + Vector3(cx3, 3.05, cz3), Core.GOLD)

	# --- dungeon (where the enemy princess is held) ------------------
	var dun_p := wpt(flip, CX + 2.2, DUNGEON_Z)
	Core.cyl(n, 2.6, 2.8, 0.30, dun_p + Vector3(0, 0.17, 0), Color("4a4f56"), Vector3.ZERO, 20)
	Core.cyl(n, 2.35, 2.35, 0.10, dun_p + Vector3(0, 0.35, 0), Core.STONE_DARK, Vector3.ZERO, 20)
	for i in 9:
		var a2 := TAU * float(i) / 9.0
		var bx := dun_p.x + cos(a2) * 2.3
		var bz2 := dun_p.z + sin(a2) * 2.3
		if (team == 0 and bx > dun_p.x + 1.2) or (team == 1 and bx < dun_p.x - 1.2):
			continue
		Core.box(n, Vector3(0.18, 2.1, 0.18), Vector3(bx, 1.35, bz2), Color("2b2f36"))
		Core.box(n, Vector3(0.24, 0.16, 0.24), Vector3(bx, 2.36, bz2), Color("1d2127"))
	Core.torus(n, 2.02, 2.34, dun_p + Vector3(0, 2.40, 0), Color("2b2f36"))
	Core.torus(n, 2.28, 2.52, dun_p + Vector3(0, 2.50, 0), dark)
	# cage door on the courtyard side: swings open when somebody has the key
	var door := Node3D.new()
	door.name = "CageDoor"
	door.position = Vector3(dun_p.x + flip * 2.3, 0.0, dun_p.z - 2.2)
	n.add_child(door)
	for i in 5:
		Core.box(door, Vector3(0.15, 2.0, 0.15), Vector3(0, 1.35, 0.5 + float(i) * 0.42), Color("2b2f36"))
	Core.box(door, Vector3(0.18, 0.18, 2.1), Vector3(0, 2.32, 1.35), Color("2b2f36"))
	Core.box(door, Vector3(0.26, 0.30, 0.26), Vector3(0, 1.35, 1.85), Core.GOLD, Vector3.ZERO, 0.5)
	Core.cyl(n, 1.5, 1.5, 0.06, dun_p + Vector3(0, 0.40, 0), Color("b9a05e"), Vector3.ZERO, 14)
	var table_p := wpt(flip, CX + 12.5, DUNGEON_Z + 3.4)
	Core.box(n, Vector3(1.8, 0.1, 1.2), table_p + Vector3(0, 0.85, 0), Core.WOOD)
	for lx in [-0.7, 0.7]:
		for lz in [-0.4, 0.4]:
			Core.box(n, Vector3(0.1, 0.85, 0.1), table_p + Vector3(lx, 0.42, lz), Core.WOOD_DARK)

	# --- courtyard clutter -------------------------------------------
	for i in 4:
		var bp := wpt(flip, BACK_X - 2.6, -10.0 + float(i) * 6.0)
		if i % 2 == 0:
			barrel(n, bp)
		else:
			crate(n, bp, col)
	for tz2 in [-13.0, 0.0, 13.0]:
		torch(n, wpt(flip, BACK_X - 1.2, tz2))
	for tx2 in [-42.0, -26.0]:
		torch(n, wpt(flip, tx2, -SIDE_Z + 1.4))

	# --- hat machines -------------------------------------------------
	var hats := []
	for i in 3:
		var hp := wpt(flip, GATE_X + 6.0, 12.0 + float(i) * -3.6)
		var cls: String = ["warrior", "ranger", "mage"][i]
		var stand := hat_station(n, hp, cls, col)
		hats.append({"pos": hp, "cls": cls, "node": stand})

	# --- spawn point --------------------------------------------------
	var spawn := wpt(flip, GATE_X + 5.0, -1.0)
	Core.flat_disc(n, 1.8, spawn + Vector3(0, 0.14, 0), col, 0.55)
	Core.flat_disc(n, 1.2, spawn + Vector3(0, 0.16, 0), light, 0.5)

	# --- gate leaf: a real door that has to be broken down ------------
	var gate_node := Node3D.new()
	gate_node.name = "GateLeaf"
	n.add_child(gate_node)
	var gate_h: float = 4.3
	for i in 7:
		var gz3 := -4.6 + float(i) * 1.53
		Core.box(gate_node, Vector3(0.32, gate_h, 1.45), Vector3(gx, gate_h * 0.5, gz3),
			Core.WOOD if i % 2 == 0 else Core.WOOD.darkened(0.18), Vector3.ZERO, 0.85)
	for band in [1.0, 2.3, 3.6]:
		Core.box(gate_node, Vector3(0.42, 0.26, 10.2), Vector3(gx, band, 0), Core.STONE_DARK, Vector3.ZERO, 0.7)
	Core.box(gate_node, Vector3(0.5, 0.3, 1.2), Vector3(gx - 0.3 * flip, 2.0, 0), Core.GOLD, Vector3.ZERO, 0.6)
	var gate_rect := rect_at(Vector3(gx, 0, 0), Vector2(1.1, 10.6))
	solids.append({"r": gate_rect, "top": Terrain.PLATEAU_H + gate_h, "tag": "gate%d" % team})

	# --- the cage key, hanging on a hook by the dungeon ----------------
	# the key waits on the shrine, one storey up: you have to climb for it
	var key_p := wpt(flip, mcx + 0.9, 0.0)
	var key_node := key_rig(n, key_p + Vector3(0, MID_H + 1.30, 0))

	# --- archer perches on the parapet --------------------------------
	var perches := [
		wpt(flip, BACK_X, -10.0), wpt(flip, BACK_X, 0.0), wpt(flip, BACK_X, 10.0),
		wpt(flip, (BACK_X + GATE_X) * 0.5, -SIDE_Z), wpt(flip, (BACK_X + GATE_X) * 0.5, SIDE_Z),
	]

	var lift := Vector3(0.0, Terrain.PLATEAU_H, 0.0)
	for h in hats:
		h["pos"] = h["pos"] + lift
	var perches_out := []
	for p in perches:
		perches_out.append(p + Vector3(0.0, WALK_H, 0.0))
	return {
		"throne": throne_p + lift,
		"dungeon": dun_p + lift,
		"spawn": spawn + lift,
		"hats": hats,
		"perches": perches_out,
		"gate_node": gate_node,
		"gate_rect": gate_rect,
		"gate_pos": Vector3(gx, 0.0, 0.0),
		"key_node": key_node,
		"cage_door": door,
		"key_pos": Vector3(key_p.x, 0.0, key_p.z),
		"gate": Vector3(-flip * (GATE_X + CASTLE_SHIFT - 1.0), Terrain.PLATEAU_H, 0.0),
		"court": wpt(flip, CX, 0) + lift,
		"table": table_p + lift,
	}


## A flight of steps from the courtyard up to the parapet. Each tread is both a
## visual box and a walkable deck, so movement follows it step by step.
static func stair_run(parent: Node3D, flip: float, lx: float, side: float, solids: Array) -> void:
	var steps := 11
	var run := 1.15
	var rise: float = (WALL_H + 0.22) / float(steps)
	var z0: float = side * ((SIDE_Z - WALL_T * 0.5 - 0.15) - run * float(steps))
	for i in steps:
		var h: float = Terrain.PLATEAU_H + rise * float(i + 1)
		var lz: float = z0 + side * run * float(i)
		var p := wpt(flip, lx, lz)
		# solid riser: bottom sits on the previous step, top IS the walk surface,
		# so the tread and Terrain.h agree to the millimetre
		Core.box(parent, Vector3(2.7, rise, run + 0.12), Vector3(p.x, h - rise * 0.5, p.z), Core.STONE_DARK, Vector3.ZERO, 0.9)
		Core.box(parent, Vector3(2.8, 0.05, run + 0.14), Vector3(p.x, h - 0.025, p.z), Core.STONE, Vector3.ZERO, 0.9)
		Terrain.add_deck(Rect2(p.x - 1.4, p.z - run * 0.5 - 0.06, 2.8, run + 0.12), h)


static func wall(parent: Node3D, centre: Vector3, size: Vector3, col: Color, dark: Color,
		solids: Array, outer: Vector3) -> void:
	var top: float = Terrain.PLATEAU_H + size.y + 0.22
	Core.box(parent, size, centre + Vector3(0, size.y * 0.5, 0), dark)
	Core.box(parent, size - Vector3(0.3, 0.4, 0.3), centre + Vector3(0, size.y * 0.5, 0), col)
	# walkway slab: this is the part archers stand on
	Core.box(parent, Vector3(size.x, 0.22, size.z), centre + Vector3(0, size.y + 0.11, 0), Core.STONE_DARK)
	Core.box(parent, Vector3(size.x + 0.1, 0.06, size.z + 0.1), centre + Vector3(0, size.y + 0.24, 0), Core.STONE)
	# merlons on the outside face only, so the walkway behind them stays clear
	var along_x: bool = size.x > size.z
	var span: float = size.x if along_x else size.z
	var steps: int = maxi(2, int(span / 1.8))
	var inset: float = (size.z * 0.5 if along_x else size.x * 0.5) - 0.5
	for i in steps:
		var t := -span * 0.5 + 0.9 + float(i) * (span / float(steps))
		var mp: Vector3
		if along_x:
			mp = centre + Vector3(t, size.y + 0.6, outer.z * inset)
		else:
			mp = centre + Vector3(outer.x * inset, size.y + 0.6, t)
		var ms := Vector3(0.95, 0.85, size.z * 0.55) if along_x else Vector3(size.x * 0.55, 0.85, 0.95)
		Core.box(parent, ms, mp, dark, Vector3.ZERO, 0.9)
	Terrain.add_deck(rect_at(centre, Vector2(size.x, size.z)), top)
	solids.append({"r": rect_at(centre, Vector2(size.x, size.z)), "top": top})


static func tower(parent: Node3D, p: Vector3, col: Color, dark: Color, light: Color,
		solids: Array, flip: float) -> void:
	Core.cyl(parent, 2.0, 2.3, 4.2, p + Vector3(0, 2.1, 0), dark, Vector3.ZERO, 10)
	Core.cyl(parent, 1.8, 2.0, 3.8, p + Vector3(0, 2.15, 0), col, Vector3.ZERO, 10)
	Core.cyl(parent, 2.6, 2.6, 0.4, p + Vector3(0, 4.3, 0), Core.STONE_DARK, Vector3.ZERO, 10)
	for i in 6:
		var a := TAU * float(i) / 6.0
		Core.box(parent, Vector3(0.8, 0.6, 0.8), p + Vector3(cos(a) * 2.2, 4.8, sin(a) * 2.2), dark,
				Vector3(0, rad_to_deg(a), 0))
	Core.cyl(parent, 0.06, 0.06, 1.2, p + Vector3(0, 5.5, 0), Core.WOOD_DARK, Vector3.ZERO, 6)
	Core.box(parent, Vector3(0.05, 0.7, 0.9), p + Vector3(0.25 * flip, 5.6, 0), light)
	Terrain.add_deck(rect_at(p, Vector2(4.0, 4.0)), Terrain.PLATEAU_H + 4.5)
	solids.append({"r": rect_at(p, Vector2(4.4, 4.4)), "top": Terrain.PLATEAU_H + 6.2})


static func banner(parent: Node3D, p: Vector3, col: Color, dark: Color, flip: float) -> void:
	Core.cyl(parent, 0.07, 0.09, 3.2, p + Vector3(0, 1.6, 0), Core.WOOD_DARK, Vector3.ZERO, 6)
	Core.box(parent, Vector3(0.06, 1.4, 1.0), p + Vector3(0.06 * flip, 2.2, 0.55 * flip), col)
	Core.box(parent, Vector3(0.08, 0.35, 1.05), p + Vector3(0.07 * flip, 2.9, 0.55 * flip), Core.GOLD)
	Core.cyl(parent, 0.14, 0.14, 0.12, p + Vector3(0, 3.25, 0), Core.GOLD, Vector3.ZERO, 8)


static func hat_station(parent: Node3D, p: Vector3, cls: String, col: Color) -> Node3D:
	Core.cyl(parent, 0.62, 0.75, 0.75, p + Vector3(0, 0.37, 0), Core.STONE_DARK, Vector3.ZERO, 10)
	Core.cyl(parent, 0.55, 0.62, 0.12, p + Vector3(0, 0.8, 0), Core.STONE_LIGHT, Vector3.ZERO, 10)
	Core.flat_disc(parent, 1.15, p + Vector3(0, 0.10, 0), col, 0.35)
	var hat := Node3D.new()
	hat.name = "Hat"
	hat.position = p + Vector3(0, 1.25, 0)
	parent.add_child(hat)
	hat_piece(hat, cls)
	return hat


## A dropped hat lying on the ground, waiting for a hatless worker.
static func dropped_hat(parent: Node3D, cls: String, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	parent.add_child(n)
	Core.flat_disc(n, 0.85, Vector3(0, 0.03, 0), Color("ffd447"), 0.18)
	var hat := Node3D.new()
	hat.position = Vector3(0, 0.22, 0)
	hat.rotation = Vector3(0.35, 0.0, 0.25)
	n.add_child(hat)
	hat_piece(hat, cls)
	return n


static func hat_piece(parent: Node3D, cls: String) -> void:
	if cls == "warrior":
		Core.cyl(parent, 0.30, 0.32, 0.30, Vector3.ZERO, Core.STONE_LIGHT, Vector3.ZERO, 10)
		Core.box(parent, Vector3(0.10, 0.30, 0.55), Vector3(0, 0.22, 0), Core.RED)
	elif cls == "ranger":
		Core.cyl(parent, 0.04, 0.36, 0.46, Vector3(0, 0.10, 0), Core.GREEN, Vector3.ZERO, 10)
		Core.cyl(parent, 0.36, 0.36, 0.08, Vector3(0, -0.12, 0), Core.GREEN.darkened(0.2), Vector3.ZERO, 10)
	elif cls == "worker":
		Core.cyl(parent, 0.30, 0.32, 0.24, Vector3(0, 0.04, 0), Core.WOOD, Vector3.ZERO, 10)
		Core.box(parent, Vector3(0.42, 0.07, 0.42), Vector3(0, -0.09, 0), Core.WOOD_DARK)
		Core.box(parent, Vector3(0.30, 0.10, 0.10), Vector3(0, 0.19, 0.02), Core.STONE_LIGHT)
	else:
		Core.cyl(parent, 0.03, 0.34, 0.62, Vector3(0, 0.16, 0), Core.PURPLE, Vector3.ZERO, 10)
		Core.cyl(parent, 0.46, 0.46, 0.07, Vector3(0, -0.14, 0), Core.PURPLE.darkened(0.25), Vector3.ZERO, 12)
		Core.sphere(parent, 0.09, Vector3(0, 0.5, 0), Core.GOLD, 1.0, 8, 0.4)


static func barrel(parent: Node3D, p: Vector3) -> void:
	Core.cyl(parent, 0.42, 0.42, 0.95, p + Vector3(0, 0.48, 0), Core.WOOD, Vector3.ZERO, 12)
	Core.cyl(parent, 0.45, 0.45, 0.10, p + Vector3(0, 0.28, 0), Core.WOOD_DARK, Vector3.ZERO, 12)
	Core.cyl(parent, 0.45, 0.45, 0.10, p + Vector3(0, 0.72, 0), Core.WOOD_DARK, Vector3.ZERO, 12)
	Core.cyl(parent, 0.36, 0.36, 0.05, p + Vector3(0, 0.97, 0), Core.WOOD_DARK, Vector3.ZERO, 12)


static func crate(parent: Node3D, p: Vector3, col: Color) -> void:
	Core.box(parent, Vector3(0.92, 0.92, 0.92), p + Vector3(0, 0.46, 0), Core.WOOD, Vector3(0, 12, 0))
	Core.box(parent, Vector3(0.98, 0.14, 0.98), p + Vector3(0, 0.46, 0), Core.WOOD_DARK, Vector3(0, 12, 0))
	Core.box(parent, Vector3(0.30, 0.30, 0.30), p + Vector3(0.25, 0.96, -0.1), col, Vector3(0, 20, 0))


static func torch(parent: Node3D, p: Vector3) -> void:
	Core.cyl(parent, 0.06, 0.06, 0.85, p + Vector3(0, 1.55, 0), Core.WOOD_DARK, Vector3.ZERO, 6)
	Core.cyl(parent, 0.16, 0.10, 0.28, p + Vector3(0, 2.05, 0), Core.INK, Vector3.ZERO, 8)
	var f := Core.sphere(parent, 0.17, p + Vector3(0, 2.22, 0), Color("ff9a3c"), 1.5, 8, 0.35)
	f.material_override = Core.mat(Color("ff9a3c"), 0.4, 0.0, 2.6)


# ================================================================= projectiles
## Arrow: shaft, bright head, fletching. Built pointing down +Z so the game can
## aim it with rotation.y alone.
static func arrow_model(parent: Node3D) -> void:
	Core.box(parent, Vector3(0.075, 0.075, 1.05), Vector3.ZERO, Core.WOOD, Vector3.ZERO, 0.7)
	var head := Core.cyl(parent, 0.0, 0.12, 0.30, Vector3(0, 0, 0.62), Color("f2f6ff"), Vector3(90, 0, 0), 6, 0.3)
	head.material_override = Core.mat(Color("f2f6ff"), 0.2, 0.5, 0.9)
	for i in 3:
		var a := TAU * float(i) / 3.0
		Core.box(parent, Vector3(0.025, 0.22, 0.34), Vector3(cos(a) * 0.05, sin(a) * 0.05, -0.44),
			Core.RED_LIGHT, Vector3(0, 0, rad_to_deg(a)))
	# a glowing head: the single biggest thing that makes a thin arrow visible
	var glow := Core.sphere(parent, 0.10, Vector3(0, 0, 0.56), Color("fff3c4"), 1.0, 8, 0.3)
	glow.material_override = Core.mat(Color("fff3c4"), 0.3, 0.0, 1.6)


## Fireball: a lumpy burning core with a flame tail, not a bare sphere.
static func fireball_model(parent: Node3D) -> void:
	var core := Core.sphere(parent, 0.26, Vector3(0, 0, 0.06), Color("f2541b"), 1.05, 10, 0.35)
	core.material_override = Core.mat(Color("f2541b"), 0.4, 0.0, 1.35)
	var inner := Core.sphere(parent, 0.135, Vector3(0, 0, 0.18), Color("ffb43a"), 1.0, 8, 0.3)
	inner.material_override = Core.mat(Color("ffb43a"), 0.3, 0.0, 2.0)
	# long flame tail: the shape is what separates this from "a sphere"
	var tail := Core.cyl(parent, 0.24, 0.015, 0.85, Vector3(0, 0, -0.46), Color("e2401a"), Vector3(90, 0, 0), 8, 0.5)
	tail.material_override = Core.mat(Color("e2401a"), 0.45, 0.0, 1.15)
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		Core.sphere(parent, 0.10, Vector3(cos(a) * 0.26, sin(a) * 0.26, 0.02),
			Color("ff9a3c"), 1.0, 6, 0.3)


## Wood pile or ore rock: the worker's raw materials.
static func resource_node(parent: Node3D, kind: String, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	n.name = "Res_" + kind
	parent.add_child(n)
	if kind == "wood":
		for i in 3:
			Core.cyl(n, 0.21, 0.23, 1.5, Vector3(-0.30 + float(i) * 0.30, 0.24 + float(i) * 0.30, 0.05 * float(i)),
				Core.WOOD if i % 2 == 0 else Core.WOOD_DARK, Vector3(0, 0, 90), 8)
		Core.box(n, Vector3(1.3, 0.10, 0.30), Vector3(0, 0.06, 0.3), Core.WOOD_DARK)
		Core.flat_disc(n, 1.1, Vector3(0, 0.02, 0), Color("b08a5a"), 0.25)
	else:
		Core.sphere(n, 0.60, Vector3(0, 0.34, 0), Core.STONE_DARK, 0.65, 8, 0.95)
		Core.sphere(n, 0.38, Vector3(0.42, 0.26, 0.22), Core.STONE, 0.6, 7, 0.95)
		for i in 3:
			Core.box(n, Vector3(0.12, 0.12, 0.34), Vector3(-0.2 + float(i) * 0.22, 0.52, 0.1 - float(i) * 0.12),
				Color("b9c6d4"), Vector3(0, float(i) * 40.0, 20))
		Core.flat_disc(n, 1.1, Vector3(0, 0.02, 0), Color("9fc6d8"), 0.25)
	return n


## A gold key, drawn small but readable: bow, shaft, two teeth.
static func key_rig(parent: Node3D, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	parent.add_child(n)
	var gold := Core.mat(Core.GOLD, 0.35, 0.7, 0.35)
	var bow := Core.torus(n, 0.13, 0.21, Vector3.ZERO, Core.GOLD)
	bow.material_override = gold
	bow.rotation_degrees = Vector3(90, 0, 0)
	var shaft := Core.cyl(n, 0.045, 0.045, 0.62, Vector3(0, -0.40, 0), Core.GOLD, Vector3.ZERO, 6, 0.4)
	shaft.material_override = gold
	Core.box(n, Vector3(0.16, 0.07, 0.07), Vector3(0.10, -0.62, 0), Core.GOLD, Vector3.ZERO, 0.4)
	Core.box(n, Vector3(0.11, 0.07, 0.07), Vector3(0.08, -0.48, 0), Core.GOLD, Vector3.ZERO, 0.4)
	return n


static func rect_at(centre: Vector3, size_xz: Vector2) -> Rect2:
	return Rect2(centre.x - size_xz.x * 0.5, centre.z - size_xz.y * 0.5, size_xz.x, size_xz.y)

# ================================================================= props
static func cake_pile(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	Core.cyl(n, 0.62, 0.66, 0.10, Vector3(0, 0.05, 0), Core.STONE_LIGHT, Vector3.ZERO, 14)
	Core.cyl(n, 0.52, 0.52, 0.05, Vector3(0, 0.12, 0), Core.WOOD)
	for i in 3:
		var a := TAU * float(i) / 3.0
		var slice_n := Node3D.new()
		slice_n.position = Vector3(cos(a) * 0.22, 0.16, sin(a) * 0.22)
		slice_n.rotation_degrees.y = rad_to_deg(a)
		n.add_child(slice_n)
		Core.box(slice_n, Vector3(0.30, 0.26, 0.22), Vector3(0, 0.13, 0), Core.CAKE)
		Core.box(slice_n, Vector3(0.32, 0.07, 0.24), Vector3(0, 0.27, 0), Core.FROST)
		Core.sphere(slice_n, 0.06, Vector3(0, 0.33, 0), Core.CHERRY, 1.0, 8, 0.4)
	var glow := Core.flat_disc(n, 0.95, Vector3(0, 0.015, 0), Core.FROST, 0.30)
	glow.name = "Glow"
	n.name = "CakePile"
	return n


static func dummy(parent: Node3D, p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	parent.add_child(n)
	Core.cyl(n, 0.10, 0.14, 1.2, Vector3(0, 0.6, 0), Core.WOOD_DARK, Vector3.ZERO, 6)
	Core.cyl(n, 0.5, 0.55, 0.9, Vector3(0, 1.3, 0), Core.DIRT.lerp(Color("cbb27a"), 0.5), Vector3.ZERO, 10)
	Core.sphere(n, 0.3, Vector3(0, 1.92, 0), Color("d8c391"), 1.0, 8)
	Core.box(n, Vector3(0.7, 0.1, 0.1), Vector3(0, 1.65, 0), Core.WOOD_DARK)
	Core.box(n, Vector3(0.1, 0.1, 0.7), Vector3(0, 1.65, 0), Core.WOOD_DARK)
	n.name = "Dummy"
	return n

# ================================================================= fighters
## Returns a rigged fighter model. `root` is at the feet; `body` bobs; `arm` swings.
## A limb built as two tapered segments around a joint node so the walk cycle
## can bend it properly: shoulder -> elbow -> hand, hip -> knee -> foot.
static func _limb(parent: Node3D, at: Vector3, up_len: float, lo_len: float,
		r0: float, r1: float, r2: float, r3: float, col: Color) -> Dictionary:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	Core.cyl(pivot, r0, r1, up_len, Vector3(0, -up_len * 0.5, 0), col, Vector3.ZERO, 10, 0.78)
	var joint := Node3D.new()
	joint.position = Vector3(0, -up_len, 0)
	pivot.add_child(joint)
	Core.sphere(joint, r1 * 1.15, Vector3.ZERO, col, 1.0, 10, 0.78)
	Core.cyl(joint, r2, r3, lo_len, Vector3(0, -lo_len * 0.5, 0), col, Vector3.ZERO, 10, 0.78)
	var end := Node3D.new()
	end.position = Vector3(0, -lo_len, 0)
	joint.add_child(end)
	return {"pivot": pivot, "joint": joint, "end": end}


## Head: skull, jaw, brow, nose, eyes with a catchlight, ears, and the class's
## headgear. All of it is primitives, but the proportions are what sell it.
static func _head(parent: Node3D, cls: String) -> Node3D:
	var head := Node3D.new()
	head.name = "Head"
	head.rotation.x = -0.12
	parent.add_child(head)
	Core.sphere(head, 0.20, Vector3(0, 0.055, 0), Core.SKIN, 1.02, 14, 0.7)
	Core.box(head, Vector3(0.175, 0.10, 0.155), Vector3(0, -0.045, 0.012), Core.SKIN, Vector3.ZERO, 0.7)
	Core.sphere(head, 0.062, Vector3(0, -0.085, 0.03), Core.SKIN, 0.95, 10, 0.7)   # chin
	# brow ridge and nose
	Core.box(head, Vector3(0.175, 0.022, 0.04), Vector3(0, 0.088, 0.152), Core.SKIN.darkened(0.12), Vector3.ZERO, 0.7)
	Core.box(head, Vector3(0.042, 0.062, 0.05), Vector3(0, 0.038, 0.178), Core.SKIN.darkened(0.05), Vector3(0, 0, 0), 0.7)
	# eyes: dark socket, white bead, tiny pupil glint
	for sx in [-1.0, 1.0]:
		Core.sphere(head, 0.034, Vector3(0.066 * sx, 0.048, 0.158), Color("f3f4f6"), 1.0, 8, 0.4)
		Core.sphere(head, 0.017, Vector3(0.072 * sx, 0.046, 0.184), Color("2a2118"), 1.0, 6, 0.35)
		Core.sphere(head, 0.030, Vector3(0.19 * sx, 0.045, 0.005), Core.SKIN.darkened(0.10), 1.0, 8, 0.7)  # ear
	Core.box(head, Vector3(0.062, 0.014, 0.022), Vector3(0, -0.028, 0.168), Color("8a5a52"), Vector3.ZERO, 0.6)
	var gear := Node3D.new()
	gear.position = Vector3(0, 0.155, 0)
	head.add_child(gear)
	head_gear(gear, cls)
	return head


static func head_gear(parent: Node3D, cls: String) -> void:
	match cls:
		"warrior":
			Core.cyl(parent, 0.208, 0.215, 0.15, Vector3(0, 0.06, 0), Core.STONE_LIGHT, Vector3.ZERO, 12, 0.45)
			Core.cyl(parent, 0.218, 0.218, 0.032, Vector3(0, -0.015, 0), Core.STONE, Vector3.ZERO, 12, 0.5)
			Core.box(parent, Vector3(0.045, 0.16, 0.05), Vector3(0, 0.10, 0.185), Core.STONE_LIGHT, Vector3(0, 0, 0), 0.4)
			Core.box(parent, Vector3(0.055, 0.20, 0.34), Vector3(0, 0.19, -0.02), Core.RED, Vector3.ZERO, 0.8)
		"ranger":
			Core.cyl(parent, 0.02, 0.20, 0.28, Vector3(0, 0.13, -0.03), Core.GREEN, Vector3.ZERO, 12, 0.85)
			Core.cyl(parent, 0.215, 0.225, 0.065, Vector3(0, 0.01, -0.02), Core.GREEN.darkened(0.22), Vector3.ZERO, 14, 0.85)
			Core.box(parent, Vector3(0.30, 0.22, 0.10), Vector3(0, -0.02, -0.16), Core.GREEN.darkened(0.12), Vector3(0, 0, 0), 0.85)
		"mage":
			Core.cyl(parent, 0.022, 0.185, 0.44, Vector3(0, 0.22, 0), Core.PURPLE, Vector3.ZERO, 12, 0.85)
			Core.cyl(parent, 0.245, 0.245, 0.05, Vector3(0, 0.02, 0), Core.PURPLE.darkened(0.28), Vector3.ZERO, 16, 0.85)
			Core.sphere(parent, 0.045, Vector3(0, 0.43, 0), Core.GOLD, 1.0, 8, 0.35)
		"worker":
			Core.cyl(parent, 0.195, 0.205, 0.11, Vector3(0, 0.035, 0), Core.WOOD, Vector3.ZERO, 12, 0.8)
			Core.box(parent, Vector3(0.26, 0.035, 0.20), Vector3(0, -0.03, 0.12), Core.WOOD_DARK, Vector3.ZERO, 0.8)
		_:
			Core.sphere(parent, 0.208, Vector3(0, 0.02, -0.02), Core.WOOD_DARK, 0.82, 12, 0.85)
			Core.sphere(parent, 0.075, Vector3(0.09, 0.10, 0.10), Core.WOOD_DARK, 1.0, 8, 0.85)


static func fighter(parent: Node3D, team: int, cls: String) -> Dictionary:
	var col := team_col(team)
	var dark := team_dark(team)
	var light := team_light(team)
	var robe := cls == "mage"
	var root := Node3D.new()
	root.scale = Vector3(1.24, 1.24, 1.24)
	parent.add_child(root)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# ---- legs: thigh -> knee -> shin -> boot
	var leg_col := Core.PURPLE.darkened(0.30) if robe else dark
	var leg_l_r := _limb(body, Vector3(-0.135, 0.92, 0), 0.40, 0.37, 0.090, 0.074, 0.070, 0.058, leg_col)
	var leg_r_r := _limb(body, Vector3(0.135, 0.92, 0), 0.40, 0.37, 0.090, 0.074, 0.070, 0.058, leg_col)
	for l in [leg_l_r, leg_r_r]:
		Core.box(l["end"], Vector3(0.145, 0.105, 0.255), Vector3(0, -0.045, 0.045), Core.INK, Vector3.ZERO, 0.65)
	var leg_l: Node3D = leg_l_r["pivot"]
	var leg_r: Node3D = leg_r_r["pivot"]

	# ---- hips, belt, tabard
	var hips := Node3D.new()
	hips.position = Vector3(0, 0.92, 0)
	body.add_child(hips)
	Core.cyl(hips, 0.178, 0.168, 0.20, Vector3(0, 0.02, 0), dark, Vector3.ZERO, 12, 0.8)
	Core.cyl(hips, 0.186, 0.186, 0.055, Vector3(0, 0.115, 0), Core.WOOD_DARK, Vector3.ZERO, 12, 0.6)
	Core.box(hips, Vector3(0.072, 0.058, 0.03), Vector3(0, 0.115, 0.176), Core.GOLD, Vector3.ZERO, 0.3)
	Core.box(hips, Vector3(0.205, 0.30, 0.035), Vector3(0, -0.08, 0.158), col, Vector3.ZERO, 0.9)
	Core.box(hips, Vector3(0.205, 0.022, 0.04), Vector3(0, -0.225, 0.158), Core.GOLD, Vector3.ZERO, 0.4)

	# ---- torso: waist, chest, neck, shoulder pads
	var torso := Node3D.new()
	torso.position = Vector3(0, 1.02, 0)
	body.add_child(torso)
	Core.cyl(torso, 0.186, 0.158, 0.15, Vector3(0, 0.075, 0), col, Vector3.ZERO, 12, 0.85)
	Core.cyl(torso, 0.214, 0.190, 0.21, Vector3(0, 0.245, 0), col, Vector3.ZERO, 12, 0.85)
	Core.sphere(torso, 0.212, Vector3(0, 0.345, 0), col, 0.78, 12, 0.85)
	Core.box(torso, Vector3(0.10, 0.14, 0.03), Vector3(0, 0.30, 0.196), light, Vector3.ZERO, 0.8)  # chest plate
	Core.cyl(torso, 0.068, 0.082, 0.10, Vector3(0, 0.445, 0), Core.SKIN, Vector3.ZERO, 8, 0.7)
	Core.sphere(torso, 0.104, Vector3(-0.208, 0.395, 0), light, 0.88, 10, 0.8)
	Core.sphere(torso, 0.104, Vector3(0.208, 0.395, 0), light, 0.88, 10, 0.8)

	# ---- head
	var head := _head(torso, cls)
	head.position = Vector3(0, 0.545, 0)

	# ---- arms: upper -> elbow -> forearm -> hand
	var arm_l_r := _limb(torso, Vector3(-0.238, 0.375, 0), 0.255, 0.24, 0.068, 0.058, 0.050, 0.043, dark)
	var arm_r_r := _limb(torso, Vector3(0.238, 0.375, 0), 0.255, 0.24, 0.068, 0.058, 0.050, 0.043, dark)
	# forearms in skin tone so the silhouette breaks up
	for a2 in [arm_l_r, arm_r_r]:
		Core.cyl(a2["joint"], 0.048, 0.042, 0.22, Vector3(0, -0.13, 0), Core.SKIN, Vector3.ZERO, 10, 0.7)
	var arm: Node3D = arm_r_r["pivot"]
	var arm_l: Node3D = arm_l_r["pivot"]
	Core.box(arm_r_r["end"], Vector3(0.082, 0.10, 0.086), Vector3(0, -0.02, 0.005), Core.SKIN, Vector3.ZERO, 0.7)
	Core.box(arm_l_r["end"], Vector3(0.082, 0.10, 0.086), Vector3(0, -0.02, 0.005), Core.SKIN, Vector3.ZERO, 0.7)
	for a in [arm_l_r, arm_r_r]:
		Core.cyl(a["joint"], 0.062, 0.062, 0.03, Vector3(0, -0.02, 0), dark, Vector3.ZERO, 10, 0.8)

	var hand_r: Node3D = arm_r_r["end"]
	var hand_l: Node3D = arm_l_r["end"]
	var weapon: Node3D = null

	# ---- class gear
	match cls:
		"warrior":
			# sword in the right hand, blade down and slightly forward
			Core.cyl(hand_r, 0.028, 0.030, 0.17, Vector3(0, -0.02, 0), Core.WOOD_DARK, Vector3.ZERO, 8, 0.6)
			Core.sphere(hand_r, 0.042, Vector3(0, 0.075, 0), Core.GOLD, 1.0, 8, 0.25)
			Core.box(hand_r, Vector3(0.29, 0.05, 0.075), Vector3(0, -0.115, 0), Core.GOLD, Vector3.ZERO, 0.3)
			weapon = Core.box(hand_r, Vector3(0.045, 0.86, 0.075), Vector3(0.015, -0.56, 0.06), Core.STONE_LIGHT, Vector3(0.12, 0, -0.08), 0.28)
			Core.sphere(hand_r, 0.05, Vector3(0, -0.99, 0), Core.STONE_LIGHT, 1.0, 6, 0.28)
			# round shield on the left forearm
			Core.cyl(hand_l, 0.30, 0.30, 0.055, Vector3(-0.045, 0.04, 0.02), col, Vector3(0, 0, 90), 16, 0.8)
			Core.torus(hand_l, 0.255, 0.31, Vector3(-0.05, 0.04, 0.02), Core.GOLD, Vector3(0, 0, 90))
			Core.sphere(hand_l, 0.075, Vector3(-0.075, 0.04, 0.02), Core.GOLD, 1.0, 8, 0.3)
		"ranger":
			# bow held vertical, string toward the body
			var bow := Node3D.new()
			bow.position = Vector3(0, 0.0, 0.03)
			hand_r.add_child(bow)
			Core.cyl(bow, 0.026, 0.026, 0.56, Vector3(0, 0, 0.02), Core.WOOD, Vector3.ZERO, 8, 0.7)
			Core.cyl(bow, 0.024, 0.018, 0.22, Vector3(0, 0.36, 0.05), Core.WOOD, Vector3(28, 0, 0), 8, 0.7)
			Core.cyl(bow, 0.024, 0.018, 0.22, Vector3(0, -0.36, 0.05), Core.WOOD, Vector3(-28, 0, 0), 8, 0.7)
			Core.box(bow, Vector3(0.012, 0.98, 0.012), Vector3(0, 0, 0.085), Color("efe7d2"), Vector3.ZERO, 0.4)
			weapon = bow
			# quiver with fletchings
			Core.cyl(torso, 0.10, 0.085, 0.40, Vector3(0.16, 0.22, -0.20), Core.WOOD_DARK, Vector3(14, 0, 0), 10, 0.75)
			for i in 3:
				Core.cyl(torso, 0.012, 0.012, 0.22, Vector3(0.14 + float(i) * 0.03, 0.48, -0.245), Core.STONE_LIGHT, Vector3(14, 0, 0), 6, 0.5)
				Core.box(torso, Vector3(0.055, 0.05, 0.012), Vector3(0.14 + float(i) * 0.03, 0.575, -0.272), Color("f2f6ff"), Vector3.ZERO, 0.6)
		"mage":
			# long staff, orb at the top, cape behind
			var staff := Node3D.new()
			staff.position = Vector3(0, -0.02, 0.04)
			staff.rotation.z = -0.26
			staff.rotation.x = -0.12
			hand_r.add_child(staff)
			Core.cyl(staff, 0.028, 0.032, 1.28, Vector3(0, 0.34, 0), Core.WOOD_DARK, Vector3.ZERO, 8, 0.7)
			Core.torus(staff, 0.075, 0.10, Vector3(0, 1.00, 0), Core.GOLD, Vector3(0, 0, 0))
			weapon = Core.sphere(staff, 0.105, Vector3(0, 1.00, 0), Core.TEAL, 1.0, 12, 0.25)
			weapon.material_override = Core.mat(Core.TEAL, 0.25, 0.0, 2.4)
			Core.box(torso, Vector3(0.36, 0.62, 0.04), Vector3(0, 0.20, -0.185), Core.PURPLE.darkened(0.35), Vector3(6, 0, 0), 0.9)
			Core.cyl(hips, 0.215, 0.255, 0.24, Vector3(0, -0.09, 0), Core.PURPLE.darkened(0.22), Vector3.ZERO, 12, 0.9)
		"worker":
			# hammer: handle in the fist, heavy head up top
			Core.cyl(hand_r, 0.030, 0.034, 0.52, Vector3(0, 0.10, 0.02), Core.WOOD, Vector3.ZERO, 8, 0.75)
			weapon = Core.box(hand_r, Vector3(0.14, 0.155, 0.34), Vector3(0, 0.38, 0.02), Core.STONE, Vector3.ZERO, 0.5)
			Core.box(hand_r, Vector3(0.145, 0.06, 0.12), Vector3(0, 0.38, 0.02), Core.STONE_DARK, Vector3.ZERO, 0.5)
			Core.box(torso, Vector3(0.34, 0.42, 0.035), Vector3(0, 0.16, 0.196), Core.FROST, Vector3.ZERO, 0.95)
		_:
			# villager: a satchel over the shoulder, nothing else
			Core.box(torso, Vector3(0.055, 0.56, 0.035), Vector3(0.10, 0.24, 0.19), Core.WOOD_DARK, Vector3(0, 0, -18), 0.9)
			Core.box(torso, Vector3(0.22, 0.24, 0.14), Vector3(-0.18, 0.03, 0.10), Core.WOOD, Vector3(0, 12, 0), 0.85)

	return {
		"root": root, "body": body, "torso": torso, "head": head,
		"arm": arm, "arm_l": arm_l, "weapon": weapon,
		"leg_l": leg_l, "leg_r": leg_r,
		"knee_l": leg_l_r["joint"], "knee_r": leg_r_r["joint"],
		"elbow_l": arm_l_r["joint"], "elbow_r": arm_r_r["joint"],
	}


# ================================================================= princess
static func princess(parent: Node3D, team: int) -> Dictionary:
	var col := team_col(team)
	var dark := team_dark(team)
	var root := Node3D.new()
	root.scale = Vector3(1.22, 1.22, 1.22)
	parent.add_child(root)
	var body := Node3D.new()
	root.add_child(body)

	# The silhouette is the weight read: a bell skirt that widens, a bodice,
	# a gut that swells out in front of it, and a head that keeps its size.
	var dress := Core.cyl(body, 0.28, 0.62, 0.72, Vector3(0, 0.36, 0), col, Vector3.ZERO, 16)
	Core.cyl(body, 0.65, 0.65, 0.08, Vector3(0, 0.04, 0), dark, Vector3.ZERO, 16)
	Core.cyl(body, 0.25, 0.33, 0.36, Vector3(0, 0.90, 0), col, Vector3.ZERO, 14)
	Core.cyl(body, 0.27, 0.30, 0.24, Vector3(0, 1.05, 0), Core.FROST, Vector3.ZERO, 14)
	var belly := Core.sphere(body, 0.30, Vector3(0, 0.72, 0.09), col.lightened(0.16), 0.82, 14)
	belly.visible = false

	var head := Node3D.new()
	head.position = Vector3(0, 1.42, 0)
	body.add_child(head)
	Core.sphere(head, 0.28, Vector3.ZERO, Core.SKIN, 1.0, 12)
	Core.sphere(head, 0.30, Vector3(0, 0.05, -0.08), Core.GOLD.darkened(0.45), 0.72, 12)
	Core.box(head, Vector3(0.10, 0.10, 0.06), Vector3(-0.10, 0.02, 0.24), Core.INK)
	Core.box(head, Vector3(0.10, 0.10, 0.06), Vector3(0.10, 0.02, 0.24), Core.INK)
	Core.box(head, Vector3(0.11, 0.06, 0.04), Vector3(-0.16, -0.06, 0.22), Color("e08a8a"))
	Core.box(head, Vector3(0.11, 0.06, 0.04), Vector3(0.16, -0.06, 0.22), Color("e08a8a"))
	var mouth := Core.box(head, Vector3(0.14, 0.05, 0.05), Vector3(0, -0.13, 0.24), Color("7d2b31"))
	var crown := Node3D.new()
	crown.position = Vector3(0, 0.26, 0)
	head.add_child(crown)
	Core.cyl(crown, 0.17, 0.17, 0.05, Vector3.ZERO, Core.GOLD, Vector3.ZERO, 10)
	for i in 5:
		var a := TAU * float(i) / 5.0
		Core.cyl(crown, 0.0, 0.05, 0.14, Vector3(cos(a) * 0.14, 0.09, sin(a) * 0.14), Core.GOLD, Vector3.ZERO, 5)

	# arms on pivots so she can raise both hands and eat
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-0.30, 1.06, 0.0)
	body.add_child(arm_l)
	Core.box(arm_l, Vector3(0.28, 0.13, 0.13), Vector3(0.02, 0, 0.02), col)
	Core.sphere(arm_l, 0.085, Vector3(0.14, 0, 0.03), Core.SKIN, 1.0, 8)
	var arm_r := Node3D.new()
	arm_r.position = Vector3(0.30, 1.06, 0.0)
	body.add_child(arm_r)
	Core.box(arm_r, Vector3(0.28, 0.13, 0.13), Vector3(-0.02, 0, 0.02), col)
	Core.sphere(arm_r, 0.085, Vector3(-0.14, 0, 0.03), Core.SKIN, 1.0, 8)

	return {"root": root, "body": body, "dress": dress, "belly": belly,
		"head": head, "mouth": mouth, "arm_l": arm_l, "arm_r": arm_r}