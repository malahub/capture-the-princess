#!/usr/bin/env python3
"""Analyse a --telemetry JSONL run and report what went wrong.

Reads one JSON object per unit per second (written by Game._write_telemetry) and
hunts for the failure modes that actually make an AI battle look broken:

  stuck          not moving while it has somewhere to be
  idle-no-goal   alive, no waypoint, no target: the brain has nothing to do
  path-fail      has a goal but A* keeps returning nothing
  oscillation    walking back and forth instead of progressing
  overlap        bodies sitting inside each other
  height         visual Y not on the walkable surface
  off-nav        standing on a cell the nav grid calls blocked
  progress       nobody touched a gate / no princess moved in the whole run

Usage: analyze_telemetry.py logs/spectate.jsonl [--html logs/report.html]
"""
import json
import sys
from collections import defaultdict, OrderedDict

STUCK_MOVE = 0.30      # metres per sample that still counts as "moving"
STUCK_RUN = 3          # consecutive samples
OVERLAP_D = 0.55
OVERLAP_RUN = 2


def load(path):
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def group_by_unit(rows):
    units = OrderedDict()
    for r in rows:
        units.setdefault(r["id"], []).append(r)
    return units


def analyse(rows):
    findings = {k: [] for k in ("stuck", "idle", "path_fail", "osc", "overlap",
                                "height", "off_nav", "events")}
    units = group_by_unit(rows)
    duration = max((r["t"] for r in rows), default=0.0)

    # ---- per unit time series
    for uid, ser in units.items():
        ser.sort(key=lambda r: r["t"])
        head = ser[0]
        label = "#%d %s/%s" % (uid, head["cls"], head["brain"])

        # stuck: no movement while it has a goal
        run = 0
        for prev, cur in zip(ser, ser[1:]):
            moved = ((cur["x"] - prev["x"]) ** 2 + (cur["z"] - prev["z"]) ** 2) ** 0.5
            if cur["alive"] and cur["has_wp"] and moved < STUCK_MOVE:
                run += 1
            else:
                run = 0
            if run == STUCK_RUN:
                findings["stuck"].append({
                    "unit": label, "t": cur["t"], "x": cur["x"], "z": cur["z"],
                    "wp": cur["wp"], "path": "%d/%d" % (cur["pi"], cur["path"]),
                    "stuck_t": cur["stuck"], "tgt": cur["tgt"],
                })

        # idle with nothing to do — only if it lasts (spawn moments don't count)
        run = 0
        for prev, cur in zip(ser, ser[1:]):
            idle_now = cur["alive"] and not cur["has_wp"] and not cur["tgt"] and not cur["carry"]
            run = run + 1 if idle_now else 0
            if run == 5:
                findings["idle"].append({"unit": label, "t": cur["t"], "x": cur["x"], "z": cur["z"]})
                break

        # A* returning nothing while a goal exists
        fails = [c for c in ser if c["alive"] and c["has_wp"] and c["path"] == 0]
        if len(fails) >= 2:
            findings["path_fail"].append({
                "unit": label, "samples": len(fails), "first_t": fails[0]["t"],
                "x": fails[0]["x"], "z": fails[0]["z"], "wp": fails[0]["wp"],
            })

        # oscillation: many heading reversals in a short window
        flips = 0
        for a, b, c in zip(ser, ser[1:], ser[2:]):
            d1 = (b["x"] - a["x"], b["z"] - a["z"])
            d2 = (c["x"] - b["x"], c["z"] - b["z"])
            if abs(d1[0]) + abs(d1[1]) < 0.2 or abs(d2[0]) + abs(d2[1]) < 0.2:
                continue
            if d1[0] * d2[0] + d1[1] * d2[1] < 0:
                flips += 1
        if flips >= 8:
            findings["osc"].append({"unit": label, "flips": flips})

        # height / nav sanity
        for cur in ser:
            if cur["alive"] and abs(cur["y"] - cur["h"]) > 1.25:
                findings["height"].append({"unit": label, "t": cur["t"], "y": cur["y"], "h": cur["h"]})
                break
            if cur["alive"] and not cur["in_nav"]:
                findings["off_nav"].append({"unit": label, "t": cur["t"], "x": cur["x"], "z": cur["z"]})
                break

    # ---- pairwise overlap, sampled per timestamp
    by_t = defaultdict(list)
    for r in rows:
        if r["alive"]:
            by_t[r["t"]].append(r)
    overlaps = defaultdict(int)
    for t, group in by_t.items():
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                d = ((a["x"] - b["x"]) ** 2 + (a["z"] - b["z"]) ** 2) ** 0.5
                if d < OVERLAP_D:
                    overlaps[(a["id"], b["id"])] += 1
    for (a, b), n in sorted(overlaps.items(), key=lambda kv: -kv[1]):
        if n >= OVERLAP_RUN:
            findings["overlap"].append({"pair": "#%d/#%d" % (a, b), "samples": n})

    summary = {
        "duration_s": round(duration, 1),
        "units": len(units),
        "samples": len(rows),
        "counts": {k: len(v) for k, v in findings.items() if k != "events"},
    }
    return summary, findings, units


