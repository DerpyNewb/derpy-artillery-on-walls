# Artillery walls: ground recovery rewritten, descent closed - 2026-11-01

## Resume here

Supersedes the descent half of [the preview/walking handoff](HANDOFF_20261101_ARTILLERY_PREVIEW_WALKING_DESCENT.md).
The native assembly, structures and the fifteen caves are unchanged and still documented in
[the native-slot handoff](HANDOFF_20261101_ARTILLERY_NATIVE_WALL_SLOTS.md). Only the Lua mover changed.

| Role | Path |
|---|---|
| Owning generator | `tools/gen_artillery_walls.py` (`--check`, `--selftest` 26 breaks, `--pack`) |
| Runtime | `Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua` |
| Lua checks | `tools/artillery_walls_tests.lua` (ground exit, the crew slot rule, wall transfer, native queue contract, the stall detector) |
| Built and installed pack | `Modding Files/Modpacks/derpy_artillery_walls.pack` = `data/derpy_artillery_walls.pack`, MD5 **7961480F07AE6981EB677D96E1D45987** (2026-11-02 15:00, crew spots kept on the wall, last section, NOT run in game; 976BF5D9 before it, the facing MOVE and the zone re-order; A6FD970B at 11:30, an attack order on a wall battery becomes halt + fire at will, the crew placement capped, the stair level rule, §last; C1FF3B2F at 09:20 the `clearshot` cave; A9099DA4 at 08:00 the attack guard narrowed to every-engine-up; 3E35974D at 22:45 had the attack-order guard and the unreadable-slot guard, F2DAF923 at 22:06 the first alone, and 288627956DCDAACC2FF9248D06039473 at 18:40, crew rule gated on the engine's path state; 4595 and 5637 (log fields) and 29D2 at 16:45, 1B74, D4B9, 9C5C, B243, 853B, 42F1 and 242D before it) |
| Evidence | `Modding Files/Backup/artillery_walls/20261101/rematch_trace_ground_recovery.txt` (annotated), `cold_descent_trace_42F1.txt`, `cold_roof_trace_242D_partA/B/C*.txt` (the author's wall clicks, the trickle wedge, the crew walking back; part C is the hot-loaded fix), `cold_853B_trace.txt`, `cold_B243_nudge_trace.txt` (the re-order with a crewman's block), `cold_9C5C_trace.txt` (the re-order pack), `cold_D4B9_crew_slot_trace.txt` (the crew slot rule, three climbs and three descents, one descent with the mover off), `cold_1B74_crew_lift_trace.txt` and `cold_29D2_crew_lift_trace.txt` with their `script_log_cold_*.txt` (the lift) |

Both pack copies verified byte-identical to source after the build. **Local deployment only; not published.**

## What was wrong, measured

1. **Roof crew shuffle for ever.** With seven engines and 54 crew sitting on the gatehouse roof under a ground order,
   four crewmen moved over a metre inside one second while every engine stood still. The ground detector counted crew
   positions, so its five-second quiet window never opened and no recovery ever fired (730 model seconds observed).
2. **A "down" recovery replants the battery on the wall.** The old rule teleported the whole unit onto the first
   engine that had reached the ground. That engine stands at the stair foot or inside the gate passage, which is on
   the wall line, and the engine places the formation on the wall top. Then another "down" twenty seconds later,
   for ever: this is the "repeated down recoveries" of the cold regression. Pushing the point 12 m further along the
   line from the engines still up did the same thing (an engine in the gate passage lies on the wall line itself).
3. **Engines at a wall edge wander a metre or two.** Body 6 moved between (1,-314) and (-1,-313) all day, so a
   0.25 m anchor never settled. This is the "circulation" the old handoff reported.
4. **Engines pause 28 s on a legitimate climb** while their crew go up first, so a five-second ground window fired a
   recovery in the middle of a working climb and pulled the battery back down.
5. **A walkway point outside a wall zone is a plain MOVE at wall height**, and the engines climb it natively. The
   ground recovery must not treat that as a failed descent.

6. **Crew trickle hides a wedge.** A crewman getting down counted as progress, so four engines wedged on the walkway
   sat 70 s behind a trickle of one or two crew every ten seconds and no recovery fired (242D, battle 4). Engines
   still for 40 s are now stuck whatever the crew count does (`GROUND_STALL_ENGINES`, a second detector).
7. **A teleported engine never recomputes its crew positions.** After a ground recovery dropped all eight engines at
   the ordered point, 49 of 56 crew walked back up to the gatehouse roof they had been given and stood there over an
   unmanned battery (this is the author's screenshot of crew on the roof with the engines below). After a wall-point
   recovery, the six crew of the two engines that had never left the ground walked back down to where those engines
   had stood. One short move brought every crewman back both times (40-65 s). A recovery is now teleport-then-walk:
   on the ground, the drop is `STUCK_SHORT` 8 m (at most a third of the distance) short of the ordered point, back
   along the battery's own line, then a controller goto to the point; on a wall, where a script goto is silently
   dropped, the mover queues the player's own MOVE (`queue_move`, BCQ_MULTIPLE_SELECTION_ORDER_MOVE through the
   command queue at `1cae60c`) to the order's own location block (item 8).
8. **The planner parks one engine and never releases it.** In every climb one engine sat in a queue slot short of a
   stair with its three crew beside it while the other seven climbed past (853B: engine 7 at (16,-302) for 77 s;
   B243: engine 3 at the left stair foot; 9C5C: engine 2 at (27,-301)); in every descent most of the battery parked
   on the wall while one or two walked down. The first stall signal is now the player's order again, once per order
   (`'nudge'`): a wall-height MOVE re-queued through the command queue, a ground order re-issued through the
   controller; the next signal is the drop. A third signal was added for it: one engine standing on the wrong side
   of the order for `NUDGE` 30 s (above the 28 s a legitimate climb paused for) while the rest move. **Measured
   rate: the re-order unparked 1 of 3 parked climbs and 0 of 2 parked descents**, so most of the time it costs
   30 s before the drop that would have come anyway; it is kept because the one success walked the engine up the
   stairs with no snap, and the player's complaint is the snap.
9. **A MOVE order keeps the player's location block at order+0x40**: x, y, z, zero, the wall surface his click
   resolved, a companion pointer (null on the roof). Re-queuing that block is an exact re-click. The first
   re-order borrowed the nearest crewman's block and moved the whole line 15 m along the roof (B243, order (1,-314)
   became (16,-317)); the wall drop's walk now uses a copy of the block taken before the halt discards the order
   (`copy_location`, `ORDER_LOCATION`), which also retires `wall_man_near`.

No detach call fired at `3065744` or `3065a94` in any of the three battles (hooks filtered on the battery, polled
every 100 ms). The abandonment in the cold regression was never reproduced once the recovery stopped looping; the
loop is the likeliest cause and is gone.

## What changed in the mover (ground mode only; wall mode untouched)

- Motion actors are the engines, without heading, plus one pseudo-actor carrying the crew-on-wall count times 100:
  a crewman getting down is progress, crew shuffling is not, an engine turning in place is not.
- `GROUND_STALL` 20 s and `GROUND_DRIFT` 4 m: `stalled()` takes a window and a radius (defaults 5 s / 0.25 m keep the
  wall path as it was).
- A stalled battery goes to the **ordered point**, never to the first engine down, one rank wide
  (`max(ordered width, engines x 6)`): the player picked that ground. `'down'` and the resumed goto are gone.
- An order whose point sits more than 2 m above the terrain (`WALL_TOP`) is a wall order: complete only when every
  engine and crewman is up; otherwise recovered to the wall point (and that recovery makes the unit fire).
- Two ground detectors, both run every tick: the quiet one (engines plus the crew count, 20 s) and the engines-only one
  (40 s, `GROUND_STALL_ENGINES`), because crew trickling down one at a time reset the first for ever.
- Never a bare teleport: ground recoveries drop 8 m short and walk; wall recoveries drop on the point and queue the
  player's MOVE to the order's own location block (`queue_move`, `copy_location`). The tests pin the drop point, the
  walk target, the wall flag and the MOVE's native contract (`tools/artillery_walls_tests.lua`).
- The first stall signal re-orders (`'nudge'`), the second drops; a per-engine parked timer (`NUDGE` 30 s, wrong side
  of the order, 4 m radius) is the third signal. After a nudge every detector gets a fresh window.

## Evidence

- Battle 2 (rematch, hot-loaded source): inside ground order from the gatehouse, three engines and their crew walked
  down natively, nothing moved for 20 s, recovery at 348800 ms, all eight down with 56 crew attached, then walked to the
  order. Outside order from the walkway: one engine into the gate passage, the rest shuffling; the old rule looped
  (605800, 666800, 726800, 785800 all replanted on the wall top); the shipped rule fired at 1032800 and put all eight at
  (-45,-365) outside the wall, attached, then firing (176 -> 160 ammunition).
- Cold load of 42F1 (shipped Lua, no hot-load): all eight climbed natively in 60 s; an inside ground order brought six
  down natively, two stayed on the walkway with 14 crew, `(stuck)` logged at 219600 ms, all eight at (-20,-270) with
  56 crew attached, zero detach calls.
- Cold load, single-engine Deathshrieker (u5): the same queued wall-height MOVE walked it 250 m and up onto the
  walkway at (-48,624,-319) natively; a ground goto walked it back down to (-23,-260) natively. No recovery fired for
  it (the log's only recovery line is the battery's), no detach call.
