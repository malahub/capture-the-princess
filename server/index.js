// Capture The Princess — room relay.
//
// Design goals, in order: never break the solo game (this server is optional and
// the client runs without it), keep 100 players in one room responsive, and make
// joining a room feel instant.
//
// Model: clients own their own movement (they already simulate it); the server
// owns identity, team assignment, room membership and the snapshot clock. That
// is the cheapest thing that still supports 100 players at 20 Hz in a browser,
// and it means a dropped packet is a dropped position, never a rollback.
//
// Wire format is compact JSON arrays, quantised to 2 decimals: a 100-player
// snapshot is ~4 KB, so 20 Hz costs ~80 KB/s per client instead of ~400 KB/s for
// named-field objects.

const http = require("http");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");

const PORT = parseInt(process.env.PORT || "8080", 10);
const TICK_HZ = parseInt(process.env.TICK_HZ || "20", 10);
const MAX_PER_ROOM = parseInt(process.env.MAX_PER_ROOM || "100", 10);
const MAX_ROOMS = parseInt(process.env.MAX_ROOMS || "64", 10);
const ROOM_IDLE_MS = 30 * 60 * 1000;
const MAX_MSG_PER_SEC = 60;
const MAX_BUFFERED = 1 << 20;

const CLASSES = ["worker", "warrior", "ranger", "mage"];
const started = Date.now();

/** @type {Map<string, Room>} */
const rooms = new Map();
let nextPlayerId = 1;

class Room {
  constructor(id) {
    this.id = id;
    this.players = new Map(); // id -> player
    this.tick = 0;
    this.lastActivity = Date.now();
    this.score = { 0: 0, 1: 0 };
  }

  get count() {
    return this.players.size;
  }

  teamCount(team) {
    let n = 0;
    for (const p of this.players.values()) if (p.team === team) n++;
    return n;
  }

  /** Balance first, honour the request second. */
  pickTeam(requested) {
    const red = this.teamCount(0);
    const blue = this.teamCount(1);
    if (red >= MAX_PER_ROOM / 2 && blue < red) return 1;
    if (blue >= MAX_PER_ROOM / 2 && red < blue) return 0;
    if (requested === 0 || requested === 1) return requested;
    return red <= blue ? 0 : 1;
  }

  broadcast(payload, exceptId) {
    const data = typeof payload === "string" ? payload : JSON.stringify(payload);
    for (const p of this.players.values()) {
      if (p.id === exceptId) continue;
      if (p.ws.readyState !== 1) continue;
      if (p.ws.bufferedAmount > MAX_BUFFERED) continue; // slow client: drop a frame, never queue forever
      p.ws.send(data);
    }
  }

  snapshot() {
    const p = [];
    for (const pl of this.players.values()) {
      p.push([
        pl.id,
        r2(pl.x), r2(pl.z), r2(pl.yaw),
        pl.clsIdx, pl.team,
        Math.round(pl.hp), pl.alive ? 1 : 0,
      ]);
    }
    return JSON.stringify({
      t: "snap",
      k: this.tick,
      r: this.score[0],
      b: this.score[1],
      p,
    });
  }
}

const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const clamp = (n, a, b) => Math.max(a, Math.min(b, Number(n) || 0));

function getRoom(id) {
  if (rooms.has(id)) return rooms.get(id);
  if (rooms.size >= MAX_ROOMS) return null;
  const room = new Room(id);
  rooms.set(id, room);
  return room;
}

// ---------------------------------------------------------------- http
const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  const cors = {
    "access-control-allow-origin": "*",
    "cache-control": "no-store",
  };
  if (url.pathname === "/health") {
    let players = 0;
    for (const r of rooms.values()) players += r.count;
    res.writeHead(200, { ...cors, "content-type": "application/json" });
    res.end(JSON.stringify({
      ok: true,
      uptime_s: Math.round((Date.now() - started) / 1000),
      rooms: rooms.size,
      players,
      tick_hz: TICK_HZ,
      max_per_room: MAX_PER_ROOM,
    }));
    return;
  }
  if (url.pathname === "/rooms") {
    const list = [...rooms.values()]
      .filter((r) => r.count > 0)
      .map((r) => ({ id: r.id, red: r.teamCount(0), blue: r.teamCount(1), players: r.count }))
      .sort((a, b) => b.players - a.players);
    res.writeHead(200, { ...cors, "content-type": "application/json" });
    res.end(JSON.stringify({ rooms: list }));
    return;
  }
  res.writeHead(200, { ...cors, "content-type": "text/plain; charset=utf-8" });
  res.end(
    "Capture The Princess — room relay\n\n" +
      `health : /health\nrooms  : /rooms\nsocket : wss://${req.headers.host}/ws?room=<id>&name=<name>&team=red|blue\n\n` +
      `tick ${TICK_HZ} Hz · ${MAX_PER_ROOM} players per room\n`
  );
});

