extends Node3D
## Heavy Flag — an isometric 3D siege. Two castles, two kidnapped princesses,
## and a cake economy that decides how easily either one can be carried home.

const WIN_HOLD := 25.0
const SUDDEN_AT := 300.0
const SUDDEN_HOLD := 9.0
const MATCH_RESPAWN := 8.0
const ALLY_RESPAWN := 6.0
const PLAYER_RESPAWN := 4.0
const ORTHO_SIZE := 30.0

enum { S_MENU, S_TUTORIAL, S_PLAY, S_PAUSE, S_OVER }

var state: int = S_MENU
var world: Node3D
var units: Array = []
var player: Unit = null
var red_princess: Princess = null
var blue_princess: Princess = null
var castles: Array = [{}, {}]
var solids: Array = []
var cakes: Array = []
var hats: Array = []
var gates: Array = []
var keys: Array = []
var resources: Array = []
var dropped_hats: Array = []
var projectiles: Array = []
var throws: Array = []
var fx: Array = []
var dummies: Array = []
var camera: Camera3D
var ui: UI

var sudden := false
var hold_target := WIN_HOLD
var hold_red := 0.0
var hold_blue := 0.0
var hold_active := -1
var match_time := 0.0
var match_start_ms := 0
var respawn_queue: Array = []
var cam_focus := Vector3.ZERO
var demo_focus := Vector3.ZERO
var demo_zoom := 0.0
var cam_dir := Vector3(0.72, 0.82, 0.72).normalized()
const CAM_HORIZ := 0.72
const CAM_HEIGHT := 0.82
var cam_yaw := PI * 0.25
var cam_yaw_target := PI * 0.25
var zoom := ORTHO_SIZE
var zoom_target := ORTHO_SIZE
var shake := 0.0
var menu_t := 0.0
var near_lbl: Label3D
var hint_lbl: Label3D
var tutorial_step := 0
var tutorial_done := false
var tut_progress := 0.0
var tut_last_pos := Vector3.ZERO
var tut_zoom_seen := false
var sfx_noted := false

# headless / automation
var sfx: Array = []
var sfx_i := 0
var muted := true   # beta builds start silent; M toggles
var shot_path := ""
var shot_frame := 0
var frame_count := 0
var autoplay := false
var simtest := 0.0
var dbg_t := 0.0
var start_play := false
var start_tutorial := false
var start_help := false
var _last_goal := Vector3.ZERO
var _last_want := Vector3.ZERO
var demo := ""
var demo_fired := false
var click_target := ""
var movetest := false
var keytest := false
var attacktest := false
var walltest := false
var siegetest := false
var synergytest := false
var wintest := false
var occtest := false
var respawntest := false
var jumptest := false
var hattest := false
var nettest := false
var keyflow := false
var shottest := false
var pathaudit := false
var deckaudit := false
var snaptest := false
var stuckaudit := false
var navprobe := false
var telemetry := ""
var telemetry_t := 0.0
var telemetry_file: FileAccess = null
var spectate := false
var spectate_lbl: Label = null
var perf := false
var perf_acc := {}
var perf_frames := 0
var perf_frame_us := 0
var perf_max_us := 0
var fire_at_frame := -1
var fire_shot: Dictionary = {}
var showsil := false
var camtest := false
var sudden_applied := false
var net: Net = null
var input_debug := false
var spawn_at := Vector3(9999, 0, 0)
var autoplay_t := 0.0


func _ready() -> void:
	AudioServer.set_bus_mute(0, muted)
	print("[HF] boot build 1")
	Core.setup_input()
	_parse_args()
	Bld.make_env(self)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	Terrain.build(world)
	Bld.scatter(world)
	castles[0] = Bld.castle(world, 0, solids)
	castles[1] = Bld.castle(world, 1, solids)
	# the map never changes between matches, so the grid is built once here
	# rather than at every kickoff (it costs ~0.6 s)
	Nav.build(solids)
	_make_camera()
	_make_ui()
	_make_audio()
	_make_world_labels()
	spawn_princesses()
	start_menu()
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		if q.find("autostart=tutorial") >= 0:
			start_match(true)
		elif q.find("autostart=play") >= 0:
			start_match(false)
		elif q.find("spectate=1") >= 0:
			demo = "spectate"
			start_match(false)
			_setup_demo()
	if simtest > 0.0:
		autoplay = true
		_run_simtest()
		return
	if navprobe:
		_run_navprobe()
		return
	if stuckaudit:
		_run_stuckaudit()
		return
	if snaptest:
		_run_snaptest()
		return
	if deckaudit:
		_run_deckaudit()
		return
	if pathaudit:
		_run_pathaudit()
		return
	if shottest:
		_run_shottest()
		return
	if keyflow:
		_run_keyflow()
		return
	if nettest:
		_run_nettest()
		return
	if hattest:
		_run_hattest()
		return
	if jumptest:
		_run_jumptest()
		return
	if respawntest:
		_run_respawntest()
		return
	if occtest:
		_run_occtest()
		return
	if camtest:
		_run_camtest()
		return
	if wintest:
		_run_wintest()
		return
	if synergytest:
		_run_synergytest()
		return
	if siegetest:
		_run_siegetest()
		return
	if walltest:
		_run_walltest()
		return
	if attacktest:
		_run_attacktest()
		return
	if keytest:
		_run_keytest()
		return
	if movetest:
		_run_movetest()
		return
	if demo != "":
		start_match(false)
		_setup_demo()
	_setup_net()
	if start_help:
		ui.help.visible = true
	if click_target != "":
		await get_tree().create_timer(1.0).timeout
		print("[HF] synthetic click: ", click_target)
		if click_target == "tutorial":
			ui._fire(ui.tutorial_pressed)
		elif click_target == "play":
			ui._fire(ui.play_pressed)
		elif click_target == "help":
			ui.help.visible = true
	if autoplay or start_play:
		start_match(false)
	elif start_tutorial:
		start_match(true)


## Walks the nav graph to every height in the game and checks the surface it
## crosses never jumps more than a unit can step.
## Prints the walkable height around the keep so a deck that bleeds past its
## platform shows up as a shape you can look at.
func _run_navprobe() -> void:
	start_match(false)
	var pts := [
		Vector3(-0.1, 0, -4.0), Vector3(1.9, 0, -3.5), Vector3(0.0, 0, 0.0),
		Vector3(38.9, 0, 6.5), Vector3(-41.1, 0, -19.6), Vector3(-41.7, 0, -8.6),
		Vector3(-20.0, 0, -4.0), Vector3(20.0, 0, 4.0),
	]
	for p: Vector3 in pts:
		var i: int = Nav.cell_of(p)
		print("[HF] NAVPROBE (%.1f, %.1f) cell=%d walkable=%s on_bridge=%s h=%.2f cells=%s" % [
			p.x, p.z, i, str(Terrain.walkable(p.x, p.z)), str(Terrain.on_bridge(p.x, p.z)),
			Terrain.h(p.x, p.z), str(Nav.cells[i]) if i >= 0 else "n/a"])
	for p2: Vector3 in [Vector3(1.9,0,-3.5), Vector3(38.9,0,6.5), Vector3(-41.7,0,-8.6), Vector3(-41.1,0,-19.6)]:
		for so in solids:
			var rr: Rect2 = so["r"].grow(0.45)
			if rr.has_point(Vector2(p2.x, p2.z)):
				print("[HF] NAVPROBE solid over (%.1f,%.1f): tag='%s' top=%.2f ground=%.2f" % [
					p2.x, p2.z, String(so.get("tag","")), float(so["top"]), Terrain.h(p2.x, p2.z)])
	var pairs := [[Vector3(-0.1,0,-4.0), Vector3(-41.4,0,0.0)],
		[Vector3(1.9,0,-3.5), Vector3(-41.4,0,0.0)],
		[Vector3(-40,0,0), Vector3(40,0,0)],
		[Vector3(-40,0,20), Vector3(40,0,-20)]]
	for pr: Array in pairs:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var path: Array = Nav.find_path(a, b)
		print("[HF] NAVPROBE path (%.0f,%.0f)->(%.0f,%.0f) = %d waypoints %s" % [a.x, a.z, b.x, b.z, path.size(), "OK" if path.size() > 0 else "EMPTY"])
	get_tree().quit()


## Runs the match and reports units that spend seconds with a waypoint but no
## movement — the "NPCs get stuck" complaint, with the location to look at.
func _run_stuckaudit() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	var last := {}
	var stuck := {}
	var t := 0.0
	for i in int(120.0 / dt):
		_step(dt)
		t += dt
		if i % 30 != 0:
			continue
		for u: Unit in units:
			if not u.alive or not u.has_waypoint:
				continue
			if u.target_unit != null or _gate_reach(u) or u.pos.distance_to(u.waypoint) < 0.7:
				stuck[u.get_instance_id()] = 0.0
				continue
			var id: int = u.get_instance_id()
			var prev: Vector3 = last.get(id, u.pos)
			var moved: float = prev.distance_to(u.pos)
			if moved < 0.35:
				stuck[id] = float(stuck.get(id, 0.0)) + 0.5
				if float(stuck[id]) >= 3.0:
					print("[HF] STUCK %s at (%.1f, %.1f) wp=(%.1f, %.1f) path=%d/%d tgt=%s" % [
						u.cls, u.pos.x, u.pos.z, u.waypoint.x, u.waypoint.z,
						u.path_i, u.path.size(), str(u.target_unit != null)])
					stuck[id] = 0.0
			else:
				stuck[id] = 0.0
			last[id] = u.pos
	var total := 0
	for id2 in stuck.keys():
		if float(stuck[id2]) > 0.0:
			total += 1
	print("[HF] STUCKAUDIT ran %.0f s, %d units still flagged  %s" % [t, total, "PASS" if total <= 2 else "FAIL"])
	get_tree().quit()


## A crowd pressed against the keep must not get shoved onto its 2.15 m ledge.
func _run_snaptest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	var kp: Vector3 = castles[0]["key_pos"]
	var base_h: float = Terrain.PLATEAU_H
	var crowd: Array = []
	for i in 9:
		var u := _new_unit(0, "villager", false)
		place(u, Vector3(kp.x - 3.6 + float(i % 3) * 0.3, 0.0, kp.z - 0.8 + float(i / 3) * 0.3))
		u.brain = "none"
		units.append(u)
		crowd.append(u)
	var worst := -99.0
	for step in 240:
		for u2: Unit in crowd:
			var toward := Vector3(kp.x - u2.pos.x, 0.0, kp.z - u2.pos.z).normalized()
			u2.update_unit(dt, toward, Vector3.ZERO)
		separate_units()
		for u3: Unit in crowd:
			worst = maxf(worst, u3.position.y - base_h)
	var ok: bool = worst <= Terrain.STEP_UP + 0.06
	print("[HF] SNAPTEST crowd=%d max_rise_above_courtyard=%.2f m (limit %.2f)  %s" % [
		crowd.size(), worst, Terrain.STEP_UP, "PASS" if ok else "FAIL"])
	for u4: Unit in crowd:
		print("[HF]   y=%.2f h=%.2f at (%.1f,%.1f)" % [u4.position.y, Terrain.h(u4.pos.x, u4.pos.z), u4.pos.x, u4.pos.z])
	get_tree().quit()


func _run_deckaudit() -> void:
	start_match(false)
	var c: Vector3 = castles[0]["court"]
	var cx: float = c.x
	var cz: float = c.z
	print("[HF] DECK around keep centre (%.1f, %.1f), plateau %.2f" % [cx, cz, Terrain.PLATEAU_H])
	for iz in range(-8, 9):
		var row := ""
		for ix in range(-8, 9):
			var x := cx + float(ix) * 1.0
			var z := cz + float(iz) * 1.0
			var hh: float = Terrain.h(x, z) - Terrain.PLATEAU_H
			if hh < 0.05:
				row += " ."
			elif hh < 0.8:
				row += " 1"
			elif hh < 1.6:
				row += " 2"
			elif hh < 2.5:
				row += " 3"
			else:
				row += " #"
		print("[HF]   " + row)
	get_tree().quit()


func _run_pathaudit() -> void:
	start_match(false)
	var walkable := 0
	for i in Nav.cells.size():
		if Nav.cells[i] == 1:
			walkable += 1
	var from: Vector3 = castles[0]["spawn"]
	var goals: Array = [
		["wall walk", Vector3(-(Bld.BACK_X + Bld.CASTLE_SHIFT), 0.0, 0.0)],
		["shrine terrace", Vector3(castles[0]["key_pos"].x, 0.0, castles[0]["key_pos"].z)],
		["middle bridge", Vector3(0.0, 0.0, 0.0)],
		["north bridge", Vector3(0.0, 0.0, Terrain.BRIDGE_Z[2])],
		["enemy courtyard", castles[1]["spawn"]],
		["assault ramp crest", Vector3(-Terrain.RAMP_X, 0.0, Terrain.RAMP_Z)],
	]
	var bad := 0
	var lines: Array = []
	var t0 := Time.get_ticks_msec()
	for g in goals:
		var goal: Vector3 = g[1]
		var path: Array = Nav.find_path(from, goal)
		var ok_len: bool = path.size() > 0
		var worst := 0.0
		var prev := from
		for wp in path:
			var p: Vector3 = wp
			var leg: float = prev.distance_to(p)
			var nseg: int = maxi(1, int(leg / 0.4))
			var hprev: float = Terrain.h(prev.x, prev.z)
			for s2 in range(1, nseg + 1):
				var t2 := float(s2) / float(nseg)
				var q := prev.lerp(p, t2)
				var hq: float = Terrain.h(q.x, q.z)
				worst = maxf(worst, absf(hq - hprev))
				hprev = hq
			prev = p
		var ok_step: bool = worst <= Terrain.STEP_UP + 0.001
		if not (ok_len and ok_step):
			bad += 1
		lines.append("%s:%d/%s" % [g[0], path.size(), "ok" if (ok_len and ok_step) else "BAD %.2f" % worst])
		if not (ok_len and ok_step):
			var clear_direct: bool = Nav._clear(from, goal)
			var a := Nav.snap(from)
			var b := Nav.snap(goal)
			print("[HF]   %s: clear=%s cells a=%d(h=%.2f) b=%d(h=%.2f) hs=%s" % [g[0], str(clear_direct), a,
				Terrain.h(Nav.centre(a).x, Nav.centre(a).z) if a >= 0 else -99.0,
				b, Terrain.h(Nav.centre(b).x, Nav.centre(b).z) if b >= 0 else -99.0,
				str(path.map(func(v): return "(%0.1f,%0.1f h%0.1f)" % [v.x, v.z, Terrain.h(v.x, v.z)]))])
	var took := Time.get_ticks_msec() - t0
	print("[HF] PATHAUDIT cells=%d/%d (%.0f%%) %s" % [walkable, Nav.cells.size(),
		100.0 * float(walkable) / float(Nav.cells.size()), " | ".join(lines)])
	print("[HF] PATHAUDIT %d goals in %d ms  %s" % [goals.size(), took,
		"PASS" if bad == 0 else "FAIL"])
	get_tree().quit()


