class_name Unit
extends Node3D
## A fighter. Units move on the y=0 plane; the game resolves walls against
## axis-aligned rects, so there is no physics body to fight with.

var game: Node = null
var team := 0
var cls := "villager"
var is_player := false
var alive := true

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var hp := 100.0
var max_hp := 100.0
var speed := 6.0

var cake := 0                 # cake slices carried (max 3)
var has_key := false          # opens the enemy cage
var key_team := -1            # which castle's key this is
var wood := 0                 # building materials, worker only
var metal := 0
var gather_t := 0.0
var repair_t := 0.0
var key_model: Node3D = null  # the enemy key, held over the head
var path: Array = []          # A* waypoints, consumed front to back
var path_i := 0
var path_goal := Vector3.ZERO
var path_t := 0.0             # seconds until a replan is allowed
var vy := 0.0                 # vertical velocity while jumping
var airborne := false
var carrying: Princess = null
var attack_cd := 0.0
var swing := 0.0             # 1.0 -> 0.0 over the swing, drives the arm
var hurt := 0.0
var dash_cd := 0.0
var dash_t := 0.0
var bob := 0.0
var brain := "idle"
var role_t := 0.0
var waypoint := Vector3.ZERO
var has_waypoint := false
var target_unit: Unit = null
var stuck_t := 0.0
var last_pos := Vector3.ZERO

var rig: Dictionary = {}
var deco: Node3D = null
var you_label: Label3D = null
var marker: MeshInstance3D = null
var hpbar: Node3D = null
var hpfill: MeshInstance3D = null
var label: Label3D = null

const SPEEDS := {"villager": 6.4, "warrior": 5.4, "ranger": 5.6, "mage": 5.2, "worker": 5.3}
const HPS := {"villager": 110.0, "warrior": 240.0, "ranger": 150.0, "mage": 170.0, "worker": 160.0}
const NAMES := {"villager": "Villager", "warrior": "Warrior", "ranger": "Ranger", "mage": "Mage", "worker": "Worker"}


func setup(g: Node, t: int, klass: String, player: bool) -> void:
	game = g
	team = t
	cls = klass
	is_player = player
	yaw = deg_to_rad(45.0)
	set_class(klass)
	hp = max_hp
	label = Core.label3d(self, "", Vector3(0, 3.25, 0), 40, Color.WHITE)
	label.text = ""


func set_class(klass: String) -> void:
	if rig.has("root") and is_instance_valid(rig["root"]):
		rig["root"].queue_free()
	cls = klass
	max_hp = HPS[klass]
	hp = minf(hp, max_hp) if hp > 0.0 else max_hp
	speed = SPEEDS[klass]
	rig = Bld.fighter(self, team, klass)
	_build_silhouette()
	if marker != null:
		marker = null
	if deco != null and is_instance_valid(deco):
		deco.queue_free()
	deco = null
	if is_player:
		var p := Node3D.new()
		deco = p
		p.position = Vector3(0, 0.02, 0)
		add_child(p)
		Core.flat_disc(p, 0.95, Vector3.ZERO, Core.GOLD, 0.55)
		var chev := Node3D.new()
		chev.position = Vector3(0, 3.05, 0)
		p.add_child(chev)
		var prism := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.34, 0.26, 0.34)
		prism.mesh = pm
		prism.material_override = Core.mat(Core.GOLD, 0.4, 0.3, 0.9)
		prism.rotation_degrees = Vector3(180, 0, 0)
		chev.add_child(prism)
		marker = prism
		you_label = Core.label3d(p, "YOU", Vector3(0, 4.3, 0), 38, Core.GOLD)
		you_label.no_depth_test = false
	_build_hpbar()


func _build_hpbar() -> void:
	if hpbar != null:
		hpbar.queue_free()
	hpbar = Node3D.new()
	hpbar.position = Vector3(0, 2.62, 0)
	add_child(hpbar)
	Core.box(hpbar, Vector3(0.86, 0.11, 0.04), Vector3.ZERO, Color(0.08, 0.07, 0.07), Vector3.ZERO, 0.9)
	hpfill = Core.box(hpbar, Vector3(0.8, 0.07, 0.05), Vector3(0, 0, 0.01), Bld.team_light(team))
	hpbar.visible = false


