# Artillery on Walls - handoff, 2026-10-31

Build `6acec6f4`. Script-only mod through memreader Plus (Workshop 3811098873). Status: **built and deployed to
`data/`, not published**. Single-gun units stand on walls and fire from them. Batteries (39 of the 58 whitelisted
units) on a wall now fire under fire at will AND an explicit order, with five caves (section 4c). **But a battery's own
walking on the walls jams** (section 4d): it cannot reliably get up, along or down. Open items in section 5.

## 1. Files

| What | Where |
|---|---|
| Shipped script | `Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua` (generated block between the markers) |
| Battle AI weights | `Modding Files/source/artillery_walls/battle_ai/bai_values_{major,minor}.txt`: CA's text, `OCCUPY_WALL` `AIUF_ARTILLERY` -1.0 -> 0.65, CRLF kept |
| Generator and checks | `tools/gen_artillery_walls.py`: default writes the Lua block and the bai files; `--check`; `--selftest` (unicorn runs the shipped cave bytes, 8 assembly breaks, whitelist positives and negatives); `--pack` |
| Built pack | `Modding Files/Modpacks/derpy_artillery_walls.pack`, deployed to `data/` (md5 `dbfe854c6d15ce52ff579c58f2fa9fe9`) |
| Probes | `Modding Files/source/artillery_walls/probes/artwalls_probe.lua` (`AW.status/capture/move/patch`), `artwalls_trace.lua` |
| Test mod list | `F:\...\Total War WARHAMMER III\used_mods_artwalls.txt` (bridge, intro skip, memreader, memreader Plus, this pack). Delete when testing ends |

Load a probe over the bridge with `loadfile(path)`, `setfenv(f, getfenv(1))`, `pcall(f)`. A new battle is a new Lua
state, so reload it after every rematch.

## 2. How infantry get onto a wall, and the four gates

No climbing animation is involved. Each man's own path holds a stair link (vtable `exe+3ad77f0`) at man `+0x220`. He walks
to its ground end and is moved about 20 m up in one tick (`+0x910` jumps, surface `+0x920` becomes the wall section,
link `+0x220` -> `+0x30`). The memory note `wh3-artillery-on-walls-flag-not-enough` has the field detail.

The gates for a gun: the DB flag `can_climb_ladder_and_stair_pipes` (record `+0xb4`); `is_infantry` (`exe+303425c`)
inside the climb checks `exe+3014da8` and `exe+301d69c`; the man slot `+0xa0` = `exe+305952c`, which asks the
entity's `+0x2a0` first (false on a vehicle body).

## 3. The mod: three whitelist caves

Each cave sits at its function's entry (`40 53 48 83 EC 20`). It looks the unit up in a block the script fills, and
answers true only for units in it. Every other unit runs CA's code unchanged. The block holds `count` and up to 250
unit pointers at `+0x20`, plus the targets the caves call.

- `climb` (`exe+3014da8`): a listed unit returns `unit+0x1a4 == 0`, skipping the `battle_entities` flag and
  `is_infantry`.
- `links` (`exe+301d69c`): a listed unit gets CA's own first three tests (`exe+301d214`, `unit+0x154`,
  `exe+301d098`) and nothing about the flag or infantry.
- `man` (`exe+305952c`): a man or body whose unit (`+0x2e8`) is listed skips the `+0x2a0` question, then runs CA's
  tail through the `climb` check.

The script fills the table at load, at Deployment and every 2 s. It adds units only and never removes one. Caves
cannot be removed for the session; on a later battle the script finds them by `hook_info(site).cave` and reuses the
block.

**Why the table fills only after the caves are in.** A gun put on a wall without the gate code crashed the game at
`exe+313219c`, inside the nav-cell lookup `exe+3132130` (live). Order the steps that way in any rewrite.

Whitelist (58 vanilla units): class not `com`, and either category `artillery`, or `war_machine` whose engine carries a
missile weapon or whose engine body is type artillery with a primary missile weapon. Excluded on purpose: chariots,
sleds, the steam tank, characters.

## 4. Firing: what was measured (battles 2 and 3 of the session)

