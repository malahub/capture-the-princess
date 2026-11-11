class_name Core
extends RefCounted
## Shared palette, material cache and primitive-mesh helpers.
## Everything in Heavy Flag is built from primitives at runtime, so this file is
## the only place that knows what the game looks like.

# ---------------------------------------------------------------- palette
const RED := Color("cf3f36")
const RED_DARK := Color("7d211c")
const RED_LIGHT := Color("ef6a5a")
const BLUE := Color("3364cc")
const BLUE_DARK := Color("1f356f")
const BLUE_LIGHT := Color("5b8bf0")
const GRASS := Color("557f3f")
const GRASS_DARK := Color("456b34")
const GRASS_LIGHT := Color("6b9a4b")
const DIRT := Color("8d7150")
const STONE := Color("8f959d")
const STONE_DARK := Color("6d737b")
const STONE_LIGHT := Color("b6bbc2")
const WOOD := Color("8a5a33")
const WOOD_DARK := Color("5e3c22")
const SKIN := Color("f0c39a")
const SKIN_DARK := Color("c99a72")
const GOLD := Color("e8b53f")
const INK := Color("2a2320")
const CAKE := Color("e8c07a")
const FROST := Color("f6b8cf")
const CHERRY := Color("cf2f3d")
const PURPLE := Color("7a4bb5")
const GREEN := Color("4e8c4a")
const TEAL := Color("3f9c9c")

# ---------------------------------------------------------------- materials
static var _mats: Dictionary = {}