func world_center() -> Vector3:
	return pos + Vector3(0, 1.0, 0)


func is_full_hp() -> bool:
	return hp >= max_hp - 0.5


## How hard this unit hits. Two team-level force multipliers live here:
## an upgraded station (workers delivered the materials) and high ground.
func damage_scale() -> float:
	var s := 1.0
	if game != null and game.class_upgraded(team, cls):
		s *= 1.22
	if (cls == "ranger" or cls == "mage") and game != null and game.on_wall(pos):
		s *= 1.35
	return s


## A ghost copy of the figure that is only shown when a tower or wall hides the
## unit from the camera. Yellow for your side, red for theirs.
var ghost: Node3D = null

static var _sil_mats := {}


static func silhouette_material(enemy: bool) -> ShaderMaterial:
	var key := "enemy" if enemy else "ally"
	if _sil_mats.has(key):
		return _sil_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/silhouette.gdshader")
	m.set_shader_parameter("tint", Color("ff4a3d") if enemy else Color("ffd447"))
	_sil_mats[key] = m
	return m


func _build_silhouette() -> void:
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = Node3D.new()
	ghost.name = "Silhouette"
	ghost.visible = false
	add_child(ghost)
	var mat: Material = silhouette_material(team != 0)
	# a simple readable body: legs, torso, head — no detail, it is a shadow
	var parts := [
		[Vector3(0, 0.55, 0), 0.30, 1.10],   # legs + skirt as one column
		[Vector3(0, 1.42, 0), 0.34, 0.62],   # torso
		[Vector3(0, 1.92, 0), 0.27, 0.30],   # head
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = float(p[1])
		cm.height = maxf(float(p[2]), float(p[1]) * 2.0)
		mi.mesh = cm
		mi.material_override = mat
		mi.position = p[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(mi)


func show_silhouette(on: bool) -> void:
	if ghost != null and is_instance_valid(ghost) and ghost.visible != on:
		ghost.visible = on


## A hop that clears a battlement: 8 m/s up under 24 m/s^2 gravity gives about
## 0.67 s of hang time and 1.3 m of lift, enough to step off the assault ramp
## and land inside a courtyard 4.6 m below.
func start_jump() -> void:
	if airborne or not alive:
		return
	airborne = true
	vy = 8.0


func carry_factor() -> float:
	if carrying == null:
		return 1.0
	var w := carrying.weight
	return clampf(1.0 - 0.075 * float(w), 0.22, 1.0)


func cur_speed() -> float:
	var s := speed
	if carrying != null:
		s *= carry_factor()
		s += float(carrying.helpers) * 0.55
	elif cls == "villager":
		s *= 1.15
	if cls == "villager" and cake > 0:
		s *= 1.06                      # the courier runs cake, not walks it
	return s


func update_unit(dt: float, dir: Vector3, aim: Vector3) -> void:
	if not alive:
		return
	attack_cd = maxf(0.0, attack_cd - dt)
	dash_cd = maxf(0.0, dash_cd - dt)
	dash_t = maxf(0.0, dash_t - dt)
	swing = maxf(0.0, swing - dt * 3.4)
	hurt = maxf(0.0, hurt - dt * 3.0)

	var d := Vector3(dir.x, 0, dir.z)
	if d.length() > 1.0:
		d = d.normalized()
	var sp := cur_speed()
	if dash_t > 0.0:
		sp *= 1.9
	var want := d * sp
	vel = vel.lerp(want, 1.0 - exp(-14.0 * dt))
	var before := pos
	pos = game.move_unit(pos, vel * dt, self)
	var moved := (pos - before).length()
	if d.length() > 0.5:
		if moved < 0.02 * d.length():
			stuck_t += dt
		else:
			stuck_t = maxf(0.0, stuck_t - dt * 2.0)

	# face movement, or the aim point when standing still/attacking
	var want_yaw := yaw
	if d.length() > 0.15:
		want_yaw = atan2(d.x, d.z)
	elif aim != Vector3.ZERO:
		want_yaw = Core.yaw_to(pos, aim)
	yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-13.0 * dt))
	rotation.y = yaw
	if airborne:
		vy -= 24.0 * dt
		var ground := Terrain.h(pos.x, pos.z)
		position = Vector3(pos.x, position.y + vy * dt, pos.z)
		if position.y <= ground and vy < 0.0:
			position.y = ground
			vy = 0.0
			airborne = false
	else:
		position = Vector3(pos.x, _stand_h(pos.x, pos.z), pos.z)

	bob += dt * (4.0 + vel.length() * 1.1)
	_animate(dt)