**The engine fire path** (trace cave on the projectile spawn `exe+309eea4`): body update `exe+3086224` -> fire state
machine `exe+308ae34` -> spawn. `3086224` runs it while body `+0xc98` != 10, `+0xd48` > 10 and `+0x108 & 0x10`.
`308ae34` idles while body `+0xcfe` == 1 and starts when vslot `+0x658` is true, `(+0xce0 & 0x1080000) == 0x80000`
(bit `0x80000` = fire requested).

**Body commands at `+0x330`:** `3ad3a40` is the engine attack command. Its update `30862bc` calls `3070344` or `30690dc`,
which clear `+0xcfe` and set `+0xce0`. `3ae2400` is a walk, `3919350` the regiment's walk, `39126f0` stand. The body's
running action is at `+0x4a8` (has `+0x5c0`, started `+0x5c1`), as on a man. Order kinds, from the constructor
`30525d4`: kind 5 gets mask `DAT 373901c` (no fire bits), kind 6 `0xf0000`, kind 7 `DAT 3739024`, any other
`DAT 3739020` (`0xf00f0fff`). Kind 1 is the firing order.

**Readiness:** `30690dc` requests fire only when `((ce0 ^ ce8) & 0xf) == 0`. `+0xce8` is the body's capability mask.
The low bits of `+0xce0` are set by the crew, so a crew that cannot reach its posts never makes its engine ready.