// ---------------------------------------------------------------- socket
const wss = new WebSocketServer({ server, path: "/ws", maxPayload: 4096 });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, "http://x");
  const roomId = (url.searchParams.get("room") || "lobby").slice(0, 32).replace(/[^\w-]/g, "") || "lobby";
  const name = (url.searchParams.get("name") || "princess").slice(0, 16);
  const wantTeam = url.searchParams.get("team") === "blue" ? 1 : url.searchParams.get("team") === "red" ? 0 : -1;

  const room = getRoom(roomId);
  if (!room) {
    ws.close(4000, "server full");
    return;
  }
  if (room.count >= MAX_PER_ROOM) {
    ws.close(4001, "room full");
    return;
  }

  const id = nextPlayerId++;
  const team = room.pickTeam(wantTeam);
  const player = {
    id, ws, name, team,
    x: team === 0 ? -30 : 30, z: 0, yaw: 0,
    clsIdx: 0, hp: 160, alive: true, cake: 0,
    msgsThisSecond: 0, windowStart: Date.now(),
  };
  room.players.set(id, player);
  room.lastActivity = Date.now();

  ws.send(JSON.stringify({
    t: "welcome",
    id,
    room: roomId,
    team,
    tick_hz: TICK_HZ,
    max: MAX_PER_ROOM,
    peers: room.count,
  }));
  room.broadcast({ t: "join", id, name, team, peers: room.count });

  ws.on("message", (raw) => {
    const now = Date.now();
    if (now - player.windowStart > 1000) {
      player.windowStart = now;
      player.msgsThisSecond = 0;
    }
    if (++player.msgsThisSecond > MAX_MSG_PER_SEC) return; // silently drop; a spamming client cannot starve the room

    if (raw.length > 2048) return;
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      return;
    }
    room.lastActivity = now;

    switch (msg.t) {
      case "s": { // position + class + hp
        player.x = clamp(msg.x, -200, 200);
        player.z = clamp(msg.z, -200, 200);
        player.yaw = clamp(msg.y, -Math.PI * 4, Math.PI * 4);
        const ci = Number(msg.c);
        if (Number.isInteger(ci) && ci >= 0 && ci < CLASSES.length) player.clsIdx = ci;
        player.hp = clamp(msg.h, 0, 400);
        player.alive = msg.a !== 0;
        break;
      }
      case "hit": { // cosmetic combat relay: attacker id -> target id
        room.broadcast({ t: "hit", id: player.id, to: Number(msg.to) || 0, d: clamp(msg.d, 0, 400) }, player.id);
        break;
      }
      case "chat": {
        const text = String(msg.m || "").slice(0, 120);
        if (text) room.broadcast({ t: "chat", from: name, team, m: text });
        break;
      }
      case "score": { // only the server decides score shape; clamp to sane steps
        const side = Number(msg.s) === 1 ? 1 : 0;
        room.score[side] = clamp(room.score[side] + 1, 0, 999);
        room.broadcast({ t: "score", r: room.score[0], b: room.score[1] });
        break;
      }
      default:
        break;
    }
  });

  const drop = () => {
    if (!room.players.has(id)) return;
    room.players.delete(id);
    room.broadcast({ t: "leave", id, peers: room.count });
    room.lastActivity = Date.now();
    if (room.count === 0 && rooms.size > 8) rooms.delete(room.id);
  };
  ws.on("close", drop);
  ws.on("error", drop);
});

// keepalive: drop half-open sockets so a phone that slept does not hold a slot
const alive = new Set();
wss.on("connection", (ws) => {
  alive.add(ws);
  ws.on("pong", () => alive.add(ws));
  ws.on("close", () => alive.delete(ws));
});

// ---------------------------------------------------------------- tick
setInterval(() => {
  for (const ws of alive) {
    if (ws.readyState !== 1) {
      alive.delete(ws);
      continue;
    }
    ws.ping();
  }
}, 20000).unref();

setInterval(() => {
  const now = Date.now();
  for (const room of rooms.values()) {
    if (room.count === 0) {
      if (now - room.lastActivity > ROOM_IDLE_MS) rooms.delete(room.id);
      continue;
    }
    room.tick++;
    room.broadcast(room.snapshot());
  }
}, Math.round(1000 / TICK_HZ));

server.listen(PORT, () => {
  console.log(`[ctp] relay listening on :${PORT} — ${TICK_HZ} Hz, ${MAX_PER_ROOM}/room, ${MAX_ROOMS} rooms max`);
});

const shutdown = () => {
  console.log("[ctp] draining");
  for (const ws of wss.clients) try { ws.close(1001, "restarting"); } catch {}
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