## Collapse every static MeshInstance3D under `root` into one MultiMeshInstance3D
## per (mesh, colour, roughness). Subtrees whose name matches `skip` are left
## alone (they get hidden or animated later: gate leaf, cage door, key, hats).
static func batch_static(root: Node3D, skip: Array) -> int:
	var groups := {}
	var victims: Array = []
	_gather(root, root, skip, groups, victims)
	if victims.is_empty():
		return 0
	for v in victims:
		var p: Node = v.get_parent()
		if p != null:
			p.remove_child(v)
		v.free()
	var root_inv: Transform3D = root.global_transform.affine_inverse()
	for key in groups.keys():
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		mm.instance_count = g["xf"].size()
		for i in g["xf"].size():
			mm.set_instance_transform(i, root_inv * (g["xf"][i] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat(g["col"], g["rough"])
		root.add_child(mmi)
	return victims.size()


static func _gather(root: Node3D, n: Node, skip: Array, groups: Dictionary, victims: Array) -> void:
	for ch in n.get_children():
		var nm: String = String(ch.name)
		var blocked := false
		for sk in skip:
			if nm.find(String(sk)) >= 0:
				blocked = true
				break
		if blocked:
			continue
		if ch is MeshInstance3D and ch.mesh != null and ch.material_override != null:
			# Only shared unit primitives: a custom mesh (terrain, water, the
			# crown torus) carries vertex colours or transparency that a
			# MultiMesh override would throw away.
			var shared: bool = ch.has_meta("core_prim")
			var m: BaseMaterial3D = ch.material_override
			if not shared or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var key := "%d|%s|%.2f" % [ch.mesh.get_instance_id(), m.albedo_color.to_html(), m.roughness]
			if not groups.has(key):
				groups[key] = {"mesh": ch.mesh, "col": m.albedo_color, "rough": m.roughness, "xf": []}
			var g: Dictionary = groups[key]
			g["xf"].append(ch.global_transform)
			victims.append(ch)
			continue
		_gather(root, ch, skip, groups, victims)


static func mat(color: Color, rough: float = 0.82, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

# ---------------------------------------------------------------- primitives
# Shared unit meshes: a box is a 1 m cube scaled by the node transform. That
# lets multi_mesh() instance hundreds of them in one draw call, which is what
# took the wide view from ~7000 draw calls to a few hundred.
static var _unit_box: BoxMesh = null
static var _unit_sphere: SphereMesh = null
static var _unit_cyl: CylinderMesh = null

static var _mesh_cache := {}


## Identical primitives must share one mesh resource or a MultiMesh cannot
## instance them together. This is why only a quarter of the world batched.
static func cached_mesh(key: String, maker: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = maker.call()
	return _mesh_cache[key]


static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box

static func unit_sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
		_unit_sphere.radial_segments = 12
		_unit_sphere.rings = 6
	return _unit_sphere

static func unit_cyl() -> CylinderMesh:
	if _unit_cyl == null:
		_unit_cyl = CylinderMesh.new()
		_unit_cyl.top_radius = 1.0
		_unit_cyl.bottom_radius = 1.0
		_unit_cyl.height = 1.0
		_unit_cyl.radial_segments = 16
		_unit_cyl.rings = 1
	return _unit_cyl


static func box(parent: Node, size: Vector3, pos: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO, rough: float = 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box()
	mi.scale = size
	mi.material_override = mat(color, rough)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.set_meta("core_prim", true)
	parent.add_child(mi)
	return mi

static func cyl(parent: Node, top_r: float, bot_r: float, height: float, pos: Vector3,
		color: Color, rot: Vector3 = Vector3.ZERO, segs: int = 16,
		rough: float = 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if is_equal_approx(top_r, bot_r) and segs == 16:
		mi.mesh = unit_cyl()
		mi.scale = Vector3(top_r, height, top_r)
	else:
		var kr := "c|%.3f|%.3f|%.3f|%d" % [top_r, bot_r, height, segs]
		mi.mesh = cached_mesh(kr, func() -> Mesh:
			var cm := CylinderMesh.new()
			cm.top_radius = top_r
			cm.bottom_radius = bot_r
			cm.height = height
			cm.radial_segments = segs
			cm.rings = 1
			return cm)
	mi.material_override = mat(color, rough)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.set_meta("core_prim", true)
	parent.add_child(mi)
	return mi

static func sphere(parent: Node, radius: float, pos: Vector3, color: Color,
		flat: float = 1.0, segs: int = 12, rough: float = 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if segs == 12:
		mi.mesh = unit_sphere()
		mi.scale = Vector3(radius, radius * flat, radius)
	else:
		var ks := "s|%.3f|%.3f|%d" % [radius, flat, segs]
		mi.mesh = cached_mesh(ks, func() -> Mesh:
			var sm := SphereMesh.new()
			sm.radius = radius
			sm.height = radius * 2.0 * flat
			sm.radial_segments = segs
			sm.rings = maxi(4, segs / 2)
			return sm)
	mi.material_override = mat(color, rough)
	mi.position = pos
	mi.set_meta("core_prim", true)
	parent.add_child(mi)
	return mi

static func torus(parent: Node, inner: float, outer: float, pos: Vector3, color: Color,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 22
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = mat(color, 0.7)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.set_meta("core_prim", true)
	parent.add_child(mi)
	return mi


static func flat_disc(parent: Node, radius: float, pos: Vector3, color: Color,
		alpha: float = 1.0) -> MeshInstance3D:
	var mi := cyl(parent, radius, radius, 0.02, pos, color, Vector3.ZERO, 24)
	var m := mat(color)
	if alpha < 1.0:
		var nm: StandardMaterial3D = m.duplicate()
		nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		nm.albedo_color.a = alpha
		mi.material_override = nm
	return mi

# ---------------------------------------------------------------- text
static func label3d(parent: Node, text: String, pos: Vector3, size: int = 48,
		color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.016
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.05, 0.04, 0.04, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.position = pos
	l.render_priority = 2
	parent.add_child(l)
	return l

# ---------------------------------------------------------------- audio
static var _sounds: Dictionary = {}

## Generates a short PCM tone. No audio files ship with the game.
static func tone(freq: float, dur: float, kind: String = "sine", vol: float = 0.4,
		freq2: float = 0.0) -> AudioStreamWAV:
	var key := "%.0f_%.3f_%s_%.2f_%.0f" % [freq, dur, kind, vol, freq2]
	if _sounds.has(key):
		return _sounds[key]
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var f := freq if freq2 <= 0.0 else lerpf(freq, freq2, t / dur)
		phase += TAU * f / float(rate)
		var env := pow(1.0 - t / dur, 1.8)
		var sx := sin(phase)
		if kind == "square":
			sx = signf(sx)
		elif kind == "noise":
			sx = randf_range(-1.0, 1.0)
		elif kind == "tri":
			sx = 2.0 * absf(2.0 * (phase / TAU - floor(phase / TAU + 0.5))) - 1.0
		var v := int(clampf(sx * env * vol, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_sounds[key] = w
	return w


# ---------------------------------------------------------------- input
static func setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"act": [KEY_E],
		"feed": [KEY_F],
		"drop": [KEY_Q],
		"attack": [KEY_SPACE],
		"dash": [KEY_SHIFT],
		"jump": [KEY_V],
		"help": [KEY_H],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for k in keys[action]:
			# both physical and logical bindings: some web runtimes deliver only one
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
			var ev2 := InputEventKey.new()
			ev2.keycode = k
			InputMap.action_add_event(action, ev2)
	if not InputMap.has_action("attack_mouse"):
		InputMap.add_action("attack_mouse")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack_mouse", mb)

# ---------------------------------------------------------------- math
static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-rate * dt))

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

static func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.x, d.z)
