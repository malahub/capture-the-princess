# Heavy Flag — design and implementation notes

Original game. Isometric 3D, two castles, two kidnapped princesses, one cake
economy. No assets, code, names or audio from any commercial title.

## The loop

Each team's princess starts locked in the *other* team's dungeon:

- **Red Princess** — held in the Blue dungeon.
- **Blue Princess** — held in *your* (Red) dungeon.

You win by getting your own princess onto your throne and holding her there for
25 seconds. The Blue team is trying to do exactly the same thing.

Because both princesses are already captive, the game is a double job:

1. **Defend** — collect cake and feed the Blue Princess in your dungeon. Weight
   is the only wall in the game: a fat princess takes forever to carry, so the
   Blue rescuer crawls home and you have time.
2. **Attack** — cross the field, lift the Red Princess out of the Blue dungeon,
   and carry her back. Her weight is whatever the Blue feeder managed to feed
   her, so the trip home may be a crawl.
3. **Hold** — 25 seconds on the throne. If a match passes four minutes both
   princesses have usually been fattened to a standstill, so the cake melts:
   weight decays 2.4x faster and the hold drops to 9 s ("sudden death"), which
   guarantees the match resolves. Blue switches to kidnapping: any Blue
   soldier who reaches her picks her up and hauls her back to their dungeon.
   The hold timer decays three times faster than it fills whenever she leaves
   the throne.

## Weight model

`carry_speed = base_speed * clamp(1.0 - 0.075 * weight, 0.22, 1.05) + 0.55 * helpers`

- Weight 0 → 100 % speed. Weight 6 → 55 %. Weight 10 → 22 %, i.e. a statue.
- Weight bleeds off one slice every 11 s, at half rate while she is being
  carried, so a fat princess is a temporary wall, not a permanent one.
- Allied soldiers within 4 m of a carrier each add 0.55 m/s (up to three), which
  is what makes "carry together" matter.
- Cake: 3 slices carried, piles respawn after 11 s, one slice per F press.

### Feeding is a physical event, not a number

The weight step never happens when you press F. F throws: a slice leaves the
thrower's hand (the thrower's arm plays the swing animation), arcs for 0.55 s
with a puff trail, and only lands on contact at her face. On impact the slice is
consumed, her weight ticks up, and she plays a 0.75 s chew:

- both arms lift to her face and drop back
- her head tips back and her mouth opens/closes twice
- her body squashes wide and low, then bounces back past her new size
- crumbs spray, a "+1" pops off her head, and the weight tag re-reads

Size is stepped by the same event: `target_scale = 1 + 0.105·weight` on x/z and
`1 + 0.04·weight` on y, and the body lerps into the new target over ~0.3 s, so
each slice is a visible, animated size step rather than a teleport. A belly
sphere that is hidden at weight 0 swells out in front of the skirt, and idle
breathing gets stronger as she gets heavier, so a fat princess also *looks*
heavy when she is standing still.

## The map, and the second way in

The field is now **176 × 116 m** (was 132 × 88) with castles at |x| = 56 and
bridges at z = −32, 0, +32. `Bld.CASTLE_SHIFT` is derived from
`Terrain.CASTLE_X`, so growing the map cannot leave a castle stranded off its
plateau, and `Bld.GATE_ABS` follows it so "inside the castle" stays correct.

Each castle has an **assault ramp**: a shoulder of ground (`Terrain.h_ramp`,
centred at |x| = 52, |z| = 21, 16 m radius, 8 m high) that climbs from the field
to about 8.0 m — above the 5.97 m battlement line. The ramp is clipped by
`smoothstep(15.0, 18.6, |z|)` so it dies inside the wall thickness and the
courtyard stays perfectly flat. It is tinted toward rock so the way in reads
from a distance.

From the crest you can walk straight onto the parapet, or **jump** (V) off the
bank and drop into the courtyard — a 5 m fall the step rules would otherwise
refuse. Jumping is general: 8 m/s impulse under 24 m/s² gravity, ~1.3 m of lift,
with air control, and airborne units ignore wall collision so the jump can carry
you over a battlement.

## Three storeys

The keep is now layered, which both shrinks the courtyard and gives the key
somewhere to live:

- **Courtyard** at plateau height — the floor the carriages and cake piles use.
- **Middle storey** (`Bld.MID_H` = 2.15 m): a raised keep in the middle of the
  courtyard, reached by three 0.72 m steps, ringed with a gold balustrade. The
  key hangs over the **shrine** on top, so a raider has to climb for it and is a
  silhouette on the skyline while they do.
- **Wall walk** at 4.62 m, on walls now **3.6 m thick** (was 2.6) — the archer
  gallery is wide enough to stand, turn and shoot along.

Stairs and the walk surface are now generated from one number: each tread's top
*is* the deck height `Terrain.h` returns, and bridge planks follow the same
blended surface they sit on, so feet never sink into a step or a plank.

## Camera and outlines

- **The camera turns in 90° steps** (`R`). `cam_yaw` is damped toward
  `cam_yaw_target`, so the world swings round rather than cutting. Movement is
  already expressed in camera space, so WASD follows the new orientation for
  free — W is always "up the screen".