**Who gets a kind 1 order:** the regiment attack behaviour `exe+327d528` (vtable from `3ae43b0`, slot `0xf0`). It
fires only when `exe+2f6fdf0` passes. That check is a quorum of available engines (vslot `+0x3a0` = `305f9c4`, "not
busy") plus a per-tick throttle (`2ddb398` / `2dd5b34`). It is **not** a line-of-fire check. Engines holding a slot in
the list `exe+3282a5c` rebuilds (`-> 326744c -> 3266bbc -> 2f5f15c`) get kind 1 through `2f64d5c` -> body vslot
`0x380`. The rest get kind 5 through `3266a08`. A slot is 0x20 bytes: the entity, a position at `+8`, and a frame at
`+0x18` (the order stores the position relative to `frame+0x88`).

Results, all from the wall walkway (y 624.1) unless stated:

| Unit | Fire at will | Explicit `attack_unit` |
|---|---|---|
| Magma Cannon (1 engine) | kind 5, no shot | turns in place, kind 1, fires: **255 kills, 25 -> 16 ammo**; after that, fire at will also issued kind 1 |
| Deathshrieker (1 engine) | kind 5, no target | turns (bearing 109 -> 135), `+0xce0` `804 -> b0804`, fires: 61 kills |
| Hobgoblin Bolt Thrower (8 engines x 7 crew) | kind 5 | 0 shots: the engines take regiment walks to **ground-level** slots (y 609, inside the town) and stall, crews idle 5-7 m off their engines, `+0xce0` 0 |

Ruled out: `is_infantry` (P2 on for 11 s under fire at will, and again with an attack order: no change); friendly
infantry on the wall in front (Infernal Guard moved off: no change); target distance or depression (no fire at
285 m either). Placement by forged move leaves a gun's facing arbitrary (bearing 0 = +z), which is why fire at will
sat on kind 5 until an order turned the gun.

In battle 2 the same bolt thrower fired 46 bolts from the gatehouse top. What was different there was not caught.

## 4b. Batteries, second pass (later on 2026-10-31)

All on the Hobgoblin Bolt Thrower (8 engines), wall walkway y 624.1, enemy held 150-215 m out.

**Facing decides fire at will.** A forged move keeps the formation's facing from before the move: the bolt thrower
deploys at bearing 273 deep in town, and that is the 274 it had on the wall in battle 3. Teleported in deployment to
bearing 180 behind the wall first, then moved up, it stands at 183 (outward). **Fire at will then works with no order:**
a target at 202 m at once, all eight engines kind 1, 176 -> 166 ammo and 8 kills in 25 s, every engine still on the
wall. The arc cave below was live in that game session, so whether it is needed is not proven.

**An explicit order still breaks it, in three steps, each found live:**

1. The order lands (`uc:attack_unit` -> `exe+3035864(unit, 2, block)` -> queued order `vtable 390d2f0`, start
   `exe+302a88c` -> unit FSM `3ac13e0`, update `exe+2f5aed0` -> regiment executor `exe+30de840` -> regiment order
   `vtable 3ad50c8`, start `exe+30d7a04` -> behaviour `exe+32697e0`). The missile attack behaviour's approach state
   `exe+32739c0` calls `exe+3281514` (re-plan) and `exe+327ebc8` (builds the formation move `326a7d4`, only caller). That
   march re-faced the battery to 85 and stalled it: no shots.
2. With `327ebc8` held (cave below), the solver gives slots, but `exe+2f7f448` dispatches move-then-shoot (vslot `0x5b0`,
   bit 8 of action `+0xd8`) and the engines walk ~25 m east along the walkway to a new line (destination at body
   `+0x368`/`+0x370`). Clearing that bit (cave below): **all eight kind 1 within 0.5 s of the order, firing from where
   they stand, facing kept at 183, 6 kills in 11 s.**
3. **Open:** ~20-22 s in, once the target drifts ~25 deg off the facing, the unit's bearing swings 183 -> 88, then each
   engine walks to a moved formation slot through its own update (`exe+3086f04` -> `exe+3075e7c`, "go to my slot",
   slot block at body `+0x858`; stack `30873e4 -> 3076500 -> 307613b -> walk_start 306f954`). The line slides ~7-14 m
   east, kinds go 0 then 5, the target is dropped, and **every later order on that unit drops within a second** (wedged
   until the battle ends). Holding `32739c0` as well did not stop it, so the re-face comes from another path. Blocking
   `3075e7c` from the body update stops the slide but also stops the first near-zero step into the slot, and then no
   engine ever gets kind 1. Next: find what rotates the formation (trace writers of the unit's facing, or of body
   `+0x858`), and hold that for listed units on a wall instead.

**Caves tried live, owner `aw_test`, all whitelist-gated like the shipped three, none in the pack yet:**

| Site | For a listed unit whose engine is on a wall | Result |
|---|---|---|
| `exe+2f8ed98` (solver's arc check) | half-arc `ctx+2` = `0x8000` (full circle) | live all session; necessity unproven |
| `exe+327ebc8` (formation march) | `ret`; unit = `[[rcx+8]+0xa10]`, wall = first man's `+0x920` | stops the march (step 1) |
| `exe+2f7f448` (action dispatch) | `and byte [rcx+0xd8], 0xf7`; body = `[[rcx+0x10]+8]`, unit = body `+0x2e8` | shoot in place (step 2) |
| `exe+32739c0` (approach state) | `ret`, same test as `327ebc8` | no effect on step 3 |
| `exe+3075e7c` (slot walk), only when `[rsp]` = `exe+30873e4` | `ret` | breaks the first engagement; switched off live by patching its `je` to `jmp` |

Facts checked on the way: `[[unit+0x32f8]+0xa10]` is the unit again (the regiment AI object's back pointer); body
`+0x2e8` is the unit; unit `+0x154` is 0 for infantry on a wall too, so it is not a wall mode; unit `+0x1a4` was 0 for
every unit. `bm:is_paused` is nil at runtime; `uc:teleport_to_location` does nothing late in a battle, and an enemy
controller's `goto_location` can stop responding. The probe `AWH.fhook` (in `probes/artwalls_hooks.lua`) records only
calls whose `[rcx+0x2e8]` is one unit; the setup and start scripts for this test were scratch files, not kept.

## 4c. Batteries, third pass: the re-face found and blocked (shipped, evening 2026-10-31)

The attack behaviour lives in the unit's order slot, `[unit+0x32f8]+0x30` (vtable `3ae4a90`); its FSM state pointer
is at behaviour `+0x38`. States are slots `3d20c80..3d20cf0`, each pointing at a table `{update, enter, exit}` near
`3946xxx`; vtable slots `0xd0..0x120` of `3ae4a90` are one-line getters (`lea rax, [slot]; ret`) naming the next
state. Logged live, an explicit order on a target that drifts off the arc runs: `REPLAN` (0.3 s) -> `f0` (firing,
update `3275304`) -> at ~20 s `e0` (enter `3277084`: new heading at the target, formation position moved FORWARD along
it) -> `QUERY` (enter `3270020`: a planner query into `+0x190`, request flag `+0x1c2`) -> `REPLAN` (enter `3282ed4`:
slot realign, every fire action cancelled) -> `f0` -> `d0` -> the order is dropped and the battery idles, aim only.

The trigger is **`328507c`, "the target left the planned arc"**: the fire zone of the planned position `+0x198` and
heading `+0x1b8`, and the bearing to the target against the unit's arc. `f0` and the decide state `3275c70` both go
to `e0` on it. Shipped caves (generator `SITES`, selftest 12 breaks):

- `noarc` at `328507c`: a listed unit on a wall answers false. No re-face, so the battery keeps a frontal arc, as
  wall infantry do. Each engine still traverses a little (headings 150-180 seen) since the engine is
  `Generic_No_Crew_Fixed`.
- `hold` at `327ebc8`: the attack's march toward a target out of reach returns at once. Without it the `d0` state at
  ~31 s turned the battery into town and walked one engine off the wall (measured).
- `2f7f448` (move-then-shoot -> in place) is NOT needed once `noarc` is in (measured: same result without it).
Measured with the shipped pack alone: two volleys by 33 s, the order ends cleanly at ~32 s, the battery picks up the
next enemy by itself (kills 20 by 57 s), and a fresh order at 57 s is accepted. Rockets have `minimum_range` 60, so an
enemy 55 m out is never shot from the wall either.

**A cave that skips a state's ENTER crashes the game.** `noquery` (ret at `3270020`) left `+0x190` null and the
query state's update `3274cf0` read `[0+8]`: access violation on the battle thread, caught by the game's handler, so
the process lived on with battle time frozen (`memreader_crash_report_311026_2043.txt`). Skip an enter only when
whatever it sets already holds a valid value, or block the transition into the state instead.

## 4d. Batteries walking on walls jam (found 2026-10-31, NOT fixed)

Measured with the shipped pack, Deathshrieker battery (8 engines), every engine read separately (the unit's position
is ONE engine's, which hid this):

- **Down**, walkway to a ground point 40 m inside: engines queue at one drop point on the inner edge and drop one at a
  time, 624 -> 609 at the same x, z. All 8 down in ~26 s.
- **Up**, ground to the walkway: some came up on the walkway (y 624), four came up on the gatehouse roof (y 629). By
  36 s nothing moved: the roof group never stepped down to the walkway, the walkway group stopped short of its slots,
  and one engine stayed at the foot of the wall. Screenshot: the battery clumped on the gatehouse roof.
- **Along**, after an order ended, the regiment's own formation move (`326a7d4`, built in place in the order slot by
  `3282294`, vtable `3ae3650`; the state slot is `3d20c28`, its getter `8fa320` at `3ae5860`) walked the battery onto
  the gatehouse roof, where six engines stayed for good. A plain script `goto_location` uses the same `326a7d4`, so
  blocking it would also take moves away from the player.
The forged own walk of `probes/artwalls_probe.lua` (`AW.move`) put all 8 engines on the walkway in ~10 s every time
this session, so per-engine placement works where the regiment's pathing does not. That matches the author's first
description: "teleporting them on top once near the wall", "the predestined assignment like units".

## 5. Open

1. **Batteries walking on walls** (4d). Firing from the wall is solved (4c).
2. **Facing on arrival.** A battery keeps whatever facing it had before the move onto the wall. Fire at will needs it
   to face outward. Options: the player drags the move to face out; or set the facing for a listed unit when it arrives
   on a wall. Infantry face outward on their own; how is not traced.
3. **AI:** the `bai_values` override from a mod pack is unverified, and so is an AI defender putting guns on walls.
   The test needs the custom battle flipped so the AI defends.
4. **Multiplayer** untested. The table fill runs on model-time callbacks.
5. `docs/MY_MODS.md` gets an entry once the mod is published.

## 6. Tracing technique used here

A memreader Plus cave at a function entry that copies the call stack into a buffer is the fastest way to find who
calls what in this exe. The cave bytes: `push rsi/rdi/rcx/rax`, `mov rdi, BUF`, `inc dword [rdi]`, store the
argument registers at `[rdi+8..]`, `lea rsi, [rsp+0x20]`, `add rdi, 0x28`, `mov ecx, 0x400`, `rep movsb`, then pop.
A 100 ms Lua callback scans the copy for values inside the image and groups the stacks by signature. Caves stay for
the session, so give each its own name under a throwaway owner (`aw_trace`). Hooked this session: `309eea4` (spawn),
`3071134`, `2f64b28` (action constructor), `30525d4` (attack command constructor) and `2f64d5c` (slot to order).
