# Artillery on Walls: handoff, 2026-11-03 night (patch 9.0.5)

The short state and the author's open asks. The full record of 2026-11-03 is the last five sections of
`docs/sessions/HANDOFF_20261101_ARTILLERY_GROUND_RECOVERY.md`; read those for the evidence behind each line here.

## The author's asks, latest first, in their words

1. "it seems like the engines only move if there are the crew around the vehicle, where are all the effort of
   decompiling go"
2. "theres also stuck personell on the ground". Their screenshot: a battery standing on the wall, and about ten of
   its crew in a row on the ground at the foot of the wall.
3. "the teleporting parts of the mod are not immersive friendly, remove it all and fix the navigation issues
   instead, still only moving one engine on the ground makes the rest be stuck on the walls"
4. "why do some engines still not fire, check their restriction as to why"
5. "make the engine still rotate and remove the janky reposition" (done, see below)

Asks 1-4 are open. The author stopped the last run to have them fixed first. Ask 3 is a design rule from now on:
**no teleports in the shipped mod**, so every movement problem must be fixed in the native navigation.

## State at hand-over

- Game build **6ae2a00b** (patch 9.0.5; the exe was rewritten 2026-11-03 19:06). The game is shut, and the test
  set-up is cleaned up: practice battle restored, prefs reverted, `used_mods_artwalls.txt` removed.
- `data/derpy_artillery_walls.pack` is **CA401BB9** (md5 `ca401bb97a42ab03669313877174a172`).
  - Source: `Modding Files/source/artillery_walls/`.
  - Generator: `tools/gen_artillery_walls.py` (`--check` ok, `--selftest` ok with 34 break tests).
  - Harness: `tools/artillery_walls_tests.lua`.
- Backups are in `Modding Files/Backup/artillery_walls/20261103/`:
  - the 7961 generator, Lua, harness and pack (the version before today);
  - the `17f4` pack (requeue);
  - the `ca40` pack (the one deployed now).
- memreader Plus 0.15.1 and twwh3-memreader needed no update for 9.0.5. They ship no build-specific values, and
  every cave installs on 6ae2a00b.

### What CA40 does

**Caves (exe patches).** Each applies only to a listed unit's engine or man.

| cave | effect |
|---|---|
| `climb`, `links`, `man` | let guns and their crew onto walls |
| `hold` | no march toward a target out of reach |
| `noarc` | no formation re-face on a wall |
| `clearshot` | a wall engine passes the parapet line test |
| **`arc`** (new) | the planner's firing arc is a full circle for a wall engine |
| **`inplace`** (new) | a wall engine's fire order shoots from where it stands, with no walk to the solver's spot |
| `wallgate`, `cursor`, `primary`, `solver`, `fronts`, `rear`, `placement`, `preview` x3 | CA's native wall order for batteries |