- **Occluded units are outlined** (`_is_occluded()`, `_update_silhouettes()`).
  A unit is hidden if any solid rectangle or raised terrain sits on the line
  between it and the camera; the check marches 10 samples along that line and
  tests `Terrain.h()` plus every solid's `top`, so a wall that blocks a soldier
  also blocks the line of sight. The check runs 12× a second, not per frame.
- **You are outlined too.** The player, allies and enemies all get the
  treatment; testing only the chest missed units whose head was behind a low
  wall, so a unit counts as hidden if either the head or the chest is covered.
- **The outline itself** is a three-capsule ghost of the figure drawn with
  `silhouette.gdshader`: unshaded, `depth_test_disabled`, `depth_draw_never`, so
  it reads through the wall, with a fresnel term driving alpha from a 12 % body
  to a 95 % rim. Yellow for your team, red for theirs.

## Characters are sculpted, not blocked out

Every unit is still built from primitives at runtime — no imported assets — but
the rig is now a proper humanoid instead of stacked boxes:

- **Two-segment limbs.** Hip → thigh → knee → shin → boot, and shoulder → upper
  arm → elbow → forearm → hand, each joint a real node. The walk cycle bends the
  knee only backwards, swings the free arm counter to the leg, and leans the
  torso into the run.
- **A head with a face.** Skull, jaw, chin, brow ridge, nose, ears, eyes with a
  dark bead and a catchlight, a mouth line, and the head tilted slightly up so
  the face survives a 45° isometric camera.
- **Class silhouette.** Warrior: crested helm, round shield with gold rim, sword.
  Ranger: hood, longbow with a strung line, quiver with fletching. Mage: pointed
  hat, cape, robed skirt, staff with a glowing orb. Worker: flat cap, apron,
  hammer. Villager: bowl of hair and a satchel.
- **Contrast over detail.** Sleeves are the dark team colour, forearms are skin,
  boots are near-black and the belt and buckle are gold, so a 2 m figure still
  reads at the default camera distance.

## Spawning hatless

`Unit.set_class("worker")` is the spawn state for the player: the class is a
pickup, not a property. `respawn()` resets the player to worker, `on_unit_died()`
drops their hat into `dropped_hats` (a model at the death spot, capped at 14 so
the field cannot fill with litter), and `_update_dropped_hats()` lets any
*hatless* unit within 1.6 m reclaim it. Only workers can scavenge, which keeps
the loop honest: lose the hat, you are a labourer until you earn one back.

## Roles are multipliers, not requirements

Every class carries a team-wide bonus that a coordinated team extracts and a
solo player simply never gets. None of them gates content: the gate can be
smashed solo, a fight can be won with plain swords, and the princess can be
carried out by one determined villager. Ignoring the system costs percentage,
not permission.

| Who | What they give the team | Where |
|---|---|---|
| Worker | 3 wood + 3 ore at a class stand upgrades that class for **everyone**: +22 % damage for the rest of the match | `_update_stations()` |
| Ranger / Mage | +35 % damage while standing on a wall walk — shooting down from the parapet | `Unit.damage_scale()` + `on_wall()` |
| Warrior | allies within 5 m take 18 % less damage (shield wall) | `incoming_scale()` |
| Villager | fastest class, runs cake at full speed, slap forces cargo drops | `cur_speed()` |
| Worker | also the only class that repairs the gate (110 HP per material, and not while the door is being hit) | `_update_gates()` |

Two consequences worth designing around: a repair cannot happen under fire, so
a door is only rebuilt when the attackers are pushed off it; and if both sides
stall, sudden death at 300 s **drops both gates and pops both cages**, which
guarantees the match resolves in the open.

## The siege: gate, key, cage

A castle is not a walk-in any more.

- **Gate** — a real door leaf with 1800 HP in the gate arch. Any enemy melee
  hit that lands inside 3.4 m of it chips it (0.55× the unit's damage, so it
  takes a squad ~20 s). At 0 it breaks: the collision rectangle is removed, the
  leaf hides, and the banner calls it out. Your own gate never blocks you.
- **Repair** — a worker standing at their own gate with wood or ore spends one
  material every 0.5 s to restore 160 HP. A broken gate only becomes solid
  again at 40 % HP, so it can be contested while it is being rebuilt.
- **Worker** — the fifth hat. 160 HP, 11-damage chisel (the weakest melee in the
  game), gathers wood from log piles and ore from rocks (4 of each), and is the
  only class that can repair.
- **Key and cage** — each cage door is barred and locked. The matching key hangs
  from a hook inside the castle that owns the cage, so a raider has to get
  through the gate, take the key, and walk it to the cage. Walking within 1.7 m
  picks the key up automatically; carrying it within 2.9 m of the cage swings
  the door open. Dropping it (dying with it) returns it to the ground.

## Classes (hats)

Hats spawn on three stands in each castle; standing on one and pressing E swaps
your class instantly. Dropped hats are not simulated — the stands are the source.

