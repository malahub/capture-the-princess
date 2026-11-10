class_name Net
extends Node
## Multiplayer client. Optional by construction: nothing here runs unless the
## player picks a side from the menu, so the solo game is untouched.
##
## The server owns identity, team balance and the snapshot clock; this client
## owns its own movement (already simulated) and sends it at 15 Hz. Peers are
## rendered as light ghosts that lerp toward their last snapshot, which hides the
## 15 Hz gap without needing prediction on remote units.

signal connected
signal failed(why: String)

const SEND_HZ := 15.0
const CLASS_INDEX := {"worker": 0, "warrior": 1, "ranger": 2, "mage": 3}

var game: Node = null
var world: Node3D = null
var socket: WebSocketPeer = null
var open := false
var my_id := 0
var my_team := 0
var room := "public"
var peers: Dictionary = {}          # id -> {node, target, yaw, cls, team, name, hp, alive, last}
var _send_t := 0.0
var _url := ""
var server_tick := 0
var score := [0, 0]
var last_error := ""


func _ready() -> void:
	set_process(false)


func default_url() -> String:
	# ?api=ws://host/ws overrides the endpoint (used by the soak harness and by
	# anyone pointing a build at a staging relay)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if typeof(q) == TYPE_STRING and String(q).find("api=") >= 0:
			var m := RegEx.new()
			m.compile("api=([^&]+)")
			var hit := m.search(String(q))
			if hit != null:
				return hit.get_string(1).uri_decode()
		return "wss://capturetheprincess-api.723studios.com/ws"
	return "ws://127.0.0.1:8080/ws"


## Join a side. team 0 = red, 1 = blue, -1 = let the server balance.
func join(team: int, name: String = "player", url: String = "") -> void:
	_url = url if url != "" else default_url()
	var q := "?room=%s&name=%s&team=%s" % [room, name.uri_encode(), "red" if team == 0 else ("blue" if team == 1 else "auto")]
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(_url + q)
	if err != OK:
		last_error = "connect failed (%d)" % err
		failed.emit(last_error)
		return
	open = false
	peers.clear()
	set_process(true)


func close() -> void:
	open = false
	set_process(false)
	if socket != null:
		socket.close()
	socket = null
	for k in peers.keys():
		var n = peers[k]["node"]
		if is_instance_valid(n):
			n.queue_free()
	peers.clear()


func _process(dt: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not open:
				open = true
				connected.emit()
			while socket.get_available_packet_count() > 0:
				_on_message(socket.get_packet().get_string_from_utf8())
			_send_t += dt
			if _send_t >= 1.0 / SEND_HZ:
				_send_t = 0.0
				_send_state()
			_lerp_peers(dt)
		WebSocketPeer.STATE_CLOSED:
			open = false
			set_process(false)


func _send_state() -> void:
	var p: Unit = game.player if game != null else null
	if p == null or not is_instance_valid(p):
		return
	var msg := {
		"t": "s", "x": snappedf(p.pos.x, 0.01), "z": snappedf(p.pos.z, 0.01),
		"y": snappedf(p.yaw, 0.01), "c": int(CLASS_INDEX.get(p.cls, 0)),
		"h": int(maxf(p.hp, 0.0)), "a": 1 if p.alive else 0,
	}
	socket.send_text(JSON.stringify(msg))


func _on_message(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match String(msg.get("t", "")):
		"welcome":
			my_id = int(msg.get("id", 0))
			my_team = int(msg.get("team", 0))
		"snap":
			server_tick = int(msg.get("k", 0))
			score[0] = int(msg.get("r", 0))
			score[1] = int(msg.get("b", 0))
			for row in msg.get("p", []):
				if typeof(row) != TYPE_ARRAY or row.size() < 8:
					continue
				var id := int(row[0])
				if id == my_id:
					continue
				_upsert_peer(id, Vector3(float(row[1]), 0.0, float(row[2])), float(row[3]),
					int(row[4]), int(row[5]), int(row[6]), int(row[7]) != 0)
		"leave":
			_drop_peer(int(msg.get("id", 0)))
		"error":
			last_error = String(msg.get("m", "server error"))
			failed.emit(last_error)


func _upsert_peer(id: int, at: Vector3, yaw: float, cls: int, team: int, hp: int, alive: bool) -> void:
	if peers.has(id):
		var e: Dictionary = peers[id]
		e["target"] = at
		e["yaw"] = yaw
		e["hp"] = hp
		e["alive"] = alive
		if int(e["cls"]) != cls:
			e["cls"] = cls
			_rebuild_visual(id)
		if is_instance_valid(e["node"]):
			e["node"].visible = alive
		return
	var node := Bld.remote_ghost(world, team, _class_name(cls))
	node.position = Vector3(at.x, Terrain.h(at.x, at.z), at.z)
	peers[id] = {"node": node, "target": at, "yaw": yaw, "cls": cls, "team": team,
		"hp": hp, "alive": alive, "name": "P%d" % id}
	var tag := node.get_node_or_null("Tag")
	if tag != null:
		tag.text = "P%d" % id


func _rebuild_visual(id: int) -> void:
	if not peers.has(id):
		return
	var e: Dictionary = peers[id]
	var at := Vector3.ZERO
	if is_instance_valid(e["node"]):
		at = e["node"].position
		e["node"].queue_free()
	var node := Bld.remote_ghost(world, int(e["team"]), _class_name(int(e["cls"])))
	node.position = at
	peers[id]["node"] = node


func _drop_peer(id: int) -> void:
	if not peers.has(id):
		return
	var n = peers[id]["node"]
	if is_instance_valid(n):
		n.queue_free()
	peers.erase(id)


func _lerp_peers(dt: float) -> void:
	var k := 1.0 - exp(-12.0 * dt)
	for id in peers.keys():
		var e: Dictionary = peers[id]
		var n = e["node"]
		if not is_instance_valid(n):
			continue
		var t: Vector3 = e["target"]
		var cur: Vector3 = n.position
		var nxt := Vector3(lerpf(cur.x, t.x, k), Terrain.h(t.x, t.z), lerpf(cur.z, t.z, k))
		n.position = nxt
		n.rotation.y = lerp_angle(n.rotation.y, float(e["yaw"]), k)


func _class_name(idx: int) -> String:
	match idx:
		1: return "warrior"
		2: return "ranger"
		3: return "mage"
		_: return "worker"


func peer_count() -> int:
	return peers.size()