**Lua.**
- **Still in, and it teleports** (ask 3 says remove all of it):
  - the crew lift in `crew_step` (it writes a crewman's position onto his slot);
  - the `stuck` ground recovery (`halt`, then `teleport_to_location`, then a walk);
  - the `wall` recovery (`halt`, `teleport_to_location`, then `queue_wall`, with the `placement` cave enabled through
    `e.flag`).
- **Still in, no teleport:**
  - the `nudge` (re-issues the player's own order once);
  - the crew-spot re-layout (`spot_step`, `lay_spots`, `spot_at_man`). This moves a slot's offset, never a man.
- **Withdrawn today:** the whole attack-order conversion (`wall_attack`, `zone_attack_once`, `requeue`, the facing
  move, `FACE_COOL`). The attack orders it reacted to were mostly the engine's own: under fire at will the game issues
  an attack order each time a gun aims. The log showed eight conversions in 20 s for one click by the author, so the
  battery re-formed on every aim.

## Measured tonight, 9.0.5, Altdorf practice siege

Set-up for every run:
- enemy held still and immune by `probes/artwalls_static.lua`, placed at z -550;
- both batteries sent by `AWE.zone` onto CA's wall slots at z -339, facing 180;
- shots counted per engine by `probes/artwalls_engines.lua` (`AWE.start` / `AWE.report`).

**Battle 1 (pack D98B: arc cave and the once guard, 3,496 s).**
- Cannon: 3 of 4 engines fired (93, 91 and 108 shots).
- Helstorm: 0 of 4. Its engines' goal records pointed at each other's slots for the whole battle.

**Battle 4 (pack CA40), at run 297 s:**

| unit | engine | x | heading | crew on slot | state | shots |
|---|---|---|---|---|---|---|
| cannon | e3 | 569.0 | 167 | 10/11 | firing | 10 |
| cannon | e2 | 578.2 | 170 | 10/11 | reloading | 11 |
| cannon | e1 | 572.8 | 168, facing a foe | 10/11 | idle `4/0/20/0` | 0 |
| cannon | e4 | 583.6 | 180, 9 deg off | 8/11 | idle | 0 |
| helstorm | e1 | 703.6 | 192 | 11/11 | firing | 16 |
| helstorm | e3 | 698.2 | 180 | **4/11** | firing (goal 703.6) | 15 |
| helstorm | e2 | 709.0 | 180, 11 deg off | 10/11 | idle | 0 |
| helstorm | e4 | 712.8 | 180, 12 deg off | **1/11** | idle (goal 698.2) | 0 |

What these numbers rule out:
- **Readiness** `((ce0 ^ ce8) & 0xf) == 0` passes on all eight engines (low nibble 4 = `ce8` 0x34).
- **The "busy" fields** that exe+305f9c4 reads (`+0x5c0` 1, `+0x5c1` 1, `+0x4c8` 0, `+0x324` 0) are identical on
  firing and idle engines. Read the way the 2026-11-03 handoff reads that function, they would make ALL eight busy,
  so that reading is wrong or the fire order reaches engines another way. Unresolved.
- **The crew count does not decide firing:** helstorm e3 fires with 4 of 11 crew.
- `inplace` did not fix the helstorm goal records that point at other engines' spots. Those come from the zone
  placement, not from a fire order.

**One descent check (not clean).** The cannon was ordered to the ground at (598,-281) through a controller. All
four engines stood at the point within 20 s. But the author was giving orders in the same battle, and the battery
was already on the ground 2 s after the order, so this says nothing about the wall exit.

## Why the decompiling has not fixed movement (ask 1)

What it found, on 2026-11-01 and 11-02:
- The crew-slot machinery: `exe+308de70` the per-tick loop, `3086a80` places a slot point, `3086e0c` sets `+0x81`
  "manned" when the man is within 0.25 m in x/z only, and `308dde4` lays the slots out.
- An engine with an unmanned slot sits waiting for its crew.

What it did not find: **the code that holds the engine until its crew are on their slots**. The handoff says so at
line 201 ("The gate that holds the engine was never found in the code"). Instead the Lua was built to satisfy the
gate from outside: crewmen are written onto their slots, and stalled batteries are teleported and re-ordered. That
is the teleporting the author now rejects. It is also why one engine reaching the ground leaves the rest stuck on the
wall: they wait for crew who cannot reach slots laid out on the other level.

## Next, in order

1. **Find the crew gate in the exe**, on the 6ae2a00b Ghidra project (it exists: `ghidra_cache/wh3_6ae2a00b`).
   - Where to look:
     - the engine walk path: body update `308d768`, then "go to my slot" (6acec6f4 `3075e7c`), then `walk_start`
       `3076e90`;
     - every reader of slot `+0x80` / `+0x81` / `+0x84`, and of `+0xce0`'s crew bits, on that path.
   - First migrate `3074270`, `3070950`, `3075e7c`, `3086f04` and `30690dc` with `tools/exe_migrate.py` (add them to
     `ARTWALLS`).
   - Confirm live by watching which branch an idle engine with unmanned slots takes.
2. **Cave the gate** for a listed unit's engine, so it walks without waiting for crew at their posts. The crew then
   follow it rather than lead it.
3. **Stuck crew on the ground (ask 2).** Find why crewmen do not path up to slots that are laid out on a wall
   surface.
   - The `man` cave lets a listed unit's men use wall links, so check whether these men reach it.
   - `+0x81` is x/z only: men 20 m below their slots read "manned" (handoff line 438). That can also leave an engine
     believing its crew are there.
4. **Remove every teleport** listed under "Still in, and it teleports" above. Keep the `nudge` and the crew-spot
   re-layout. Expect the stalls those teleports covered to come back until 1-3 land, and say so to the author.
5. **Engines that do not fire (ask 4).**
   - Trace which engines receive a fire order, with a counting cave on the order builder `2f6c1d0` (6acec6f4
     `2f64d5c`) or on the body's vslot `0x380`.
   - Then follow an idle engine (cannon e1 above: facing a foe, crew on slots, never fires) through the fire
     update `3092384`.
   - The helstorm's crossed goal records are the zone placement's slot assignment. Find who writes `+0x1e0` for a
     zone order (goal writers are `306d308` and 6acec6f4 `3071c84`).

Test method (the author's rule): enemy held and immune before any order. Count per engine, never by unit ammo.
Screenshot each stage. The siege's 60-minute limit ends a battle at 3,600 s model time, which is 15 minutes at 4x
speed. Rematch through `button_rematch` then `button_tick`.

## Addresses on 6ae2a00b (from 6acec6f4 by `tools/exe_migrate.py`)

| what | 6acec6f4 | 6ae2a00b |
|---|---|---|
| arc / inplace caves | 2f8ed98 / 2f7f448 | 2f96234 / 2f86888 |
| fire update / body update | 308ae34 / 3086224 | 3092384 / 308d768 |
| attack tick / available list / busy | 327d528 / 326fea4 / 305f9c4 | 3284d8c / 3277708 / 3066f40 |
| order builder / re-plan / small-battery spots | 2f64d5c / 3266a08 / 2f5f748 | 2f6c1d0 / 326e25c / 2f66bbc |
| crew slot tick / place / manned / layout | 308de70 / 3086a80 / 3086e0c / 308dde4 | 30953ac / 308dfc4 / 308e350 / 3095320 |
| goal writer / fire-relocate | 3065db8 / 30729d8 | 306d308 / 3079f14 |
| walk_start / walk_stop | 306f954 / 306edd4 | 3076e90 / 3076310 |
| engine body vt / attack behaviour vt | 3ad3360 / 3ae43b0 | 3adee48 / 3af12a0 |

The cave sites and Lua addresses are in the generator and the Lua. The full 56-row table is in the ground-recovery
handoff's 9.0.5 section. Struct offsets did not move: all 31 functions decompile identically on both builds.

## Tools added on 2026-11-03

- `tools/exe_migrate.py` finds each old address in a new exe, by masked bytes, by vtable slots, or through one
  instruction that reads or calls it. It has a `--selftest`.
- `tools/ghidra/DumpImage.java` dumps a Ghidra project's bytes, which makes an old project the pre-patch snapshot.
  The 6acec6f4 snapshot is `Modding Files/Backup/exe_snapshots/image_6acec6f4.bin`.
- `tools/ghidra_decompile.py` now names its project after the exe stamp. `WH3_BUILD=<stamp>` picks an older project.
- `tools/exe_re.py` takes `WH3_EXE=<image.bin>` to scan a snapshot. Its selftest facts are moved to 6ae2a00b.
- `probes/artwalls_engines.lua` has `AWE.busy(i)` and the 6ae2a00b engine vtable. The other artillery probes
  still carry 6acec6f4 addresses.
- The third-person mod's own finders resolve on 6ae2a00b. Its `BUILDS` row is not added, which another session
  (modding-for-resources-88) owns.