| class | hp | speed | attack | role |
|---|---|---|---|---|
| Villager | 110 | 5.6 (×1.15 when empty) | 14 dmg slap, 1.9 m | fastest; forces enemies to **drop** cake and princesses |
| Worker | 160 | 5.3 | 11 dmg chisel, 1.75 m | gathers wood/ore, repairs the gate — deliberately bad in a fight |
| Warrior | 240 | 4.7 | 36 dmg wide arc, 2.25 m | front line / carrier escort |
| Ranger | 150 | 4.9 | 24 dmg arrow, 30 m/s | ranged pressure on carriers |
| Mage | 170 | 4.5 | 32 dmg + 14 splash, 2.5 m | breaks up groups on the throne |

## Map

132 × 88 m of playable ground — roughly four times the area the layout started
at. Castles sit on flat plateaus at x = ±40; a river runs north–south through
the middle (|x| < 6.4 is water) with exactly three crossings at z = −24, 0, +24,
so every push across the map goes through a bridge and somebody can hold it.

Terrain is an analytic height field (`scripts/terrain.gd`), not a mesh authored
by hand:

- rolling base + seven gaussian knolls, 3–8 m high
- two castle plateaus, flat at y = 1.35 and ramped back into the field
- a carved river channel 4.4 m deep, water at y = −0.85
- bridges: 16 m decks at y = 1.15 with stone quays at each mouth

Units sample `Terrain.h(x, z)` and stand on it; movement refuses water and any
step taller than 0.9 m, so banks, quays and cliffs are physical without collision
meshes. Bots route through `Terrain.bridge_step()`: near mouth, then far mouth,
then the goal — the same three crossings the player has to use. Projectiles fly
at chest height over the terrain and can cross the river, which is what makes
rangers worth putting on a bank.

### Castles are two-storey

Each castle is 28 × 34 m of courtyard inside walls 4.4 m tall and 2.6 m thick.
That thickness is the point: the top of every wall is a **walkway**, registered
as a deck in the terrain field (`Terrain.add_deck`), with merlons on the outside
face only so archers can stand behind cover and shoot down into the courtyard or
out over the field.

- 11-step stone stairs run up the inside of both side walls; each tread is its
  own deck, rising 0.42 m, so the normal step rules carry a unit up.
- `_can_step()` is height-aware: a wall only blocks a unit whose feet are below
  its top, and a drop over 1.1 m is refused — you cannot walk off a parapet, you
  have to take the stairs.
- Wall solids carry their `top` in world space, so the same rectangle blocks a
  soldier on the ground and supports an archer standing on it.
- Corner towers also expose a deck at 4.5 m, and each castle returns five
  `perches` on the parapet for future defender AI.

Castle geometry is built in a local frame and shifted by `CASTLE_SHIFT`, so the
same builder places either castle on its plateau. Walls are axis-aligned
rectangles resolved with slide-and-stop movement — no physics bodies for units,
so nothing can tunnel or jitter.

## AI

- **Blue:** five — a rescuer (fetches the Blue Princess), a feeder (fattens the
  Red Princess) and three attackers. When the enemy princess sits on her throne
  every Blue unit switches to kidnapping.
- **Red allies:** three — two escorts that follow a carrying player and fight,
  and a feeder that keeps the Blue Princess heavy. The player is the fourth.
  Blue outnumbers you; you are supposed to be better than they are.
- Pathing is a two-state router: in a castle → leave through the gate; on the
  field → enter through the target castle's gate. Straight lines inside a
  region, so no navmesh and no stuck-behind-wall loops.

## Tuning knobs

| what | where |
|---|---|
| hold length, respawns | `scripts/game.gd` constants |
| class hp / speed | `scripts/unit.gd` `SPEEDS`, `HPS` |
| weight curve, decay | `scripts/unit.gd` `carry_factor`, `scripts/princess.gd` |
| damage, ranges | `scripts/unit.gd` `attack()`, `scripts/game.gd` projectiles |
| squad size and roles | `start_match()` in `scripts/game.gd` |
| gate HP, break multiplier, repair rate | `_spawn_gates()`, `melee_hit()`, `_update_gates()` |
| difficulty | squad sizes: `ally_classes` (3) vs Blue's 5 in `start_match()` |

## Architecture

| file | job |
|---|---|
| `scripts/core.gd` | palette, material cache, primitive meshes, generated SFX, input map |
| `scripts/build.gd` | the map, castles, props, fighter and princess rigs |
| `scripts/unit.gd` | movement, animation, combat, carrying |
| `scripts/princess.gd` | weight, cage/carry state, world tag |
| `scripts/ui.gd` | menu, HUD, minimap, tutorial panel, cards |
| `scripts/game.gd` | state machine, AI, economy, win/lose, debug harnesses |

Everything is generated in code — the project ships as text plus `icon.svg`.

## Test harnesses

```bash
godot --headless --path . -- --simtest=240      # 4 min of match in ~2 s, prints state
godot --headless --path . -- --smoke            # boots the real scene and plays
godot --headless --path . -- --play --shot-path=/tmp/a.png --shot-frame=120
godot --headless --path . -- --tutorial --at=-33,-5
```

`--at=x,z` teleports the player, which is how the interaction prompts were
photographed. `--autoplay` hands the player to a simple bot.