func _run_shottest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0

	# 1. aim at a person: the shot lands on them
	var shooter := _new_unit(0, "ranger", false)
	var target := _new_unit(1, "warrior", false)
	place(shooter, Vector3(-20.0, 0.0, 45.0))
	place(target, Vector3(-6.0, 0.0, 45.0))
	units.append(shooter)
	units.append(target)
	var hp0: float = target.hp
	spawn_projectile(shooter, shooter.pos + Vector3(0, 1.25, 0), target.position + Vector3(0, 1.15, 0), "arrow")
	var n := 0
	while n < 120 and not projectiles.is_empty():
		_update_projectiles(dt)
		n += 1
	var chest_hit: bool = target.hp < hp0

	# 2. aim at the ground: it flies out and poofs on the terrain, no damage
	spawn_projectile(shooter, shooter.pos + Vector3(0, 1.25, 0), Vector3(-2.0, 0.0, 45.0), "arrow")
	var travelled := 0.0
	var start_x: float = shooter.pos.x
	n = 0
	while n < 200 and not projectiles.is_empty():
		_update_projectiles(dt)
		if projectiles.size() > 0:
			travelled = absf((projectiles[0]["pos"] as Vector3).x - start_x)
		n += 1
	var ground_poof: bool = projectiles.is_empty() and travelled > 8.0

	# 3. a wall in the way stops the shot
	var inside := _new_unit(0, "ranger", false)
	var outside := _new_unit(1, "warrior", false)
	place(inside, Vector3(-44.0, 0.0, 8.0))
	place(outside, Vector3(-30.0, 0.0, 8.0))
	units.append(inside)
	units.append(outside)
	var hp1: float = outside.hp
	spawn_projectile(inside, inside.pos + Vector3(0, 1.25, 0), outside.position + Vector3(0, 1.15, 0), "arrow")
	n = 0
	while n < 120 and not projectiles.is_empty():
		_update_projectiles(dt)
		n += 1
	var wall_blocked: bool = is_equal_approx(outside.hp, hp1) and projectiles.is_empty()

	var ok: bool = chest_hit and ground_poof and wall_blocked
	print("[HF] SHOTTEST chest_hit=%s ground_poof=%s(%.1fm) wall_blocked=%s  %s" % [
		str(chest_hit), str(ground_poof), travelled, str(wall_blocked), "PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_keyflow() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	# the blue key (team 1) lives on the blue shrine; red raiders want it
	var kb: Dictionary = keys[1]
	var home: Vector3 = kb["home"]

	# 1. standing near the shrine, E picks it up
	place(player, Vector3(home.x + 2.4, 0.0, home.z))
	_player_interact()
	var picked: bool = player.has_key and int(player.key_team) == 1
	var carried_model: bool = player.key_model != null and is_instance_valid(player.key_model)

	# 2. carrying means no weapon
	var swing_before := player.swing
	player.attack_cd = 0.0
	player.attack(player.pos + Vector3(0, 0, 2))
	var no_shoot: bool = player.swing == swing_before

	# 3. E again sets it down, and it is not on the shrine
	_player_interact()
	var set_down: bool = not player.has_key and bool(kb["dropped"])
	var hint_off: bool = key_hint_target() != null

	# 4. off the shrine for 20 s and it goes home
	place(player, Vector3(home.x + 40.0, 0.0, home.z))
	for i in int(21.0 / dt):
		_update_keys(dt)
	var back_home: bool = (kb["pos"] as Vector3).distance_to(home) < 0.5 and not bool(kb["dropped"])
	var hint_home: bool = key_hint_target() == null

	# 5. with the key, walking to the cage opens it with no button press
	place(player, Vector3(home.x + 1.2, 0.0, home.z))
	_update_keys(dt)
	var re_taken: bool = player.has_key
	var pr: Princess = red_princess
	pr.locked = true
	var cage_at := Vector3(pr.position.x + 2.0, 0.0, pr.position.z)
	place(player, cage_at)
	_update_keys(dt)
	var auto_open: bool = not pr.locked

	var ok: bool = picked and carried_model and no_shoot and set_down and hint_off 		and back_home and hint_home and re_taken and auto_open
	print("[HF] KEYFLOW picked=%s model=%s no_shoot=%s setdown=%s hint=%s home_again=%s hint_home=%s retake=%s auto_open=%s  %s" % [
		str(picked), str(carried_model), str(no_shoot), str(set_down), str(hint_off),
		str(back_home), str(hint_home), str(re_taken), str(auto_open), "PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_nettest() -> void:
	# two clients in one room: a raw peer playing RED, and the real Net client
	# playing BLUE, so the snapshot really contains somebody else.
	if net == null:
		_setup_net()
	var url := "ws://127.0.0.1:8080/ws"
	var peer := WebSocketPeer.new()
	peer.connect_to_url(url + "?room=ctptest&name=peer&team=red")
	var sent := 0
	var got_peer := false
	var got_ghost := false
	var t := 0.0
	net.room = "ctptest"
	net.join(1, "me", url)
	while t < 12.0 and not (got_peer and got_ghost):
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN and sent < 60:
			peer.send_text(JSON.stringify({"t": "s", "x": 30.0, "z": 6.0, "y": 1.0, "c": 1, "h": 240, "a": 1}))
			sent += 1
		got_peer = net.peers.size() > 0
		for id in net.peers.keys():
			var n = net.peers[id]["node"]
			if is_instance_valid(n) and n.get_child_count() > 0:
				got_ghost = true
		await get_tree().process_frame
		t += get_process_delta_time()
	var seen: int = net.peer_count()
	var welcomed: bool = net.my_id > 0
	peer.close()
	net.close()
	if not welcomed and seen == 0:
		print("[HF] NETTEST SKIP — no local relay on %s (start server/: node index.js)" % url)
	else:
		print("[HF] NETTEST welcomed=%s peers=%d ghost_node=%s t=%.1f  %s" % [
			str(welcomed), seen, str(got_ghost), t,
			"PASS" if (welcomed and got_peer and got_ghost) else "FAIL"])
	get_tree().quit()


func _run_hattest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	var spawn_worker: bool = player.cls == "worker"
	var stands: int = hats.size() / 2
	# take a warrior hat off its stand
	var st := {}
	for h in hats:
		if int(h["team"]) == 0 and String(h["cls"]) == "warrior":
			st = h
			break
	place(player, st["pos"])
	_player_interact()
	var got_hat: bool = player.cls == "warrior"
	# die, and check the hat falls and you come back hatless
	player.take_damage(9999.0, player.pos + Vector3(0, 0, 4), false)
	var fell: bool = dropped_hats.size() > 0
	var fell_cls: String = String(dropped_hats[0]["cls"]) if fell else ""
	var t := 0.0
	while not player.alive and t < 30.0:
		_update_respawns(dt)
		t += dt
	var back_worker: bool = player.cls == "worker" and player.alive
	# and the dropped hat is reclaimable
	var reclaimed := false
	if fell and dropped_hats.size() > 0:
		place(player, dropped_hats[0]["pos"])
		_update_dropped_hats(dt)
		reclaimed = player.cls == fell_cls
	var ok: bool = spawn_worker and stands == 3 and got_hat and fell and back_worker and reclaimed
	print("[HF] HATTEST spawn_worker=%s stands=%d took=%s dropped=%s(%s) respawn=%s reclaimed=%s  %s" % [
		str(spawn_worker), stands, str(got_hat), str(fell), fell_cls, str(back_worker), str(reclaimed),
		"PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_jumptest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	# stand on the assault ramp, outside the red castle's side wall
	place(player, Vector3(-Terrain.RAMP_X, 0.0, Terrain.RAMP_Z))
	var start_h: float = Terrain.h(player.pos.x, player.pos.z)
	var over_wall: bool = start_h > Bld.WALK_H
	player.start_jump()
	var t := 0.0
	while player.airborne and t < 4.0:
		player.pos.z -= 0.13
		player.update_unit(dt, Vector3(0.0, 0.0, -1.0), Vector3.ZERO)
		t += dt
	var inside: bool = absf(player.pos.x) > 38.0 and absf(player.pos.z) < 17.0
	var on_floor: bool = absf(player.position.y - Terrain.PLATEAU_H) < 0.6
	var ok: bool = over_wall and inside and on_floor and not player.airborne
	print("[HF] JUMPTEST ramp_top=%.2f (wall %.2f) over=%s landed=%s inside=%s floor=%s t=%.2f  %s" % [
		start_h, Bld.WALK_H, str(over_wall), str(not player.airborne), str(inside), str(on_floor), t,
		"PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_respawntest() -> void:
	start_match(false)
	var spread := {}
	var wrong_side := 0
	var on_wall := 0
	for i in 60:
		var p := _respawn_point(0)
		if p.x > -12.0:
			wrong_side += 1
		if Terrain.h(p.x, p.z) > Terrain.PLATEAU_H + 0.5:
			on_wall += 1
		spread[Vector2i(int(p.x), int(p.z))] = true
	var blue_side := 0
	for i in 30:
		if _respawn_point(1).x < 12.0:
			blue_side += 1
	var ok: bool = wrong_side == 0 and blue_side == 0 and on_wall == 0 and spread.size() > 8
	print("[HF] RESPAWNTEST red_wrong_side=%d blue_wrong_side=%d on_wall=%d distinct=%d/60  %s" % [
		wrong_side, blue_side, on_wall, spread.size(), "PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_occtest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	cam_yaw = PI * 0.25
	cam_yaw_target = cam_yaw
	for i in 40:
		_update_camera(dt)
	# behind the west wall of the blue castle
	var behind := _is_occluded(Vector3(35.5, 1.4, 10.0))
	# middle of the open field
	var open := _is_occluded(Vector3(0.0, 1.4, 15.0))
	# a unit standing on the wall itself must not be occluded by its own wall
	var onwall := _is_occluded(Vector3(42.0, Bld.WALK_H + 1.2, 0.0))
	var ok: bool = behind and not open and not onwall
	print("[HF] OCCTEST behind_wall=%s open_field=%s on_parapet=%s  %s" % [
		str(behind), str(open), str(onwall), "PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_camtest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	cam_yaw = PI * 0.25
	cam_yaw_target = cam_yaw
	for i in 40:
		_update_camera(dt)
	var d0 := cam_dir
	var fwd0 := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw)).normalized()
	cam_yaw_target += PI * 0.5
	for i in 60:
		_update_camera(dt)
	var d1 := cam_dir
	var turned := absf(fposmod(rad_to_deg(cam_yaw) - 135.0 + 180.0, 360.0) - 180.0) < 1.0
	var fwd1 := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw)).normalized()
	var perp := absf(fwd0.dot(fwd1)) < 0.05
	# four turns come back to the start
	for i in 3:
		cam_yaw_target += PI * 0.5
		for j in 60:
			_update_camera(dt)
	var back := absf(fposmod(rad_to_deg(cam_yaw) - 45.0 + 180.0, 360.0) - 180.0) < 1.0
	var ok: bool = turned and perp and back
	print("[HF] CAMTEST yaw=%.0f turned=%s horizontal_fwd_perp=%s full_circle=%s  %s" % [
		rad_to_deg(cam_yaw), str(turned), str(perp), str(back), "PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_wintest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	# put the red princess on her own throne and let the clock run
	red_princess.carried_by = null
	red_princess.locked = false
	red_princess.position = castles[0]["throne"] + Vector3(0.4, 0, 0.3)
	var t := 0.0
	while state == S_PLAY and t < 60.0:
		_update_holds(dt)
		_check_end()
		t += dt
	var won: bool = state == S_OVER and hold_red >= hold_target - 0.01
	print("[HF] WINTEST held=%.1f/%.1f t=%.1f over=%s won=%s  %s" % [
		hold_red, hold_target, t, str(state == S_OVER), str(won), "PASS" if won else "FAIL"])
	get_tree().quit()


func _run_synergytest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0

	# baseline: no multipliers
	var w := _new_unit(0, "warrior", false)
	place(w, castles[0]["court"])
	units.append(w)
	var plain: float = w.damage_scale()

	# worker delivers 3 wood + 3 ore to the warrior stand
	var wk := _new_unit(0, "worker", false)
	wk.wood = 3
	wk.metal = 3
	units.append(wk)
	var stand := {}
	for h in hats:
		if int(h["team"]) == 0 and String(h["cls"]) == "warrior":
			stand = h
			break
	place(wk, stand["pos"])
	_update_stations(dt)
	var upgraded: bool = class_upgraded(0, "warrior")
	var spent: bool = wk.wood == 0 and wk.metal == 0
	var scaled: float = w.damage_scale()

	# ranger on the wall walk
	var wall_pos := Vector3.ZERO
	for d in Terrain.decks:
		if absf(float(d["h"]) - Bld.WALK_H) < 0.3:
			var rr: Rect2 = d["r"]
			wall_pos = Vector3(rr.position.x + rr.size.x * 0.5, 0.0, rr.position.y + rr.size.y * 0.5)
			break
	var r := _new_unit(0, "ranger", false)
	units.append(r)
	place(r, wall_pos)
	var onwall: bool = on_wall(r.pos)
	var high: float = r.damage_scale()

	# shield wall: an ally warrior nearby soaks damage
	var mate := _new_unit(0, "warrior", false)
	units.append(mate)
	place(mate, w.pos + Vector3(2.0, 0, 0))
	var guarded: float = incoming_scale(w)
	w.hp = 200.0
	w.take_damage(100.0, w.pos + Vector3(0, 0, 5), false)
	var soaked: bool = w.hp > 100.5

	var ok: bool = is_equal_approx(plain, 1.0) and upgraded and spent and scaled > plain 		and onwall and high > 1.3 and guarded < 1.0 and soaked
	print("[HF] SYNERGYTEST plain=%.2f upgraded=%s spent=%s ->%.2f | wall=%s high=%.2f | guard=%.2f soaked=%s (%d hp)  %s" % [
		plain, str(upgraded), str(spent), scaled, str(onwall), high, guarded, str(soaked), int(w.hp),
		"PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_siegetest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	var g: Dictionary = gates[0]
	var gp: Vector3 = g["pos"]

	# 1. a closed gate takes hits and breaks
	var attacker := _new_unit(1, "warrior", false)
	place(attacker, Vector3(gp.x + 2.2, 0, gp.z))
	units.append(attacker)
	var hp0: float = float(g["hp"])
	for i in 30:
		melee_hit(attacker, 2.25, 40.0, false)
	var hp1: float = float(g["hp"])
	for i in 60:
		melee_hit(attacker, 2.25, 40.0, false)
	var broke: bool = not bool(g["alive"])

	# 2. a worker with materials puts it back up
	var w := _new_unit(0, "worker", false)
	place(w, Vector3(gp.x - 2.2, 0, gp.z))
	# a door under fire cannot be repaired: hold the window open and check
	w.wood = 4
	w.metal = 4
	units.append(w)
	g["last_hit"] = Time.get_ticks_msec() / 1000.0
	for i in 60:
		_update_gates(dt)
	var under_fire_hp: float = float(g["hp"])
	units.erase(w)
	units.append(w)
	g["last_hit"] = -99.0
	for i in 600:
		_update_gates(dt)
	var fixed: bool = bool(g["alive"]) and float(g["hp"]) > float(g["max"]) * 0.4

	# 3. the key opens the cage
	var k: Dictionary = keys[1]
	place(player, k["pos"])
	_update_keys(dt)
	var got_key: bool = player.has_key
	place(player, Vector3(red_princess.position.x + 2.0, 0, red_princess.position.z))
	for i in 5:
		_update_keys(dt)
	var unlocked: bool = not red_princess.locked
	pick_up(red_princess, player)
	var carried: bool = player.carrying != null

	var ok: bool = hp1 < hp0 and broke and under_fire_hp <= 0.01 and fixed and got_key and unlocked and carried
	print("[HF] SIEGETEST gate %.0f->%.0f broke=%s no_repair_under_fire=%s rebuilt=%s (%.0f) | key=%s unlocked=%s carried=%s  %s" % [
		hp0, hp1, str(broke), str(under_fire_hp <= 0.01), str(fixed), float(g["hp"]), str(got_key), str(unlocked), str(carried),
		"PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_walltest() -> void:
	start_match(false)
	var u := player
	# red team stairs: local (BACK_X - 4, +3.15) with flip = +1
	var base := Vector3(-(Bld.BACK_X - 4.0 + Bld.CASTLE_SHIFT), 0.0, 3.2)
	place(u, base)
	var h0 := Terrain.h(u.pos.x, u.pos.z)
	var climbed := false
	for i in 500:
		u.pos = move_unit(u.pos, Vector3(0, 0, 0.12), u)
		if Terrain.h(u.pos.x, u.pos.z) > Bld.WALK_H - 0.5:
			climbed = true
			break
	var h1 := Terrain.h(u.pos.x, u.pos.z)
	# now try to walk straight off the parapet into the courtyard
	var before := u.pos
	for i in 40:
		u.pos = move_unit(u.pos, Vector3(-0.12, 0, 0), u)
	var fell := Terrain.h(u.pos.x, u.pos.z) < h1 - 1.0
	print("[HF] WALLTEST base=%.2f top=%.2f climbed=%s walkh=%.2f off_wall=%s" % [
		h0, h1, str(climbed), Bld.WALK_H, str(fell)])
	print("[HF] WALLTEST ", "PASS" if climbed and not fell else "FAIL")
	get_tree().quit()


func _run_attacktest() -> void:
	start_match(false)
	# on dry ground: the old test stood them inside the bridge deck, which now
	# (correctly) stops a shot that flies into it
	var target := _new_unit(1, "warrior", false)
	place(target, Vector3(-20.0, 0.0, 46.0))
	units.append(target)
	var shooter := _new_unit(0, "ranger", false)
	place(shooter, Vector3(-20.0, 0.0, 53.0))
	units.append(shooter)
	var dt := 1.0 / 60.0
	var hp0 := target.hp

	var chest := target.position + Vector3(0, 1.15, 0)
	spawn_projectile(shooter, shooter.position + Vector3(0, 1.25, 0), chest, "arrow")
	for i in 60:
		_update_projectiles(dt)
	var hp1 := target.hp

	spawn_projectile(shooter, shooter.position + Vector3(0, 1.35, 0), chest, "fire")
	for i in 90:
		_update_projectiles(dt)
	var hp2 := target.hp

	# melee, for completeness
	var brute := _new_unit(0, "warrior", false)
	place(brute, target.pos + Vector3(0, 0, -1.8))
	brute.yaw = 0.0
	units.append(brute)
	melee_hit(brute, 2.25, 36.0, false)
	var hp3 := target.hp

	var ok: bool = hp1 < hp0 and hp2 < hp1 and hp3 < hp2
	print("[HF] ATTACKTEST arrow %.0f->%.0f | fire %.0f->%.0f | melee %.0f->%.0f  %s" % [
		hp0, hp1, hp1, hp2, hp2, hp3, "PASS" if ok else "FAIL"])
	get_tree().quit()


func _run_keytest() -> void:
	start_match(false)
	var results := []
	for pair in [["move_right", KEY_D, 68], ["move_up", KEY_W, 87], ["act", KEY_E, 69]]:
		var action: String = pair[0]
		var kc: int = pair[1]
		var vk: int = pair[2]
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.physical_keycode = kc
		ev.unicode = vk
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().process_frame
		var held := Input.is_action_pressed(action)
		var ev2 := InputEventKey.new()
		ev2.keycode = kc
		ev2.physical_keycode = kc
		ev2.pressed = false
		Input.parse_input_event(ev2)
		await get_tree().process_frame
		results.append("%s=%s" % [action, "PASS" if held else "FAIL"])
	print("[HF] KEYTEST ", " ".join(results))
	get_tree().quit()


func _run_movetest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	var p0: Vector3 = player.pos
	Input.action_press("move_right")
	for i in 60:
		_step(dt)
	Input.action_release("move_right")
	var d1 := player.pos - p0
	p0 = player.pos
	Input.action_press("move_up")
	for i in 60:
		_step(dt)
	Input.action_release("move_up")
	var d2 := player.pos - p0
	print("[HF] MOVETEST right=(%.2f,%.2f) up=(%.2f,%.2f)" % [d1.x, d1.z, d2.x, d2.z])
	var ok := d1.length() > 1.0 and d2.length() > 1.0
	print("[HF] MOVETEST ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _run_simtest() -> void:
	start_match(false)
	var dt := 1.0 / 60.0
	var steps := int(simtest * 60.0)
	for i in steps:
		if state == S_OVER:
			break
		_step(dt)
		if i % 600 == 0:
			_dbg()
	print("[HF] SIMTEST END state=%d time=%.1f" % [state, match_time])
	print("[HF] red=%.1f blue=%.1f redp=%s bluep=%s" % [hold_red, hold_blue, _princess_desc(red_princess), _princess_desc(blue_princess)])
	get_tree().quit()


func _princess_desc(pr: Princess) -> String:
	if pr == null:
		return "none"
	var cb := pr.carried_by
	var where := "none"
	if cb != null and is_instance_valid(cb):
		where = "carried by t%d/pl%d" % [cb.team, 1 if cb.is_player else 0]
	var dthr := pr.position.distance_to(castles[pr.team]["throne"])
	return "w%d @%.0f,%.0f cb=%s dthr=%.1f" % [int(pr.weight), pr.position.x, pr.position.z, where, dthr]


func _dbg() -> void:
	var ul := []
	for u: Unit in units:
		if not u.alive:
			continue
		ul.append("%s%d:%s@%.0f,%.0f/%s" % ["R" if u.team == 0 else "B", 1 if not u.is_player else 0, u.cls.substr(0, 3), u.pos.x, u.pos.z, u.brain])
	print("[HF] gates R=%.0f/%s B=%.0f/%s keys R=%s B=%s" % [
		gates[0]["hp"], str(gates[0]["alive"]), gates[1]["hp"], str(gates[1]["alive"]),
		str(keys[0]["taken"] != -1), str(keys[1]["taken"] != -1)])
	print("[HF] units " + " ".join(ul))
	print("[HF] route goal=%s want=%s" % [_last_goal, _last_want])
	for u: Unit in units:
		if u.team == 1 and u.brain == "rescuer":
			print("[HF] rescuer pos=%s wp=%s has=%s tgt=%s stuck=%.1f cake=%d" % [
				u.pos, u.waypoint, str(u.has_waypoint), str(u.target_unit), u.stuck_t, u.cake])
			break
	print("[HF] t=%.1f player=%s hp=%.0f alive=%s rq=%d carry=%s | %s | %s | holdR=%.1f holdB=%.1f" % [
		match_time, "%.1f,%.1f" % [player.pos.x, player.pos.z] if player != null else "-",
		player.hp if player != null else 0.0,
		str(player.alive) if player != null else "-", respawn_queue.size(),
		player.carrying.title() if (player != null and player.carrying != null) else "-",
		_princess_desc(red_princess), _princess_desc(blue_princess), hold_red, hold_blue])


func _setup_demo() -> void:
	if demo == "sizes":
		var i := 0
		for w in [0.0, 3.0, 6.0, 10.0]:
			var pr := Princess.new()
			world.add_child(pr)
			pr.setup(self, 0, Vector3(-5.4 + float(i) * 3.6, 0.0, 6.0), castles[0]["throne"])
			pr.add_weight(w)
			pr.tag.text = ""
			pr.glow.visible = false
			i += 1
		player.pos = Vector3(0.0, 0.0, 13.0)
		player.position = player.pos
		zoom = 13.0
		zoom_target = 13.0
	elif demo == "chew":
		var pr := Princess.new()
		world.add_child(pr)
		pr.setup(self, 0, Vector3(0.0, 0.0, 9.6), castles[0]["throne"])
		pr.tag.text = ""
		pr.add_weight(2.0)
		player.pos = Vector3(0.0, 0.0, 13.6)
		player.position = player.pos
		player.yaw = Core.yaw_to(player.pos, pr.position)
		player.cake = 3
		zoom = 10.0
		zoom_target = 10.0
		cam_focus = Vector3(0, 0, 11.6)
	elif demo == "world":
		place(player, Vector3(0, 0, 0))
		zoom = 120.0
		zoom_target = 120.0
		cam_focus = Vector3(0, 0, 0)
	elif demo == "siege":
		place(player, Vector3(34, 0, 0))
		player.set_class("warrior")
		zoom = 23.0
		zoom_target = 23.0
		cam_focus = Vector3(30, 0, 0)
	elif demo == "cage":
		place(player, Vector3(-44, 0, -7))
		zoom = 14.0
		zoom_target = 14.0
	elif demo == "parapet":
		place(player, Vector3(-54, 0, -6))
		player.set_class("ranger")
		zoom = 27.0
		zoom_target = 27.0
	elif demo == "river":
		place(player, Vector3(13, 0, 0))
		zoom = 30.0
		zoom_target = 30.0
		cam_focus = Vector3(6, 0, 0)
	elif demo == "hill":
		place(player, Vector3(24, 0, -20))
		zoom = 26.0
		zoom_target = 26.0
		cam_focus = Vector3(24, 0, -20)
	elif demo == "worldlow":
		place(player, Vector3(0, 0, 0))
		zoom = 95.0
		zoom_target = 95.0
		cam_focus = Vector3(-16, 0, -10)
		cam_dir = Vector3(0.9, 0.30, 0.9).normalized()
	elif demo == "shots":
		var tgt := _new_unit(1, "warrior", false)
		tgt.pos = Vector3(0, 0, 7)
		tgt.position = tgt.pos
		units.append(tgt)
		var rr := _new_unit(0, "ranger", false)
		rr.pos = Vector3(-4.5, 0, 13.5)
		rr.position = rr.pos
		rr.yaw = Core.yaw_to(rr.pos, tgt.pos)
		units.append(rr)
		var mm := _new_unit(0, "mage", false)
		mm.pos = Vector3(4.5, 0, 12.5)
		mm.position = mm.pos
		mm.yaw = Core.yaw_to(mm.pos, tgt.pos)
		units.append(mm)
		player.pos = Vector3(0, 0, 17.5)
		player.position = player.pos
		zoom = 15.0
		zoom_target = 15.0
		cam_focus = Vector3(0, 0, 11.0)
	elif demo == "shotarc":
		var sh := _new_unit(0, "ranger", false)
		place(sh, Vector3(-26.0, 0.0, 46.0))
		sh.brain = "none"
		sh.yaw = Core.yaw_to(sh.pos, Vector3(-10.0, 0.0, 46.0))
		sh.rotation.y = sh.yaw
		units.append(sh)
		var tg := _new_unit(1, "warrior", false)
		place(tg, Vector3(-10.0, 0.0, 46.0))
		tg.brain = "none"
		units.append(tg)
		player.pos = Vector3(-18.0, 0.0, 34.0)
		player.position = Vector3(-18.0, Terrain.h(-18.0, 34.0), 34.0)
		zoom = 17.0
		zoom_target = 17.0
		cam_focus = Vector3(-18.0, 0.6, 44.0)
		# fire a couple of shots once the frame is warm
		fire_at_frame = 12
		fire_shot = {"owner": sh, "target": tg.position + Vector3(0, 1.15, 0), "kind": "arrow"}
	elif demo == "spectate":
		spectate = true
		# 10 v 10, all real AI brains, nothing scripted
		var roles_r := ["rescuer", "feeder", "attacker", "attacker", "worker", "feeder", "attacker", "rescuer", "feeder", "worker"]
		var classes_r := ["warrior", "ranger", "mage", "warrior", "worker", "mage", "ranger", "warrior", "mage", "worker"]
		for t in 2:
			for i in 10:
				var u := _new_unit(t, String(classes_r[i]), false)
				place(u, castles[t]["spawn"] + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
				u.brain = String(roles_r[i])
				units.append(u)
		# the "player" is a spectator: park them off-field and hide them
		player.alive = false
		player.visible = false
		zoom = 128.0
		zoom_target = 128.0
		cam_focus = Vector3.ZERO
		spectate_lbl = Label.new()
		spectate_lbl.position = Vector2(0, 80)
		var fnt: Font = ThemeDB.fallback_font
		spectate_lbl.add_theme_font_override("font", fnt)
		spectate_lbl.add_theme_font_size_override("font_size", 26)
		spectate_lbl.size = Vector2(1600, 34)
		spectate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spectate_lbl.add_theme_color_override("font_color", Core.GOLD)
		ui.add_child(spectate_lbl)
		if telemetry != "":
			telemetry_file = FileAccess.open(telemetry, FileAccess.WRITE)
			print("[HF] SPECTATE telemetry -> %s" % telemetry)
	elif demo == "staircheck":
		player.pos = Vector3(-(Bld.BACK_X - 8.0 + Bld.CASTLE_SHIFT), 0.0, 7.0)
		player.position = Vector3(player.pos.x, Terrain.h(player.pos.x, player.pos.z), player.pos.z)
		zoom = 12.0
		zoom_target = 12.0
		cam_focus = Vector3(-(Bld.BACK_X - 3.0 + Bld.CASTLE_SHIFT), 3.2, 5.0)
	elif demo == "keyprompt":
		# clear the field so the shot is about the prompt, not a fight
		for u5 in units.duplicate():
			if u5 != player and u5.team == 1:
				units.erase(u5)
				u5.queue_free()
		var kb3: Dictionary = keys[1]
		place(player, Vector3(kb3["home"].x + 2.2, 0.0, kb3["home"].z))
		zoom = 20.0
		zoom_target = 20.0
		cam_focus = player.pos + Vector3(0, 2.6, 0)
	elif demo == "keycarry":
		var kb: Dictionary = keys[1]
		place(player, Vector3(kb["home"].x + 1.0, 0.0, kb["home"].z))
		_take_key(player, kb)
		player.has_key = true
		player.key_team = 1
		place(player, Vector3(kb["home"].x + 3.2, 0.0, kb["home"].z + 1.2))
		zoom = 9.0
		zoom_target = 9.0
		cam_focus = player.pos + Vector3(0, 1.4, 0)
	elif demo == "keyhint":
		var kb2: Dictionary = keys[1]
		place(player, Vector3(kb2["home"].x + 1.0, 0.0, kb2["home"].z))
		_take_key(player, kb2)
		place(player, Vector3(kb2["home"].x + 2.0, 0.0, kb2["home"].z))
		_set_key_down(player)
		# walk away so the key is off screen: the edge arrow takes over
		place(player, Vector3(-34.0, 0.0, 6.0))
		zoom = 22.0
		zoom_target = 22.0
		cam_focus = player.pos + Vector3(0, 0.8, 0)
	elif demo == "ramp":
		player.pos = Vector3(-Terrain.RAMP_X, 0.0, Terrain.RAMP_Z)
		player.position = Vector3(player.pos.x, Terrain.h(player.pos.x, player.pos.z), player.pos.z)
		player.yaw = PI
		zoom = 40.0
		zoom_target = 40.0
		cam_focus = player.pos + Vector3(0, 1.0, 0.0)
	elif demo == "levels":
		player.pos = Vector3(-40.0, 0.0, 0.0)
		player.position = Vector3(-40.0, Terrain.h(-40.0, 0.0), 0.0)
		zoom = 26.0
		zoom_target = 26.0
		cam_focus = player.pos + Vector3(0, 0.5, 0)
	elif demo == "occ":
		# two units standing behind the red castle's back wall: one of ours, one
		# of theirs, so both silhouette colours are in frame
		var ally := _new_unit(0, "warrior", false)
		ally.pos = Vector3(-29.6, 0, 5.6)
		ally.position = Vector3(-29.6, Terrain.h(-29.6, 5.6), 5.6)
		ally.yaw = 1.5
		ally.brain = "none"
		units.append(ally)
		var foe := _new_unit(1, "ranger", false)
		foe.pos = Vector3(-29.6, 0, 9.4)
		foe.position = Vector3(-29.6, Terrain.h(-29.6, 9.4), 9.4)
		foe.yaw = -1.5
		foe.brain = "none"
		units.append(foe)
		player.pos = Vector3(-44.0, 0.0, 0.0)
		player.position = Vector3(-44.0, Terrain.h(-44.0, 0.0), 0.0)
		zoom = 12.0
		zoom_target = 13.0
		cam_focus = player.pos + Vector3(0, 0.6, 0.0)
	elif demo == "lineup2":
		var dl3 := ["villager", "warrior", "ranger", "mage", "worker"]
		for i in dl3.size():
			var u := _new_unit(0, dl3[i], false)
			var px := -44.9 + float(i) * 1.45
			u.pos = Vector3(px, 0, -3.0)
			u.position = Vector3(px, Terrain.h(px, -3.0), -3.0)
			u.yaw = 0.0
			u.brain = "none"
			units.append(u)
		player.pos = Vector3(-42.2, 0.0, -12.0)
		player.position = Vector3(player.pos.x, Terrain.h(player.pos.x, -11.0), -11.0)
		zoom = 13.0
		zoom_target = 13.0
		cam_focus = Vector3(-39.8, 0.85, -8.5)
	elif demo == "lineup":
		# mirrors the proven --demo=shots framing
		var dl2 := ["villager", "warrior", "ranger", "mage", "worker"]
		for i in dl2.size():
			var u := _new_unit(0, dl2[i], false)
			var px := -6.0 + float(i) * 3.0
			u.pos = Vector3(px, 0, 13.0)
			u.position = Vector3(px, Terrain.h(px, 13.0), 13.0)
			u.yaw = 0.0
			u.brain = "none"
			units.append(u)
		player.pos = Vector3(0.0, 0.0, 20.0)
		player.position = Vector3(0.0, Terrain.h(0.0, 20.0), 20.0)
		zoom = 15.0
		zoom_target = 15.0
		cam_focus = Vector3(0.0, 0.0, 13.0)
	elif demo.begins_with("show_"):
		var who: String = demo.substr(5)
		var su := _new_unit(0, who, false)
		su.pos = Vector3(-41.0, 0, 2.0)
		su.position = Vector3(-41.0, Terrain.h(-41.0, 2.0), 2.0)
		su.yaw = 0.0
		su.brain = "none"
		units.append(su)
		print("[HF] show unit %s placed %s global %s visible %s" % [who, str(su.pos), str(su.global_position), str(su.visible)])
		player.pos = Vector3(-41.0, 0.0, 12.0)
		player.position = Vector3(-41.0, Terrain.h(-41.0, 12.0), 12.0)
		zoom = 8.0
		zoom_target = 8.0
		cam_focus = Vector3(-41.0, 1.05, 2.0)
	elif demo == "classes":
		var dl := ["villager", "warrior", "ranger", "mage", "worker"]
		for i in dl.size():
			var u := _new_unit(0, dl[i], false)
			var px := -46.0 + float(i) * 2.5
			u.pos = Vector3(px, 0, 2.0)
			u.position = Vector3(px, Terrain.h(px, 2.0), 2.0)
			u.yaw = 0.0
			u.brain = "none"
			units.append(u)
		player.pos = Vector3(-41.0, 0.0, 12.0)
		player.position = Vector3(-41.0, Terrain.h(-41.0, 12.0), 12.0)
		zoom = 12.0
		zoom_target = 12.0
		cam_focus = Vector3(-41.0, 1.0, 2.0)
	elif demo == "feed":
		player.pos = castles[0]["dungeon"] + Vector3(4.2, 0.0, 3.0)
		player.position = player.pos
		player.cake = 3
		zoom = 12.0
		zoom_target = 12.0


	_lock_demo_cam()


func _lock_demo_cam() -> void:
	demo_focus = cam_focus
	demo_zoom = zoom


func _demo_princess() -> Princess:
	for pr in [red_princess, blue_princess]:
		if pr != null and is_instance_valid(pr):
			pass
	# the demo princess is the extra one added in _setup_demo, closest to the player
	var best: Princess = null
	var bd := 999.0
	for node in world.get_children():
		if node is Princess:
			var pr: Princess = node
			var d := pr.position.distance_to(player.pos)
			if d < bd:
				bd = d
				best = pr
	return best


func _setup_net() -> void:
	net = Net.new()
	net.game = self
	net.world = world
	add_child(net)
	net.connected.connect(_on_net_connected)
	net.failed.connect(_on_net_failed)
	ui.online_pressed.connect(_join_online)


func _join_online(team: int) -> void:
	if net == null:
		return
	net.my_team = team
	net.room = "public"
	net.join(team, "player")
	ui.toast("joining the %s side…" % ("red" if team == 0 else "blue"))


func _on_net_connected() -> void:
	start_match(false)
	net.world = world
	if player != null:
		player.team = net.my_team
		player.set_class(player.cls)
	ui.flash_banner("%s SIDE — ONLINE" % ("RED" if net.my_team == 0 else "BLUE"),
		Color("cf3f36") if net.my_team == 0 else Color("3364cc"), 2.2)
	ui.toast("in the room — other players appear as ghosts")


func _on_net_failed(why: String) -> void:
	ui.toast("online unavailable (%s) — solo still works" % why)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-path="):
			shot_path = a.substr(12)
		elif a.begins_with("--shot-frame="):
			shot_frame = int(a.substr(13))
		elif a == "--autoplay":
			autoplay = true
		elif a == "--smoke":
			autoplay = true
		elif a == "--inputdebug":
			input_debug = true
		elif a == "--showsil":
			showsil = true
		elif a.begins_with("--telemetry="):
			telemetry = a.substr(12)
		elif a == "--navprobe":
			navprobe = true
		elif a == "--stuckaudit":
			stuckaudit = true
		elif a == "--snaptest":
			snaptest = true
		elif a == "--deckaudit":
			deckaudit = true
		elif a == "--perf":
			perf = true
		elif a == "--pathaudit":
			pathaudit = true
		elif a == "--shottest":
			shottest = true
		elif a == "--keyflow":
			keyflow = true
		elif a == "--nettest":
			nettest = true
		elif a == "--hattest":
			hattest = true
		elif a == "--jumptest":
			jumptest = true
		elif a == "--respawntest":
			respawntest = true
		elif a == "--occtest":
			occtest = true
		elif a == "--camtest":
			camtest = true
		elif a == "--wintest":
			wintest = true
		elif a == "--synergytest":
			synergytest = true
		elif a == "--siegetest":
			siegetest = true
		elif a == "--walltest":
			walltest = true
		elif a == "--attacktest":
			attacktest = true
		elif a == "--keytest":
			keytest = true
		elif a == "--movetest":
			movetest = true
		elif a == "--play":
			start_play = true
		elif a == "--tutorial":
			start_tutorial = true
		elif a.begins_with("--demo="):
			demo = a.substr(7)
		elif a == "--help":
			start_help = true
		elif a.begins_with("--click="):
			click_target = a.substr(8)
		elif a.begins_with("--at="):
			var parts := a.substr(5).split(",")
			if parts.size() == 2:
				spawn_at = Vector3(float(parts[0]), 0.0, float(parts[1]))
		elif a.begins_with("--simtest="):
			simtest = float(a.substr(10))
		elif a.begins_with("--match="):
			pass


func _make_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ORTHO_SIZE
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	camera.position = cam_dir * 90.0
	camera.look_at(Vector3.ZERO)


func _make_ui() -> void:
	ui = UI.new()
	ui.game = self
	add_child(ui)
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.play_pressed.connect(func(): start_match(false))
	ui.tutorial_pressed.connect(func(): start_match(true))
	ui.resume_pressed.connect(func(): _set_pause(false))
	ui.restart_pressed.connect(func(): start_match(state == S_TUTORIAL))
	ui.menu_pressed.connect(func(): _set_pause(false); start_menu())
	if ui.map_view != null:
		ui.map_view.game = self


func _make_audio() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx.append(p)


func play_sfx(stream: AudioStream, db: float = -9.0) -> void:
	if sfx.is_empty():
		return
	var p: AudioStreamPlayer = sfx[sfx_i % sfx.size()]
	sfx_i += 1
	p.stream = stream
	p.volume_db = db
	p.play()


func _make_world_labels() -> void:
	near_lbl = Core.label3d(self, "", Vector3.ZERO, 34, Color("ffd766"))
	near_lbl.fixed_size = true
	# fixed_size scales by pixel_size: 0.016 (the world-space default) made this
	# a screen-filling banner, so it gets its own tiny value
	near_lbl.pixel_size = 0.00115
	near_lbl.no_depth_test = true
	near_lbl.visible = false
	hint_lbl = Core.label3d(self, "", Vector3.ZERO, 40, Color(0.9, 0.95, 1.0, 0.85))
	hint_lbl.no_depth_test = true
	hint_lbl.visible = false


# ================================================================ match setup
func start_menu() -> void:
	_clear_actors()
	state = S_MENU
	ui.show_menu()
	menu_t = 0.0
	zoom_target = 40.0
	zoom = 40.0
	_spawn_scenery_units()


func _spawn_scenery_units() -> void:
	# A few idle soldiers so the menu backdrop is a live scene, not a diorama.
	for i in 3:
		var u := _new_unit(0, ["warrior", "ranger", "mage"][i], false)
		place(u, Vector3(-58 + float(i) * 2.4, 0, -2.0 + float(i) * 1.2))
		u.yaw = 1.2
		units.append(u)
	var b := _new_unit(1, "warrior", false)
	b.pos = Vector3(8, 0, 4)
	b.position = b.pos
	units.append(b)


func spawn_princesses() -> void:
	if red_princess != null and is_instance_valid(red_princess):
		red_princess.queue_free()
	if blue_princess != null and is_instance_valid(blue_princess):
		blue_princess.queue_free()
	red_princess = Princess.new()
	world.add_child(red_princess)
	red_princess.setup(self, 0, castles[1]["dungeon"], castles[0]["throne"])
	blue_princess = Princess.new()
	world.add_child(blue_princess)
	blue_princess.setup(self, 1, castles[0]["dungeon"], castles[1]["throne"])


func start_match(is_tutorial: bool) -> void:
	_clear_actors()
	match_time = 0.0
	hold_red = 0.0
	hold_blue = 0.0
	hold_target = WIN_HOLD
	sudden = false
	hold_active = -1
	tutorial_step = 0
	tutorial_done = false
	tut_last_pos = Vector3.ZERO
	tut_zoom_seen = false
	zoom = 27.0
	zoom_target = 27.0
	spawn_princesses()
	_spawn_cakes()
	_spawn_hats()
	_spawn_gates()
	_spawn_keys()
	_spawn_resources()
	_spawn_dummies(is_tutorial)

	player = _new_unit(0, "worker", true)
	place(player, castles[0]["spawn"] + Vector3(0.8, 0, 1.6))
	if spawn_at.x < 9000.0:
		place(player, spawn_at)
	player.position = player.pos
	player.label.text = ""
	units.append(player)
	match_start_ms = Time.get_ticks_msec()
	tut_last_pos = player.pos

	if is_tutorial:
		state = S_TUTORIAL
		ui.show_hud()
		ui.set_tutorial(1, 7, "MOVE", "WASD or the arrow keys. Scroll to zoom. The camera is isometric and follows you.")
	else:
		state = S_PLAY
		ui.show_hud()
		ui.hide_tutorial()
		ui.flash_banner("RESCUE THE RED PRINCESS", Color("e8b53f"), 2.6)
		# Blue army
		var roles := ["rescuer", "feeder", "attacker", "attacker", "worker"]
		var classes := ["warrior", "ranger", "mage", "warrior", "worker"]
		for i in roles.size():
			var b := _new_unit(1, classes[i], false)
			place(b, castles[1]["spawn"] + Vector3(float(i % 2) * 1.6, 0, float(i) * 1.1))
			b.brain = roles[i]
			units.append(b)
		# Red allies: enough bodies to contest four Blue bots
		var ally_classes := ["warrior", "ranger", "mage", "worker"]
		var ally_brains := ["ally", "ally", "feeder", "worker"]
		for i in ally_classes.size():
			var r := _new_unit(0, ally_classes[i], false)
			place(r, castles[0]["spawn"] + Vector3(float(i) * 1.8, 0, -1.4 - float(i) * 0.6))
			r.brain = ally_brains[i]
			units.append(r)
	if not Nav.built:
		Nav.build(solids)
	cam_focus = player.pos
	camera.size = zoom
	ui.ui_guard = 0.5


func _clear_actors() -> void:
	for u: Unit in units:
		if is_instance_valid(u):
			u.queue_free()
	units.clear()
	for p in projectiles:
		if is_instance_valid(p["node"]):
			p["node"].queue_free()
	projectiles.clear()
	for th in throws:
		if is_instance_valid(th["node"]):
			th["node"].queue_free()
	throws.clear()
	for f in fx:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	fx.clear()
	for c in cakes:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	cakes.clear()
	for h in hats:
		if is_instance_valid(h["node"]):
			h["node"].queue_free()
	hats.clear()
	for d in dummies:
		if is_instance_valid(d["node"]):
			d["node"].queue_free()
	dummies.clear()
	for r in resources:
		if is_instance_valid(r["node"]):
			r["node"].queue_free()
	resources.clear()
	for h in dropped_hats:
		if is_instance_valid(h["node"]):
			h["node"].queue_free()
	dropped_hats.clear()
	gates.clear()
	keys.clear()
	respawn_queue.clear()
	if red_princess != null and is_instance_valid(red_princess):
		red_princess.queue_free()
		red_princess = null
	if blue_princess != null and is_instance_valid(blue_princess):
		blue_princess.queue_free()
		blue_princess = null
	player = null


func place(u: Unit, p: Vector3) -> void:
	u.pos = Vector3(p.x, 0.0, p.z)
	u.position = Vector3(p.x, Terrain.h(p.x, p.z), p.z)


func _new_unit(team: int, klass: String, is_player: bool) -> Unit:
	var u := Unit.new()
	world.add_child(u)
	u.setup(self, team, klass, is_player)
	return u


func _spawn_gates() -> void:
	gates.clear()
	for t in 2:
		var c: Dictionary = castles[t]
		gates.append({
			"team": t, "hp": 700.0, "max": 700.0,
			"node": c["gate_node"], "rect": c["gate_rect"], "pos": c["gate_pos"],
			"alive": true, "solid": "gate%d" % t, "open_t": 0.0, "last_hit": -99.0, "sealed": false,
		})


func _spawn_keys() -> void:
	keys.clear()
	for t in 2:
		var c: Dictionary = castles[t]
		var kp := Vector3(c["key_pos"].x, 0.0, c["key_pos"].z)
		keys.append({"team": t, "pos": kp, "home": kp,
			"node": c["key_node"], "taken": -1, "dropped": false, "t": 0.0})


func _spawn_resources() -> void:
	for r in resources:
		if is_instance_valid(r["node"]):
			r["node"].queue_free()
	resources.clear()
	var spots := [
		["wood", castles[0]["court"] + Vector3(9.0, 0, -13.0)], ["wood", castles[0]["court"] + Vector3(2.0, 0, 14.0)],
		["metal", castles[0]["court"] + Vector3(-8.0, 0, -14.0)],
		["wood", castles[1]["court"] + Vector3(-9.0, 0, 13.0)], ["wood", castles[1]["court"] + Vector3(-2.0, 0, -14.0)],
		["metal", castles[1]["court"] + Vector3(8.0, 0, 14.0)],
		["wood", Vector3(-19, 0, 21)], ["wood", Vector3(19, 0, -21)],
		["metal", Vector3(-21, 0, -13)], ["metal", Vector3(21, 0, 13)],
	]
	for sp in spots:
		var kind: String = sp[0]
		var p: Vector3 = sp[1]
		var n := Bld.resource_node(world, kind, Vector3(p.x, Terrain.h(p.x, p.z), p.z))
		resources.append({"kind": kind, "pos": Vector3(p.x, 0.0, p.z), "node": n, "count": 3, "t": 0.0, "active": true})


func _spawn_hats() -> void:
	for t in 2:
		for h in castles[t]["hats"]:
			hats.append({"team": t, "pos": Vector3(h["pos"].x, 0.0, h["pos"].z), "cls": h["cls"]})


func _spawn_dummies(on: bool) -> void:
	if not on:
		return
	var base: Vector3 = castles[0]["court"]
	var spots := [base + Vector3(6.0, 0, -4.0), base + Vector3(9.0, 0, -6.0), base + Vector3(3.0, 0, -8.5)]
	for s in spots:
		var n := Bld.dummy(world, Vector3(s.x, Terrain.h(s.x, s.z), s.z))
		dummies.append({"node": n, "pos": Vector3(s.x, 0.0, s.z), "hp": 60.0, "t": 0.0})


func _spawn_cakes() -> void:
	var spots := [
		Vector3(-40, 0, -16), Vector3(-40, 0, 17), Vector3(-24, 0, 0),
		Vector3(40, 0, 16), Vector3(40, 0, -17), Vector3(24, 0, 0),
		Vector3(-13, 0, 34), Vector3(13, 0, -34), Vector3(-15, 0, -26), Vector3(15, 0, 26),
		Vector3(0, 0, 42), Vector3(0, 0, -42),
	]
	for s in spots:
		_add_cake_pile(s, 2)
	for t in 2:
		var d: Vector3 = castles[t]["dungeon"]
		_add_cake_pile(d + Vector3(0, 0, 4.6), 2)


func _add_cake_pile(pos: Vector3, count: int) -> void:
	var n := Bld.cake_pile(world)
	n.position = Vector3(pos.x, Terrain.h(pos.x, pos.z), pos.z)
	# flat pos: unit positions are logic-space (y = 0), props sit on the terrain
	cakes.append({"node": n, "pos": Vector3(pos.x, 0.0, pos.z), "count": count, "active": true, "t": 0.0})


# ================================================================ loop
func _process(dt: float) -> void:
	var frame_t0 := Time.get_ticks_usec() if perf else 0
	frame_count += 1
	if demo == "shots" and frame_count == 20:
		for u: Unit in units:
			if u.cls == "ranger" and u.team == 0:
				spawn_projectile(u, u.pos + Vector3(0, 1.25, 0), Vector3(0, 0, 7), "arrow")
			elif u.cls == "mage" and u.team == 0:
				spawn_projectile(u, u.pos + Vector3(0, 1.35, 0), Vector3(0, 0, 7), "fire")
		for pr in projectiles:
			pr["speed"] = 11.0
	if demo == "chew" and frame_count == 40:
		player.cake -= 1
		throw_cake(player, _demo_princess())
	if demo == "feed" and not demo_fired and frame_count >= 100:
		demo_fired = true
		if blue_princess != null:
			player.cake -= 1
			throw_cake(player, blue_princess)
	if shot_path != "" and frame_count >= shot_frame:
		print("[SHOT] frame=%d cam.size=%.1f focus=%s vis=%s aabb=%s" % [frame_count, camera.size, cam_focus,
			str(Terrain.ground_node.is_visible_in_tree()) if Terrain.ground_node != null else "nul",
			Terrain.ground_node.get_aabb() if Terrain.ground_node != null else Rect2()])
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("[HF] shot saved ", shot_path)
		get_tree().quit()
		return

	_update_camera(dt)
	_animate_props(dt)
	if input_debug and ui != null and ui.dbg_label != null:
		ui.dbg_label.visible = true
		ui.dbg_label.text = "mr=%.2f pos=%.2f,%.2f vel=%.2f alive=%s st=%d block=%s" % [
			Input.get_action_strength("move_right"),
			player.pos.x if player != null else 0.0, player.pos.z if player != null else 0.0,
			player.vel.length() if player != null else 0.0,
			str(player.alive) if player != null else "-", state,
			str(_blocked(player.pos, 0.4)) if player != null else "-"]
	if autoplay:
		dbg_t -= dt
		if dbg_t <= 0.0:
			dbg_t = 2.0
			_dbg()

	if state == S_PLAY or state == S_TUTORIAL:
		_step(dt)
		if perf:
			var us := Time.get_ticks_usec() - frame_t0
			perf_frame_us += us
			perf_max_us = maxi(perf_max_us, us)
			if us > 30000:
				var parts := []
				for k in perf_frame_labels.keys():
					parts.append("%s=%.1f" % [k, float(perf_frame_labels[k]) / 1000.0])
				print("[HF] SPIKE frame=%d %.1f ms  %s" % [frame_count, float(us) / 1000.0, " ".join(parts)])
			if perf_frames >= 600:
				_perf_report()
	elif state == S_MENU:
		for u: Unit in units:
			if is_instance_valid(u) and u.alive:
				u.update_unit(dt, Vector3.ZERO, Vector3.ZERO)

	# the YOU tag is onboarding: it fades out once the player has their bearings
	if player != null and is_instance_valid(player) and player.you_label != null:
		var t := (Time.get_ticks_msec() - match_start_ms) * 0.001
		player.you_label.modulate.a = clampf(1.5 - t / 28.0, 0.0, 1.0)
	if state != S_OVER:
		ui.update_hud(_hud_data())


func _animate_props(dt: float) -> void:
	for h in hats:
		var hc: Dictionary = castles[h["team"]]
		pass
	for c in cakes:
		if c["active"] and is_instance_valid(c["node"]):
			c["node"].rotation.y += dt * 0.9
			var glow: Node = c["node"].get_node_or_null("Glow")
			if glow != null:
				glow.scale = Vector3.ONE * (0.96 + sin(Time.get_ticks_msec() * 0.003) * 0.06)
	if red_princess != null and is_instance_valid(red_princess):
		red_princess.update_princess(dt)
	if blue_princess != null and is_instance_valid(blue_princess):
		blue_princess.update_princess(dt)


## Profiler: every block in _step records how long it took, and the run prints a
## mean-ms-per-frame table. Cheap enough to leave in (it is a no-op unless --perf).
var perf_frame_labels := {}
var nav_budget := 2          # A* searches allowed per frame: one long path is
                             # ~4 ms, so ten of them at once was a 50 ms hitch


func _pt(label: String, since: int) -> int:
	if not perf:
		return 0
	var now := Time.get_ticks_usec()
	var d := now - since
	perf_acc[label] = float(perf_acc.get(label, 0.0)) + float(d)
	perf_frame_labels[label] = float(perf_frame_labels.get(label, 0.0)) + float(d)
	return now


func _perf_report() -> void:
	if not perf or perf_frames == 0:
		return
	var rows := []
	for k in perf_acc.keys():
		rows.append([String(k), float(perf_acc[k]) / float(perf_frames) / 1000.0])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var total := float(perf_frame_us) / float(perf_frames) / 1000.0
	print("[HF] PERF frames=%d  frame mean=%.2f ms  worst=%.2f ms  (~%.0f fps)" % [
		perf_frames, total, float(perf_max_us) / 1000.0, 1000.0 / maxf(total, 0.01)])
	for r in rows:
		if r[1] >= 0.01:
			print("[HF]   %-22s %6.2f ms  %5.1f%%" % [r[0], r[1], 100.0 * r[1] / maxf(total, 0.01)])
	get_tree().quit()


func _step(dt: float) -> void:
	if demo == "world":
		return
	if demo == "shots":
		# frozen actors: only the projectiles animate, so a frame can be judged
		_update_projectiles(dt)
		_update_fx(dt)
		return
	perf_frame_labels.clear()
	nav_budget = 2
	match_time += dt
	var t := Time.get_ticks_usec() if perf else 0
	_handle_player(dt)
	t = _pt("player", t)
	_update_ai(dt)
	t = _pt("ai_think", t)
	for u: Unit in units:
		if not is_instance_valid(u) or not u.alive:
			continue
		if u == player:
			continue
		var t2 := Time.get_ticks_usec() if perf else 0
		if not u.has_waypoint and u.target_unit == null:
			u.idle_t += dt
			if u.idle_t > 3.0:
				u.idle_t = 0.0
				u.waypoint = gates[1 - u.team]["pos"]
				u.has_waypoint = true
		else:
			u.idle_t = 0.0
		var dir := _ai_dir(u, dt)
		t2 = _pt("  ai_nav", t2)
		var aim := u.target_unit.pos if (u.target_unit != null and is_instance_valid(u.target_unit)) else u.waypoint
		u.update_unit(dt, dir, aim)
		_auto_attack(u, aim)
		_pt("  unit_update", t2)
	t = _pt("units_total", t)
	separate_units()
	t = _pt("separate", t)
	_update_home_heal(dt)
	_update_carry_helpers()
	t = _pt("helpers", t)
	_update_projectiles(dt)
	t = _pt("projectiles", t)
	_update_throws(dt)
	_update_gates(dt)
	t = _pt("gates", t)
	_update_stations(dt)
	_update_keys(dt)
	_update_resources(dt)
	_update_fx(dt)
	_update_cakes(dt)
	_update_respawns(dt)
	_update_dropped_hats(dt)
	t = _pt("world_systems", t)
	_update_silhouettes(dt)
	t = _pt("silhouettes", t)
	_maybe_fire_demo()
	_write_telemetry(dt)
	if spectate and spectate_lbl != null:
		var ra := 0
		var ba := 0
		for u: Unit in units:
			if u.team == 0 and u.alive:
				ra += 1
			elif u.team == 1 and u.alive:
				ba += 1
		spectate_lbl.text = "SPECTATING · RED %d · BLUE %d · GATES %d%% / %d%%" % [
			ra, ba, int(100.0 * float(gates[0]["hp"]) / float(gates[0]["max"])),
			int(100.0 * float(gates[1]["hp"]) / float(gates[1]["max"]))]
	_update_interaction_label()
	if state == S_TUTORIAL:
		_update_tutorial(dt)
	else:
		_update_sudden_death()
		_update_holds(dt)
	_check_end()
	perf_frames += 1


func _handle_player(dt: float) -> void:
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	var dir := Vector3.ZERO
	var iv := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	)
	if autoplay:
		iv = _autoplay_input(dt)
	if iv.length() > 0.05:
		var cam_fwd := -camera.global_transform.basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()
		var cam_right := camera.global_transform.basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()
		dir = (cam_right * iv.x + cam_fwd * iv.y).normalized()
	var aim := _mouse_aim()
	if autoplay:
		aim = player.pos + Vector3(0, 0, 1)
		if player.target_unit != null and is_instance_valid(player.target_unit):
			aim = player.target_unit.pos
	player.update_unit(dt, dir, aim)

	if Input.is_action_just_pressed("jump") and not player.airborne:
		player.start_jump()
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("attack_mouse") or (autoplay and player.target_unit != null):
		player.attack(aim)
	if Input.is_action_just_pressed("dash") and player.dash_cd <= 0.0:
		player.dash_t = 0.2
		player.dash_cd = 1.5
		add_shake(0.05)
	if Input.is_action_just_pressed("act"):
		_player_interact()
	if Input.is_action_just_pressed("drop") and player.carrying != null:
		drop_princess(player)
	if Input.is_action_just_pressed("feed"):
		_player_feed()
	if autoplay:
		_autoplay_actions()


## What the player is pointing at. A unit under the cursor wins (aimed at its
## chest); otherwise the point on the ground, so a shot into open field lands
## where the cursor is and poofs on the terrain.
func _mouse_aim() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var best: Unit = null
	var best_d := 46.0
	for u: Unit in units:
		if not u.alive or u.team == player.team or not is_instance_valid(u):
			continue
		var chest: Vector3 = u.position + Vector3(0, 1.15, 0)
		if camera.is_position_behind(chest):
			continue
		var sp: Vector2 = camera.unproject_position(chest)
		var d: float = sp.distance_to(mp)
		if d < best_d:
			best_d = d
			best = u
	if best != null:
		player.target_unit = best
		return best.position + Vector3(0, 1.15, 0)
	player.target_unit = null
	return _mouse_ground()


func _mouse_ground() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var n := camera.project_ray_normal(mp)
	if absf(n.y) < 0.001:
		return player.pos + Vector3(0, 0, 1)
	var t: float = (1.0 - o.y) / n.y
	var p := o + n * t
	p.y = 0.0
	return p


func _player_interact() -> void:
	if player.carrying != null:
		drop_princess(player)
		return
	# putting a carried key down is the same button that picked it up
	if player.has_key:
		_set_key_down(player)
		return
	var kk := _nearest_key(player.pos, 3.0)
	if not kk.is_empty():
		_take_key(player, kk)
		return
	var pr := _nearest_princess(player.pos, 3.2, true)
	if pr != null:
		pick_up(pr, player)
		return
	var st := _nearest_hat(player.pos, 2.6)
	if not st.is_empty():
		if player.cls == st["cls"]:
			ui.toast("already a " + st["cls"])
		else:
			player.set_class(st["cls"])
			play_sfx(Core.tone(420.0, 0.22, "square", 0.22, 660.0), -11.0)
			add_shake(0.04)
			ui.flash_banner(Unit.NAMES[st["cls"]].to_upper() + " HAT", Color("e8b53f"), 1.0)
			ui.toast("you are a %s now" % st["cls"])
		return
	ui.toast("nothing to pick up here")


func _player_feed() -> void:
	var pr := _nearest_princess(player.pos, 3.4, true)
	if pr == null:
		ui.toast("stand next to the captive princess")
		return
	if pr.team == player.team:
		ui.toast("she is your own princess — feed the captive instead")
		return
	if player.cake <= 0:
		ui.toast("no cake — find a cake pile")
		return
	if pr.carried_by != null:
		ui.toast("put her down first")
		return
	if pr.weight >= pr.max_weight - 0.01:
		ui.toast("she cannot eat another bite")
		return
	player.cake -= 1
	throw_cake(player, pr)
	ui.toast("cake away — catch!")
	add_shake(0.02)


func _nearest_princess(p: Vector3, rng: float, skip_carried: bool) -> Princess:
	var best: Princess = null
	var bd := rng
	for pr in [red_princess, blue_princess]:
		if pr == null or not is_instance_valid(pr):
			continue
		if skip_carried and pr.carried_by != null:
			continue
		var d := p.distance_to(pr.position)
		if d < bd:
			bd = d
			best = pr
	return best


func _nearest_hat(p: Vector3, rng: float) -> Dictionary:
	var best := {}
	var bd := rng
	for h in hats:
		if h["team"] != 0:
			continue
		var d := p.distance_to(h["pos"])
		if d < bd:
			bd = d
			best = h
	return best


func _update_cakes(dt: float) -> void:
	for c in cakes:
		if not c["active"]:
			c["t"] -= dt
			if c["t"] <= 0.0:
				c["active"] = true
				c["count"] = 2
				c["node"].visible = true
			continue
		for u: Unit in units:
			if not u.alive or u.cake >= 3:
				continue
			if u.pos.distance_to(c["pos"]) < 1.35:
				u.pickup_cake(1)
				c["count"] -= 1
				if c["count"] <= 0:
					c["active"] = false
					c["t"] = 11.0
					c["node"].visible = false
				break


func _update_respawns(dt: float) -> void:
	for i in range(respawn_queue.size() - 1, -1, -1):
		var r: Dictionary = respawn_queue[i]
		r["t"] -= dt
		if r["t"] <= 0.0:
			var u: Unit = r["unit"]
			if is_instance_valid(u):
				u.respawn(_respawn_point(u.team))
			respawn_queue.remove_at(i)


## Hats left by the dead. Walk over one and it is yours — the fastest way for a
## hatless worker to get back into a fight.
func _update_dropped_hats(dt: float) -> void:
	for i in range(dropped_hats.size() - 1, -1, -1):
		var h: Dictionary = dropped_hats[i]
		var node: Node3D = h["node"]
		if is_instance_valid(node):
			node.rotation.y += dt * 0.9
		for u: Unit in units:
			if not u.alive or u.cls == String(h["cls"]):
				continue
			if u.pos.distance_to(h["pos"]) > 1.6:
				continue
			if u.cls != "worker":
				continue                       # you have to be hatless to scavenge
			u.set_class(String(h["cls"]))
			if u == player:
				ui.toast("%s hat — press E on a stand to change again" % String(h["cls"]).to_upper())
			play_sfx(Core.tone(680.0, 0.14, "tri", 0.25, 900.0), -10.0)
			if is_instance_valid(node):
				node.queue_free()
			dropped_hats.remove_at(i)
			break


## Respawn on your own half, not always in the same doorway.
func _respawn_point(team: int) -> Vector3:
	var sx := -1.0 if team == 0 else 1.0
	for i in 40:
		var x: float = sx * randf_range(20.0, 74.0)
		var z := randf_range(-48.0, 48.0)
		if not Terrain.walkable(x, z):
			continue
		if Terrain.on_bridge(x, z):
			continue
		if Terrain.h(x, z) > Terrain.PLATEAU_H + 0.4:
			continue                     # not on top of a wall
		return Vector3(x, 0.0, z)
	return castles[team]["spawn"]


func _update_holds(dt: float) -> void:
	if state != S_PLAY:
		return
	var rp := red_princess
	var bp := blue_princess
	var red_home := rp != null and rp.carried_by == null and rp.position.distance_to(castles[0]["throne"]) < 3.6
	var blue_home := bp != null and bp.carried_by == null and bp.position.distance_to(castles[1]["throne"]) < 3.6
	hold_red = clampf(hold_red + (dt if red_home else -dt * 3.0), 0.0, hold_target)
	hold_blue = clampf(hold_blue + (dt if blue_home else -dt * 3.0), 0.0, hold_target)
	if red_home:
		hold_active = 0
	elif blue_home:
		hold_active = 1
	else:
		hold_active = -1
	if red_home and fmod(hold_red, 4.0) < dt and hold_red > 1.0:
		ui.flash_banner("%.0f" % ceilf(hold_target - hold_red), Color("e8b53f"), 0.8)
	if blue_home and fmod(hold_blue, 4.0) < dt and hold_blue > 1.0:
		ui.toast("blue is holding her princess — stop them!")


## Both princesses fattened to a standstill is a real stalemate: the cake melts
## and the hold shortens so a match always resolves.
func _update_sudden_death() -> void:
	if sudden or match_time < SUDDEN_AT:
		return
	sudden = true
	hold_target = SUDDEN_HOLD
	hold_red = minf(hold_red, hold_target)
	hold_blue = minf(hold_blue, hold_target)
	for pr in [red_princess, blue_princess]:
		if pr != null and is_instance_valid(pr):
			pr.fast_decay = true
	# A siege can stall forever with two workers rebuilding two doors. Sudden
	# death ends that: the gates come down, the cages pop open, and the fight
	# has to be settled in the open.
	for g in gates:
		g["sealed"] = true
		_damage_gate(int(g["team"]), 99999.0)
	for pr2 in [red_princess, blue_princess]:
		if pr2 != null and is_instance_valid(pr2) and pr2.locked:
			pr2.locked = false
	ui.flash_banner("SUDDEN DEATH — THE GATES FALL", Color("f2541b"), 3.0)
	ui.toast("gates broken, cages open · hold the throne for 9 seconds")


func _check_end() -> void:
	if state != S_PLAY:
		return
	if hold_red >= hold_target:
		_end_match(true)
	elif hold_blue >= hold_target:
		_end_match(false)


func _end_match(win: bool) -> void:
	state = S_OVER
	var detail := ""
	if win:
		detail = "The Red Princess is home and the throne is yours.\nThe Blue Princess is still fat and forgotten in your dungeon."
	else:
		detail = "The Blue team walked your princess out of the dungeon and crowned her at their throne.\nFeed her more cake next time — weight is the only wall that matters."
	if win:
		play_sfx(Core.tone(523.0, 0.30, "tri", 0.32))
		play_sfx(Core.tone(659.0, 0.32, "tri", 0.32))
		play_sfx(Core.tone(784.0, 0.55, "tri", 0.32))
	else:
		play_sfx(Core.tone(392.0, 0.35, "tri", 0.30, 196.0))
	ui.show_end(win, _clock(), detail)
	ui.flash_banner("", Color.WHITE, 0.01)


func _clock() -> String:
	return "%02d:%02d" % [int(match_time) / 60, int(match_time) % 60]


# ================================================================ combat
func move_unit(p: Vector3, delta: Vector3, u: Unit) -> Vector3:
	var rad := 0.40
	var np := p + delta
	np.x = clampf(np.x, -Terrain.HALF_X + 1.5, Terrain.HALF_X - 1.5)
	np.z = clampf(np.z, -Terrain.HALF_Z + 1.5, Terrain.HALF_Z - 1.5)
	var h0 := Terrain.h(p.x, p.z)
	if u.airborne:
		np.x = clampf(np.x, -Terrain.HALF_X + 1.5, Terrain.HALF_X - 1.5)
		np.z = clampf(np.z, -Terrain.HALF_Z + 1.5, Terrain.HALF_Z - 1.5)
		u.pos = np
		return np
	if not _can_step(np, h0, rad, u.team):
		var try_x := Vector3(np.x, 0, p.z)
		var try_z := Vector3(p.x, 0, np.z)
		if _can_step(try_x, h0, rad, u.team):
			np = try_x
		elif _can_step(try_z, h0, rad, u.team):
			np = try_z
		else:
			np = p
	np.y = 0.0
	return np


## A step is legal if the ground is walkable, no wall taller than the unit's feet
## is in the way, and the height change is one a body can make.
func _can_step(p: Vector3, from_h: float, rad: float, team: int = -1) -> bool:
	if not Terrain.walkable(p.x, p.z):
		return false
	var h1 := Terrain.h(p.x, p.z)
	if h1 - from_h > Terrain.STEP_UP:
		return false
	# No walking off a ledge. The river is 6 m below the bridge deck and there was
	# no downward check, so a unit nudged at the bridge lip stepped into the water
	# and then had no legal route out of a cell A* refuses to start from.
	if from_h - h1 > 2.45:
		return false                                # too high to climb
	if from_h - h1 > Terrain.STEP_DOWN:
		return false                                # do not walk off the parapet
	for s in solids:
		var rr: Rect2 = s["r"]
		if float(s["top"]) < from_h + 0.25:
			continue                                # we are standing on top of this
		var tag: String = String(s.get("tag", ""))
		if tag != "" and team >= 0 and tag == "gate%d" % team:
			continue                                # your own gate opens for you
		if rr.grow(rad).has_point(Vector2(p.x, p.z)):
			return false
	return true


func _blocked(p: Vector3, rad: float, team: int = -1) -> bool:
	return not _can_step(p, Terrain.h(p.x, p.z), rad, team)


func _update_home_heal(dt: float) -> void:
	for u: Unit in units:
		if not u.alive or u.hp >= u.max_hp:
			continue
		if u.pos.distance_to(castles[u.team]["spawn"]) < 3.4 or u.pos.distance_to(castles[u.team]["throne"]) < 3.0:
			u.hp = minf(u.max_hp, u.hp + 20.0 * dt)


func separate_units() -> void:
	for i in units.size():
		var a: Unit = units[i]
		if not a.alive:
			continue
		for j in range(i + 1, units.size()):
			var b: Unit = units[j]
			if not b.alive:
				continue
			var d := b.pos - a.pos
			d.y = 0.0
			var dist := d.length()
			if dist > 0.001 and dist < 0.9:
				var push := d / dist * (0.9 - dist) * 0.5
				# never shove someone onto a ledge they cannot climb
				var na := a.pos - push
				if absf(Terrain.h(na.x, na.z) - Terrain.h(a.pos.x, a.pos.z)) <= Terrain.STEP_UP:
					a.pos = na
				var nb := b.pos + push
				if absf(Terrain.h(nb.x, nb.z) - Terrain.h(b.pos.x, b.pos.z)) <= Terrain.STEP_UP:
					b.pos = nb


func _update_carry_helpers() -> void:
	for u: Unit in units:
		if not u.alive or u.carrying == null:
			continue
		var n := 0
		for o: Unit in units:
			if o == u or not o.alive or o.team != u.team:
				continue
			if o.pos.distance_to(u.pos) < 4.0:
				n += 1
		u.carrying.helpers = mini(n, 3)


func melee_hit(u: Unit, rng: float, dmg: float, force_drop: bool) -> void:
	play_sfx(Core.tone(190.0, 0.09, "noise", 0.22), -14.0)
	# a closed gate is a target: hold the line or break through
	if _gate_reach(u):
		_damage_gate(1 - u.team, dmg * 0.55)
	var fwd := Vector3(sin(u.yaw), 0, cos(u.yaw))
	for o: Unit in units:
		if o == u or not o.alive or o.team == u.team:
			continue
		var d := o.pos - u.pos
		d.y = 0.0
		if d.length() > rng:
			continue
		if fwd.dot(d.normalized()) < -0.35:
			continue
		o.take_damage(dmg, u.pos, force_drop)
	# dummies take hits too
	for dm in dummies:
		var dd: Vector3 = dm["pos"] - u.pos
		dd.y = 0.0
		if dd.length() < rng + 0.4:
			dm["hp"] -= dmg
			_spawn_hit_fx(dm["pos"] + Vector3(0, 1.2, 0), dmg, 1, u.pos - dm["pos"])
			if dm["hp"] <= 0.0:
				dm["node"].visible = false
				dm["t"] = 5.0


func spawn_projectile(owner: Unit, from: Vector3, target: Vector3, kind: String) -> void:
	var y_off := 1.25 if kind == "arrow" else 1.35
	var origin := from
	origin.y = Terrain.h(origin.x, origin.z) + y_off
	var aim := target
	# never aim at your own feet: a click right next to you still fires forward
	var flat := Vector3(aim.x - origin.x, 0.0, aim.z - origin.z)
	if flat.length() < 4.0:
		var fwd := Vector3(sin(owner.yaw), 0.0, cos(owner.yaw))
		aim = origin + fwd * 9.0
		aim.y = Terrain.h(aim.x, aim.z) + 0.4
	var floor_y: float = Terrain.h(aim.x, aim.z) + 0.05
	if aim.y < floor_y:
		aim.y = floor_y
	var to := aim - origin
	var dist: float = maxf(to.length(), 1.0)
	var dir := to / dist
	var node := Node3D.new()
	world.add_child(node)
	if kind == "arrow":
		Bld.arrow_model(node)
	else:
		Bld.fireball_model(node)
	node.position = origin
	node.rotation.y = atan2(dir.x, dir.z)
	node.rotation.x = -asin(clampf(dir.y, -1.0, 1.0))
	projectiles.append({
		"node": node, "pos": origin, "prev": origin, "dir": dir, "kind": kind,
		"team": owner.team, "owner": owner, "life": 2.6,
		"speed": 34.0 if kind == "arrow" else 17.0,
		"dmg": (24.0 if kind == "arrow" else 32.0) * owner.damage_scale(),
		"trail": 0.0, "left": dist, "range": 34.0 if kind == "arrow" else 24.0,
	})
	play_sfx(Core.tone(880.0, 0.07, "tri", 0.16, 1400.0) if kind == "arrow"
		else Core.tone(180.0, 0.22, "noise", 0.18, 90.0), -18.0)


## Anything the shot runs into: sparks, a puff, and the projectile is gone.
func _impact_projectile(p: Dictionary, at: Vector3) -> void:
	var kind: String = p["kind"]
	for i in 5:
		var n := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.10
		n.mesh = sm
		n.material_override = Core.mat(Color("ffd9a0") if kind == "arrow" else Color("ff7a33"), 0.5, 0.0, 1.2)
		n.position = at
		world.add_child(n)
		fx.append({"node": n, "vel": Vector3(randf_range(-1.6, 1.6), randf_range(0.4, 2.0), randf_range(-1.6, 1.6)),
			"life": 0.32, "spin": 4.0, "fade": true})
	play_sfx(Core.tone(300.0, 0.10, "noise", 0.14, 120.0), -20.0)


## Swept 2D segment vs the world's solid rectangles, height-aware, so a shot into
## a wall stops at the wall instead of passing through it.
func _segment_hits_solid(a: Vector3, b: Vector3) -> bool:
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	var box := Rect2(lo, hi - lo)
	for s in solids:
		var rr: Rect2 = s["r"]
		if not rr.intersects(box):
			continue
		var top: float = float(s["top"])
		for i in 5:
			var t := float(i) / 4.0
			var q := a.lerp(b, t)
			if q.y <= top and rr.has_point(Vector2(q.x, q.z)):
				return true
	# trees: a trunk stops a shot even though nothing blocks walking through it
	for tr in Bld.trunks:
		var tp: Vector3 = tr["p"]
		if not box.grow(float(tr["r"])).has_point(Vector2(tp.x, tp.z)):
			continue
		var top2: float = float(tr["top"])
		for i in 5:
			var t2 := float(i) / 4.0
			var q2 := a.lerp(b, t2)
			if q2.y > top2:
				continue
			var d2 := Vector2(q2.x - tp.x, q2.z - tp.z).length()
			if d2 <= float(tr["r"]):
				return true
	return false



## Swept hit test: a fast projectile moves most of a unit per frame, so the
## segment it travelled is checked, not just the point it stopped at.
func _projectile_hit_test(p: Dictionary, target_pos: Vector3, radius: float) -> bool:
	var a := Vector2(p["prev"].x, p["prev"].z)
	var b := Vector2(p["pos"].x, p["pos"].z)
	var t := Vector2(target_pos.x, target_pos.z)
	var closest := Geometry2D.get_closest_point_to_segment(t, a, b)
	return closest.distance_to(t) <= radius


func _update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var node: Node3D = p["node"]
		if not is_instance_valid(node):
			projectiles.remove_at(i)
			continue
		p["life"] = float(p["life"]) - dt
		var dir: Vector3 = p["dir"]
		var step: float = float(p["speed"]) * dt
		p["prev"] = p["pos"]
		var nxt: Vector3 = (p["pos"] as Vector3) + dir * step
		p["left"] = float(p["left"]) - step
		p["pos"] = nxt
		node.position = nxt
		node.rotation.y = atan2(dir.x, dir.z)
		node.rotation.x = -asin(clampf(dir.y, -1.0, 1.0))

		# trail: an arrow at play zoom is a couple of pixels without it
		p["trail"] = float(p["trail"]) - dt
		if float(p["trail"]) <= 0.0:
			p["trail"] = 0.03 if p["kind"] == "arrow" else 0.055
			_spawn_projectile_trail(nxt, p["kind"])

		# 1. the ground wins first: a shot into open field lands where it lands
		var gh: float = Terrain.h(nxt.x, nxt.z)
		if nxt.y <= gh + 0.05:
			_impact_projectile(p, Vector3(nxt.x, gh + 0.05, nxt.z))
			node.queue_free()
			projectiles.remove_at(i)
			continue
		# 2. walls, gates and towers
		if _segment_hits_solid(p["prev"], nxt):
			_impact_projectile(p, nxt)
			node.queue_free()
			projectiles.remove_at(i)
			continue
		# 3. people: the shot flies at the height it was aimed at
		var dead := false
		for o: Unit in units:
			if not o.alive or o.team == p["team"]:
				continue
			if absf(nxt.y - (o.position.y + 1.10)) > 1.2:
				continue
			if _projectile_hit_test(p, o.pos, 0.75):
				o.take_damage(p["dmg"], nxt - dir, false)
				if p["kind"] == "fire":
					_splash(nxt, p["team"], 2.6, 16.0)
					play_sfx(Core.tone(120.0, 0.30, "noise", 0.28, 60.0), -12.0)
				_impact_projectile(p, nxt)
				dead = true
				break
		if not dead:
			for dm in dummies:
				if not dm["node"].visible:
					continue
				if _projectile_hit_test(p, dm["pos"] + Vector3(0, 1.0, 0), 0.85):
					dm["hp"] -= p["dmg"]
					_spawn_hit_fx(dm["pos"] + Vector3(0, 1.3, 0), p["dmg"], p["team"], dir)
					if dm["hp"] <= 0.0:
						dm["node"].visible = false
						dm["t"] = 5.0
					_impact_projectile(p, nxt)
					dead = true
					break
		# 4. out of reach
		if not dead and (float(p["left"]) <= 0.0 or float(p["life"]) <= 0.0):
			_impact_projectile(p, nxt)
			dead = true
		if dead:
			node.queue_free()
			projectiles.remove_at(i)



func _spawn_projectile_trail(at: Vector3, kind: String) -> void:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var fire := kind == "fire"
	sm.radius = 0.13 if fire else 0.075
	sm.height = (0.20 if fire else 0.10)
	sm.radial_segments = 6
	sm.rings = 3
	n.mesh = sm
	n.material_override = Core.mat(Color("ff8a2d") if fire else Color("ffe9b0"), 0.5, 0.0, 2.0)
	n.position = at
	world.add_child(n)
	fx.append({"node": n, "vel": Vector3(0, 0.5 if fire else 0.0, 0), "life": 0.26 if fire else 0.16,
		"spin": 0.0, "fade": true})


func _splash(at: Vector3, team: int, rng: float, dmg: float) -> void:
	for o: Unit in units:
		if not o.alive or o.team == team:
			continue
		if o.pos.distance_to(at) < rng:
			o.take_damage(dmg, at, false)


func spawn_hit_fx(at: Vector3, amount: float, team: int, dir: Vector3) -> void:
	_spawn_hit_fx(at, amount, team, dir)


func _spawn_hit_fx(at: Vector3, amount: float, team: int, dir: Vector3) -> void:
	if amount > 1.0:
		play_sfx(Core.tone(150.0, 0.10, "square", 0.20), -15.0)
	var col := Core.RED_LIGHT if team == 0 else Core.BLUE_LIGHT
	for i in 5:
		var n := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.08, 0.18)
		bm.size = Vector3(s, s, s)
		n.mesh = bm
		n.material_override = Core.mat(Color("c22a2a") if randf() < 0.6 else col, 0.7)
		n.position = at
		world.add_child(n)
		var v := Vector3(randf_range(-3, 3), randf_range(2.5, 5.5), randf_range(-3, 3))
		v += dir.normalized() * 1.5
		fx.append({"node": n, "vel": v, "life": randf_range(0.35, 0.6), "spin": randf_range(-8, 8)})
	if amount > 1.0:
		var l := Core.label3d(world, str(int(amount)), at + Vector3(0, 0.5, 0), 60,
			Color("ffd766") if team == 0 else Color("a8c4ff"))
		l.no_depth_test = true
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		fx.append({"node": l, "vel": Vector3(randf_range(-0.6, 0.6), 2.4, 0), "life": 0.85, "spin": 0.0, "fade": true})


func _spawn_feed_fx(at: Vector3) -> void:
	for i in 9:
		var n := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.12, 0.12)
		n.mesh = bm
		n.material_override = Core.mat(Core.FROST if i % 2 == 0 else Core.CAKE, 0.6)
		n.position = at + Vector3(randf_range(-0.5, 0.5), 1.2, randf_range(-0.5, 0.5))
		world.add_child(n)
		fx.append({"node": n, "vel": Vector3(randf_range(-2, 2), randf_range(3, 5.5), randf_range(-2, 2)),
			"life": 0.7, "spin": randf_range(-6, 6)})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f["life"] -= dt
		var n = f["node"]
		if not is_instance_valid(n):
			fx.remove_at(i)
			continue
		f["vel"] = f["vel"] + Vector3(0, -14.0 * dt, 0)
		n.position = n.position + f["vel"] * dt
		if n is Node3D and not (n is Label3D):
			n.rotation.y += f["spin"] * dt
		if f.get("fade", false):
			if n is Label3D:
				n.modulate.a = clampf(f["life"] / 0.85, 0.0, 1.0)
			elif n is Node3D:
				n.scale = Vector3.ONE * clampf(f["life"] * 2.2, 0.05, 1.0)
		if f["life"] <= 0.0:
			n.queue_free()
			fx.remove_at(i)
	for dm in dummies:
		if not dm["node"].visible:
			dm["t"] -= dt
			if dm["t"] <= 0.0:
				dm["node"].visible = true
				dm["hp"] = 60.0


func add_shake(a: float) -> void:
	shake = minf(shake + a, 0.35)


# ================================================================ cake throwing
## A slice leaves the thrower's hand, arcs across, and only counts when it lands
## on her — the weight step, the chew and the growth all key off the impact.
func throw_cake(feeder: Unit, pr: Princess) -> void:
	if pr == null or not is_instance_valid(pr):
		return
	var from := feeder.pos + Vector3(0, 1.30, 0) + Vector3(sin(feeder.yaw), 0, cos(feeder.yaw)) * 0.35
	var node := Node3D.new()
	world.add_child(node)
	Core.box(node, Vector3(0.55, 0.42, 0.40), Vector3.ZERO, Core.CAKE, Vector3.ZERO, 0.6)
	Core.box(node, Vector3(0.58, 0.12, 0.43), Vector3(0, 0.25, 0), Core.FROST, Vector3.ZERO, 0.45)
	Core.sphere(node, 0.11, Vector3(0, 0.37, 0), Core.CHERRY, 1.0, 8, 0.4)
	# faint glow so a slice in flight is unmissable
	var halo := Core.sphere(node, 0.42, Vector3.ZERO, Core.FROST, 1.0, 8, 0.3)
	var hm := Core.mat(Core.FROST, 0.5, 0.0, 0.6)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color.a = 0.18
	halo.material_override = hm
	node.position = from
	node.scale = Vector3(0.8, 0.8, 0.8)
	feeder.swing = 0.9
	feeder.attack_cd = maxf(feeder.attack_cd, 0.3)
	throws.append({
		"node": node, "from": from, "t": 0.0, "dur": 0.55,
		"pr": pr, "feeder": feeder, "spin": randf_range(-8.0, 8.0), "trail": 0.0,
	})
	play_sfx(Core.tone(300.0, 0.14, "tri", 0.22, 520.0), -15.0)


func _update_throws(dt: float) -> void:
	for i in range(throws.size() - 1, -1, -1):
		var th: Dictionary = throws[i]
		var node: Node3D = th["node"]
		var pr: Princess = th["pr"]
		if not is_instance_valid(node):
			throws.remove_at(i)
			continue
		if pr == null or not is_instance_valid(pr):
			node.queue_free()
			throws.remove_at(i)
			continue
		th["t"] += dt
		var k: float = clampf(th["t"] / th["dur"], 0.0, 1.0)
		var to: Vector3 = pr.position + Vector3(0, 1.55, 0)
		var p: Vector3 = th["from"].lerp(to, k)
		p.y += sin(k * PI) * 0.7
		node.position = p
		node.rotation.x += dt * th["spin"]
		node.rotation.y += dt * 5.0
		node.scale = Vector3.ONE * lerpf(0.8, 1.0, k)
		# trail puffs: a 0.55-unit slice is a few pixels at play zoom, the trail is not
		th["trail"] -= dt
		if th["trail"] <= 0.0:
			th["trail"] = 0.05
			var puff := MeshInstance3D.new()
			var pm := SphereMesh.new()
			pm.radius = 0.11
			pm.height = 0.16
			puff.mesh = pm
			puff.material_override = Core.mat(Core.FROST, 0.5, 0.0, 0.9)
			puff.position = p
			world.add_child(puff)
			fx.append({"node": puff, "vel": Vector3.ZERO, "life": 0.28, "spin": 0.0, "fade": true})
		if k >= 1.0:
			_land_cake(pr, th["feeder"])
			node.queue_free()
			throws.remove_at(i)


func _land_cake(pr: Princess, feeder: Unit) -> void:
	var before := pr.weight
	pr.eat(1.0)
	_spawn_feed_fx(pr.position + Vector3(0, 1.1, 0))
	play_sfx(Core.tone(520.0, 0.18, "tri", 0.30, 820.0), -10.0)
	play_sfx(Core.tone(180.0, 0.10, "noise", 0.18), -18.0)
	add_shake(0.04)
	if feeder == player:
		ui.toast("fed her: weight %d / %d" % [int(pr.weight), int(pr.max_weight)])
	# "+1 WEIGHT" pops off her head so the growth step is unmistakable
	var l := Core.label3d(world, "+1", pr.position + Vector3(0.75, 1.9 + 0.09 * pr.weight, 0.2), 64, Core.GOLD)
	l.no_depth_test = true
	l.outline_size = 12
	fx.append({"node": l, "vel": Vector3(0, 2.2, 0), "life": 0.9, "spin": 0.0, "fade": true})
	if int(pr.weight) >= 6 and before < 6.0:
		ui.flash_banner("SHE IS GETTING HEAVY", Color("f6b8cf"), 1.6)


# ================================================================ team synergy
## Nothing here is required to play: every one of these is a multiplier a team
## earns by using its classes properly, and a solo player just goes without.
func class_upgraded(team: int, cls: String) -> bool:
	if team < 0 or team >= castles.size():
		return false
	var upg: Dictionary = castles[team].get("upg", {})
	return bool(upg.get(cls, false))


## True when the unit is standing on a wall walk or a bridge deck, i.e. above
## the battlefield — archers and mages shoot down with a damage bonus.
func on_wall(p: Vector3) -> bool:
	return Terrain.h(p.x, p.z) > Bld.WALK_H - 0.5


## Shield wall: a warrior standing among allies soaks part of the damage.
func incoming_scale(u: Unit) -> float:
	var s := 1.0
	for o: Unit in units:
		if o == u or not o.alive or o.team != u.team or o.cls != "warrior":
			continue
		if o.pos.distance_to(u.pos) < 5.0:
			s *= 0.82
			break
	if u.cls == "worker":
		s *= 1.12                        # no shield, no armour, no luck
	return s


## Workers deliver 3 wood + 3 ore to a station to upgrade that class for the
## whole team.
func _update_stations(dt: float) -> void:
	for u: Unit in units:
		if not u.alive or u.cls != "worker" or u.wood < 3 or u.metal < 3:
			continue
		var upg: Dictionary = castles[u.team].get("upg", {})
		for h in hats:
			if int(h["team"]) != u.team or bool(upg.get(String(h["cls"]), false)):
				continue
			if u.pos.distance_to(h["pos"]) > 2.6:
				continue
			u.wood -= 3
			u.metal -= 3
			upg[String(h["cls"])] = true
			castles[u.team]["upg"] = upg
			_mark_station(h)
			play_sfx(Core.tone(520.0, 0.25, "tri", 0.3, 880.0), -8.0)
			ui.toast("%s station upgraded — the whole team hits harder" % Unit.NAMES[h["cls"]].to_upper())
			return


func _mark_station(h: Dictionary) -> void:
	var node: Node3D = h.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	var star := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.26
	sm.height = 0.5
	star.mesh = sm
	star.material_override = Core.mat(Core.GOLD, 0.4, 0.2, 1.4)
	star.position = Vector3(0, 2.35, 0)
	node.add_child(star)
	fx.append({"node": star, "vel": Vector3(0, 0.6, 0), "life": 1.0, "spin": 2.0, "fade": true})


# ================================================================ siege
## The gate is a door with hit points. Anyone on the other side can break it;
## a worker with materials can put it back up.
func _damage_gate(team: int, dmg: float) -> void:
	var g: Dictionary = gates[team]
	if not g["alive"]:
		return
	g["hp"] = maxf(0.0, float(g["hp"]) - dmg)
	g["last_hit"] = Time.get_ticks_msec() / 1000.0
	if g["hp"] <= 0.0:
		g["alive"] = false
		_break_gate_solid(g)
		var node: Node3D = g["node"]
		if is_instance_valid(node):
			node.visible = false
		play_sfx(Core.tone(90.0, 0.7, "noise", 0.35, 45.0), -6.0)
		add_shake(0.18)
		ui.flash_banner("%s GATE IS DOWN" % ("RED" if team == 0 else "BLUE"), Color("f2a03d"), 2.0)


func _break_gate_solid(g: Dictionary) -> void:
	var tag: String = g["solid"]
	for i in range(solids.size() - 1, -1, -1):
		if String(solids[i].get("tag", "")) == tag:
			solids.remove_at(i)


func _restore_gate_solid(g: Dictionary) -> void:
	var tag: String = g["solid"]
	for i in solids.size():
		if String(solids[i].get("tag", "")) == tag:
			return
	solids.append({"r": g["rect"], "top": Terrain.PLATEAU_H + 4.3, "tag": tag})


func _update_gates(dt: float) -> void:
	# door swing animation on the cage, per castle
	for t in 2:
		var c: Dictionary = castles[t]
		var door = c.get("cage_door", null)
		if door == null or not is_instance_valid(door):
			continue
		var want: float = 0.0
		var pr: Princess = red_princess if t == 1 else blue_princess
		if pr != null and not pr.locked:
			want = 1.0
		c["door_t"] = move_toward(float(c.get("door_t", 0.0)), want, dt * 2.2)
		door.rotation_degrees.y = lerpf(0.0, 105.0 * (1.0 if t == 0 else -1.0), c["door_t"])

	for g in gates:
		var team: int = g["team"]
		if not g["alive"]:
			# workers can rebuild, but only back to a solid door above 40%
			if float(g["hp"]) >= float(g["max"]) * 0.4:
				g["alive"] = true
				_restore_gate_solid(g)
				var node: Node3D = g["node"]
				if is_instance_valid(node):
					node.visible = true
		var node2: Node3D = g["node"]
		if is_instance_valid(node2) and g["alive"]:
			# a damaged gate visibly sags and darkens
			var f: float = clampf(float(g["hp"]) / float(g["max"]), 0.0, 1.0)
			node2.rotation_degrees.x = (1.0 - f) * 7.0
			node2.scale = Vector3(1.0, lerpf(0.86, 1.0, f), 1.0)

	# workers repair their own gate with what they carry
	for u: Unit in units:
		if not u.alive or u.cls != "worker":
			continue
		var g2: Dictionary = gates[u.team]
		if bool(g2.get("sealed", false)):
			continue
		if u.pos.distance_to(g2["pos"]) > 3.4:
			continue
		if float(g2["hp"]) >= float(g2["max"]) or (u.wood + u.metal) <= 0:
			continue
		# you cannot nail planks onto a door somebody is breaking down
		if Time.get_ticks_msec() / 1000.0 - float(g2.get("last_hit", -99.0)) < 2.5:
			continue
		u.attack_cd = maxf(u.attack_cd, 0.4)
		u.repair_t -= dt
		if u.repair_t <= 0.0:
			u.repair_t = 0.6
			if u.wood > 0:
				u.wood -= 1
			else:
				u.metal -= 1
			g2["hp"] = minf(float(g2["max"]), float(g2["hp"]) + 110.0)
			_spawn_hammer_fx(g2["pos"] + Vector3(0, 1.2, 0))
			if u == player:
				ui.toast("repairing the gate — %d%%" % int(100.0 * float(g2["hp"]) / float(g2["max"])))


func _spawn_hammer_fx(at: Vector3) -> void:
	var n := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.16)
	n.mesh = bm
	n.material_override = Core.mat(Color("ffd166"), 0.5, 0.0, 1.6)
	n.position = at + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	world.add_child(n)
	fx.append({"node": n, "vel": Vector3(0, 1.6, 0), "life": 0.3, "spin": 6.0, "fade": true})
	play_sfx(Core.tone(420.0, 0.07, "square", 0.12), -18.0)


func _gate_reach(u: Unit) -> bool:
	var g: Dictionary = gates[1 - u.team]
	if not g["alive"]:
		return false
	return u.pos.distance_to(g["pos"]) < 3.4


# ================================================================ keys and cages
## Where the enemy key is, when it is not sitting on its shrine — the UI draws a
## marker for it on the minimap and an arrow at the screen edge.
func key_hint_target() -> Variant:
	if player == null or not is_instance_valid(player):
		return null
	for k in keys:
		if int(k["team"]) == 1 - player.team:
			var on_shrine: bool = not bool(k.get("dropped", false)) and k["taken"] == -1 and (k["pos"] as Vector3).distance_to(k["home"]) < 0.5
			if on_shrine:
				return null
			return Vector3(k["pos"].x, Terrain.h(k["pos"].x, k["pos"].z) + 1.6, k["pos"].z)
	return null


func _nearest_key(p: Vector3, rng: float) -> Dictionary:
	var best := {}
	var bd := rng
	for k in keys:
		if k["taken"] != -1:
			continue
		var d: float = p.distance_to(Vector3(k["pos"].x, 0.0, k["pos"].z))
		if d < bd:
			bd = d
			best = k
	return best


func _take_key(u: Unit, k: Dictionary) -> void:
	if k.is_empty():
		return
	k["taken"] = u.get_instance_id()
	k["dropped"] = false
	k["t"] = 0.0
	u.has_key = true
	u.key_team = int(k["team"])
	var node: Node3D = k["node"]
	if is_instance_valid(node):
		node.visible = false
	_attach_carried_key(u)
	play_sfx(Core.tone(760.0, 0.16, "tri", 0.28, 1140.0), -10.0)
	if u == player:
		ui.toast("the %s key — walk it to their cage, or E to put it down" % ("red" if k["team"] == 0 else "blue"))


func _attach_carried_key(u: Unit) -> void:
	if u.key_model != null and is_instance_valid(u.key_model):
		u.key_model.queue_free()
	u.key_model = Bld.key_rig(u, Vector3(0, 2.62, 0))
	u.key_model.scale = Vector3(0.85, 0.85, 0.85)


## Set the key down where you stand. It keeps for 20 s, then goes home.
func _set_key_down(u: Unit) -> void:
	if not u.has_key:
		return
	var team := u.key_team
	for k in keys:
		if int(k["team"]) != team:
			continue
		k["taken"] = -1
		k["dropped"] = true
		k["t"] = 20.0
		k["pos"] = Vector3(u.pos.x, 0.0, u.pos.z)
		var nd: Node3D = k["node"]
		if is_instance_valid(nd):
			nd.visible = true
			nd.position = Vector3(u.pos.x, Terrain.h(u.pos.x, u.pos.z) - Terrain.PLATEAU_H + 1.2, u.pos.z)
		break
	if u.key_model != null and is_instance_valid(u.key_model):
		u.key_model.queue_free()
	u.key_model = null
	u.has_key = false
	u.key_team = -1
	if u == player:
		ui.toast("key set down — it returns to the shrine in 20 s")


func _update_keys(dt: float) -> void:
	# keys float and turn so they read from a distance
	for k in keys:
		var node: Node3D = k["node"]
		if is_instance_valid(node) and k["taken"] == -1:
			node.rotation.y += dt * 1.6
			node.position.y = Terrain.h(k["pos"].x, k["pos"].z) - Terrain.PLATEAU_H + 1.42 				+ sin(Time.get_ticks_msec() * 0.004) * 0.08
	# a key left on the ground goes back to its shrine after 20 s
	for k in keys:
		if not bool(k.get("dropped", false)):
			continue
		k["t"] = float(k["t"]) - dt
		if k["t"] <= 0.0:
			k["dropped"] = false
			k["pos"] = k["home"]
			var home_node: Node3D = k["node"]
			if is_instance_valid(home_node):
				home_node.visible = true
				home_node.position = Vector3(k["home"].x, 2.42, k["home"].z)
	# auto pickup: walk into the key
	for u: Unit in units:
		if not u.alive or u.has_key:
			continue
		var near := _nearest_key(u.pos, 1.7)
		if not near.is_empty():
			_take_key(u, near)
	# a keyed unit opens the cage it belongs to
	for pr in [red_princess, blue_princess]:
		if pr == null or not is_instance_valid(pr) or not pr.locked:
			continue
		var cage_team: int = 1 - pr.team
		for u: Unit in units:
			if not u.alive or not u.has_key or u.key_team != cage_team:
				continue
			# only the raiders open a cage: freeing your own prisoner is never wanted
			if u.team == cage_team:
				continue
			if u.pos.distance_to(Vector3(pr.position.x, 0.0, pr.position.z)) < 2.9:
				pr.locked = false
				play_sfx(Core.tone(320.0, 0.3, "square", 0.25, 520.0), -8.0)
				if u == player:
					ui.toast("the cage door swings open")
				else:
					ui.toast("the enemy is opening their cage!")
				u.has_key = false
				u.key_team = -1
				# return the key to its hook after a moment
				for k in keys:
					if int(k["team"]) == cage_team:
						k["taken"] = -1
						var nd: Node3D = k["node"]
						if is_instance_valid(nd):
							nd.visible = true
				break


func _nearest_resource(p: Vector3) -> Dictionary:
	var best := {}
	var bd := 1e9
	for r in resources:
		if not r["active"]:
			continue
		var d := p.distance_to(r["pos"])
		if d < bd:
			bd = d
			best = r
	return best


func _update_resources(dt: float) -> void:
	for r in resources:
		if not r["active"]:
			r["t"] -= dt
			if r["t"] <= 0.0:
				r["active"] = true
				r["count"] = 3
				var nd: Node3D = r["node"]
				if is_instance_valid(nd):
					nd.visible = true
			continue
		for u: Unit in units:
			if not u.alive or u.cls != "worker":
				continue
			if u.pos.distance_to(r["pos"]) > 1.9:
				continue
			var kind: String = r["kind"]
			if kind == "wood" and u.wood >= 4:
				continue
			if kind == "metal" and u.metal >= 4:
				continue
			u.gather_t -= dt
			if u.gather_t > 0.0:
				continue
			u.gather_t = 0.55
			if kind == "wood":
				u.wood += 1
			else:
				u.metal += 1
			r["count"] -= 1
			_spawn_hammer_fx(Vector3(r["pos"].x, Terrain.h(r["pos"].x, r["pos"].z) + 0.7, r["pos"].z))
			if r["count"] <= 0:
				r["active"] = false
				r["t"] = 20.0
				var n2: Node3D = r["node"]
				if is_instance_valid(n2):
					n2.visible = false
			break


# ================================================================ carrying
func pick_up(pr: Princess, u: Unit) -> void:
	if pr.carried_by == u:
		return
	if pr.locked:
		if u == player:
			ui.toast("the cage is locked — the key hangs in this castle")
		return
	# exactly one carrier and one cargo, always: clear the other side first
	if u.carrying != null and u.carrying != pr:
		drop_princess(u)
	if pr.carried_by != null:
		drop_princess(pr.carried_by)
	pr.detach(Vector3.ZERO)
	pr.attach(u)
	u.carrying = pr
	play_sfx(Core.tone(680.0, 0.15, "tri", 0.28, 1000.0), -11.0)
	ui.toast("carrying — she is %s (weight %d)" % [pr.carry_speed_note().to_lower(), int(pr.weight)])
	add_shake(0.03)


func drop_princess(u: Unit) -> void:
	if u.carrying == null:
		return
	var pr := u.carrying
	u.carrying = null
	var at := u.pos + Vector3(sin(u.yaw), 0, cos(u.yaw)) * 1.3
	at.y = 0.0
	pr.detach(at)
	pr.tag.text = "DROPPED"


func drop_cake(at: Vector3, count: int, _team: int) -> void:
	if count <= 0 or cakes.size() > 26:
		return
	_add_cake_pile(Vector3(at.x, 0.0, at.z), count)


func _drop_key(u: Unit) -> void:
	if not u.has_key:
		return
	u.has_key = false
	for k in keys:
		if int(k["team"]) != u.key_team:
			continue
		k["taken"] = -1
		k["dropped"] = true
		k["t"] = 20.0
		k["pos"] = Vector3(u.pos.x, 0.0, u.pos.z)
		var nd: Node3D = k["node"]
		if is_instance_valid(nd):
			nd.visible = true
			nd.position = Vector3(u.pos.x, Terrain.h(u.pos.x, u.pos.z) + 1.1, u.pos.z)
		break
	u.key_team = -1


func _drop_hat(u: Unit) -> void:
	if u.cls == "worker" or dropped_hats.size() >= 14:
		return
	var p := Vector3(u.pos.x, Terrain.h(u.pos.x, u.pos.z), u.pos.z)
	var n := Bld.dropped_hat(world, u.cls, p)
	dropped_hats.append({"cls": u.cls, "pos": Vector3(u.pos.x, 0.0, u.pos.z), "node": n, "t": 0.0})


func on_unit_died(u: Unit) -> void:
	var delay := PLAYER_RESPAWN if u == player else (ALLY_RESPAWN if u.team == 0 else MATCH_RESPAWN)
	respawn_queue.append({"unit": u, "t": delay})
	if u == player:
		ui.flash_banner("DOWN — BACK IN %ds" % int(delay), Color("e2544a"), delay)


# ================================================================ AI
func _update_ai(dt: float) -> void:
	for u: Unit in units:
		if not u.alive or u == player:
			continue
		u.role_t -= dt
		if u.role_t <= 0.0:
			u.role_t = 0.45 + randf() * 0.2
			_think(u)


func _think(u: Unit) -> void:
	u.target_unit = null
	u.has_waypoint = false
	var enemy_team := 1 - u.team
	var enemy := _nearest_enemy(u, 999.0)
	var own_princess: Princess = red_princess if u.team == 0 else blue_princess
	var enemy_princess: Princess = blue_princess if u.team == 0 else red_princess

	# Carrying: keep walking to the goal.
	if u.carrying != null:
		var pr := u.carrying
		if pr.team == u.team:
			u.waypoint = castles[u.team]["throne"]
		else:
			u.waypoint = castles[u.team]["dungeon"]
		u.has_waypoint = true
		# drop her off if we are already inside the right zone
		var zone: Vector3 = u.waypoint
		if u.pos.distance_to(zone) < 2.6:
			drop_princess(u)
		return

	# The enemy princess is sitting on their throne, being held: kidnap her back.
	# This is the only defence that matters once a hold starts.
	if enemy_princess != null and enemy_princess.carried_by == null 			and enemy_princess.position.distance_to(castles[enemy_team]["throne"]) < 3.6:
		if u.pos.distance_to(enemy_princess.position) < 2.4:
			pick_up(enemy_princess, u)
			return
		u.waypoint = enemy_princess.position
		u.has_waypoint = true
		if enemy != null and u.pos.distance_to(enemy.pos) < 3.5:
			u.target_unit = enemy
		return

	# A closed gate blocks the way in: everybody who wants inside hits it.
	var eg: Dictionary = gates[1 - u.team]
	if not eg.is_empty() and eg["alive"] and _gate_reach(u):
		u.waypoint = eg["pos"]
		u.has_waypoint = true
		if u.brain != "worker":
			return

	# Someone is stealing a princess we care about: fight them.
	for pr in [own_princess, enemy_princess]:
		if pr != null and pr.carried_by != null and pr.carried_by.team != u.team:
			u.target_unit = pr.carried_by
			return

	if u.brain == "feeder" and enemy_princess != null and enemy_princess.carried_by == null:
		if u.cake <= 0:
			var pile := _nearest_cake(u.pos)
			if pile.size() > 0:
				u.waypoint = pile["pos"]
				u.has_waypoint = true
				return
		if enemy_princess.weight >= 6.0:
			u.waypoint = _gate_out(u.team)
			u.has_waypoint = true
			return
		if u.pos.distance_to(enemy_princess.position) < 3.0:
			if u.attack_cd <= 0.0:
				u.attack_cd = 1.3
				u.cake -= 1
				throw_cake(u, enemy_princess)
			return
		u.waypoint = enemy_princess.position
		u.has_waypoint = true
		return

	if u.brain == "rescuer" and own_princess != null and own_princess.locked:
		var cage_team: int = 1 - u.team
		if u.has_key and u.key_team == cage_team:
			u.waypoint = Vector3(own_princess.position.x, 0.0, own_princess.position.z)
			u.has_waypoint = true
			return
		var kk: Dictionary = keys[cage_team]
		if kk["taken"] == -1:
			u.waypoint = kk["pos"]
			u.has_waypoint = true
			return

	if u.brain == "rescuer" and own_princess != null and own_princess.carried_by == null:
		# already at her own throne: stand guard, never pick her up again
		if own_princess.position.distance_to(castles[u.team]["throne"]) < 3.6:
			u.waypoint = own_princess.position
			u.has_waypoint = true
			if enemy != null and u.pos.distance_to(enemy.pos) < 9.0:
				u.target_unit = enemy
			return
		if u.pos.distance_to(own_princess.position) < 2.4:
			pick_up(own_princess, u)
			return
		u.waypoint = own_princess.position
		u.has_waypoint = true
		return

	if u.brain == "worker":
		var g: Dictionary = gates[u.team]
		if float(g["hp"]) < float(g["max"]) * 0.8:
			if u.wood + u.metal <= 0:
				var res := _nearest_resource(u.pos)
				if not res.is_empty():
					u.waypoint = res["pos"]
					u.has_waypoint = true
					return
			u.waypoint = g["pos"]
			u.has_waypoint = true
			return
		if u.wood + u.metal < 6:
			var res2 := _nearest_resource(u.pos)
			if not res2.is_empty():
				u.waypoint = res2["pos"]
				u.has_waypoint = true
				return
		u.waypoint = g["pos"]
		u.has_waypoint = true
		return

	if u.brain == "ally" and player != null and is_instance_valid(player) and player.alive and player.carrying != null:
		u.waypoint = player.pos
		u.has_waypoint = true
		if enemy != null and u.pos.distance_to(enemy.pos) < 5.0:
			u.target_unit = enemy
		return

	var engage: float = 16.0 if u.brain == "attacker" else 5.0
	if enemy != null and u.pos.distance_to(enemy.pos) < engage:
		u.target_unit = enemy
		return

	# default: push toward the enemy castle
	u.waypoint = _gate_in(enemy_team)
	u.has_waypoint = true
	if enemy != null:
		u.target_unit = enemy


func _nearest_enemy(u: Unit, rng: float) -> Unit:
	var best: Unit = null
	var bd := rng
	for o: Unit in units:
		if o == u or not o.alive or o.team == u.team:
			continue
		var d := o.pos.distance_to(u.pos)
		if d < bd:
			bd = d
			best = o
	return best


func _nearest_cake(p: Vector3) -> Dictionary:
	var best := {}
	var bd := 999.0
	for c in cakes:
		if not c["active"]:
			continue
		var d := p.distance_to(c["pos"])
		if d < bd:
			bd = d
			best = c
	return best


func _ai_dir(u: Unit, dt: float) -> Vector3:
	var goal := u.pos
	var chasing := false
	if u.target_unit != null and is_instance_valid(u.target_unit) and u.target_unit.alive:
		goal = u.target_unit.pos
		chasing = true
		var d := u.pos.distance_to(goal)
		if d < 1.7:
			return Vector3.ZERO
	elif u.has_waypoint:
		goal = u.waypoint
	else:
		return Vector3.ZERO

	var flat := Vector3(goal.x - u.pos.x, 0.0, goal.z - u.pos.z)
	if flat.length() < 0.5:
		u.has_waypoint = false      # arrived: let the brain pick the next job
		return Vector3.ZERO

	# A goal inside a wall (or on top of one) is not something to walk into:
	# resolve it to the closest cell at the unit's own level first. This is what
	# kept a handful of soldiers leaning on a castle wall for the whole match.
	if true:
		var reach_cell: int = Nav.snap_for(goal, Terrain.h(u.pos.x, u.pos.z))
		if reach_cell >= 0:
			var near := Nav.centre(reach_cell)
			if near.distance_to(goal) < 7.0 and near.distance_to(u.pos) > 0.35:
				goal = near
				if not chasing:
					u.waypoint = near    # stop re-targeting the unreachable point

	u.path_t -= dt
	# replan when the path is empty, the goal moved, or the cooldown lapsed
	var stale: bool = u.path.is_empty() or u.path_i >= u.path.size()
	var moved: bool = u.path_goal.distance_to(goal) > 4.0
	var goal_cell: int = Nav.cell_of(goal)
	# A chase moves its goal every frame, but if it is still in the same nav cell
	# the path is still right: replanning on "moved" alone was the remaining cost.
	var same_cell: bool = goal_cell == u.path_goal_cell and not u.path.is_empty() and u.path_i < u.path.size()
	if u.path_t <= 0.0 and not same_cell and (stale or moved):
		if nav_budget > 0:
			nav_budget -= 1
			u.path = Nav.find_path(u.pos, goal)
			if u.path.is_empty():
				# the goal is inside a wall or a solid footprint: walk to the
				# nearest cell that can actually be reached instead of pressing
				# into the brickwork forever
				var cell: int = Nav.snap_for(goal, Terrain.h(u.pos.x, u.pos.z))
				if cell >= 0:
					u.path = Nav.find_path(u.pos, Nav.centre(cell))
			u.path_i = 0
			u.path_goal = goal
			u.path_goal_cell = goal_cell
			# a failed search is expensive and won't improve next frame: wait longer
			u.path_t = (1.2 + randf() * 0.8) if Nav.last_found else (2.5 + randf() * 1.5)
			if perf and Nav.last_expansions > 1500:
				print("[HF] NAV heavy: %d expansions found=%s" % [Nav.last_expansions, str(Nav.last_found)])
		else:
			# over budget this frame: keep walking the old path, try again shortly
			u.path_t = 0.05 + randf() * 0.1
			if u.path.is_empty():
				return flat.normalized()
		if u.path.is_empty() and not Nav.built:
			return flat.normalized()        # nav unavailable: straight line fallback

	# no progress for a while (empty path or an unreachable tail): drop the goal
	# so the brain picks a new one instead of leaning on a wall forever
	if u.stuck_t > 2.4 or (u.path.is_empty() and u.stuck_t > 1.2):
		u.has_waypoint = false
		u.stuck_t = 0.0
		u.path_t = 0.0
		return Vector3.ZERO

	var target := goal
	while u.path_i < u.path.size():
		var wp: Vector3 = u.path[u.path_i]
		if u.pos.distance_to(wp) < 0.75:
			u.path_i += 1
			continue
		target = wp
		break
	if u.path_i >= u.path.size():
		target = goal

	# A target standing on the keep ledge is 2.15 m up and there is no route to
	# it, so a chaser used to press into the platform for the rest of the match.
	# Hold at standoff range instead: still a threat, no longer a pile of bodies
	# jammed against a wall.
	if u.target_unit != null and is_instance_valid(u.target_unit):
		var th: float = Terrain.h(u.target_unit.pos.x, u.target_unit.pos.z)
		var uh: float = Terrain.h(u.pos.x, u.pos.z)
		if absf(th - uh) > Terrain.STEP_UP:
			var gap: float = u.pos.distance_to(u.target_unit.pos)
			if gap < 3.2:
				return Vector3.ZERO
			var away := Vector3(u.pos.x - u.target_unit.pos.x, 0.0, u.pos.z - u.target_unit.pos.z)
			if away.length() > 0.01:
				return away.normalized()      # back off to firing range

	var d2 := Vector3(target.x - u.pos.x, 0.0, target.z - u.pos.z)
	if d2.length() < 0.15:
		return Vector3.ZERO
	var dir := d2.normalized()
	if chasing and u.pos.distance_to(goal) < 2.0:
		dir = Vector3(goal.x - u.pos.x, 0.0, goal.z - u.pos.z).normalized()

	# last resort when wedged against another body: sidestep once
	if u.stuck_t > 1.2:
		u.stuck_t = 0.0
		u.path_t = 0.0
		dir = (dir + Vector3(-dir.z, 0.0, dir.x) * (1.0 if randf() < 0.5 else -1.0)).normalized()
	return dir


## Sends the unit through the castle gate instead of into a wall.
## Two states only: in a castle, or on the field. If the goal is in another
## region, walk to the gate point that crosses the wall.
func _inside(team: int, p: Vector3) -> bool:
	return p.x < -Bld.GATE_ABS if team == 0 else p.x > Bld.GATE_ABS


func _castle_of(p: Vector3) -> int:
	if _inside(0, p):
		return 0
	if _inside(1, p):
		return 1
	return -1


func _flip(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func _gate_out(team: int) -> Vector3:
	return Bld.wpt(_flip(team), Bld.GATE_X - 2.0, 0.0)


func _gate_in(team: int) -> Vector3:
	return Bld.wpt(_flip(team), Bld.GATE_X + 2.5, 0.0)


func _route(u: Unit, goal: Vector3) -> Vector3:
	var cur := _castle_of(u.pos)
	var dest := _castle_of(goal)
	var base := goal
	if dest == cur:
		base = goal
	elif cur != -1:
		base = _gate_out(cur)
	elif dest != -1:
		base = _gate_in(dest)
	# the river only has three crossings, so route through one of them
	if Terrain.needs_bridge(u.pos, base):
		return Terrain.bridge_step(u.pos, base)
	return base


func _auto_attack(u: Unit, aim: Vector3) -> void:
	# a closed gate is a target even with nobody in sight
	var g: Dictionary = gates[1 - u.team]
	if not g.is_empty() and g["alive"] and _gate_reach(u) and u.brain != "worker":
		u.attack(g["pos"])
		return
	if u.target_unit == null or not is_instance_valid(u.target_unit) or not u.target_unit.alive:
		return
	var d := u.pos.distance_to(u.target_unit.pos)
	var reach := 2.0
	if u.cls == "ranger":
		reach = 15.0
	elif u.cls == "mage":
		reach = 11.0
	if d <= reach:
		var shot_at: Vector3 = u.target_unit.position + Vector3(0, 1.15, 0)
		if u.cls == "ranger":
			# lead the shot: at 34 m/s an arrow takes long enough that a running
			# target would otherwise always be missed
			var travel: float = d / 34.0
			shot_at += u.target_unit.vel * travel * 0.85
		u.attack(shot_at)


# ================================================================ tutorial
func _update_tutorial(dt: float) -> void:
	if tutorial_done:
		return
	tut_progress += player.pos.distance_to(tut_last_pos) if player != null and player.alive else 0.0
	tut_last_pos = player.pos if player != null else Vector3.ZERO
	match tutorial_step:
		0:
			if tut_progress > 5.0:
				_advance_tutorial("GRAB A HAT", "Hats are classes. Walk onto one of the three hat stands beside you and press E. Warrior swings, ranger shoots, mage burns.")
		1:
			if player != null and player.cls != "worker":
				_advance_tutorial("COLLECT CAKE", "Good. Now walk over a cake pile — the pink platters. You can carry three slices at once.")
		2:
			if player != null and player.cake > 0:
				_advance_tutorial("FEED THE CAPTIVE", "Stand beside the BLUE Princess in your dungeon (the cage) and press F. Every slice makes her heavier, and a heavy princess is slow to steal back.")
		3:
			if blue_princess != null and blue_princess.weight >= 1.0:
				_advance_tutorial("PRACTISE", "Now swing at the straw dummies with SPACE or LEFT CLICK. A worker's chisel is weak — the real damage is the hat you take next.")
		4:
			for dm in dummies:
				if dm["hp"] < 60.0:
					_advance_tutorial("RESCUE HER", "The RED Princess is locked in the BLUE dungeon across the field. Walk there, stand beside her and press E.")
					return
		5:
			if player != null and player.carrying != null and player.carrying.team == 0:
				_advance_tutorial("CARRY HER HOME", "Weight %d. The heavier she is, the slower you crawl, and allied soldiers standing with you add speed. Get her to your throne." % int(player.carrying.weight))
		6:
			if player != null and player.carrying != null:
				ui.set_tutorial(7, 7, "CARRY HER HOME", "Weight %d — walk her to the throne in your castle. Then the hold begins." % int(player.carrying.weight))
			if red_princess != null and red_princess.carried_by == null and red_princess.position.distance_to(castles[0]["throne"]) < 3.6:
				tutorial_done = true
				ui.set_tutorial(7, 7, "TUTORIAL COMPLETE", "That is the whole loop: feed the captive, rescue your own, hold the throne. Press H to start the real siege.")
				ui.flash_banner("TUTORIAL COMPLETE", Color("e8b53f"), 3.0)
	tut_last_pos = player.pos if player != null else Vector3.ZERO


func _advance_tutorial(title: String, body: String) -> void:
	tutorial_step += 1
	ui.set_tutorial(tutorial_step + 1, 7, title, body)
	ui.toast("step %d done" % tutorial_step)
	add_shake(0.02)


func _skip_tutorial_step() -> void:
	if state != S_TUTORIAL:
		return
	if tutorial_done:
		start_match(false)
		return
	tutorial_step = mini(tutorial_step + 1, 6)
	ui.set_tutorial(tutorial_step + 1, 7, "STEP SKIPPED", "Move to the next objective. H skips again, or starts the real siege once training is done.")


# ================================================================ hud / camera
func _hud_data() -> Dictionary:
	var d := {
		"hp": 1.0, "cls": "worker", "cake": 0, "prompt": "", "hold_text": "", "hold_frac": 0.0,
		"hold_red": true, "objectives": "",
	}
	if player != null and is_instance_valid(player):
		d["hp"] = player.hp / maxf(player.max_hp, 1.0)
		d["cls"] = player.cls
		d["cake"] = player.cake
	d["prompt"] = _prompt_text()
	var rp := red_princess
	var bp := blue_princess
	var lines := []
	if state == S_TUTORIAL:
		lines.append("TRAINING GROUND")
		lines.append("no enemies — learn the loop")
	else:
		if hold_red > 0.05:
			d["hold_text"] = "HOLDING THE THRONE  %.1f s" % hold_red
			d["hold_frac"] = hold_red / hold_target
			d["hold_red"] = true
		elif hold_blue > 0.05:
			d["hold_text"] = "BLUE IS CROWNING — STOP THEM  %.1f s" % hold_blue
			d["hold_frac"] = hold_blue / hold_target
			d["hold_red"] = false
		else:
			d["hold_text"] = "RESCUE YOUR PRINCESS · HOLD THE THRONE %ds%s" % [
				int(hold_target), "  ·  SUDDEN DEATH" if sudden else ""]
		if bp != null:
			lines.append("BLUE PRINCESS (captive)  weight %d" % int(bp.weight))
			lines.append("  feed her cake to slow their rescue")
		if not gates.is_empty():
			var mg: Dictionary = gates[0]
			lines.append("YOUR GATE  %d%%%s" % [int(100.0 * float(mg["hp"]) / float(mg["max"])),
				"" if mg["alive"] else "  — BROKEN"])
		if net != null and net.open:
			lines.append("ONLINE  ·  %d here  ·  %d v %d" % [net.peer_count() + 1, net.score[0], net.score[1]])
		if player != null and is_instance_valid(player) and player.cls == "worker":
			lines.append("NO HAT  —  take one at a stand (E)")
			lines.append("CARRYING  wood %d   ore %d" % [player.wood, player.metal])
		if rp != null:
			if rp.carried_by == player:
				lines.append("RED PRINCESS  carried — get her to your throne")
			elif rp.carried_by != null:
				lines.append("RED PRINCESS  taken by blue!")
			elif rp.position.distance_to(castles[0]["throne"]) < 3.6:
				lines.append("RED PRINCESS  at your throne — hold!")
			else:
				lines.append("RED PRINCESS  in the blue dungeon")
	d["objectives"] = "\n".join(lines)
	return d


func _prompt_text() -> String:
	if player == null or not is_instance_valid(player) or not player.alive:
		return ""
	if player.carrying != null:
		return "E drop her   ·   she is %s" % player.carrying.carry_speed_note()
	var pr := _nearest_princess(player.pos, 3.2, true)
	if pr != null:
		if pr.team != player.team and player.cake > 0:
			return "E carry princess   ·   F feed cake (%d)" % player.cake
		if pr.team != player.team:
			return "E carry princess   ·   find cake to feed her"
		return "E carry your princess home"
	var st := _nearest_hat(player.pos, 2.6)
	if not st.is_empty():
		return "E take the %s hat" % String(st["cls"]).to_upper()
	var pile := _nearest_cake(player.pos)
	if pile.size() > 0 and player.pos.distance_to(pile["pos"]) < 4.0:
		return "walk over the cake to collect"
	return ""


func _update_interaction_label() -> void:
	if state == S_TUTORIAL and tutorial_done:
		hint_lbl.visible = true
		hint_lbl.text = "press H to start the real siege"
		hint_lbl.position = player.pos + Vector3(0, 2.9, 0)
		near_lbl.visible = false
		return
	hint_lbl.visible = false
	var pr := _nearest_princess(player.pos, 3.2, true)
	if pr != null:
		near_lbl.visible = true
		near_lbl.text = "E — CARRY"
		if pr.team != player.team:
			near_lbl.text = "E — CARRY   ·   F — FEED"
		near_lbl.position = pr.position + Vector3(0, 3.4, 0)
		return
	if player.has_key:
		near_lbl.visible = true
		near_lbl.text = "E — SET THE KEY DOWN"
		near_lbl.position = player.position + Vector3(0, 3.2, 0)
		return
	var kk := _nearest_key(player.pos, 3.0)
	if not kk.is_empty():
		near_lbl.visible = true
		near_lbl.text = "E — TAKE THE KEY"
		near_lbl.position = Vector3(kk["pos"].x, Terrain.h(kk["pos"].x, kk["pos"].z) + 2.2, kk["pos"].z)
		return
	var st := _nearest_hat(player.pos, 2.6)
	if not st.is_empty():
		near_lbl.visible = true
		near_lbl.text = "E — %s HAT" % String(st["cls"]).to_upper()
		near_lbl.position = st["pos"] + Vector3(0, 2.6, 0)
		return
	near_lbl.visible = false


## True when something solid sits between the unit and the camera.
## Terrain, wall decks and every solid rectangle are checked, so a figure in a
## courtyard is hidden by the wall it stands behind.
func _is_occluded(target: Vector3) -> bool:
	var dir := cam_dir.normalized()
	var dist := 34.0
	var start := target + dir * dist
	# terrain first, coarsely: hills are wide, walls are handled below
	for k in range(1, 18):
		var t := float(k) / 18.0
		var p: Vector3 = start.lerp(target, t)
		if Terrain.h(p.x, p.z) > p.y + 0.05:
			return true
	# solids: one pass over the rectangles that can touch this sight line. The
	# old version looped every solid inside every sample: 34 x ~200 per unit,
	# per check, twice per unit, twenty times a second.
	var lo := Vector2(minf(start.x, target.x), minf(start.z, target.z))
	var hi := Vector2(maxf(start.x, target.x), maxf(start.z, target.z))
	var box := Rect2(lo, hi - lo)
	for s in solids:
		var rr: Rect2 = s["r"]
		if not rr.intersects(box):
			continue
		var top: float = float(s["top"])
		if top < target.y - 1.2:
			continue
		for i in 6:
			var t2 := float(i) / 5.0
			var p2: Vector3 = start.lerp(target, t2)
			if p2.y < top and rr.has_point(Vector2(p2.x, p2.z)):
				return true
	return false


## A unit is outlined when something covers either its chest or its head — a
## low wall hides the legs but a real wall hides the head, and that is the case
## people actually notice.
func _unit_hidden(u: Unit) -> bool:
	if _is_occluded(u.position + Vector3(0, 2.0, 0)):
		return true
	return _is_occluded(u.position + Vector3(0, 1.1, 0))


var occ_t := 0.0


func _update_silhouettes(dt: float) -> void:
	occ_t += dt
	if occ_t < 0.10:
		return
	occ_t = 0.0
	for u: Unit in units:
		if not is_instance_valid(u):
			continue
		if not u.alive:
			u.show_silhouette(false)
			continue
		if u.position.distance_to(cam_focus) > 60.0:
			u.show_silhouette(false)
			continue
		u.show_silhouette(showsil or _unit_hidden(u))


func _maybe_fire_demo() -> void:
	if fire_at_frame < 0:
		return
	if Engine.get_process_frames() >= fire_at_frame and not fire_shot.is_empty():
		var o: Unit = fire_shot["owner"]
		if o != null and is_instance_valid(o):
			spawn_projectile(o, o.position + Vector3(0, 1.25, 0), fire_shot["target"], String(fire_shot["kind"]))
		fire_shot = {}


## Telemetry: one JSON line per unit per second. Everything that could go wrong
## (stuck, no goal, path failure, gate loitering, overlap) is derivable here, and
## tools/analyze_telemetry.py turns it into a report.
func _write_telemetry(dt: float) -> void:
	if telemetry_file == null:
		return
	telemetry_t += dt
	if telemetry_t < 1.0:
		return
	telemetry_t = 0.0
	var t := snappedf(match_time, 0.1)
	for u: Unit in units:
		if not is_instance_valid(u):
			continue
		var gh := Terrain.h(u.pos.x, u.pos.z)
		var line := {
			"t": t, "id": u.get_instance_id() % 100000, "team": u.team, "cls": u.cls,
			"brain": u.brain, "x": snappedf(u.pos.x, 0.1), "z": snappedf(u.pos.z, 0.1),
			"y": snappedf(u.position.y, 0.1), "h": snappedf(gh, 0.1),
			"alive": u.alive, "hp": int(u.hp), "vel": snappedf(u.vel.length(), 0.1),
			"wp": [snappedf(u.waypoint.x, 0.1), snappedf(u.waypoint.z, 0.1)], "has_wp": u.has_waypoint,
			"path": u.path.size(), "pi": u.path_i, "stuck": snappedf(u.stuck_t, 0.1),
			"tgt": u.target_unit != null, "carry": u.carrying != null, "key": u.has_key,
			"cake": u.cake, "in_nav": Nav.cell_of(u.pos) >= 0 and Nav.cells.size() > 0 and Nav.cells[Nav.cell_of(u.pos)] == 1,
		}
		telemetry_file.store_line(JSON.stringify(line))
	telemetry_file.flush()


func _update_camera(dt: float) -> void:
	zoom = Core.damp(zoom, zoom_target, 8.0, dt)
	camera.size = zoom
	if state == S_MENU:
		menu_t += dt * 0.10
		var focus := Vector3(0, 0, 0)
		var dir := Vector3(sin(menu_t), 0.0, cos(menu_t)) * 0.82 + Vector3(0, 0.95, 0)
		camera.position = focus + dir.normalized() * 90.0
		camera.look_at(focus)
		return
	cam_yaw = lerp_angle(cam_yaw, cam_yaw_target, 1.0 - exp(-9.0 * dt))
	cam_dir = Vector3(sin(cam_yaw) * CAM_HORIZ, CAM_HEIGHT, cos(cam_yaw) * CAM_HORIZ).normalized()
	var focus2 := cam_focus
	if player != null and is_instance_valid(player) and demo == "":
		focus2 = player.position
	if demo == "spectate":
		focus2 = Vector3.ZERO
		zoom = 128.0
		cam_focus = Vector3.ZERO
	elif demo != "":
		# demo shots own the camera: the match setup resets it otherwise
		focus2 = demo_focus
		zoom = demo_zoom
		cam_focus = demo_focus
	cam_focus = cam_focus.lerp(focus2, 1.0 - exp(-6.0 * dt))
	shake = maxf(0.0, shake - dt * 2.2)
	var off := Vector3.ZERO
	if shake > 0.0:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake
	camera.position = cam_focus + cam_dir * 90.0 + off
	camera.look_at(cam_focus + off * 0.5)


func _autoplay_actions() -> void:
	if player == null or not player.alive:
		return
	if player.carrying != null:
		if player.pos.distance_to(castles[0]["throne"]) < 2.8:
			drop_princess(player)
		return
	var pr := _nearest_princess(player.pos, 3.0, true)
	if pr != null:
		if pr.team == 0 and pr.position.distance_to(castles[0]["throne"]) > 3.6:
			pick_up(pr, player)
		elif player.cake > 0:
			player.cake -= 1
			pr.add_weight(1.0)


func _autoplay_input(dt: float) -> Vector2:
	# Simple driver for headless smoke runs: push toward the enemy dungeon.
	autoplay_t += dt
	if player == null:
		return Vector2.ZERO
	var goal: Vector3
	if player.carrying != null:
		goal = castles[0]["throne"]
	elif red_princess != null and red_princess.carried_by == null and red_princess.position.distance_to(castles[0]["throne"]) > 3.6:
		goal = red_princess.position
	elif blue_princess != null and player.cake == 0:
		goal = castles[0]["dungeon"]
	else:
		goal = blue_princess.position
	var want := _route(player, goal)
	_last_goal = goal
	_last_want = want
	var d := want - player.pos
	d.y = 0.0
	if d.length() < 0.3:
		return Vector2.ZERO
	var cam_fwd := -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	var cam_right := camera.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var n := d.normalized()
	return Vector2(n.dot(cam_right), n.dot(cam_fwd))


# ================================================================ input
func _unhandled_input(event: InputEvent) -> void:
	if state == S_MENU and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			start_match(false)
			return
		if event.keycode == KEY_T:
			start_match(true)
			return
	if event.is_action_pressed("ui_cancel"):
		if state == S_PLAY or state == S_TUTORIAL:
			_set_pause(true)
		elif state == S_PAUSE:
			_set_pause(false)
		return
	if event.is_action_pressed("help"):
		if state == S_TUTORIAL:
			_skip_tutorial_step()
		else:
			ui.help.visible = not ui.help.visible
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		ui.fps_on = not ui.fps_on
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		cam_yaw_target = fposmod(cam_yaw_target + PI * 0.5, TAU)
		ui.toast("camera turned")
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_M:
		muted = not muted
		AudioServer.set_bus_mute(0, muted)
		ui.toast("sound " + ("off" if muted else "on"))
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target - 1.8, 18.0, 44.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target + 1.8, 18.0, 44.0)


var pause_prev := S_PLAY

func _set_pause(v: bool) -> void:
	if v and (state == S_PLAY or state == S_TUTORIAL):
		pause_prev = state
		state = S_PAUSE
		ui.show_pause(true)
	elif not v and state == S_PAUSE:
		state = pause_prev
		ui.show_pause(false)
