class_name Princess
extends Node3D
## A princess is a heavy object: her weight is the whole strategy.
## Weight = cake slices fed to her. She visibly swells with every slice, and
## every slice arrives as a thrown cake she catches and chews.

var game: Node = null
var team := 0
var weight := 0.0
var max_weight := 10.0
var carried_by: Unit = null
var helpers := 0
var alive := true
var home_throne := Vector3.ZERO
var dungeon := Vector3.ZERO
var rig: Dictionary = {}
var tag: Label3D = null
var glow: MeshInstance3D = null
var decay_t := 0.0
var wobble := 0.0
var delivered := false
var locked := true          # cage door: needs the castle key
var fast_decay := false

var eat_t := 0.0                 # 1 -> 0 over EAT_TIME, drives the chew
var target_scale := Vector3.ONE

const DECAY_EVERY := 11.0
const EAT_TIME := 0.75


func setup(g: Node, t: int, dungeon_pos: Vector3, throne_pos: Vector3) -> void:
	game = g
	team = t
	dungeon = dungeon_pos
	home_throne = throne_pos
	rig = Bld.princess(self, team)
	position = Vector3(dungeon_pos.x, Terrain.h(dungeon_pos.x, dungeon_pos.z), dungeon_pos.z)
	tag = Core.label3d(self, "", Vector3(0, 2.62, 0), 40, Color.WHITE)
	# the default world pixel_size made this a 2 m tall banner across the cage
	tag.pixel_size = 0.003
	glow = Core.flat_disc(self, 2.5, Vector3(0, 0.03, 0), Bld.team_light(team), 0.30)
	glow.name = "Glow"
	recompute_target()
	refresh_visual()


## Target size from weight. Wider than taller: she should read as fat, not tall.
func recompute_target() -> void:
	var w := clampf(weight, 0.0, max_weight)
	target_scale = Vector3(1.0 + 0.105 * w, 1.0 + 0.040 * w, 1.0 + 0.105 * w)


func refresh_visual() -> void:
	if tag != null:
		if carried_by != null:
			tag.text = ""
		elif weight < 0.5:
			tag.text = "LIGHT"
			tag.modulate = Color(0.85, 0.95, 0.85)
		else:
			tag.text = "WEIGHT %d / %d" % [int(round(weight)), int(max_weight)]
			tag.modulate = Color(1.0, 0.86, 0.55) if weight < 6.0 else Color(1.0, 0.55, 0.45)
	if glow != null:
		glow.visible = carried_by == null and not delivered


## Called by the game when a thrown slice lands on her.
func eat(n: float) -> void:
	eat_t = 1.0
	wobble = 1.0
	add_weight(n)


func add_weight(n: float) -> void:
	weight = clampf(weight + n, 0.0, max_weight)
	decay_t = DECAY_EVERY
	recompute_target()
	refresh_visual()


func carry_speed_note() -> String:
	if weight >= 8.0:
		return "BACKBREAKING"
	if weight >= 5.5:
		return "HEAVY"
	if weight >= 2.0:
		return "WEIGHTED"
	return "LIGHT"


func attach(unit: Unit) -> void:
	carried_by = unit
	helpers = 0
	get_parent().remove_child(self)
	unit.add_child(self)
	position = Vector3(0, 2.55, 0)
	rotation = Vector3.ZERO
	tag.text = ""
	if glow != null:
		glow.visible = false


func detach(at: Vector3) -> void:
	carried_by = null
	helpers = 0
	var parent: Node = game.world
	if get_parent() != null:
		get_parent().remove_child(self)
	parent.add_child(self)
	position = Vector3(at.x, Terrain.h(at.x, at.z), at.z)
	rotation = Vector3.ZERO
	refresh_visual()


func update_princess(dt: float) -> void:
	if not alive:
		return
	wobble = maxf(0.0, wobble - dt * 2.0)
	if not delivered:
		# cake wears off eventually, twice as slowly while someone is hauling her
		decay_t -= dt * (0.5 if carried_by != null else 1.0) * (2.4 if fast_decay else 1.0)
		if decay_t <= 0.0:
			decay_t = DECAY_EVERY
			if weight > 0.0:
				weight = maxf(0.0, weight - 1.0)
				recompute_target()
				refresh_visual()

	eat_t = maxf(0.0, eat_t - dt / EAT_TIME)
	var p := 1.0 - clampf(eat_t, 0.0, 1.0)
	var bump := sin(p * PI)           # 0 -> 1 -> 0 through the chew

	# idle breathing, stronger the heavier she is
	var br := sin(Time.get_ticks_msec() * 0.0022) * 0.006 * weight
	var sx := target_scale.x * (1.0 + 0.14 * bump) + br
	var sy := target_scale.y * (1.0 - 0.24 * bump) - br
	if rig.has("body"):
		var body: Node3D = rig["body"]
		var want := Vector3(sx, sy, sx)
		if carried_by == null:
			want.y += sin(Time.get_ticks_msec() * 0.004) * 0.012 * weight
		body.scale = body.scale.lerp(want, 1.0 - exp(-13.0 * dt))
		body.position.y = -0.14 * bump
		body.rotation.z = sin(Time.get_ticks_msec() * 0.0016) * 0.02 * clampf(weight, 0.0, 8.0)

	# chew: head tips back, mouth opens, both hands come up to the face
	if rig.has("head"):
		var head: Node3D = rig["head"]
		head.rotation.x = lerpf(head.rotation.x, -0.5 * bump, 1.0 - exp(-16.0 * dt))
		head.position.y = 1.32 - 0.05 * bump
	if rig.has("mouth"):
		var mouth: MeshInstance3D = rig["mouth"]
		# two open-close cycles per slice: that is what makes it chew rather than gape
		var chew := absf(sin(p * PI * 2.6))
		Core.anim_scale(mouth, Vector3(1.0 + 0.5 * chew, 1.0 + 4.0 * chew, 1.0))
	if rig.has("arm_l") and rig.has("arm_r"):
		var arm_l: Node3D = rig["arm_l"]
		var arm_r: Node3D = rig["arm_r"]
		var lift := 1.55 * bump
		arm_l.rotation.z = -lift
		arm_l.rotation.x = -0.7 * bump
		arm_r.rotation.z = lift
		arm_r.rotation.x = -0.7 * bump
		arm_l.position.y = 1.14 + 0.10 * bump
		arm_r.position.y = 1.14 + 0.10 * bump
	if rig.has("belly"):
		var belly: MeshInstance3D = rig["belly"]
		var w := clampf(weight, 0.0, max_weight)
		belly.visible = weight >= 1.0
		Core.anim_scale(belly, Vector3(1.0 + 0.115 * w, 1.0 + 0.10 * w, 1.0 + 0.13 * w))
		belly.position.z = 0.10 + 0.02 * w

	if carried_by != null:
		position.y = 2.55 + sin(Time.get_ticks_msec() * 0.006) * 0.05
		if carried_by.alive == false:
			game.drop_princess(carried_by)


func title() -> String:
	return "Red Princess" if team == 0 else "Blue Princess"


func display_weight() -> String:
	return "%d" % int(round(weight))
