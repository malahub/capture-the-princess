// Load test: N browser-shaped clients in one room, each pretending to play.
// Mirrors what the Godot client does — join a side, send state at 15 Hz, count
// the 20 Hz snapshots coming back. Prints per-client snapshot rate, snapshot
// size and join latency so "it holds 100 players" is a measurement, not a hope.
//
//   node soak.js --url ws://127.0.0.1:8080/ws --clients 100 --seconds 20

const WebSocket = require("ws");

const args = process.argv.slice(2);
const arg = (k, d) => {
  const i = args.indexOf(k);
  return i >= 0 && args[i + 1] ? args[i + 1] : d;
};

const URL_BASE = arg("--url", "ws://127.0.0.1:8080/ws");
const CLIENTS = parseInt(arg("--clients", "100"), 10);
const SECONDS = parseInt(arg("--seconds", "20"), 10);
const ROOM = arg("--room", "soak-" + Date.now().toString(36));

const clients = [];
const stats = { welcome: 0, snapshots: 0, bytes: 0, errors: 0, joined: [] };

function spawn(i) {
  const team = i % 2 === 0 ? "red" : "blue";
  const ws = new WebSocket(`${URL_BASE}?room=${ROOM}&name=p${i}&team=${team}`);
  const c = { ws, snaps: 0, last: 0, gaps: [], joinedAt: 0, team, id: 0 };
  clients.push(c);

  ws.on("open", () => { c.joinedAt = Date.now(); });
  ws.on("message", (buf) => {
    const now = Date.now();
    stats.bytes += buf.length;
    let m;
    try { m = JSON.parse(buf.toString()); } catch { return; }
    if (m.t === "welcome") {
      stats.welcome++;
      c.id = m.id;
      c.team = m.team;
      stats.joined.push(now - c.joinedAt);
    } else if (m.t === "snap") {
      c.snaps++;
      stats.snapshots++;
      if (c.last) c.gaps.push(now - c.last);
      c.last = now;
    }
  });
  ws.on("error", () => { stats.errors++; });

  // 15 Hz state, jittering around the spawn so peers see movement
  const timer = setInterval(() => {
    if (ws.readyState !== 1) return;
    ws.send(JSON.stringify({
      t: "s",
      x: (Math.random() - 0.5) * 40,
      z: (Math.random() - 0.5) * 30,
      y: Math.random() * 6.28,
      c: i % 4,
      h: 160,
      a: 1,
    }));
  }, 66);
  c.timer = timer;
}

const pct = (arr, p) => {
  if (!arr.length) return 0;
  const s = [...arr].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(s.length * p))];
};

for (let i = 0; i < CLIENTS; i++) {
  spawn(i);
  if (i % 25 === 24) require("timers").setTimeout(() => {}, 0); // let the loop breathe
}

const report = () => {
  const rates = clients.map((c) => c.snaps / SECONDS);
  const allGaps = clients.flatMap((c) => c.gaps);
  const avgRate = rates.reduce((a, b) => a + b, 0) / (rates.length || 1);
  const expected = 20;
  const worst = Math.min(...rates);
  const kbPerClient = (stats.bytes / 1000) / (clients.length || 1) / SECONDS;
  console.log(JSON.stringify({
    room: ROOM,
    clients: clients.length,
    welcomed: stats.welcome,
    join_ms: { p50: pct(stats.joined, 0.5), p95: pct(stats.joined, 0.95), max: Math.max(0, ...stats.joined) },
    snapshots_total: stats.snapshots,
    snap_hz: { avg: +avgRate.toFixed(1), worst: +worst.toFixed(1), expected },
    gap_ms: { p50: pct(allGaps, 0.5), p95: pct(allGaps, 0.95), max: Math.max(0, ...allGaps) },
    egress_kb_per_client_per_s: +kbPerClient.toFixed(1),
    errors: stats.errors,
    pass: stats.welcome === clients.length && worst >= expected * 0.8 && kbPerClient < 150,
  }, null, 2));
  for (const c of clients) { clearInterval(c.timer); try { c.ws.close(); } catch {} }
  setTimeout(() => process.exit(0), 200);
};

setTimeout(report, SECONDS * 1000);