## Ground height under the whole footprint, not just the centre. On stairs the
## centre can sit on one step while half the body is inside the riser above it,
## which reads as the character being cut in half.
func _stand_h(px: float, pz: float) -> float:
	const R := 0.34
	var h := Terrain.h(px, pz)
	h = maxf(h, Terrain.h(px + R, pz))
	h = maxf(h, Terrain.h(px - R, pz))
	h = maxf(h, Terrain.h(px, pz + R))
	h = maxf(h, Terrain.h(px, pz - R))
	return h


func _animate(dt: float) -> void:
	if not rig.has("body"):
		return
	var body: Node3D = rig["body"]
	var spd := vel.length()
	var k := clampf(spd / 5.2, 0.0, 1.35)
	var ph := bob * 2.0
	body.position.y = lerpf(body.position.y, absf(sin(ph)) * 0.05 * k, 0.4)
	body.rotation.z = lerpf(body.rotation.z, sin(ph) * 0.04 * k, 0.25)

	# legs: hip swing with a knee that only bends backwards
	if rig.has("leg_l") and rig["leg_l"] != null:
		rig["leg_l"].rotation.x = sin(ph) * 0.62 * k
		rig["leg_r"].rotation.x = -sin(ph) * 0.62 * k
	if rig.has("knee_l") and rig["knee_l"] != null:
		rig["knee_l"].rotation.x = lerpf(rig["knee_l"].rotation.x, maxf(0.0, -sin(ph)) * 1.05 * k, 0.45)
		rig["knee_r"].rotation.x = lerpf(rig["knee_r"].rotation.x, maxf(0.0, sin(ph)) * 1.05 * k, 0.45)
	# free arm counter-swings, torso leans into the run
	if rig.has("arm_l") and rig["arm_l"] != null:
		var al: Node3D = rig["arm_l"]
		al.rotation.x = lerpf(al.rotation.x, -sin(ph) * 0.55 * k - 0.14, 0.32)
		al.rotation.z = lerpf(al.rotation.z, 0.17, 0.2)
	if rig.has("torso") and rig["torso"] != null:
		var t: Node3D = rig["torso"]
		t.rotation.x = lerpf(t.rotation.x, 0.02 + k * 0.11, 0.2)
		t.rotation.y = lerpf(t.rotation.y, sin(ph) * 0.07 * k, 0.2)
	if rig.has("head") and rig["head"] != null:
		rig["head"].rotation.x = lerpf(rig["head"].rotation.x, -0.02 - k * 0.06, 0.25)

	if rig.has("elbow_r") and rig["elbow_r"] != null:
		rig["elbow_r"].rotation.x = lerpf(rig["elbow_r"].rotation.x, -0.22 - 0.20 * k, 0.3)
		rig["elbow_l"].rotation.x = lerpf(rig["elbow_l"].rotation.x, -0.30 - 0.20 * k, 0.3)
	if rig.has("arm") and rig["arm"] != null:
		var arm: Node3D = rig["arm"]
		if swing > 0.0:
			arm.rotation.x = -2.3 * swing * swing
			arm.rotation.y = 0.55 * swing
			if rig.has("torso") and rig["torso"] != null:
				rig["torso"].rotation.y = 0.42 * swing * swing
		else:
			arm.rotation.x = lerpf(arm.rotation.x, -0.14 + sin(ph) * 0.30 * k, 0.35)
			arm.rotation.y = lerpf(arm.rotation.y, 0.0, 0.35)
			arm.rotation.z = lerpf(arm.rotation.z, -0.17, 0.3)
	if hpbar != null:
		hpbar.rotation.y = deg_to_rad(45.0) - yaw
		if hpfill != null:
			var f := clampf(hp / max_hp, 0.0, 1.0)
			hpfill.scale.x = maxf(f, 0.001)
			hpfill.position.x = -0.4 * (1.0 - f)
			var m: StandardMaterial3D = Core.mat(Bld.team_light(team) if f > 0.55 else Color("e8c04a") if f > 0.28 else Color("e05a4a"))
			hpfill.material_override = m
	if hurt > 0.0 and rig.has("body"):
		var hk := 1.0 + hurt * 0.10
		rig["body"].scale = Vector3(hk, 2.0 - hk, hk)
	elif rig.has("body"):
		rig["body"].scale = rig["body"].scale.lerp(Vector3.ONE, 0.35)
	if marker != null and marker.get_parent() != null:
		marker.get_parent().position.y = 3.05 + sin(Time.get_ticks_msec() * 0.004) * 0.12
		marker.rotation.y += dt * 2.0