- Battle 4 (cold 242D, the author's own wall clicks then my ground orders): native wall order up in 60 s with a `(wall)`
  recovery completing it, 176 -> 103 firing from the walkway; the ground order wedged four engines behind a crew trickle
  for 70 s with no recovery (item 6). Hot-loaded fix: the engine timer fired at 920500, all eight at the point, and 49
  crew walked back up (item 7); a 13 m nudge brought all 56 down in 65 s. Roof move: six up natively, two never left,
  the wall-point recovery at 2067000 put all eight up and six crew walked back down; the re-queued wall MOVE brought them
  up in 40 s. Descent with the teleport-then-walk: recovery at 3100500, every engine on the ground with its three crew
  within 5 m, no crew left on the roof.
- Battle 5 (cold 853B, shipped Lua only): roof MOVE queued at 26300, seven engines up natively by 96800, one wedged at
  the stair foot with its crew for 80 s; `(stuck)` at 138600 dropped all eight on the roof and queued the MOVE to
  (20,-316); the engines walked it, every engine kept three crew within 5 m, 56 crew up, firing 176 -> 161 in 60 s.
  Ground order at 209000: two engines down natively, six stayed on the roof with 42 crew; `(stuck)` at about 276000
  dropped all eight 8 m short of (-45,-275) and walked them in; at 301800 every engine on the ground with its three
  crew within 5 m, none left on the roof, 56 crew linked.
- Battle 6 (cold B243, first re-order build): roof MOVE at 75800; engine 3 parked at the left stair foot (-32,609,-304)
  from 136800; nudge at 167600 (crewman block, the line moved to (16,-317)) and it climbed natively, up by 182800,
  all eight up with three crew each by 215800, no drop. Ground order at 288100: seven down natively, engine 2 parked
  at the wall end (36,624,-305); nudge at 318600 did nothing; `(stuck)` at 348600, all down with crew.
- Battle 7 (cold 9C5C, shipped Lua only): roof MOVE at 52800; engine 2 parked at (27,609,-301) from 95800; nudge at
  126100 (order block, point kept at (1,-314)) did nothing; `(stuck)` at 156100 dropped all eight on the point and
  the queued MOVE walked them along the wall, three crew per engine by 197800, firing 176 -> 160. Ground order at
  237100: one engine down natively, seven parked; nudge at 277100 did nothing; `(stuck)` at 307100, all eight on the
  ground with crew by 307800.
- Battle 1 (manual wall clicks by the author while I worked): native ascent to eight front markers and 56 crew in
  60 s with no recovery; the bodies then ignored every ground click for 100 s, which is the roof case above.

## Test route that needs no mouse

Camera aiming failed repeatedly: `move_to`'s target is the screen centre only at shallow pitch, the camera clamps
height and pitch, and the author moved the camera while I aimed. The route that works:

1. `uc:teleport_to_location` the Infernal Guard onto the walkway (it lands on the nearest wall surface).
2. `AW.capture(2)` (probes/artwalls_probe.lua) copies a wall man's location block with its surface pointer.
3. `AW.move(3,false)` queues the battery's MOVE through the player's own command queue. The engines climb natively.
4. `uc:goto_location_angle_width` for the ground order. A script goto onto a wall point is silently dropped; a
   script goto gives width 8, i.e. a one-engine file, so do not read formation shape off these tests.

A real right-click on the walkway gives the native wall order (controller at unit+3300); my scripted clicks only ever
gave wall-height MOVEs. Both paths are covered by the mover now.

## Traps found this session

- **The custom siege has a 60-minute model-time limit.** Fast-forward reaches it in 15 real minutes; the phase goes
  `Complete`, every `bm` callback stops while `time_elapsed_ms` keeps advancing. Rematch: `in_battle_results_popup >
  ... > button_rematch`, then `dialogue_box > both_group > button_tick`. A rematch resets the Lua state: reload the
  probes and re-aim the trace hooks on the new unit pointers.
- `artwalls_hooks.lua`: `AWH.poll` stored its group at `AWH[name]`, so a hook named `b` overwrote the buffer table
  `AWH.b`. Groups now live in `AWH.g[name]`.
- The script log's `[ui] uicomponent root` lines are real clicks; scripted `mouse_event` clicks never log one, so
  the log tells you whether a human is driving.
- `wh3_stop` kills the process; the test preferences file survives because the game never wrote it at exit.


## Root cause of the parked engine, found 2026-11-01 (RE session after 9C5C)

**An engine walks only when every one of its crew stands on his manning slot, and the slots are laid out
relative to the engine, 2-7 m behind it. At a stair top or a roof edge some slots fall off the walkway, the crewmen
walk at the edge for ever (own walk `3ae2400`, path state 4, goal a few metres past the edge), and the engine
waits for ever.** Measured with the mover off (`bm:remove_process('derpy_artillery_walls_exit')`), probe
`probes/artwalls_park_probe.lua`:

- Engine 1 stood at (-28,624,-308.5) for 300 s with six crew idle on their slots and one crewman (m40) walking 0.8 m
  from his slot at (-27.7,-306.2) and never arriving. Writing that one man's position to his slot (`+0x910`/`+0x918`,
  the way the third-person pack's `P.place` does) made the engine walk within a second: 24 m along the walkway and up
  the roof step to (-4,629,-314.7) in 20 s, crew following in formation. The roof step itself is passable.
- Engine 2 at the right stair top (31.5,624,-304.5): six of seven crew walking to slots at z -297.7..-302.8, north of
  the stair edge at z -304.5, standing on the edge line. Engine 7 the same at (35.8,-304.5). Engine 5 on the roof at
  (15,629,-307.3): four crew idle ON THE GROUND at y 609 with slots projected to the ground beyond the roof's north
  edge; they went down and stayed. Redirecting the crew walks in place was undone within 25 s: the engine rebuilds
  the crew walks from its slot table.
- Slot table on the body (vtable `exe+3ad3360`, the engine body class; 44 slots differ from the man's `3912950`):
  count at body `+0xc1c`, array at `+0xc20` (one pointer per slot; the slot's `+0x10` is the man, `+0x20` his point),
  rebuilt by `exe+306c298(body, 0)` when the count is short of the crew count `+0xb64` (crew array `+0xb68`) or the
  body's state `+0xcfb` changes; `exe+30783fc(slot+0x20, man, body, flag)` places a man on his slot. Both are called
  from the body's placement override `exe+3077ee4` (vslot `+0xe8`) and from `exe+30785e0` (vslot `+0x478`).
- The engines' walks are stopped and re-issued continuously by the unit's formation movement (`'stop'` hook on
  `exe+306edf8`: 450 calls in 70 s from the HALT action start `2f700f8` under the action runner `3088218`; `'post'`
  hook on vslot `+0x4a0` `exe+30751e4`: 5,359 action posts in 80 s). That churn is normal and not the fault.
- Not the cause: path state (4 throughout), the walk update's entry gate `30595b0` (an animation check), `+0xdc`
  (a minimum-speed state set by `308cee8` once the entity moves), the roof step, the planner's link permission.

**Trap:** a 100 ms poller that ran `gsub`/`sub` on strings crashed the game in `string.sub`
(`memreader_crash_report_011126_1524.txt`, 15:37): keep the game's string library out of fast callbacks, build tags
with `..` and `mr.tostring` only.

## The slot table decoded, the crew rule shipped, and what the descent turned out to be (16:00-16:55)

The slot is 0xb0 bytes, created by `exe+3061d80` from a template table on the body (`+0xcbc` count, `+0xcc0`
array, 0x50 stride) through `exe+305289c`:

| slot field | meaning | written by |
|---|---|---|
| `+0x00` | kind (0, 1, 2 for the three at the engine's sides; 23/24 for the four pushers) | template |
| `+0x10` | the man | `exe+306c298` (assigns free crew to empty slots) |
| `+0x20/+0x24/+0x28` | offset from the engine, metres (pushers at z -6.2) | template |
| `+0x30/+0x34/+0x38`, `+0x40` | the point resolved on a surface, and that surface | `exe+3086a80`, every tick from `exe+308de70` |
| `+0x80` | the resolution succeeded | `exe+3086a80` (off a wall: `exe+1431213dc` must accept the point; on a wall, `exe+14310cfac` always does) |
| `+0x81` / `+0x82` | the man is within 0.25 m of the point (`_DAT_143922140`) / facing it | `exe+3086e0c` |
| `+0x83` | the slot could not be resolved; `+0x81`/`+0x82` are then forced on and the point is the engine itself | `exe+3075bc8` |
| `+0x84` | slot enabled this tick | `exe+308de70` |

`exe+3075bc8(slot+0x20, man, anim, speed)` drives the man (returns 1 when it issued a walk or a turn);
`exe+3074270` runs it for every manned slot each tick and posts the manning animation (`exe+3070950`) once he is
there. The gate that holds the engine was never found in the code (the readers of `+0x81` are the two above and
the writer), but it was confirmed a second time the cheap way: engine 2 on the walkway with four crew 0.26-2.2 m
off their slots (men jittering against the battlements, one on a stair step at y 625.5) stood for minutes, and
writing those four men's `+0x910/+0x914/+0x918` to the slot points made it walk 8.1 m to its goal in the same tick.
Engine 5 on the gatehouse roof's edge was the other shape: its four pusher slots unresolved (`+0x83`), the men idle
on the ground 20 m below with their slot points projected through the roof, and placing them at roof height with the
roof's surface pointers was undone by the next tick (they were back at y 609 within 27 s) - a man cannot be put
where the walkway is not. Marking those slots resolved (`+0x80`) was rewritten by the next tick too.

**Shipped in `crew_step` (`derpy_artillery_walls.lua`, pure, tested):** per engine standing still (under 0.25 m
in 500 ms) under a move order or a wall order, a crewman on a resolved slot he is not on, whose x/z distance to the
slot point has not fallen by 0.25 m in 2 s, is written onto the point (x, y, z); over 8 m off or more than 3 m above
or below it he gets 20 s instead, and that clock does not reset while he closes, because a man walking along the
wall toward the stair closes in x/z the whole way. An unresolved slot gets nobody. `update()` reads the slot table
every 500 ms for every engine of every listed unit (the body's `+0xc1c/+0xc20`, `SLOT` in the Lua) and logs
`placed a crewman on his slot`.

**Measured cold, shipped Lua only, this battery of eight bolt throwers from (-45,-275) to the roof point (1,-314) and
back:**

| pack | climb (engines up / every crewman up, s after the order) | recoveries on the climb | descent |
|---|---|---|---|
| 9C5C (before) | 145 s, three crew per engine, after a nudge and a drop | nudge + drop | nudge + drop at 70 s |
| D4B9 run 1 | 124 s, 56/56 | none | nudge + drop at 68 s |
| D4B9 run 2 | engines up at 45 s; two crew never came up; drop at 136 s | nudge + drop (for two crew) | nudge + drop |
| D4B9 run 3 | two engines parked at the gatehouse's foot (x 3-6, z -300) 40 s; drop at 101 s | nudge + drop | mover OFF: seven parked at 56 s, see below |
| 1B74 run 1 | 55 s / 73 s | none | nudge + drop at 68 s, second drop at 102 s for four crew left on the wall |
| 1B74 run 2 | 53 s / 90 s | none | **walked down natively, all down at 85 s, no recovery** |
| 29D2 run 1 | 95 s / 110 s | none | not measured: the author took the mouse (wall-zone clicks from 243800) |

Placements per climb: 80-190. They are small hops and the climb no longer needs a drop in five runs of six; the one
that did (D4B9 run 3) was two engines parked at the gatehouse's base with their crew beside them, which was not
examined live and is open.

**The descent is a different fault.** With the mover off (D4B9 run 3, ground order at 781700): every engine got a
walk (path state 4, the regiment walk `3919350` then its own `3ae2400`), moved along the walkway toward the stair at
x 29-36 for 10-25 s, and then seven of eight ended in **cmd stand `39126f0`, path state 0, every crewman on his
slot (`+0x81` set, distance 0.0)**, three of them with a goal (`+0x7f8`) that was a wall point (28,624,-313 /
-8,629,-318 / -19,629,-313), not the ground. The eighth, the one standing nearest the stair top, went down it to
the ground. A new ground order 90 s later, at width 6 so the line would fit the walkway, moved none of the seven
(`+0x330` stayed stand). So on the way down the crew gate is not it: the engines' walks END short, at a point the
unit's path gave them on the wall, and a re-order does not restart them - which is why the nudge never worked on a
descent and the drop always did. That is the unit-level path (the formation's waypoints over the stair link for
engine bodies), not the entity's, and it is the next RE target. In 1B74 run 2 the same battery walked down
natively in 85 s, so the path exists; what decides whether the engines take it is open.

## Other races' artillery, 17:05-17:50 (pack 29D2, shipped mover)

`tools/make_practice_battle.py` writes the player's army into the saved practice battle (`.singleplayer.battle_preferences`,
format in its docstring; the lord copied raw from the faction's own `army_setups` file, `--restore` puts the original
back) and `probes/artwalls_races.lua` runs every artillery unit of the army up to the roof point and back, one at a
time, 150 s cap each way, writing `races_<race>_29D2.txt` beside the script log. Batteries of four engines; seconds
after the order until every engine, then every crewman, is up or down; "cap" = not within 150 s.

| unit | up: engines / all | down: engines / all | recoveries (from the log) |
|---|---|---|---|
| Dwarf cannon | 57 / 117 | cap / cap | two wall transfers on the climb; the ground order never took (below) |
| Dwarf grudge thrower | 105 / 105 | 62 / 62 | nudge, nudge, drop; nudge, drop |
| Dwarf organ gun | 118 / 118 | 63 / 63 | nudge, nudge, drop; nudge, drop |
| Dwarf flame cannon | 41 / 110 | 38 / cap | none |
| Empire great cannon | 33 / 62 | 62 / 62 | nudge, drop |
| Empire mortar | 36 / 85 | 66 / 88 | wall transfer, nudge |
| Empire helblaster | 130 / 130 | 74 / 74 | nudge, nudge, drop; nudge, drop |
| Empire helstorm | 43 / cap | 62 / 62 | nudge x4, drop |
| High Elf eagle claw 1 | 119 / 119 | 62 / 62 | nudge, nudge, drop; nudge, drop |
| High Elf eagle claw 2 | 41 / 48 | 56 / 77 | none |
| Dark Elf reaper 1 | 55 / 88 | 66 / 86 | nudge |
| Dark Elf reaper 2 | 31 / 48 | cap / cap | wall transfer, nudge, wall transfer (below) |

So every race's battery gets up, and most get down, but on this map half of them get there by the mover's drop
rather than on their own: the crew rule alone is not enough for a four-engine battery either. Two things seen here
and not in the Chaos Dwarf runs:

- **A wall MOVE on a four-engine battery sometimes becomes a native wall-zone controller** (`ctl1`, the mover's wall
  mode fired its transfer on the Dwarf cannon, the Empire mortar and the second Reaper), where the eight-engine CHD
  line never did. Whether that is the line fitting the walkway or the race, not measured.
- **Under that controller the probe's ground order did not take.** `halt()` then `goto_location_angle_width` through
  a scripted unitcontroller left the unit on the wall for 150 s and the mover in wall mode (the Dwarf cannon, then
  the second Reaper with the halt added), so those two "cap" descents are the harness's order, not the engines. A
  player's click replaces a wall-zone order; whether the API order does is open - the scripted drop (`'stuck'`) uses
  the same route.
- The battle was paused and sped up by hand during the Dwarf and Empire runs; the times are battle time, unaffected.

## Open

- A four-engine battery's wall MOVE turning into a wall-zone controller, and a scripted ground order under it being
  ignored (above): measure with a real click, and if the API order is what fails, the probe and the mover's
  `'stuck'` walk both need the player's route.
- **Descent:** seven of eight engines end their walk in stand on the walkway with their crew on their slots and a
  wall point for a goal (above); the drop still finishes every descent. Find the unit path's waypoint assignment
  over the stair link for engine bodies.
- Two engines parked at the gatehouse's base with their crew beside them for 40 s on a climb (D4B9 run 3, x 3-6,
  z -300); not examined live.
- The lift clock (20 s) and the mover's own detectors (20 s quiet, nudge, 20 s more, drop) run on the same scale: a
  crew left on the wall over a dropped battery is lifted at about the time the second drop would come. Measured once
  (1B74 run 1, before the far clock stopped resetting); not re-measured after.

- A recovered battery is a one-rank line centred on the point; the queued MOVE that follows re-forms it the way the
  engine places a wall MOVE, a 65 m line that starts near the point and runs along the wall (x -1..64 for a click at
  x 1 in 9C5C). That is CA's placement for a line too long for the roof section, not ours.
- The re-order works 1 time in 5 on a parked engine, and the section above says why: on a climb the engine was
  waiting for a crewman the re-order does not move (the crew rule now moves him); on a descent the walk had ended
  in stand and the re-order does not restart it.
- The engines still walk badly: they queue behind their crew, wedge at the stair foot and in the gate passage, and
  shuffle at wall edges. That is CA's planner on entities it never routed over links. "Walk like infantry" on the way
  down would need the planner's link permission for engine bodies found and scoped; `305952c` (slot a0, shared by men
  and bodies) is already patched and is not it.
- Roof line of sight and firing from the roof remain untested (unchanged from the previous handoff).
- Width of a recovered formation: one rank of `engines x 6` m. Fine for eight bolt throwers on open ground; not checked
  against a narrow landing.

## The open-item battle (pack 5637, 17:58 launch): firing, abandonment, the standing crew jitter

Evidence `Modding Files/Backup/artillery_walls/20261101/items_5637_u3_trace.txt` and `script_log_items_5637.txt`;
probe `probes/artwalls_items.lua` (AWI: arm the abandonment caves, 1 s trace, a timed fire-at-will window, a
mover-off descent under PK).

- **A clean native climb leaves the wall controller on the unit for good.** The eight-engine bolt thrower climbed
  on `AW.move` with no recovery (first engine up at 102 s, all eight at 124 s, 56 crew up), to the gatehouse ROOF
  at y 629 z -321, not the walkway at 624 - and `+0x3300` stayed the wall vt (`143911218`) for the 1,300 s the
  battery then stood there. A halt did not clear it (read straight after the halt); only after the mover's own
  `(stuck)` drop was `+0x3310` zero.
- **The crew rule runs under that standing controller: 13,528 placements of mean 0.79 m (max 6.0 m) while the
  battery stood on the roof**, 12.8 a second, against 420 during the climb. `update()` returns early only when
  neither the player's MOVE is active nor the wall controller is on, so an arrived battery is "in flight" for ever
  and every crewman who idles 0.3-1 m off his slot is snapped to it every two seconds. The gate the rule needs is
  the ENGINE's state, not the unit's: the standing engines read cmd `3AD3A40` done 1 path 0; the walking vehicle
  read own-walk `3AE2400` done 0 path 4. Pack 4595 writes cmd/done/path into every placement line so the parked
  (waiting-for-crew) case can be read off the next climb before the gate is chosen.
- **No shot from the roof.** Four 40 s windows at y 629: fire at will with the enemy inside at (0,-170); attack_unit
  with it at (0,-200), 101 m, visible; fire at will with it outside at (0,-502), 180 m, under the wall controller;
  attack_unit after a halt (controllers 0). Ammunition 176 throughout. The 9C5C battle fired 176 -> 160 from the
  WALKWAY at (28,624,-315) at an enemy in the same place. Roof vs walkway is the one difference measured so far;
  the next battle puts a battery on each.
- **Abandonment's natural trigger is ammunition 0, and the cave caught it.** After the `(stuck)` drop to the wall
  base (y 609, z -325, inside) the battery emptied 176 -> 0 in 400 s at the enemy outside at (0,-502) - so the
  ground inside the wall has a shot the roof does not - and in the same second as ammunition 0 the eight engines
  became 56 primaries: `3065744` hit 56 times, once per crewman, rcx = the crewman, rdx = r8 = 0, caller chain
  `311001E 30118FA 3036359 3011C69 30339BB 3043508 2E4DA77 3073BED 307AD77 308B388 30348E0 306E4CC 3034838`.
  `3065a94` never hit. The mover then reads the unit as infantry (`inf=true`), which is right.
- The magma cannon and the deathshrieker are ONE entity each (`+0xa4` = 1, `+0x184` = 1): a vehicle, no crew
  slots, and a wall MOVE sent the cannon on a 600 s walk round the far side (z +139) that never reached the wall.
  They are not a test of the crew rule or of item 1.

## Battle two (pack 4595, 18:14 launch): the terrace jitter the stall detector cannot see

- The same `AW.capture(2)` point as battle one, (-133,654,-253) on the upper city's terrace, sent the battery the
  OTHER way this time: north round the pyramid and up the terrace ramp (y 652 at z +60 by 407 s), where it parked
  on the 641 ledge at (-82..-104, 641, -205..-235) with regiment-walk goals on the ground 32 m below (14,609,-210
  and the like). A second `AW.move` to the walkway (captured off u2 teleported to (28,-315): (27.4,624.5,-314.9),
  surface id 1366) re-pointed the order; the engines kept the ground goals and sat on the ledge for 640 s.
- **The parked engine is not still: it jitters.** PK at 500 ms over the last 30 s: every engine wandered 3-5 m in x
  and 1-4 m in z and its heading swung through the full circle (`+0xb0` samples 35..65390). `stalled()` counts a
  body as moved when it shifts 0.25 m or turns more than 182/65536 between reads, so the clock restarts every
  half second and no `nudge` or `stuck` ever fires: the mover logged nothing for 640 s with the MOVE active.
- **Nor is it a crew case.** The three side slots are manned (men idle on them, `9198C8`, path 0); the four pusher
  slots (kind 23/24, ~5 m behind the engine) read resolved and unmanned, their men in regiment walk 3-7 m off.
  Writing all four onto their points left `+0x81` zero at the next read and the engine jittering the same (+1 s
  -103.3, +6 s -100.8, +12 s -103.9): the slot points move with the engine, so the men can never settle. All 577
  crew placements this battle were on engines in a walk (504 regiment walk, 73 own walk, done 0 path 4), none on a
  standing engine - so the done byte separates the two cases the rule has to tell apart.
- Open: what the engine's path is doing on the ledge (PK rows kept: cmd, path, goal, walk target per 500 ms), and
  whether a stall detector on the CENTROID over a longer window (position span under 6 m for 30 s) would catch it
  without catching a slow climb.
- **Firing from the wall: eight windows, no shot.** Mover off, the battery teleported onto the gatehouse
  (`teleport_to_location(28,0,-315)` put the eight engines on the walkway at 624 and the roof at 629, all `+0x920`
  set, 56 crew up), the enemy outside at (0..14, 620, -487..-501), 170-185 m: `missile_range()` 320,
  `unit_in_range` true, `is_valid_target` true, visible true. Fire at will for 60 s: 176. `attack_unit` on the
  spearmen for 40 s: `current_target()` held the spearmen, `is_idle` false, 176. A wall MOVE walking them 40 m
  west along the roof with fire at will on: 176, the target picked up for one 3 s sample and dropped. With battle
  one's four windows from the roof, that is eight windows and two command states without a shot; the single
  firing on a wall ever recorded (9C5C, 176 -> 160 from the walkway) stays unexplained. `is_limbered_artillery`
  and `is_unlimbered_artillery` both read false on the walkway. A firing gate in the engine is the open question
  (item 6 stays open).
- **The descent, recorded at 500 ms (PK, mover off), ground order (-45,-275) width 50 at 2786600 from the roof
  and walkway.** Every engine took the order the same way: regiment walk `919350` path 4 at +1.3 s with a ground
  goal and `w3c0` 830000, own walk `AE2400` path 4 at +3.3 s with `w3c0` 830001, two to five metres of movement -
  and then, by +13 s, seven of eight were in stand `9126F0`, `cmd_done` 1, path 0, the walk target's x zeroed
  (`+0x368` 0 with `+0x370` still the goal's z) and the goal (`+0x7f8`) still the ground point. The order stayed
  active (`act_has` 1) for the 190 s watched and nothing re-issued the walk. The one engine that went down,
  e2, stood at the right stair top (28,624,-312) when ordered, was on the ground at +6 s and walked to the point
  (arrived +210 s, stand with `wait` counting). e7 walked WEST to the left stair top (-29.6,624,-308.8) and
  stopped there in stand, so reaching a stair top is not what ends the walk; e1 and e3 stopped after 2-5 m on the
  roof behind it. Whoever ends the own walk early, with the x of the walk target cleared, is the next thing to
  hook (the stand command's constructor is too generic; the walk command's completion path at `+0x330` is not).
- **A second ground order does not reach a parked engine at all.** Re-ordered to the left stair foot (-32,-298)
  at width 6 at 3311300: the seven parked bodies kept the goals of the FIRST order (`+0x7f8` still
  (-34.9,609,-259.9) and the like 60 s later), stayed in stand, `act_has` flickering 1/0; only e2, on the ground,
  walked to the new point. So the unit's order is not being turned into body goals for a body in this state, and
  that is why no re-order (width 50 or 6) ever moved a parked descent. The formation-to-body goal write is the
  thing to hook next (whoever writes `+0x7f8`), with a parked body and a walking one side by side.
  Evidence `items_4595_pk_descent.txt` (PK rows, 4,675 samples) and `items_4595_u3_trace.txt`.

## Altdorf (major_a_emp, pack 4595, 18:33 launch): the pyramid is the hard map, not the rule

`tools/make_practice_battle.py --map major_a_emp` (the map key is the one string at offset 4; the tile key after
it, `settlement_towers_level_2`, was left and the battle loaded). The player defends; nobody stood on a wall in
Deployment (`AWI.find_walls()` over the enemy: none), but the infernal guard's own man 1 did once Deployed, at
(665.4,106.6,-324.8), surface id 2328, and `AW.capture(2)` took it. Evidence `items_4595_altdorf_trace.txt`.

- Bolt thrower from (640,-285): five engines up at 14 s, all eight at 41 s, 48 crew up then, under the wall
  controller, no recovery.
- **It fires from this wall**: the first shot the second all eight were up, 176 -> 31 in 320 s at the enemy at
  (650,-620), 280 m, with the 320 m range. The pyramid's gatehouse roof and walkway never fired in eight windows.
- Ground order with the mover on: every engine down natively in 25 s, every crewman in 55 s, formed at the point
  in 65 s. The pyramid's descent parks seven of eight.
- Standing on this wall the engines read cmd `3AD3A40` with done 0 and path 0 (626 placements on them before the
  gate), so `+0x340` is not the standing/waiting discriminator; `+0x710` (path state) is: 0 standing on both maps,
  4 on every engine a placement ever freed. **Pack 2886 gates the crew rule on `e.path ~= 0`**; the test file
  carries the no-path case and the mutant without the gate fails it.

## Dwarf cannon, real right-click (pack 2886, 18:42 launch, black pyramid)

Real input through `Modding Files/source/lord_control/probes/tp_mouse.ps1` at the screen centre, the camera's
look-at set to the point first (`bm:camera():move_to(above, point, 0)`), so no world-to-screen projection was
needed. Selection by the unit card (`battle_orders > battle_orders_pane > card_panel_docker > cards_panel >
review_DY > 1003`, state `selected`); a real left-click on the engines missed twice from 70 m up.
Evidence `items_2886_dwf_click_pk.txt`, `items_2886_dwf_click_trace.txt`.

- Control: a right-click on open ground gave the cannons a MOVE (`14390DD00`), engines walking. The real input
  path works.
- **The walkway (28,624,-315) refused the cannons twice** (no order, `+0x2f88` 0), while the same click with the
  released longbeards selected gave them a MOVE. The mod's own queue route (`AW.move`) takes the Dwarf cannon to
  that walkway (the races run, 57 s). So the native click path still says no to a battery on the walkway
  somewhere the `cursor` cave does not reach, or the walkway's zone is too small for four engines; the roof says
  yes: **the gatehouse roof (0,629,-313) gave a native wall order with the wall controller** (`143911218`),
  order vt `14390E150`.
- Under that order every engine held an own walk (path 4, roof goals) and stood still for 350 s before moving;
  then all four were up in 25 s. The crew rule logged 582 placements on path 4; what held the engines those 350 s
  is not in the PK fields (crew were all near their engines at the start). Open.
- **The far-crew lift loops.** Eight slots per Dwarf engine (3 side, 5 pusher). Once the engines were up, ten
  pushers of engines 3 and 4 were 290-370 m away at (15,620,-20) and (24,632,60): their paths to the roof went
  round the pyramid the long way, the same route the vehicle took. The 20 s lift put each on his slot and his
  walk carried him straight off again (crew up 19 -> 9), lifts of 90-490 m every 20 s (bucket means 140-335 m,
  n = 120-130 per 50 s), until the paths finally resolved and all 32 were up at 848 s. A lift has to end the
  man's walk as well as move him: writing the man's walk target (`+0x368`/`+0x370`) and surface (`+0x378`) to
  the slot is the candidate, untested (the far men were already settled when the experiment ran).
- The `+0x81` manned flag is x/z only: engine 3's three side crew stood 20 m BELOW their slots on the ground
  (2,609,-307 against 2,629,-307) and read manned.

## Open after the open-item battles (18:00-19:00), in the order of the list the user asked for

1. Descent on the pyramid: a parked body's own walk ends within 13 s with the walk target's x cleared, and a
   later order never rewrites its goal. Hook whoever writes `+0x7f8` and whoever ends the walk. Altdorf descends
   natively in 25 s, so this is the gatehouse geometry, not the rule.
2. Climb drops on four-engine batteries: not reproduced today; the Dwarf roof click climbed clean after a 350 s
   stand nothing in PK explains.
3. Real click: the roof takes a four-engine battery with the native wall controller; the walkway refuses it while
   taking infantry. Where the refusal is (before the `cursor` cave) is the next RE question.
4. The far-crew lift loops every 20 s until the man's path resolves (90-490 m hops). Write the walk target and
   surface with the lift, then measure.
5. Maps: Altdorf is clean end to end (climb, fire, descend); the pyramid is the hard one. `--map` on
   `make_practice_battle.py` makes the next one cheap; `AWI.capture_unit` finds a wall off any unit's man.
6. Firing from a wall: works on Altdorf, never from the pyramid's gatehouse roof or walkway (eight windows).
7. Placement acceptability: with the path gate the standing jitter is gone (0 placements on standing engines
   in the Dwarf battle); walking placements are 0.5-6 m hops; the far lifts are item 4.
8. Abandonment: the trigger seen is ammunition 0 (`3065744` once per crewman, rdx = r8 = 0); the wall-order
   abandonment of earlier sessions did not recur in four battles with the caves armed.
9. Not published.

## Altdorf again, for the Workshop clips (21:00-21:20): an attack order on a wall battery trips the stall recovery

Empire great cannon and helstorm, both up on the 111.6 section by `AW.move` to the swordsmen's man 0 at
(629,111.6,-333.6) in 56 s (the lower 106.6 deck, surface 2328, is where the bolt thrower fired from). `attack_unit`
on the goblins made the deck engines shuffle along the wall; 35 s later the mover logged `recovering stalled ...
(nudge)` for both and 30 s after that `(stuck)`, and both batteries were back on the ground at y 90. The helstorm
got one volley off from the tower stair before that. With the mover removed (`derpy_artillery_walls` and `_exit`),
fire-at-will alone, fire-at-will plus `attack_unit`, the enemy at 130 m and at 280 m, and a second `AW.move` to the
106.6 point (the engines stayed on 111.6 bar one): no shot in six bursts, ammo 85 and 234 throughout. Open: why a
battery on the 111.6 section never fires when the bolt thrower on 106.6 did, and the recovery must not treat the
shuffle an attack order causes as a stall (it is the one order a player gives a wall battery).

## Fix for the attack-order drop (22:00, pack F2DAF923, game shut)

The mechanism is in CA's own doc: `unit:ordered_position()` "if the unit is attacking, as opposed to moving, then
this will return the current position of the unit" (battle_unit.html), and the order struct still reads as a MOVE, so
under `attack_unit` the mover saw an order at the unit's own ground-height centre with every engine on a wall, i.e.
on the wrong side of a ground order: `parked` after NUDGE 30 s (the nudge at +35 s), `stuck` 30 s later (the drop at
+65 s). `exit_step` now returns at once when the ordered point is within `ATTACK_HOLD` 1 m of the unit's own position
(`ux`/`uz` passed from `update()`); a unit standing on its ordered point has nothing to recover whatever its engines
stand on. Test: `tools/artillery_walls_tests.lua`, a battery on a wall under an order at its own point through 120 s
returns nothing, and the five-metre control still nudges; the mutant without the guard fails at line 63. Checks:
`luac -p`, `check_lua_api` 0, `check_lua_literal_left` 0, `gen_artillery_walls.py --check` ok, the Lua read back
out of the saved pack byte-identical to the source. **Not live-tested**: the game was in use by the Resource
Overhaul session. The live check is the Altdorf route above: both batteries up, `attack_unit` on the goblins, no
`recovering stalled` line in 120 s and ammo falling.

## Live check of the fix and the no-fire, Altdorf (22:25-22:36, pack F2DAF923, script_log_011126_2224)

One in-game script (`probes/artwalls_fire.lua` + an orchestrator over the bridge) ran: wall order to the 111.6 point
for both batteries (up in 22 s), then A: `attack_unit` as arrived, 60 s; then B: the unit teleported onto its own
centre facing the target, `attack_unit`, 60 s. Then a one-minute heading-write test.

- **The fix holds.** Two attack orders on wall batteries, 120 s, zero `recovering stalled (nudge|stuck)` lines; the
  log's only two recoveries are `(wall)` - the wall transfer, after the B teleport put the units under the native
  wall controller. Under the old pack the same order dropped both batteries at 65 s.
- **Where a gun fires from:** the engines fired only once the wall recovery had put them on the native wall slots at
  the deck EDGE (z -339 on the 106.6 deck), heading 180 (outward). On the 111.6 section and mid-deck (z -323..-333),
  spread by the `AW.move` placement, neither battery fired in A (ammo 88/228 -> 88/219, the helstorm's one volley).
- **Only one engine per battery fires.** From 378 s to 988 s the great cannon spent 23 rounds, 2.3 a minute = one
  engine's reload; 988-1342 s, 14 rounds, same rate. Headings at the edge: e2 201 = bearing 201 (off 0), the other
  three 180 (off 17-24). The engines that do not face the target within roughly 15 degrees never fire, and the
  `noarc` cave is what keeps them from turning (that is its job: the native re-face re-planned and walked the
  formation). The author saw the same from the camera: one cannon and one rocket battery firing.
- **The attack order itself turns and walks them:** at A end every great cannon engine read heading 103 (along the
  wall, 71-81 off) after 20-40 m along the deck; the B teleport with facing 178 landed every engine at heading 90 (the
  wall placement forces along-wall); the attack then walked u3 to x 684-698 and u4 to x 570-598 over 60 s, where they
  settled at 180.
- **Writing the heading does not hold.** `+0xb0` written to the bearing every 2 s for 60 s (240 writes): the engines
  read 178-208 again at the end, u3 fired 3 rounds in the minute (baseline 2.4). The facing is owned by the engine's
  behaviour, not that field.

So the no-fire is two things: placement off the native slots (the wall recovery fixes that by accident; the arrival
should put engines on the slots at the edge directly), and the frozen arc that lets only the engine already on the
bearing shoot. The fix for the second is in the exe, not Lua: `noarc` (exe+328507c) must allow the turn-in-place and
block only the formation re-plan that follows it. Open, with the pyramid descent (item 1).

## The ground order that never took (22:40, pack 3E35974D): the mover was crashing every tick

The author ordered both wall batteries to the ground. One engine of each got down (great cannon e4 at (666,91,-306),
helstorm e3 at (594,91,-305)), 41 of 43 and 42 of 44 men stayed on the wall, the MOVE order stood (orders 1,
controllers 0, move vtable, ordered point (598,91,-281) on the ground, 73 m off) and nothing moved for minutes. The
log had the answer: `movement recovery read failed: failed to read memory` twice a tick from battle time 1,799 s,
2,632 lines by 2,731 s - `update()` threw inside the per-engine crew-slot read and the pcall around it discarded the
whole tick, so `exit_step` never ran and no nudge or drop could come. Which read is not pinned (the game was
handed to another session before a per-field probe); the one thing different from every earlier tick is an engine
down off the wall with the rest still up. Fix: the slot loop of each engine runs in its own pcall, a null table or a
count outside 0..`SLOT_MAX` (32) is refused up front, and an unreadable engine goes in with no crew and one log line
per engine (`crew slots unreadable`), so the bodies list and the recovery stand. **Not live-tested.** The live check
is this exact state: both batteries up, a ground order, one engine down; expect `crew slots unreadable` once per
affected engine, then `(nudge)` at 20 s and `(stuck)` at 40 s, and the whole battery on the ground.
`check_lua_undeclared` reports `DERPY_AW_TEST`, the test hook, as before.

## The split the attack guard silenced (2026-11-02 07:46-08:15, pack 3E35974D then A9099DA4, Altdorf)

The 22:40 state reproduced on purpose with `probes/artwalls_split.lua` (`SP.run`: wait for every engine up, give the
ground order through the unit's own controller, sample both batteries every second, and on a split read each
engine's slot table one field at a time): both batteries up by `AW.move` to the swordsmen's man at (629,111.6,-333.7),
ground order to (598,-281) at 260 s, and the great cannon stood three engines on the wall over the fourth, down AT
the ordered point, for 180 s with no recovery line. **No read failed.** Zero `movement recovery read failed` and
zero `crew slots unreadable` lines; the per-field probe found every slot table readable through the split. The
22:40 crash is not reproduced and its guard stays, but it was not what blocked the battery.

What blocked it: `unit:position()` read (597.9,91.1,-281.0) against `ordered_position()` (598.0,91.1,-281.0) - the
unit's position snaps to its ordered point once ONE engine reaches it - so the `ATTACK_HOLD` guard of F2DAF923 read
the split battery as attacking and returned before any detector ran. Control in the same battle: the cannon
re-ordered 6 m away (604,-281); the down engine walked there, the position snapped onto the new point and the
guard went quiet again, no nudge in 144 s. (Then, unexplained: at 1517-1537 s the battery walked back UP to the deck
edge at z -339 and a `(wall)` recovery followed at 1560 s, and the helstorm, on the ground under `attack_unit`, got
one at 1721 s; neither was ordered onto a wall. Noted, not examined.)

Fix (pack A9099DA4): the guard holds only when every engine is up, `s.ux and up == #s.bodies and ...`. A battery
standing on its own point with every engine on a wall is the attack case; one with an engine down is a ground order
that took for one engine. `tools/artillery_walls_tests.lua`: `split()` (one body down at the point, one up, the unit
0.1 m off its point) must nudge at 20 s and drop at 40 s; the mutant without the `up` condition fails it at line 6.
Live, fresh battle (script_log_021126_0806, `split_A909_trace.txt`): ground order at 241 s, split at once (u3 3 up
1 down), `(nudge)` both batteries at +30 s (the parked detector), `(stuck)` at +60 s, and at 303 s every engine
and every crewman of both batteries on the ground at z -288/-289. The author's "cannot move all of the units when a
few get down the wall" is this.

Also measured: a controller `attack_unit` order's struct has its own vtable, `000000014390D2F0`, not the MOVE
`14390DD00` - so the mover's `active` test already ignores a plain attack order, and the 21:00 drop came through a
MOVE the attack generated (artillery out of range walks); `unit:current_target()` returned nil under that attack
(the target 340 m off, the unit walking to range), so it is no discriminator. The wall order's climb nudged each
battery twice 20-30 s apart before the helstorm's `(stuck)` wall teleport: the re-queued MOVE comes back with a new
`ordered_bearing`/`ordered_width`, which changes `parked_key` and resets `nudged`. Harmless (a re-click), noted.
Evidence: `split_3E35_trace.txt`, `script_log_split_3E35.txt`, `split_A909_trace.txt`, `script_log_split_A909.txt`.

## Wall firing measured per engine (2026-11-02 08:35-09:15, pack A9099DA4, Altdorf, the rematch battle)

Instrument first, found by snapshotting a body every 500 ms through its turn and diffing firing against silent
engines (`probes/artwalls_arc.lua` has the zone, slot and heading readers; the fire-state watcher was inline):

- **Per-engine fire cycle:** body `+0xce0`/`+0xce2`/`+0xce4` (u16) and `+0x3e8` (u16). Idle `4/0/20/0`; the shot
  `52/11/52/1` (`+0x3e8` = 1 for about 2.5 s); reloading `20/1/52/0`. An engine stuck at `52/1024/52/0` never fires.
  Count shots by the `+0x3e8` pulses; unit ammo (2.3 rounds a minute per firing cannon engine) cannot say which engine.
- **Aim goal:** body `+0x1e0` (position) and `+0x1ec` (heading u16) are the engine's goal record; the attack writes
  it about 5 s after the order with that engine's own bearing and the body turns to it over 3 s. `+0xd98` is an output
  copy of the heading: written to the bearing every 500 ms for 90 s, nothing turned.
- The BCQ_FIRE_PROJECTILE handler `exe+2ecfd54` saw none of seven cannon shots: it is the script launch path only.
- No static writer of `+0xce0`/`+0xce2` (`exe_re.py stores/writes`): the fire state is reached through a pointer.

What fires from the Altdorf wall, target straight out at bearing 180, 200 m, so no engine had to turn (`fw3` in
`firing_A909_trace.txt`): the great cannon's e1 (y 108) and e3 (y 107), on the 106.6 deck, cycled and fired (7 rounds
in 97 s); e2 (y 112, the 111.6 section), every crewman manned, sat in state 1024 for the whole 100 s; e4 (y 112) sat
idle with three of eleven crew unmanned. The three off-axis runs (bearing 204-207) match: the engines that turned and
fired were the 106.6 ones. **The 111.6 section stops a cannon's shot** (the 22:25 finding, now per engine), so for a
direct-fire gun the deck it stands on decides, before the arc does. The helstorm fired only its e1 (3 rockets every
20 s, from y 112: indirect fire clears the section); its other three engines had crew standing 220 m away.

**Teleports leave stale crew slots**, which confounds every teleport-based firing test: a teleported engine's slot
points stay where it left (u3 e4's slots 0-2 pointed at the deployment spot (623,102,-191), 150 m from the men
standing beside the engine on the wall), and the men still standing at the old spot keep "manned" slots there. Only
a natural climb (`AW.move`) is a clean setup, and under it (22:25) nothing fired from the 111.6 section either.

The frozen arc (`noarc`) still matters at 25 degrees off: with the target at 204-207, one to three engines got a goal
and turned, the rest held 180 with none, and what picks them is not pinned. A controller `attack_unit`'s order
struct carries its own vtable (`14390D2F0`, not the MOVE); `unit:current_target()` read nil under it at 340 m.

Next for firing: trace the engine's attack update (body `+0x330` cmd object) in Ghidra to the writer of the 1024
state and its condition, and test whether `hold` (327ebc8) is what leaves an engine there (an engine that wants to
relocate for a shot and may not). Evidence: `firing_A909_trace.txt`, `script_log_firing_A909.txt`; the first battle's
rows are in the same file (`AWA.rows.*`).

## The cannon fix: the engine's clear-shot test (2026-11-02 09:00-09:40, pack C1FF3B2F, Altdorf)

State 1024 has a name. The engine's fire update `exe+308ae34` (it is the function that calls the projectile spawn
`309eea4`) runs a pre-fire test `exe+305eb74` on the first tick with a target when body `+0xcd9` is 1 (direct
fire; the helstorm never takes this branch), and when it returns false the engine logs the string "Clear shot
failed" (`exe+3ad22f0`), sets bit 26 of the flag words `+0xce0`/`+0xce4` (`ce2` reads 1024) and never fires from
that spot. The test builds a query from the muzzle (vtable `+0x3e0` with the weapon slot) to the target point at
body `+0xc38` with the body's `+0xc60`/`+0xc68` records and hands it to `exe+305f6c4`, a trajectory/line check
against the world. A cannon six metres behind the 111.6 section's parapet fails it; one on the 106.6 deck passes.
Its other caller is `3072b7c` in `30729d8` (the engine's relocate state).

- **`clearshot` cave at `exe+305eb74`** (rcx the engine body; displaces `mov [rsp+8], rbx`): a listed unit's body
  (`+0x2e8` in the block list) standing on a wall surface (`+0x920` not null) answers 1; everything else runs CA's
  test. Generator `ASM["clearshot"]`, three scenarios (listed on a wall 1, listed on the ground miss, unlisted miss),
  two breaks (the wall test inverted; answers blocked), 28 breaks caught; `--check` ok, Lua checks 0, pack built with
  every file byte-identical.
- **Measured before shipping**, test cave over the bridge in the running battle, natural climb by `AW.move` to the
  111.6 point (both batteries up with every crewman at 287 s after four `(nudge)` and one `(stuck)` wall recovery),
  `attack_unit` on goblin spearmen 207 m straight out: **all four great cannon engines cycled the shot state**
  (`52/11/52/1` on e1-e4), 17 rounds in 150 s, the goblins 160 -> 123 men, so the shots land past the parapet.
  Then the shipped pack, same route (`firing_C1FF_trace.txt`): the four engines fire in lockstep, 88 -> 76 rounds
  in 122 s, goblins 160 -> 115, and the battery had spent all 88 rounds by 1,280 s. Before the cave the same
  section fired nothing (22:25) or one engine.
- The teleport-based tests earlier this morning are confounded and were dropped: a teleported engine's crew slot
  points stay where it left (u3 e4's slots pointed at the deployment spot 150 m away, three men unmanned for ever),
  and an engine with an unmanned slot sits in `20/1/52/0` waiting for its crew. Only `AW.move` climbs are clean.
  The author watched one of these walks ("cant even move the cannons properly"): a teleported battery given a MOVE
  sent one engine the wrong way and left the rest standing - test damage, not the shipped behaviour.

**Open: the helstorm (rocket battery) never fires after the wall recovery.** It has no per-engine aim: its goal
record `+0x1ec` stays 0 and its engines never turn, so it fires only when the FORMATION faces within ~10 degrees of
the target (edge test: e1 at 180 and e2 at 191 fired at bearing 190; e3 at 205 off 180 did not). After the mover's
`(stuck)` wall recovery (teleport, then the queued MOVE) CA re-forms the line facing ALONG the wall (every engine
heading 90), and under `noarc` the formation never re-faces, so the rockets sit at 90 against a bearing of 186
for ever (`0/0/0/1` states, ammo 264 through 150 s, twice). The cannon survives this because each engine turns
itself (headings 170-175 from 90 within ten seconds). The fix is the arrival facing: the queued MOVE (`queue_move`,
command builder `2ea9a94`) carries no bearing, so CA picks along-wall; a player's right-click-drag sets a facing the
recovery then throws away. Either build the MOVE with the player's `ordered_bearing`, or put the arrived battery
onto the native wall slots (outward facing, at the crenels) - the zone pointer is the missing piece for the second.
A real right-click at the screen centre with the camera above (660,106.6,-333) landed on the ground inside the wall
and gave a plain MOVE (the helstorm walked down whole, all four engines at -277 in 100 s: the movement fix holds for
a player's order too); the wall-zone click was not reproduced from script today. The surface object at `+0x920`
carries no usable normal at `+0x28` (garbage floats); the wall controller's slot row does.

Evidence: `firing_clearshot_A909_trace.txt`, `script_log_firing_clearshot_A909.txt` (test cave), `firing_C1FF_trace.txt`,
`script_log_firing_C1FF.txt` (shipped), decompiles in the session scratchpad (not kept): `308ae34`, `305eb74`, `3055748`,
`3085c44`, `3264b70`, `3262850`.

## Why a wall battery stops firing: the attack order and the formation facing (2026-11-02 10:00-12:20, Altdorf)

Seven battles, natural climb by `AW.move` to the 111.6 point every time, goblins frozen 200 m out. The earlier
"rocket batteries have no per-engine aim" was WRONG: under fire at will the helstorm's engines take aim goals and
turn one by one exactly as the cannon's do. What decides firing is two things, both measured:

- **An explicit attack order kills firing on a wall.** Same battle, three stages of one variable
  (`firing` traces of the 11:20 run): fire at will with no order, both batteries fire (cannon 88 -> 84, rockets
  264 -> 228 in 60 s, every engine turned to the target); `attack_unit` on the same target, every engine stops
  within 2.5 s (fire state `52/256/52/1`), its aim goal resets to 90, and both batteries walk west along the wall
  and down the stair; halt with fire at will, the rocket battery fires again (228 -> 186). The `hold` cave does not
  stop that walk: `327ebc8` only builds the attack's executing sub-behaviour (0xd8 object, `FUN_14326a7d4`), called
  from `32739c0` when its plan reaches state 4. Zone + attack (the 10:58 run, both on CA's wall slots facing 180,
  rockets with aim goals) fired nothing for 150 s either.
- **Fire at will fires only when the FORMATION faces the enemy.** Engines aim within a traverse of the unit's
  bearing and `noarc` (rightly) stops the re-face, so a battery whose line faces along the wall never fires: ub 277
  and 90 against targets at 170, zero shots in 120 s (12:05 run). On CA's wall slots (the mover's `(wall)` recovery
  after CA gave idle batteries a zone, 11:44 run) both face 180 and fire: cannon 88 -> 76, rockets 264 -> 204.
- **What sets the facing wrong:** every re-forming order. The mover's own re-clicks (`queue_move` carries no
  bearing; a short move came out at 266-277, westward, three runs), `halt` (left the cannon a MOVE that walked it
  down the stair into the town, 11:33 run), `rotate` (both batteries walked off the wall, 11:44), and a move of
  1.5 m toward the enemy (came out at 266). `occupy_zone(position)` is silently dropped on the 111.6 walkway (no
  zone there, 12:05). Teleport in place with a facing then a 1.5 m step: the rocket battery re-faced to 172 once the
  step ended and fired 36 rounds in 70 s, the cannon came out of the teleport in a 2x2 block facing 93 and never
  fired (12:15). No script route sets a wall battery's facing reliably yet.

**Shipped (A6FD, data/):** an attack order on a battery whose engines all stand on a wall surface becomes `halt` +
`fire_at_will(true)` (`wall_attack`); a crewman is placed on his slot once per engine stop (1,948 placements in one
battle before it); for a wall order an engine counts as up only within 2 m of the order's height (`WALL_LEVEL`, an
engine on the stair 3.2 m below read as done). The face rule (B0EC/B6B2) is withdrawn. Harness, 28 cave breaks and
four rule mutants pass. The halt is a stopgap: it can walk a cannon off the wall, as above.

**Next:** the facing. Two candidates: find the bearing field in CA's MOVE command (the player's right-click-drag
sets one, the builder `2ea9a94` does not), so every re-click and the attack conversion keep the player's outward
bearing; or put an arrived battery on CA's wall slots, which face out and fire, through `queue_wall` (needs a zone
pointer, which only a unit already in a zone carries; the 111.6 walkway has none).

Evidence: `firing_B6B2_zone_trace.txt`, `script_log_firing_B6B2_zone.txt`, `script_log_firing_B0EC_face.txt`,
`script_log_firing_A6FD_halt.txt`, `facemove_rotate_A6FD_trace.txt`, `script_log_facemove_rotate_A6FD.txt`,
`zone_then_turnstep_A6FD_trace.txt`, `script_log_zone_then_turnstep_A6FD.txt`; decompiles `327ebc8`, `32739c0`,
`3086f04`, `30729d8`, `3065db8` in the session scratchpad (not kept).

## Pack 976BF5D9 (2026-11-02 13:00-13:35, Altdorf, stopped by the author)

In data/: queue_move builds the facing MOVE (exe+2ea9c88, u16 heading at +0xa8, float width at +0xac) so every
re-click keeps the player's bearing; an attack order on a battery in a CA wall zone re-issues the zone order with
fire at will; on a wall with no zone it becomes a facing move toward the target with fire at will.

Measured in the last run, one battle:
- `occupy_zone` issued from the GROUND at a zone point (660,106.6,-339) works: the helstorm climbed, stood on the
  slots at the parapet facing 180 and fired its whole 264 to 0. NOT verified per engine: unit ammo cannot say which
  engine fired. Next run must count the +0x3e8 shot pulses per engine body (sample every 200 ms, rising edges).
- The cannon sent by AW.move to the gatehouse roof (no zone) fired 88 to 73, three guns mid-roof facing 179-218,
  one on the 106.6 deck below. It fires but is not lined up at the parapet.
- NOT tested in game: either attack conversion of 976B.

Proposed fix, not built: when a battery's wall move ends near a CA wall zone, put it on that zone's slots with the
zone order, the one route measured clean for placement and firing.

## Crew spots kept on the wall (2026-11-02 14:30-15:00, pack 7961480F, code only, not run in game)

The author asked for the first of three engine fixes after "why is the navigation very janky on the walls": lay
the crew spots on the walkway. The game was handed to other sessions, so this is static RE, code and the offline
harness. Nothing below has been seen in a battle.

**What the exe does with a crew spot** (Ghidra headless, build 6acec6f4):

| function | what it does |
|---|---|
| `exe+308de70` | every tick, per engine body: sets each slot's live flag `+0x84`, calls `3086a80(slot+0x20, body, 0)`, then `3086e0c` for a manned slot. When body `+0x318 == 0x3a` flips, or the slot count is short of the crew, it first calls `305ab14`, which re-lays every offset |
| `exe+308dde4` | the layout: a side slot (kind under 0x16) takes its template entry's offset `+0x30` (state 0x3a) or `+0x38`; a pusher is a file behind the kind-2 entry, one metre (`_DAT_143922118` = 1.0) per row, plus up to 0.5 m from the battle's own random generator (battle `+0x440` `+0x90`, so multiplayer-safe) |
| `exe+3086a80` | places the spot: offset `+0x20` sideways and `+0x24` forward, turned by the u16 heading at body `+0xd98` as x*cos+z*sin, z*cos-x*sin (`exe+1120900` returns sine low, cosine high), added to the body's location block `+0xd78`, then resolved by `exe+14310cfac` with the engine's surface as the hint into `+0x30` (point) and `+0x40` (surface, null for the ground). **Cached:** with the engine standing it keeps the old point while the heading it stored at slot `+0xa8` matches; flipping that by 0x8000 makes it place the spot again on the next tick |
| `exe+3086e0c` | manned (`+0x81`): within 0.25 m in x/z of the point; facing (`+0x82`): within one degree of slot `+0x50` |

**The rule, in `derpy_artillery_walls.lua`** (`spot_step`, `lay_spots`, `spot_at_man`, run every 500 ms from the
mover's tick for every listed unit, whatever its order):

- A live spot of an engine standing on a wall surface, placed on the ground or more than 3 m off the engine's level
  (`SPOT_DROP`), or that could not be placed at all (`+0x83`), gets its offset pulled in to 0.6, then 0.35 of its
  length, then turned to either side of the gun at 0.4. Each try is judged after the game has placed it again
  (`SPOT_SETTLE` 400 ms); the first that lands on the wall stays, and if none does the 0.35 one stays. The angle at
  `+0x28` is rewritten the way CA computes it.
- CA's offset goes back when the engine leaves the wall. A spot the game lays out afresh (the 0x3a flip) is judged
  from scratch.
- The crew rule's lift changes for one case: a man it finds stuck short of his spot, standing on the wall within 3 m
  of the gun's level and 7 m of the gun, gets the spot moved onto him (the inverse turn) instead of being
  teleported. Men off the wall or further away are lifted as before. A spot that moves restarts its man's 2 s clock.

**Checked:** `--check`, `--selftest` (28 cave breaks, all Lua groups), `check_lua_api`, `check_lua_literal_left`.
The harness gained two groups: the rule (tries, settle wait, keep, restore, rebuild, unplaceable, dead slot, and the
inverse turn run back through the exe's forward formula at six headings) and the memory contract on a fake slot
(the three writes, the 2.6 m stair step left alone, the 3.6 m drop moved, a garbage count not read). Fifteen
mutants of the new code: fourteen fail the harness; the survivor mirrors a turned spot instead of rotating it,
which is equivalent (same side of the gun, same spacing).

**Open, for the next live run:**
- Spacing. A pulled-in file keeps its order but not CA's one metre: 0.6 m at the first try, 0.35 m at the second,
  0.4 m turned. Men may crowd; the spot-to-man rule is the backstop. Look for it in screenshots.
- Whether a man re-walks to a moved spot promptly. The handoff of 2026-11-01 saw redirected crew walks rebuilt
  within 25 s.
- The log lines to grep: `moved N crew spots of`, `moved a crew spot onto its man`, `crew spot read failed`.
- Test route: the Altdorf practice battle, a battery onto the gatehouse roof edge and one up a stair, screenshots
  at the stair top, on arrival and while firing, and count the old `placed a crewman on his slot` lines against the
  new ones.

Backups of the 976B Lua, harness and pack: `Modding Files/Backup/artillery_walls/20261102/`. Decompiles in the
session scratchpad: `slot_resolve.c` (`3086a80`, `308de70`, `3061d80`), `slot_ctor.c`, `slot_ctor2.c`
(`3052a98`, `308dde4`), `slot_misc.c` (`1183a8c`, `3086e0c`).

## Live run of 7961480F (2026-11-03 07:00-08:05, Altdorf, stopped by the author)

Set-up rule from the author, now in memory: before ordering anything, hold the enemy under kept script controllers,
invincible and fearless, and make the player's units invincible (`probes/artwalls_static.lua`). Per-engine counting
and zone orders: `probes/artwalls_engines.lua` (engine bodies picked out of the +0x184 list by vtable exe+3ad3360;
the list also holds the men, and only the men once the ammo is gone). Evidence:
`Modding Files/Backup/artillery_walls/20261102/firing_7961_per_engine.txt`.

- Crew spots: the new code runs. 131 'moved a crew spot onto its man', 24 'placed a crewman on his slot' and
  several 'moved N crew spots' in the first battle; the cannon on the gatehouse roof had all 44 crew up.
- **Only some engines fire, measured per engine (keyed by body pointer).** On CA's wall slots at z -339 facing 180,
  goblins 10-23 degrees off straight-out: cannon 1 of 4 (the one at heading 169, exactly its bearing to one goblin
  unit), helstorm 2 of 4 (headings 191 and 180). The idle engines never turn. Unit ammo hid this.
- It is not the target angle alone: the idle cannon at x 584 needs 170 to the same goblins the firing one (x 578,
  168.6) hits. Writing the aim goal heading (+0x1ec) to the bearing did nothing in 40 s; the turn is driven by an
  engine state, not that field. Open: what lets one engine turn and not its neighbour (its own target, or space to
  turn between the merlons). Next probe, ready to run: scan each engine body for a pointer to an enemy unit or man
  (firing vs idle), then all enemies straight in front of one battery.
- **The spasm on an attack order:** the zone-attack conversion fires every 3 s while the attack order stays the
  unit's current order (7 times in 22 s); that path has no once-per-order guard (FACE_COOL covers only the no-zone
  path), so the battery re-forms on its slots every 3 s and never finishes a shot cycle.
- Not the aim: `exe+3071dc8` (hit/knockback), `exe+3086f04` (body tick), `exe+308d830` (idle shuffle);
  `exe+3065db8` writes the goal record and starts the move to it, `exe+3071c84` writes it alone.
- The siege's 60-minute limit ended the battle mid-test; after 'Complete' the engines' fire states froze.

## The planner's fire-order gate, and pack 6FC1ED58 (2026-11-03 12:10-13:00, Ghidra, code only, not run in game)

The author asked what removing every restriction on wall engines firing would do, then for the static RE. Decompiles
(scratchpad, not kept): `fireorder.c` (`2f8ed98`, `3266a08`, `2f64d5c`, `3282a5c`, `326744c`, `3266bbc`, `2f5f15c`,
`327d528`), `fireorder2.c` (`2f5f748`, `300f6fc`, `3015794`, `2f62b14`), `fireorder3.c` (`326fea4`, `305f9c4`, `2f6fdf0`).

How an engine gets a fire order, per tick of the regiment attack behaviour `327d528` (vtable `3ae43b0` slot `0xf0`):

| step | function | gate |
|---|---|---|
| available engines | `326fea4` (slot `0xc8`) | each body's vslot `0x3a0` = `305f9c4`: **busy** when `+0x5c0` == 1, `+0x4c8` != 1, and `+0x324` == 0 or the action at `+0x4a8` (embedded, vtable first) refuses through its slot `0x40`. A busy engine is never offered a target |
| quorum | `2f6fdf0` | available count >= unit size x a battle constant, plus the `2ddb398`/`2dd5b34` throttle. Whole unit |
| firing spots | `3282a5c` -> `326744c` -> `3266bbc` -> `2f5f15c` | pairs engines with the target unit's men. **Under 5 engines and fewer engines than men: `2f5f748`**, each engine takes the best-scored man that passes `2f8ed98`, and gets nothing if none does. Otherwise `2f62b14` assigns pairs and `2f8ed98` drops the failing ones |
| arc and range | `2f8ed98(arc, body, man)` | min range, max range (+ extra), and \|bearing body->man - FORMATION heading\| < half-arc. The record is `{u16 heading, u16 half-arc, f32 min^2, f32 extra}`; half-arc = full arc (radians, unit `+0x3db0` -> `+0x70`) x 5215.19; 0x8000 reads as the full circle. `battle_entities.fire_arc_close` is 50 for the great cannon, helstorm and hobgoblin bolt thrower engines (unconfirmed as the source) |
| the order | `2f64d5c` then body vslot `0x380` | engines with a kept spot; the rest (`3266a08`) are re-planned through the same arc test |

All three callers of `2f8ed98` (`2f5f15c`/`2f5f748`, `300f6fc`, `3015794` - the last looks like fire at will's
target pick) build the record on their own stack per call.

What today's evidence says against it: the helstorm's idle engines (x709, x712.8) had goal positions at the two
firing engines' spots (703.6, 698.2) - walks into occupied slots on a one-wide walkway, which would read busy. The
cannon's idle engines had goals at their own positions, so for them the arc test is the remaining per-engine gate.

**Pack 6FC1ED58** (Modding Files/Modpacks, NOT in data/: the game was running for another session):
- `arc` cave at `exe+2f8ed98` (displaces `mov rax, rsp; mov [rax+8], rbx`): a listed unit's engine on a wall
  surface gets `[rcx+2]` = 0x8000 (full circle), then CA's test runs, so range still applies. Three scenarios, three
  breaks; selftest 31 breaks caught, `--check` ok.
- The attack-order twitch: `zone_attack_once(e, key)` turns an attack order on a battery in a wall zone once, keyed
  by order slot and target; `e.zone_attacked` clears when the current order is not an attack. Harness: seven
  assertions; three mutants (no once check, never remembers, no attack turns anyway) all fail it at line 284. The
  reset line itself is not reachable from the harness.
- Backups of the 7961 generator, Lua, harness and pack: `Modding Files/Backup/artillery_walls/20261103/`.

**Live test, next** (game shut first, deploy to data/ and md5): `artwalls_static.lua`, both batteries onto the
Altdorf slots at z -339, enemy 10-25 degrees off straight out, `AWE.start` per-engine shot counts, `AWE.busy(i)`
every 10 s. Pass: 4 of 4 engines firing on each battery. If the cannon fires 4/4 and the helstorm stays at 2/4 with
`has 1` on its idle engines, the busy gate is the second cause: an engine on a wall with a walk it cannot finish
should be offered a target (only a walk: forcing a firing engine available would restart its shot every tick).
Also check one attack order gives one 'attack order in a wall zone turned' line, and whether an engine now turns
inward toward an enemy behind the wall (the full circle allows it).

## Patch 9.0.5: exe build 6acec6f4 -> 6ae2a00b, every address moved (2026-11-03 19:06-20:00)

The patch landed mid-test (the exe on disk rewritten 19:06 while the 6FC1 run was still going in the old process).
`gen_artillery_walls.py --check` then reported all 17 sites and 8 function anchors wrong; `exe_re.py --selftest`
failed on its first fact. Code moved +0x4920 (fn_atan) to +0x7864 (hold/noarc), unevenly; the vtable section
+0xbae8..+0xd380; data +0xbbe8 (fn_scale) and +0xe468 (the battle global). The code section grew by 0x7000.

**The pre-patch snapshot came out of Ghidra.** No copy of the old exe existed, but the Ghidra project imported
from it keeps the bytes: `tools/ghidra/DumpImage.java` writes a project's memory as one RVA-laid-out image
(`Modding Files/Backup/exe_snapshots/image_6acec6f4.bin`, 235 MB, 8 s). `tools/ghidra_decompile.py` now names its
project after the exe's stamp (`WH3_BUILD=<stamp>` picks an older one), so `--import` after a patch keeps the old
project; `tools/exe_re.py` takes `WH3_EXE=<image.bin>` to scan a snapshot.

**`tools/exe_migrate.py`** finds each old address in the new exe: a function or site by its masked bytes (rel32
targets, rip-relative displacements and imm64 wildcarded, the window grown until one match), a vtable by its first
two migrated slots, a datum or a template instance (the two queue writers have 150 byte-identical twins) through
one old instruction that reads or calls it. 56 of 56 artillery addresses found once. Then the old and new
decompiles of all 31 functions the caves and the Lua read were diffed: **identical, every struct offset the same**
(the only data change is the sine table noarc's function reads, 0x143e8f360 -> 0x143e9a8c0, which no cave uses),
and the displaced bytes at every site are the same except the two `call fn_inf` rel32s (wallgate, cursor).

| name | old | new | | name | old | new |
|---|---|---|---|---|---|---|
| climb / fn_climb | 3014da8 | 301c220 | | fn_a / fn_b | 301d214 / 301d098 | 302461c / 30244a0 |
| links | 301d69c | 3024aa4 | | fn_inf | 303425c | 303b640 |
| man | 305952c | 3060aa8 | | gate_cont / cursor_cont | 301d34b / 3021859 | 3024753 / 3028c61 |
| hold | 327ebc8 | 328642c | | fn_add | 30e54ec | 30ecaa4 |
| noarc | 328507c | 328c8e0 | | prepare_cont | 30454b3 | 304c8b7 |
| clearshot | 305eb74 | 30660f0 | | candidate_next / rear_next | 3024b12 / 3024ea8 | 302bf1e / 302c2b4 |
| arc | 2f8ed98 | 2f96234 | | wall_vt | 3911218 | 391d440 |
| wallgate / cursor | 301d346 / 3021854 | 302474e / 3028c5c | | fn_atan / fn_round | 1183a8c / 4eda50 | 11883ac / 50d908 |
| primary | 3045479 | 304c87d | | fn_scale / fn_relative | 3922260 / 2f775ac | 392de48 / 2f7e9ec |
| solver / fronts / rear | 30249f0 / 3024acc / 3024e86 | 302bdfc / 302bed8 / 302c292 | | preview conts | 2e0f3ae / 2e0f973 / 2e0f9c3 | 2e164ba / 2e16a7f / 2e16acf |
| placement | 3070a48 | 3077f84 | | Lua: battle global | 4480da0 | 448f208 |
| preview / _models / _order | 2e0f3a8 / 2e0f96c / 2e0f9bd | 2e164b4 / 2e16a78 / 2e16ac9 | | Lua: zone ctor / move ctor | 2ea9754 / 2ea9c88 | 2eb09c8 / 2eb0efc |
| move_vt / attack_vt (Lua) | 390dd00 / 390d2f0 | 3919980 / 391a670 | | Lua: queue / queue push | 2df5a94 / 2e9c154 | 2dfcac4 / 2ea33c8 |
| engine body vt | 3ad3360 | 3adee48 | | Lua: selection / add / release | 2f2efc8 / 2f37be4 / 1bcd8ac | 2f36408 / 2f3f044 / 1bd3f4c |
| attack behaviour vt | 3ae43b0 | 3af12a0 | | fire update / body update / busy | 308ae34 / 3086224 / 305f9c4 | 3092384 / 308d768 / 3066f40 |
| crew spot tick / place / manned / layout | 308de70 / 3086a80 / 3086e0c / 308dde4 | 30953ac / 308dfc4 / 308e350 / 3095320 | | goal writer / fire-relocate / walk_stop | 3065db8 / 30729d8 / 306edd4 | 306d308 / 3079f14 / 3076310 |

The probes (`artwalls_*.lua`) still carry 6acec6f4 literals; `AWE`'s engine vtable is the one that matters for a
count (3ad3360 -> 3adee48). Third-person: `third_person_patterns.py` resolves its row by pattern (battle 448f208,
cmd_push 2ea2be8, the three sub-offsets unchanged), `tp_find_walk_rvas.py` prints the five walk fields
(walk_a 39242f8, walk_b 3aed8c8, walk_start 3076e90, walk_speed 3042b48, walk_stop 3076310) and
`third_person_cave.py --check` is ok; the BUILDS row for 6ae2a00b is not added yet.

**Pack for 6ae2a00b:** the generator, the Lua's eleven `at()` literals and the harness's five fake-memory
addresses moved; `--check` ok, selftest ok (31 breaks), Lua checks clean. Content as 6FC1 (arc cave, once-per-attack
guard, crew spots). Before the patch, 6FC1 ran once on 6acec6f4 (Altdorf, the enemy held at z -550, both batteries
on the z -339 slots by AWE.zone within 230 s model time): at 402 s the cannon had 3 of 4 engines with a shot and
the helstorm 3 of 4 (e2 nine shots, two engines one each, one none) - the first run on which more than two engines
of a battery fired, cut short by the patch before a clean count.

## 9.0.5 live runs and the re-forming on every attack order (2026-11-03 21:15-22:10, Altdorf, two battles)

memreader Plus 0.15.1 and the caves install on 6ae2a00b unchanged (`arc`, `clearshot`, `hold`, `placement` all
`cave`); it ships no build-specific values, so it needed no update. Set-up as before (`artwalls_static.lua`, the
goblins at z -550, both batteries by `AWE.zone` onto the z -339 slots within 230 s model time, 4x speed).

- **Battle 1 (pack D98B: arc cave, once guard), 3,496 s of counting:** cannon 3 of 4 engines fire all game
  (93 / 91 / 108 shots, the engine at x 569 none, heading 180 throughout), helstorm **0 of 4**: its engines' goal
  records point at each other's slots (703.6 -> 712.8, 698.2 -> 703.6) for the whole battle, every action
  `has 1`, so they stand in a walk they cannot finish and are never offered a target. The arc cave did what it was
  for (the cannon went from 1 to 3 engines turning: 169 / 170 / 180) and exposed the next gate.
- **The permuted spots are the fire order's "move to the spot first" path:** the dispatch `exe+2f86888`
  (6acec6f4: `2f7f448`) sends the engine to the solver's firing spot before the shot when bit 8 of the action's
  `+0xd8` is set (vslot `0x5b0`), else shoots in place (vslot `0x5a0`). New cave **`inplace`**: a listed unit's engine
  on a wall loses the bit. Generator scenarios and three breaks; selftest 34 breaks caught. Installed live as a
  test cave in battle 2 (block reused).
- **Battle 2 (the author watched):** "janky repositioning after every firing order" still. The log has two
  `attack order in a wall zone turned` lines, one per attack order the author gave, and each one is the full
  `wall` action: halt, teleport to the drop point, native zone order - the battery visibly re-forms once per attack
  order. That is the mod's own conversion, not the engine. Fix (pack now in data/): with every engine already on
  its slot the conversion is **`requeue`**, the native zone order alone through the command queue, no halt and no
  drop; the drop stays for a battery with an engine off its slot. Harness: the arrived case must give `requeue`,
  the one-engine-off case `wall`; two mutants (always requeue, always drop) fail it.
- The battle hit the siege's 60-minute limit at 3,600 s model time; at 4x speed that is 15 minutes real. Count in
  the first 20 minutes model time or set the time limit off in the practice battle.

**Not yet measured:** `inplace` (whether the helstorm's four engines fire in place) and `requeue` (whether the
attack order is dropped and nothing moves). Next run: the same set-up, `AWE.start` once both batteries stand on
the slots, then one real attack order per battery, `AWE.busy` for the goals, and the log's `(requeue)` line.
Evidence: script_log_031126_2147 (battle 2), the counts above from battle 1 over the bridge.

## The attack-order conversion withdrawn (2026-11-03 22:40-23:00, third 9.0.5 battle, stopped by the author)

Pack 17F4 (requeue) in the author's hands: "the reposition is still there after every fire/attack order". The log
(script_log_031126_2240) has eight `attack order in a wall zone turned` lines in 20 s for ONE order of the author's:
`wall`, `wall`, `requeue` x5, `wall`, 2.5-4 s apart. The once-per-order guard held per key, and the key kept
changing, because **the attack orders are the engine's own**: under fire at will the game issues an attack order
to turn a gun toward its target (noted on 2026-11-02 and not followed through), so every aim looked like a
player's attack order, the conversion re-formed the battery, the re-forming ended the aim, the next aim was the
next order. A script reading the order list cannot tell the two apart.

Withdrawn, pack now in data/: `wall_attack`, `zone_attack_once`, the `requeue` and `fire` actions, the facing
move on a zoneless wall and `FACE_COOL`, with their harness groups (the arrived-in-zone case stays as "left
alone"). An attack order on a wall battery is left to the exe, where its four known effects are each caved:
the march (`hold`), the re-face (`noarc`), the arc gate (`arc`) and the walk to the firing spot (`inplace`).
`--check` ok, selftest ok (34 breaks), Lua checks clean; backups `Backup/artillery_walls/20261103/`.

**Not measured:** a player's attack order on a wall battery under all four caves (2026-11-02's "walks west and
down the stair" was measured before `inplace` and `arc`), and `inplace` itself (the helstorm's four engines).
Next run: both batteries on the slots, `AWE.start`, one real attack order per battery, count per engine, watch
for any walk.