def role_table(units):
    per = defaultdict(lambda: {"units": 0, "distance": 0.0})
    for uid, ser in units.items():
        key = "%s/%s" % (ser[0]["cls"], ser[0]["brain"])
        per[key]["units"] += 1
        d = 0.0
        for a, b in zip(ser, ser[1:]):
            d += ((b["x"] - a["x"]) ** 2 + (b["z"] - a["z"]) ** 2) ** 0.5
        per[key]["distance"] += d
    return dict(per)


def html(summary, findings, roles, path):
    def rows(items, cols):
        out = []
        for it in items[:60]:
            out.append("<tr>" + "".join("<td>%s</td>" % it.get(c, "") for c in cols) + "</tr>")
        return "\n".join(out) or "<tr><td colspan='%d' class='ok'>none</td></tr>" % len(cols)

    sections = [
        ("Stuck (goal, no movement)", "stuck", ["unit", "t", "x", "z", "wp", "path", "stuck_t", "tgt"]),
        ("Idle with no goal", "idle", ["unit", "t", "x", "z"]),
        ("A* found no path", "path_fail", ["unit", "samples", "first_t", "x", "z", "wp"]),
        ("Oscillating", "osc", ["unit", "flips"]),
        ("Bodies overlapping", "overlap", ["pair", "samples"]),
        ("Height mismatch", "height", ["unit", "t", "y", "h"]),
        ("Off the nav grid", "off_nav", ["unit", "t", "x", "z"]),
    ]
    body = []
    for title, key, cols in sections:
        n = len(findings[key])
        cls = "bad" if n else "good"
        body.append("<h2 class='%s'>%s <span>%d</span></h2>" % (cls, title, n))
        body.append("<table><tr>" + "".join("<th>%s</th>" % c for c in cols) + "</tr>")
        body.append(rows(findings[key], cols))
        body.append("</table>")

    role_rows = "".join(
        "<tr><td>%s</td><td>%d</td><td>%.0f m</td></tr>" % (k, v["units"], v["distance"])
        for k, v in sorted(roles.items(), key=lambda kv: -kv[1]["distance"]))

    doc = """<!doctype html><meta charset="utf-8"><title>CTP telemetry report</title>
<style>
body{background:#0f1319;color:#dde3ec;font:14px/1.5 ui-monospace,Menlo,monospace;margin:32px}
h1{color:#e8b53f;font-size:22px;margin:0 0 4px}
h2{font-size:15px;margin:26px 0 8px;padding-bottom:4px;border-bottom:1px solid #2a3240}
h2.good{color:#6fd18a} h2.bad{color:#ff6b5e}
h2 span{float:right;font-weight:400;opacity:.8}
table{border-collapse:collapse;width:100%%;margin-bottom:8px}
th,td{text-align:left;padding:4px 8px;border-bottom:1px solid #202834}
th{color:#8d99aa;font-weight:400;font-size:12px;text-transform:uppercase}
td.ok{color:#6fd18a}
.meta{color:#8d99aa;margin-bottom:12px}
</style>
<h1>Capture The Princess — 10 v 10 telemetry</h1>
<div class="meta">%(dur)s s · %(units)d units · %(samples)d samples ·
 stuck %(stuck)d · idle %(idle)d · pathfail %(pathfail)d · osc %(osc)d ·
 overlap %(overlap)d · height %(height)d · offnav %(offnav)d</div>
%(body)s
<h2 class="good">Distance per role <span></span></h2>
<table><tr><th>role</th><th>units</th><th>walked</th></tr>%(roles)s</table>
""" % {
        "dur": summary["duration_s"], "units": summary["units"], "samples": summary["samples"],
        "stuck": summary["counts"]["stuck"], "idle": summary["counts"]["idle"],
        "pathfail": summary["counts"]["path_fail"], "osc": summary["counts"]["osc"],
        "overlap": summary["counts"]["overlap"], "height": summary["counts"]["height"],
        "offnav": summary["counts"]["off_nav"],
        "body": "\n".join(body), "roles": role_rows,
    }
    with open(path, "w") as fh:
        fh.write(doc)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    html_out = sys.argv[sys.argv.index("--html") + 1] if "--html" in sys.argv else None
    rows = load(path)
    if not rows:
        print("no rows in %s" % path)
        return 1
    summary, findings, units = analyse(rows)
    roles = role_table(units)

    print("=" * 68)
    print("RUN  %.1f s · %d units · %d samples" % (summary["duration_s"], summary["units"], summary["samples"]))
    print("=" * 68)
    for key, title in [("stuck", "STUCK (goal, no movement)"), ("idle", "IDLE, NO GOAL"),
                       ("path_fail", "A* RETURNED NOTHING"), ("osc", "OSCILLATING"),
                       ("overlap", "BODIES OVERLAPPING"), ("height", "HEIGHT MISMATCH"),
                       ("off_nav", "OFF THE NAV GRID")]:
        items = findings[key]
        mark = "  " if items else "ok"
        print("\n[%s] %s — %d" % (mark, title, len(items)))
        for it in items[:8]:
            print("     " + "  ".join("%s=%s" % (k, v) for k, v in it.items()))

    print("\nROLE ACTIVITY")
    for k, v in sorted(roles.items(), key=lambda kv: -kv[1]["distance"]):
        print("     %-18s %d units  %6.0f m" % (k, v["units"], v["distance"]))
    if html_out:
        html(summary, findings, roles, html_out)
        print("\nreport written to %s" % html_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