func can_attack() -> bool:
	return alive and attack_cd <= 0.0 and swing <= 0.25


func attack(aim: Vector3) -> void:
	if not can_attack():
		return
	if has_key:
		return                      # both hands on the key: no weapon while carrying
	swing = 1.0
	match cls:
		"villager":
			attack_cd = 0.42
			game.melee_hit(self, 1.9, 14.0 * damage_scale(), true)
		"warrior":
			attack_cd = 0.55
			game.melee_hit(self, 2.25, 36.0 * damage_scale(), false)
		"worker":
			attack_cd = 0.62
			game.melee_hit(self, 1.75, 11.0 * damage_scale(), false)
		"ranger":
			attack_cd = 0.72
			game.spawn_projectile(self, pos + Vector3(0, 1.25, 0), aim, "arrow")
		"mage":
			attack_cd = 1.05
			game.spawn_projectile(self, pos + Vector3(0, 1.35, 0), aim, "fire")
	if cls != "ranger":
		game.add_shake(0.06)


func take_damage(amount: float, from: Vector3, force_drop: bool) -> void:
	if not alive:
		return
	if game != null:
		amount *= game.incoming_scale(self)
	hp -= amount
	hurt = 1.0
	game.spawn_hit_fx(pos + Vector3(0, 1.15, 0), amount, team, from - pos)
	var kb := (pos - from)
	kb.y = 0.0
	if kb.length() > 0.01:
		pos += kb.normalized() * (0.35 if not force_drop else 0.5)
	if force_drop and cake > 0:
		game.drop_cake(pos, cake, team)
		cake = 0
	if force_drop and carrying != null:
		game.drop_princess(self)
	if hp <= 0.0:
		if game != null:
			game._drop_hat(self)
		die()


func die() -> void:
	alive = false
	hp = 0.0
	vel = Vector3.ZERO
	if carrying != null:
		game.drop_princess(self)
	if cake > 0:
		game.drop_cake(pos, cake, team)
		cake = 0
	hpbar.visible = false
	if marker != null:
		marker.get_parent().visible = false
	rig["body"].visible = false
	game.on_unit_died(self)


func respawn(at: Vector3) -> void:
	# you come back as a worker with no hat: the class has to be earned again
	if is_player:
		set_class("worker")
	pos = Vector3(at.x, 0.0, at.z)
	position = Vector3(at.x, Terrain.h(at.x, at.z), at.z)
	alive = true
	hp = max_hp
	vel = Vector3.ZERO
	cake = 0
	attack_cd = 0.3
	rig["body"].visible = true
	rig["body"].scale = Vector3.ONE
	if marker != null:
		marker.get_parent().visible = true
	hpbar.visible = false


func set_hpbar_visible(v: bool) -> void:
	if hpbar != null and alive:
		hpbar.visible = v


func pickup_cake(n: int) -> void:
	cake = mini(3, cake + n)


func role_name() -> String:
	return NAMES.get(cls, "Villager")
