# Artillery on Walls: why wall engines stall, 2026-11-09 (build 6ae2a00b)

Follows `HANDOFF_20261103_ARTILLERY_WALLS_NEXT.md` (the author's five asks, the address table). Three live runs in the
morning and two in the afternoon (§5: docked by real right-click; docked batteries still never fire, and why),
Altdorf practice siege, Empire great cannon (unit 3) and helstorm (unit 4), enemy held still and immune.

**State: pack `A862`, published 2026-11-10 as Workshop item 3837212899. The Workshop folder
`workshop/content/1142710/3837212899/` is the live copy, and the `data/` copy is removed (§29-§30: single player only,
regression pass on Dwarfs and an Empire AI). `B6FB`, verified in runs 40-41 (§27): a docked gun turns and fires all the way round, under fire at will too. Runs 33-34 (§25): enemy arrows on docked guns, pushers on a long wall,
a Cathay AI holding the walls. On 2026-11-09: pack `DB5E`, after every other race was run
(§23: shots, Helstorm reach, Skaven to Chaos Dwarf, four fixes, drawn guns refused); see §30.** (The morning's state was pack
`E0ADCB2D`, which fixed mechanism A below; B was open.) Backups of the `5510` Lua and pack, three script logs and the
body dumps: `Modding Files/Backup/artillery_walls/20261109/`.

## 0. Correction to this file's first version (written mid-morning)

It said "an engine does not move until every crew slot reads manned (`+0x81`)". **Wrong.** Engines walking on the
ground and along the wall read 1-3 of 11 slots manned (run 2, `body_dumps.txt` gmove/wmove). The measurement stands
(CA's wall slots lay a gun's forward crew slots past the parapet, men pressed 1 m short; neighbouring batteries 5 m
apart overlap), but it is not the movement gate. The mod's crew-spot re-layout clears it within 10 s anyway.

## 1. The 2026-11-04 session nobody wrote up

Probably Codex (no Claude transcript). From its files: **every teleport is out** (the `placement` cave and its
recovery bytes, the crew lift, the `stuck` drop, the `wall` teleport recovery); what stays in Lua is the once-per-order
retry (`nudge`, which also re-issues the native wall order) and the crew-spot re-layout. Pack `5510B1B5`. Its logs
(`Backup/artillery_walls/20261104/`): forcing the fire readiness `(ce0^ce8)&0xf` or the nav query changed nothing;
2 of 4 engines per battery fired. 29 decompiles `ghidra_cache/artwalls_20261104_*.c` (UTF-16).

## 2. Mechanism A, FIXED: our `hold` cave froze every march of a wall battery

The chain, traced live (run 2, mover off then on):

1. `walk_stop` (body vslot `0x528`) hit each wall engine about once a second, always from `exe+2f7756c`: the start
   step of a **stop action**, vtable `exe+3917320`, built by `exe+2f6ba28`.
2. That action is queued through entity vslot `0x360` (`exe+3077e0c`), called for every entity of a group by
   `exe+30e18dc`, called from `exe+327bd74`.
3. `327bd74` is the **enter step of a halt state** (vtable `exe+3951990`) in the regiment group's state machine
   (step `exe+1825d7c`, tick `exe+3287980`). The machine sat in its move state A (vtable `exe+39521d8`: transition
   `327c88c`, enter `327b834`, update `328d908`/`327b224`) at every 100 ms sample, yet entered the halt state 631
   times: A -> halt -> A inside one tick, over and over. The group was the three helstorm engines still on the wall.
4. A's update, once its group path is ready (`+0x88` state 4, ok byte 1), calls `exe+328642c` to start the march.
   **That is our `hold` cave's site.** `hold` was meant for the attack behaviour ("no march toward a target out of
   reach"), but `exe+327b224` is its only caller and is shared by the plain move behaviour (vtable `exe+3aef828`,
   read live). The cave tests only "the unit's FIRST man stands on a wall", so whenever `men[0]` is a crewman of an
   engine still up there, no march of the unit ever starts and the halt state stops the group every tick. That is
   the author's "one engine reaches the ground and the rest are stuck on the walls".
5. Proof: `hold` neutralised in memory (`EB 48` over its first instruction) -> the enter counter froze at that tick,
   and two of the three stuck engines went down the stair within 8-20 s of game time.

**Fix (pack E0AD):** `hold` falls through to CA's code when `[rcx]` is the move behaviour's vtable, kept in the
block at `+0x60` (`CALLS["move_vt"]`); `noarc` is unchanged. `--check` verifies the vtable on disk through its
`+0x10` slot (the tick `3287980`). Selftest: a move-behaviour scenario and two breaks (gate dropped, gate inverted):
32 breaks caught. Verified in run 3 with the shipped pack: the cave's bytes and the block entry live, **no halt
loop** (0 enters), the cannon 4 of 4 down within 30 s, twice.

## 3. Mechanism B, OPEN: an engine that holds the stair link but has no link entry

Seen in every run: run 1 engine 704 (after the re-layout, 11/11 manned), run 2 e1 (already frozen before the ground
order, 0.9 m short of its wall slot), run 3 **three of the four helstorm engines**, so the helstorm got 1 of 4 down
even with A fixed. Identical state each time:

- stair link held: `+0x220` (and `+0x758`) -> vtable `exe+3ae32e0` (the 6acec6f4 stair link `3ad77f0`), `+0x270` = 1,
  `+0x390` = 1, `+0x520` = 1, `+0x538` = 0x30a; a walk command (`walk_b` `3aed8c8` or `walk_a` `39242f8`), path
  `+0x710` = 4, immediate goal `+0x1e0` the stair head (681-686, 106.6, -322.5); heading never turns toward it.
- running action (`+0x4a8`) vtable `exe+3917110`, started (`+0x9c` = 1) but its walk never issued (`+0x9d` = 0).
  Its update `exe+2f90044` issues the walk (`2f86a44`, body vslot `0x5b0`) only when `exe+2f735f4` is true, which
  needs `body+0x890` non-null (an object with type `+0x74` 4, position `+0x88..+0x90`, height `+0x9c`, i.e. the place
  to walk to). **`+0x890` is null on every engine.** So the action can neither start nor finish.
- Writing the action's done byte (`+0x20` = 1) is useless: a new `3917110` replaced it in the same tick. The ground
  order itself creates them (new start ticks matched the mover's `(nudge)` re-issue to the tenth of a second).
  Constructor `exe+2f6bc44`; callers `exe+3077f84` (CA's placement function), `exe+2f50a48`, `exe+2ed6cac`.
- Battle-code writers of `+0x890`: `exe+3261374` sets it (path-follow code), `exe+3258ca0` clears it,
  `exe+3078670`, `exe+2ffdfe4`.

## 4. Test-method traps found today

- **A script `goto_location_angle_width` leaves CA's wall controller on the unit** (`unit+0x3310` = 1, vtable
  `391d440`). With it left on, the mover's `wall_step` re-issues the wall order and walks the battery back up (the
  cannon at 683.6 s, run 3). A player-style MOVE through the command queue clears it (0 controllers): the steps of the
  Lua's `queue_move` (`2f36408`, `2f3f044`, `2eb0efc`, heading `+0xa8`, width `+0xac`, push `2ea33c8`) with a ground
  location (x, y, z, then zeros for the surface). **Use the queue MOVE for descent tests.**
- `AWH.fhook` filters on `[rcx+0x2e8]`, which men carry too, and its poll keeps only the last hit per 100 ms: three
  engines stopped in one loop show as the last one.
- Probes added: `probes/artwalls_dump.lua` (`AWD.snap(tag)`: body `0..0xe00` + command `0x100` per engine, to a
  file) and `probes/artwalls_diff.py` (fields stable within each tag set and different between them).

## 5. Afternoon: docked by real right-click, and why docked batteries still do not fire

The author's ask: dock both batteries with the mouse and see whether docked engines fire. Pack `E0AD` unchanged.
Two runs. **Run 1 (log `1010`) is void after t≈400 s**: the author was ordering the units by hand at the same time
(it looked like the mod pulling a docked cannon off its slots; it was not). It is also void after t≈3,599 s: at
4x speed it ran into the siege's 60-minute limit (phase `Complete`, memory `wh3-battle-time-limit-kills-callbacks`),
so four tests made after that mean nothing: the slot-task clear, the crew-update trace hooks, the `hold` bypass and
the pusher lift. **Run 2 (rematch, log `1034`, 2x speed) is the clean one.** Sampler: `run2_sampler.txt`
(every 2 s: each engine, and its slots 0-2 as man y / path / command / manned).

**How to dock by click (works).** `move_to(battle_vector:new(x,150,-300), battle_vector:new(x,106.6,-338))`, then park
the cursor without clicking (scratchpad `hover.ps1`, a copy of `tp_mouse.ps1` without the click) and take a
screenshot: four green triangles (the wall zone's slots) must sit under the centre. Then `tp_mouse.ps1 -fx 0.5 -fy
0.5 -button right`, and read `unit+0x3310` = 1 with order vtable `391A500`. A click a few metres in from the
parapet (z -334) gave a plain MOVE that resolved to the ground 90 m inside the city, twice. The camera can also
drift between `move_to` and the click; read it back before clicking.

**Run 2, as measured.** Cannon ordered at 244 s, helstorm at 278 s; both climbed and stood on their slots by
~330 s and ~430 s.

1. **Pushers are left at the wall foot (ask 2).** Slots 0-2 of every engine are the pushers: slot `+0x18` holds a
   task (vtable `3ADEBE0`), the man runs action `3AD8D48` (start `2f7fd78` calls man vslot `0x590` with the slot
   index and the engine; update `2f8fd60` waits for his command's done byte) and command `3925498` (a manning
   pose: it sets the man's `+0x318`, never reports done), path state 0. They are not walking. They are carried
   beside the engine on the ground plane. When the engine takes the wall link (x≈565, y 91.6 -> 106.6 in one 2 s
   sample at z -316/-322), all twelve cannon pushers stay at the wall foot (z -321.4) under their slot x. The
   other crew walk up on their own (no task; `307d118` sends them with the slot's point block, surface included).
   **CA puts the pushers back on the wall itself** when their engine starts a new walk segment: cannon e2 at
   356 s, right after the mod moved three straggler spots onto their men (`moved a crew spot onto its man`), went
   y 92 -> 107 in one sample. By 1,000 s all 24 pushers were up. So stranded pushers hold a battery up but do not
   lock it for good.
2. **Six of eight engines never finish their walk.** Cannon e3 and helstorm e3 finished on their own (path 0,
   command idle `ADF528`, action `3916C70`). The other six sat 0.2-1.2 m from their slot, five at heading 180,
   fully manned, in path state 4 for 600+ s. A field diff against the two finished engines, stable across two
   snapshots, leaves **body `+0x18f`: 1 on the finished, 0 on all six**. The path state machine `exe+307e4b4`
   (decompile in `path_stop.c`) leaves state 4 only through `LAB_14307e70a`, which needs `+0x30` null, `+0x18f`
   = 1 and `+0x218` = 2, and then sets 7 or 6 from `+0x1b0`. The six read `+0x218` 2, `+0x750` 1, `+0x18f` 0.
   **Writing `+0x18f` = 1 (test only, three cannon engines)** took them to state 6 within 14 s, set the walk
   command's done byte, finished their go-to actions (`+0x20` 1, `+0x4c8` 1) and completed the unit's order
   (orders 1 -> 0). The wall controller (still on, `ctl 1`) then gave them new `3917110` go-to actions.
3. **Nothing fired in 600+ s** (ammo 82 / 108 unchanged), not the two that finished on their own and not the
   three forced ones. Range 540 / 576 against 209-224 m; fire at will set on explicitly. `AWE.busy` reads every
   engine busy (`+0x5c0` 1, `+0x4c8` 0), the deployed `3916C70` ones included; cannon e3's goal `+0x1e0` is its
   deployment spot (607.5, -192.8). The forced engines never got `3916C70`, and their fire state `+0xce0..` stayed
   0/0/0/0 (e3: idle 4/0/20/0).
4. The six stuck engines are also mechanism B (§3): go-to action `3917110` started (`+0x9c` 1), its own walk never
   issued (`+0x9d` 0), `+0x890` null.

`+0x18f` has no direct byte writer in battle code (`exe_re.py writes 18f`: one hit, `exe+1cfae26`, outside it), so
it is set through a wider store or a sub-object. `exe+30664d8`, the other reader at the top of `307e4b4`, always
returns 0: not a gate. The crew update `exe+30807a4` -> `307b7c0` runs only from body vtable slots `+0x488`/`+0x490`
(`exe+307a3bc`, `3098acc`).

## 6. Evening: the parapet stall FIXED (pack `A860`), one stall left

Runs 3-5, Altdorf practice siege, both batteries docked by right-click, enemy held at z -550. Run 5 (log `1205`,
sampler `run5_sampler.txt`) is the clean one. It is a rematch with **both batteries refilled every 2 s**
(`set_current_ammo_unary(1)`, the call CA's `grant_infinite_ammo` makes). Run 4 is void: the Helstorm ran dry on the
ground before it was docked, and its crew abandoned the engines (the author: "the rockets dismounted because the
ammo is gone"). It would not take a wall order after that.

**The parapet stall, found and fixed.**
- CA lays the wall slots on the zone's marker line, 0.5-1.3 m into the stone for an engine. The engine walks into
  the parapet and stops short.
- `+0x18f` is the arrived byte of the engine's locomotion state machine at body `+0x158`: vtable `3aded70`, state
  pointer at `+0x160`. The arrived state `exe+3d2b640` has enter `exe+8fcaf0` = `mov byte [rdx+0x37],1`. That is why
  no battle code writes `+0x18f` directly. The other state seen is `exe+3d2b638` (exit `exe+8d8480` = `ret 0`).
- The walk's own target is body **`+0x7f8`/`+0x800`**. The locomotion copies it into `+0x1e0` and `+0x838` every
  tick, which is why writing those two did nothing.
- **Fix (`dock_step`, shipped).** An engine still walking (`+0x710` = 4) that has stood still for 1.5 s within 2 m
  of its controller slot, on the slot's level, gets two writes: its walk target set to where it stands, and the
  slot point (`+0x20`/`+0x28`) moved there too. The locomotion then reaches the arrived state the native way, the
  walk ends and the engine deploys (`3916C70`).
- The slot write stops the controller from sending the engine back into the stone (seen in run 3: a recoiling
  cannon was re-sent and stuck again).
- `wall_step` now keys its once-only retry on the zone plus the first slot's marker row (`slot+0x18`), not on the
  slot's coordinates, which the fix moves.
- Offline test in `tools/artillery_walls_tests.lua`. A scratch mutation run broke `dock_step` eight ways; all eight
  were caught.
- **Run 5 result: all four cannons fired, 13 shots each in 1,077 s.** No earlier run got more than three of four.
  The two Helstorm engines that docked cleanly fired 10 shots each.
- **Do not write `+0x18f` by hand.** It ends the walk but leaves the locomotion in `d2b638`. Two Helstorm engines
  treated that way stood deployed for 1,000 s and never turned or fired. Setting the state pointer to `d2b640` as
  well did not bring them back either: they still differ from a firing engine at `+0x16c`, `+0x17c`, `+0x180` and
  `+0x188`, all inside the `+0x158` object.

**Still open: the zero-length go-to (mechanism B again).**
- Two Helstorm engines reached CA's slots exactly (z -339.0) and deployed at ~309 s.
- When the battery's order completed (~350 s, `ord 1 -> 0`), the wall controller gave them fresh go-tos
  (`3917110`). Those started (`+0x9c` 1), and both engines sat in walk state 4 for good. (`+0x9d` 0 is NOT "walk
  never issued": see §8. It only marks the `+0x890` route; the usual route through body vslot `0x568`/`0x580`
  leaves it 0.)
- `dock_step` re-settled them every 2 s to no effect. It now stays quiet below 5 cm, so this no longer floods the
  log.
- What I ruled out: a slot write does not trigger the re-issue (I nudged a slot 5 cm and nothing happened). The
  other two engines, one of which also arrived exactly on its slot, were not affected.

## 7. Next, in order (superseded by §8 and §9)

1. The zero-length go-to: not seen again in runs 6-9. Reopen only with a sample.
2. Ask 2 (pushers at the wall foot): unchanged from §5.

## 8. Late evening: the crew gate, the retry scramble, and why docked engines never fired (packs `8D92`, `3EC8`, `74DC`)

Runs 6-9, same Altdorf siege, both batteries docked by right-click, infinite ammo (refill every 2 s). Logs
`1241`, `1302`, `1314`; samplers and `+0xce0` rows `run6-8_*.txt` in `Backup/artillery_walls/20261109/`.

**The crew gate (asks 1 and 2), FIXED (`gate_step`, pack 8D92).**
- Body `+0x190` is the "may move" flag. The motion update `exe+3080948` sets it each tick: 1 only if every pusher
  task (types 0x10-0x14 in the list at `+0xc10`, count `+0xc0c`) reports ready and `+0x898` is null.
- Overrides force it to 1: `+0xd08`, `+0xdc4`, and the countdown `+0xdac` (ticked down each tick; CA itself sets
  it to 10 in `exe+2f7f830`).
- `gate_step`: an engine on a wall, still walking, standing still for 1.5 s with the gate shut gets `+0xdac` = 30
  (3 s). It then moves on without its crew. Logged once per engine as "waited for its crew". Seen working in runs
  7-9 on both batteries.

**The wall retry scrambled a docked battery, FIXED (pack 8D92).** `wall_step` treated a battery as done only when
every crewman was also on the wall, so a docked battery whose pushers lagged got CA's wall order again at 381 s
(run 6) and walked off its slots. Done is now "every engine on its slot with its walk finished" (`+0x710` != 4).
The one retry it still sends (run 8, 343 s, one engine 2 m short) re-laid the battery 8 m west, and it re-docked.

**`+0x9d` 0 is normal.** The go-to (`2f864bc`) issues its walk through body vslot `0x568` (walk_b `3aed8c8`) or
`0x580` and sets only `+0x9c`. `+0x9d` marks the other route (`+0x890`, `2f86a44`). §6's "never issued" was a
misreading.

**Ask 4, docked engines that never fire: FOUND AND FIXED (pack 74DC).**
- The engine's deploy is a flag machine at body `+0xce0` (current), `+0xce4` (in progress), `+0xcec` (pending);
  `exe+3094fcc` steps it. Vslot `0x658` (`exe+307145c`) is `(+0xce0 & 0x1080000) == 0x80000`: deployed, the gate
  the fire update `exe+3092384` sits behind. Every idle engine read `+0xce0` = 4; every firing one passed through
  `0xb0034`. Forcing the crew gate open on an idle engine (`+0xdac` = 100 every 500 ms for 40 s) changed nothing.
- The steps are the list at `+0xca8` (count `+0xcb0`, 12 bytes: flag, task type, flag). Helstorm:
  `4:1d 10:0,1,2 20:5,6,7 10000:1e 20000:1f 80000:21 1000000:b,c,d`. Step `0x10` waits on crew tasks 0, 1 and 2.
  The idle engines sat in that step for good.
- A crew task (vtable `3ADECA8`, made by `exe+3059f40`) holds its own target: local offset `+0x38/+0x3c`
  (+z is the gun's front) and world point `+0x48/+0x4c/+0x50`. Progress is at `+0x18`: 0 waiting (FSM `394FAC8`),
  1 going (`394FB90`), 2 there (`394FAF0`).
- **The target comes from a per-engine spot table** at `+0xcc0` (count `+0xcbc`, 0x50-byte rows keyed by task type
  through `**(row+0x20)`, offset at row `+0x40/+0x44`; `exe+3070110` finds the row). Rows 0/5/11/16 mirror crew
  slot 0's offset, 1/6/12/17 slot 1's, 2/7/13/18 slot 2's: copies of the slot spots as the game last laid them.
- On every stuck engine, exactly one task was "going" to a point inside the parapet: (1.32,1.52) to z -339.62, or
  (-1.37,1.05) to z -340.05, with the wall face at about -339.4. Its man walked into the stone for good (path 4).
- **They are CA's, not ours** (run 9 proved it; this section first blamed our quarter-turn tries). They recur to
  two decimals across runs, so they are not men's positions. The table's pusher layout rows (types 23 and 24) put
  pushers ahead of the gun at (+-1.5, 1.5) and (+-3, 1.5). An engine that stops with its pushers laid in front
  copies those posts, and docked facing the parapet they are in the stone.
- Proof in game: pulling one stuck task's target back to the gun's axle (`+0x3c` = 0, world point moved to match)
  took that engine's deploy from 4 to `10014`, and the next step's task headed into the stone again (same table
  row). Pulling every forward row and active task back on the three stuck Helstorms: all four fired (4, 3, 3, 2
  shots in 40 s, from 0, 0, 0, 2).
- First fix tried, NOT enough: `behind()` caps every offset the mod lays (`spot_try`, `spot_at_man`) at z <= 0
  (pack 74DC). It stays, since our own writes should not add forward posts, but run 9 had 0 Helstorm shots with it.
  `crew_step` also acts at a standing engine (path 0) when its man is still walking (pack 3EC8). The run-7 manual
  version took a stuck Helstorm from 0 to 5 shots, but it only reaches the crew slot and not the task's own copy.
- **The fix: `pull_crew_back` (pack A133, comment-only rebuild BF0C).** Every tick, for an engine on a wall that is
  not walking: every spot-table row of crew task types 0-18 with z > 0 gets all three offset copies (row
  `+0x34/+0x3c/+0x44`) set to 0; every task in the list with `+0x3c` > 0 gets 0, and its world point recomputed level
  with the gun (base `+0xd78/+0xd80`, heading `+0xd98`). The pusher layout rows 23/24 are left alone. Logged once
  per engine: "had crew posts in the parapet". Memory contract test, plus five mutants on it, all caught (24 in
  all).
- A real right-click fire order on the goblin spearmen (run 7) did nothing for an undeployed engine: 0 shots in
  142 s while its neighbours fired 4-5. The target is read; the engine is never in the deployed state.
- Five mutants on the new rules, all caught (19 in the scratch run in all).

## 9. Run 9 (pack `74DC`): the clamp alone fails

All four Helstorms docked by 312 s and fired **0** shots in 54 s. The cannons fired 1-2 each. Every Helstorm had a
going task at z 1.52, 1.39 or 1.24, with no mod spot write behind it. That is how §8's first explanation was overturned.

## 10. Run 10 (pack `A133`): every engine fires

- My first Helstorm click registered as a ground move to (578, 91.6, -377), outside the wall by the cannons; the
  view had moved between the check and the click. The battery walked along the cannons' wall and one engine went
  down to the ground. A second click gave the wall order at 391 s. All four were docked at 513 s, and the
  ground engine climbed back on its own.
- "Had crew posts in the parapet" logged 7 times: three cannons and four Helstorms. Cannon crews post ahead of the
  barrel too.
- **88 s after docking: Helstorms 5, 4, 4, 4 shots; cannons 4, 1, 3, 3.** It is the first run where every Helstorm
  fired without a hand write.
- **Open, new: the cannon at x 572 packed and never redeployed.** It fired 6 shots up to 255 s, then read
  `+0xce0` = 0, `+0xce4` = 0, `+0xcec` = 0 (nothing in progress, nothing pending, no tasks), fully manned, 0.37 m
  off its slot. Its `+0xcfc` reads `10000`, where deployed engines read `1000000`. A right-click fire order on the
  spearmen (the battery's target read back as them) did not wake it. Most likely it was bumped when the
  misdirected Helstorm walked along the wall behind the cannons (300-460 s). Not seen in runs 5-9.

## 11. Next, in order (superseded by §12-§16)

1. **The packed cannon (§10).** Find who clears `+0xcec` and sets `+0xcfc` (`exe_re.py writes cfc`), and what
   makes an idle engine queue its deploy again. Reproduce it by walking one battery along a docked one.
2. Ask 2 (pushers at the wall foot): the crew gate now moves engines without them; check whether the men catch
   up on a long wall.
3. **State.** `data/derpy_artillery_walls.pack` is `BF0C`; nothing is published. Test preferences are reverted and
   the `aw09_*` screenshots deleted. The practice battle is still the Empire Altdorf siege. The author's own battle
   is `Backup/.../singleplayer.battle_preferences.before`.

## 12. Run 11 (pack `BF0C`): the turn walks back to the ground

All four docked Helstorms fired **0** shots. Each one read `+0xcfc` 1 ("moving"), `+0xce0` 0 and `+0xcec` b0034:
the fire command had arrived and the deploy never started.

The chain: deploy step 0x1d calls `exe+3066250`. That checks whether the target is inside the gun's traverse. If not,
and the engine reads arrived, it calls `exe+308cfa0`, which sets a goal **at the anchor `+0xd10`** with the heading
turned toward the target. CA sets the anchor from the placement block `+0xd78` (`exe+306d7d8`, also `30865c4`,
`307f434`, `307fb30`). The wall controller's moves call none of them. So on a wall the anchor is still the engine's
start-of-battle spot on the ground (goal `+0x1e0` 255 m away), the "turn" is a walk there, re-sent every tick, and
`+0xcfc` never clears.

Fix (`59E0`): `anchor_step` copies `+0xd78` into `+0xd10` (0x20 bytes: location, heading, surface) for a standing
engine on a wall, or one whose anchor is still up on a wall after it came down.

## 13. Run 12 (pack `59E0`): the anchor works; the turn window does not

Enemy at x 450, so both batteries must turn past their traverse.

- **Cannons: 5-6 shots each in 166 s.** All 8 "turned toward a point it had left" lines logged, one per engine.
- **Helstorms: never fired.** First, fire at will gave them no target. The enemy was outside the unit's own arc
  (screenshot: the green arc lines face straight out). With a right-click attack order the fire command arrived,
  they turned 10 degrees (180 to 170) and stopped. `+0xcfc` 1, `+0xce0` 0, anchor correct this time.
- **The turn window.** `308cfa0` clamps the heading it asks for to `+0xd9a` +- 25 degrees. The 0.8727 rad at
  `body+0x2d8 -> +0x70` is the whole arc. The parent term (`*(body+0x20)` slot 0x20) returns 0, so there is no
  offset. `+0xd9a` is written only by `307f434` / `307fb30`, CA's placement calls, together with the anchor. On a
  wall it was the battle-start heading on the ground: Helstorms 145.4 (window 120-170, stuck at 170), cannons 175.2
  (window 150-200, stuck at 200; their own traverse reached the target from there, so they fired).
- **Live test:** `+0xd9a` set to 180 by hand. The Helstorms turned to 205 and three of four fired 14-16 times in
  661 s. The fourth's target sat at 227.4 degrees, past 205 plus its own traverse (about 22 degrees). That is the
  reach of a wall engine: slot +- (25 + traverse), about 47 degrees for a Helstorm.

Fix (`048C`): `base_step` writes the wall slot's heading into `+0xd9a` (slot row `+0x18 -> +0x28/+0x2c`, the same
bearing the wall loop already reads) for a standing engine on a wall. `+0xd98` is the laid twin
(`exe+3091848`). It is not used: it follows the current heading, and an engine that stops facing along the walkway
on its way would centre the window there.

## 14. Run 13 (pack `048C`): every engine turns; two cannons packed after a bump

- 8 "centred that on its slot" lines. Every engine read `+0xd9a` 180.0.
- **Helstorms, right-click attack at 226 degrees: turned straight to 205 and fired 12, 9, 12, 1 in about 5 min.**
  The 1 is the eastmost engine, at the edge of its reach.
- **The packed cannon of §10, reproduced.** The two cannons east of the stairs fired 3 each, then packed for good.
  `+0xce0`, `+0xce4` and `+0xcec` were all 0, byte `+0xcfe` 1 (§10's `cfc 10000`), and the command handover guard
  `cmd+0xc4` was 1. The 4 s command log shows them deployed and firing until 297-301 s. Then each moved 0.1-0.3 m
  and packed. At that time the Helstorm battery was walking east along the wall from the stairs at x 565 to its
  slots at x 705, past exactly those two. No mod line fired for the cannons then: it was a bump, not `dock_step`.
- **Why it never redeploys.** The fire command (vtable `3adf528`, embedded at body `+0x330`) hands its target to
  the engine once (`exe+3077880` sets `+0xc8c`, the aim and `+0xcec = flags & +0xce8`, guarded by `cmd+0xc4`). A
  bump clears the deploy and the unit's target has not changed, so no new command comes. That is also why §10's
  re-click on the same target did nothing.
- **Live test:** `cmd+0xc4` cleared by hand on both. They redeployed within 4 s and fired 14 and 15 shots, level
  with the other two (13, 14).

Fix (`3DB0`): an engine on a wall that has stood packed (`+0xce0`, `+0xce4` and `+0xcec` all 0) for 3 s, holding the
fire command with `+0xc8c` 1 and `cmd+0xc4` 1, gets `cmd+0xc4` cleared. The command then hands the target over
again. It uses `still_step`, the same clock as the gate.

## 15. Run 14 (pack `3DB0`): the bump reproduced on purpose

The cannons were docked and firing first. Then the Helstorms were docked, so they walked along the wall past the
cannons.

- All four cannons were shoved 0.2-0.4 m. Cannon 1 packed at 552 s. **"Stood packed with a target: asked for its
  deploy again" logged at 554.6 s, once in the whole run, and it fired on.**
- **Cannons in the 228 s after the Helstorm order: 9, 7, 7, 8 shots.** None stayed packed.
- A cannon reads packed for one sample between two shots: the command finishes and the next one hands over within
  4 s. The 3 s wait leaves that alone (cannon 2 at 664 s, no log line).
- The step never fired on the Helstorms, whose command is the move command, not the fire command. No script errors.

## 16. Next, in order (superseded by §17-§20)

1. **Reach on a wall is about +-47 degrees for a Helstorm** (slot +- 25 + its own traverse). A target past that,
   when ordered, leaves that engine turning for good (`+0xcfc` 1, 0 shots). Fire at will never picks one, because
   the unit's arc is narrower. Widening the window means crew posts beside a gun turned along the walkway, so it
   is the author's call, not a fix.
2. Ask 2 (pushers at the wall foot): check on a long wall that the men catch up after the crew gate moves an engine
   on without them.
3. Other races' artillery: every run so far is the Empire cannon and Helstorm.
4. **State.** `data/derpy_artillery_walls.pack` is `3DB0` (md5 `3db0ed6d0421baec63399a2643dcf43b`, also in
   `Modpacks/`); nothing is published. Test preferences are reverted. Runs 12-14 samplers, command logs and script
   logs are in `Backup/artillery_walls/20261109/`. 34 mutants (scratchpad `dock_mutants.py`) are all caught. The
   three new call sites in `update` have no offline harness; runs 13 and 14 are their check.

## 17. Run 15 (pack `3DB0`, hand writes): a smaller gun on a wall, and the radius cave

The author asked whether docked guns could take up less room, since their collisions might be part of the trouble.

- **Where the size lives.** The engine's `battle_entities` record is at body `+0x2d8`: `+0x5c` radius, `+0x60`
  shape, `+0x64` radii ratio, `+0x68` mass, `+0x6c` height, `+0x70` fire arc (radians). Cannon 2.6 / 2000 / 2.0,
  Helstorm 1.9 / 2000 / 2.3. One record is shared by every engine of that type in the battle, both sides.
- The body's own radius is `+0xa0` (height `+0x9c`; `+0xb14` is a copy taken at spawn and never read back). A Lua write
  to `+0xa0` lasts one tick: `exe+30957dc`, the entity update men and engines share, sets it every tick to battle
  scale (`exe+306c910`) times the record radius, at `exe+30959d7` (`movss [rbx+0xa0], xmm7`).
- **Experiment:** both shared records' radius halved by hand (1.3 / 0.95), cannons docked and firing, then the
  Helstorms sent along the wall past them. The cannons moved **0.00 m** (run 14: 0.2-0.4 m, and one packed) and fired
  32, 34, 34, 33 shots. Both records restored after.
- **The cave (`radius`, generated by `gen_artillery_walls.py`):** at `exe+30959d7`, when the body's vtable is the
  engine body's (`exe+3adee48`, first slot checked against `exe+305f2f0`), its unit is a listed wall gun, and its
  surface `+0x920` is not null, `xmm7` is multiplied by `WALL_RADIUS` (0.5, written into the cave block at `+0x70`).
  Height, mass and the record are untouched; crewmen (vtable `391E300`) never match. Unicorn scenarios: listed engine
  on a wall 1.3; on the ground, unlisted, empty table and a crewman all 2.6. Three new self-test breaks (35 in all).
- **Not measured:** whether `+0xa0` is also the size projectiles test against. If it is, guns on walls are harder
  to hit.

## 18. Run 16 (pack `A7DF`): the radius cave live, and posts swung into the stone

- **The cave works.** Installed at load, both gun units listed. 27,896 one-second samples: every engine on the
  ground read 2.60 / 1.90 and every engine on a wall 1.30 / 0.95. The one exception is a Helstorm sampled in the tick
  it stepped onto the wall, before the next radius write. All 88 crewmen read 0.65, on the wall and off it.
- **The bump test was not repeated.** I sent no right-click this run; the wall orders came from the author at the
  PC. The Helstorms docked at x 503-518, west of the stairs, so they never walked past the cannons. Cannon drift over
  250 s: 0.00 m, which proves nothing without a battery walking past.
- **Two of four cannons never fired** (x 569 and 583.6, 0 shots in about 5 min), deploy held at `+0xce0` = 4. Each
  had one crew task "going" (`+0x18` 1) to a point 0.3-0.5 m past the parapet face (z -339.7 and -339.9, face at
  about -339.4), its man stopped against the stone. The task offsets were (-1.80, 0) and (-2.35, 0): level with the
  gun in **the gun's own frame**, which is what `pull_crew_back` makes them. The guns stood turned 23 and 25 degrees
  off the wall's 180 (laid heading `+0xd98` 203 and 205; `+0xd9a` 180 from `base_step`), so a side post level with
  the gun swings 0.7-1.0 m forward. It has been possible since run 13, which first let guns turn on a wall.
- **By hand, tasks only:** both left step 4, then the next step's task came out of the spot-table row (still level
  in the gun's frame) and walked into the stone again, as in §8.
- **By hand, rows and tasks every 500 ms:** all four cannons fired, 11, 12, 10, 12 shots in about 60 s. The
  screenshot (`run16_cannons.tga`) shows the four laid along the wall, barrels over the parapet, crews behind.

Fix (pack `42CB`): `pull_crew_back` measures "ahead" along the wall. The parapet runs along `+0xd9a`, so a post at
side offset x may stand up to `-x * tan(wall - gun)` ahead of the gun and never further than level with it. Applied to
each of a row's three copies and to every crew task, whose world point is recomputed with both offsets. The angle is
clamped to 30 degrees, because a stale `+0xd9a` 90 degrees off would send a man tens of metres back. A gun square to
the wall gets exactly the old rule. Memory test cases: turned gun, far side, stale heading. Seven new mutants, 41 in
all, all caught.

## 19. Run 17 (pack `42CB`): every engine fires, and the bump is gone

Both batteries docked by my right-click, each only after a minute with no input from the author. The second click
waited 8 minutes for that.

- **Cannons docked at x 569-584 and all four fired with no hand writes:** 3, 2, 4, 3 shots in 60 s. Turned to 203-205.
- **Bump test, run 14 repeated:** the four Helstorms walked along the wall through x 560-595 at 1061-1066 s to slots at
  x 698-713. Cannons 2-4 moved **0.00 m**. Cannon 1 (settled 1.1 m back from its slot line) crept 0.17 m over the
  400 s before the order, with nothing near it, and 0.04 m more during the pass. Run 14 was 0.2-0.4 m on all four,
  and one packed. **Cannons in the 262 s after the order: 8, 9, 10, 8 shots; none stayed packed.**
- **Helstorms docked at x 698-713 held the move command and did not fire.** That is the §16 reach limit, not a
  stall: the held enemy at x 425-475 is about 50 degrees off their wall from x 705. With the enemy moved to x 650
  (`AWS.place`, a probe): **Helstorms 5, 6, 7, 6 shots and cannons 3, 3, 4, 3 in about 100 s.** The cannons turned to
  155-156, the other way from 203, so both sides of the post rule were in play.
- **No crew task "going" past the parapet face at any docked engine.** The sampler logged 22 at 1146-1167 s, all
  while the Helstorms were still walking east along the wall, which is pusher posts of a moving gun.
  `pull_crew_back` does not act on a walking engine, and those cleared once it stood.
- Radius: 11,552 samples. The two exceptions are each a cannon sampled in the tick it stepped from the stair top
  (y 91) onto the wall (y 106.6), as in run 16. No script errors.

## 20. Next, in order (superseded by §21-§22)

1. Decide with the author whether the smaller size should also shrink what projectiles hit (if `+0xa0` is that).
2. §16's 1-3 stand: Helstorm reach of about +-47 degrees on a wall (run 17 met it again with the target at 50),
   pushers catching up on a long wall, and other races' artillery.
3. **State.** `data/derpy_artillery_walls.pack` and `Modpacks/` are `42CB` (md5
   `42cb34e59fd6145de0065751ddde7af7`), verified in run 17; nothing is published. Test preferences are reverted.
   Run 15-17 samplers, command logs, radius logs, script logs and the run 16 screenshot are in
   `Backup/artillery_walls/20261109/`. 41 mutants (scratchpad `dock_mutants.py`) are all caught.

## 21. Runs 18-24: Dwarf and Elf war machines, and two stalls fixed (packs `42CB`, `F012`, `A93D`)

The author asked for other races' war machines. Same Altdorf siege, built with `tools/make_practice_battle.py`
(lord, one infantry unit, the two artillery units as units 3 and 4), enemy held still and immune. Wood Elves have
no war machines. Both units docked by CA's own wall-zone order (`occupy_zone` through `AWE.zone`; it puts a battery on
the same slots as the right-click, which run 17 showed), so no mouse was needed. Checks per battle come from the new
probe `probes/artwalls_bump.lua`. Each engine's radius is compared with its own `battle_entities` radius, half on
a wall and full off it. Each crewman's is compared with his own. Shots are counted per engine. A crew task "going"
past the parapet face (z -339.4) at a standing engine is logged. The bump test sends unit 4 west along the wall
through unit 3's slots and watches unit 3's drift. 3x battle speed.

Every engine of all six types uses the engine body vtable `3adee48`, so the radius cave covers them all.

| run, pack | units | radius on the wall | crew | bump: drift of the passed battery | shots |
|---|---|---|---|---|---|
| 18, `42CB` | Dwarf cannon, grudge thrower | 2.10 -> 1.05 both | 0.50 untouched | 0.00 m | cannons 10 each while passed; grudge 7-8 |
| 19, `42CB` | Dwarf organ gun, flame cannon | 1.90 -> 0.95, 2.10 -> 1.05 | 0.50 | 0.00 m | organ 18-19, flame 21-25 |
| 20, `42CB` | High Elf eagle claw x2 | 1.50 -> 0.75 | 0.68 | 0.00 m | 15-19, 10-12 |
| 21-23, `42CB`/`F012`/`A93D` | Dark Elf reaper x2 | 1.50 -> 0.75 | 0.65 | 0.00 m (run 23) | 18-21, 12-13 |
| 24, `A93D` | Dwarf organ gun, flame cannon | as run 19 | 0.50 | 0.00 m | organ 18-21, flame 25-27 |

Radius mismatches: one or two per battle, every one an engine sampled in the tick it stepped from the stair top
(z -322.5) onto the wall. No crew task ever stood past the parapet face at a standing engine, except one reaper for
4 s in run 21. No script errors in any run.

**Stall 1, the east stair head (runs 19 and 22, FIXED in `A93D`).** A battery ordered to the slots at x 698-713 that
climbed the east stair (head at about x 685, z -322.5) bunched at the stair head. The wall controller kept its 4
slots, but every slot's engine pointer was null (`AWX.slots`: `<- none`), each engine's walk target `+0x7f8` was
where it stood, and the crew gates were shut. Two engines held walk commands (`39242F8`, `+0xcfc` 1) and turned
through every heading while wandering within a metre, for over 400 s. The same zone order repeated by hand docked them
(run 19). The mod's one wall retry (`wall_step`) never fired because its stall test counted a turn of 1 degree or
a 0.25 m shift as progress. **Not the radius cave:** with the cave factor set to 1.0 live, the two kept spinning at full
size (run 22). Fix: the wall motion list carries no heading, and the wall stall test allows `WALL_DRIFT` = 2 m (a walk
along the wall covers that in 2 s). Runs 23 and 24: "recovering stalled ... (wall)" logged once each, at 182.7 s
(reapers) and 167.1 s (flame cannons). Both batteries docked from the first order.

**Stall 2, a pusher 0.3 m short on open ground (runs 21 and 22, FIXED in `F012`).** One reaper of each unit stood in
its walk on the ground, 150-180 m behind the wall, for over 800 s. Crew gate `+0x190` shut. Pusher tasks 0 and 2 read
done (`+0x18` 4), and task 1's man stood 0.3 m from his post, walking and never arriving. All eight crew were within
2-8 m. A repeated order did nothing. `+0xdac` = 30 written by hand once: the gate opened and stayed open, and the
engine drove to its wall slot in about 80 s with its eight crew following (run 21, `run21_gate_release.txt`). Ground
radius is unchanged by the cave, so this is CA's gate, not today's change. Fix: `gate_step` also releases an engine
off a wall, but only when every pusher (crew slots 0-2) is within `GATE_NEAR` = 3 m of it (the crew is around, ask
1), and only after `GATE_WAIT_GROUND` = 5 s standing still (1.5 s on a wall), so CA's own set-up at the start of a
walk is not cut short. Its own log line: "waited for a pusher standing beside it: moving it on". Run 22: it fired once
and that engine reached its slot. In runs 23 and 24 it never fired, and no ground stall happened.

Tests: `pushers_near` and the ground gate cases; a spinning battery stalls while a battery walking 1 m/s does not.
49 mutants, all caught. The heading dropped from the wall motion list is inside `update`, which has no offline
harness; runs 23 and 24 are its check.

Tool fix: `make_practice_battle.py --units a b --map m` took `m` as a fifth unit. The game ignored the unknown entry
and every battle loaded with its four units. The parse now stops at the next flag. The practice battle is back to
the Empire Altdorf siege: general, swordsmen, great cannon, Helstorm, four entries.

## 22. Next, in order (superseded by §23-§24)

1. Decide with the author whether the smaller size should also shrink what projectiles hit (if `+0xa0` is that).
2. Still open from §16: Helstorm reach of about +-47 degrees on a wall, and pushers catching up on a long wall.
   Other races: Dwarf, High Elf and Dark Elf artillery all done here. Not yet: Skaven, Lizardmen, Chaos Dwarf,
   Vampire Coast, Cathay, Ogre and Kislev war machines.
3. **State.** `data/derpy_artillery_walls.pack` and `Modpacks/` are `A93D` (md5 `a93d44c69b62d40f480094f3537f5cb8`),
   verified in runs 23 and 24. Nothing is published. Test preferences are reverted. Logs for runs 18-24 (radius,
   command, script, the run 21 gate release, the run 22 spin) are in `Backup/artillery_walls/20261109/`.

## 23. Evening: the three open checks, every other race, and four fixes (runs 25-32, packs `EB58`, `7A21`, `36CA`, `DB5E`)

The author asked for the three items §22 left open. Same Altdorf siege and probes as §21, three or more guns per
battle, all docked through `AWE.zone`, no mouse. Logs and pictures: `Backup/artillery_walls/20261109/run25_*` to
`run32_*`.

**1. Shots against a docked gun (static, then installed live).** The shrunken radius did shrink the target.
`exe+3165e14` builds the volume a path is tested against. Both its callers (`exe+2f765d8` in `exe+2f75fa8`, and
`exe+30b1ad2`) pass a segment, start and end, and read back how far along it the hit lands. It loads the radius from
the body's `+0xa0` and the height from `+0x9c`. In its shot mode (its fifth argument 2) it multiplies the radius by
vslot `0x150` = `exe+8fbbe0`, which returns the `battle_entities` record's `+0xb8`. That is
`projectile_intersection_radius_ratio`: record `+0xb8` read 1.0, `+0xbc` 0.75 and `+0xc0` 5 against the DB row's
ratio, `projectile_penetration_speed_change` and `projectile_penetration_resistance`. So the radius cave halved the
width every shot saw. New cave **`hitsize`** at `exe+3165e43` (displaces `mov edi, r8d; movaps [rax-0x58], xmm7`;
`rax` is the caller's frame and is saved). For a listed engine of class `3adee48` standing on a wall, it divides
`xmm6` back by `WALL_RADIUS`, so the gun is as wide to a shot as on the ground and only its bumping is halved.
Run 26: installed (the site opens with `e9`), and a carronade battery walking past four docked mortars moved them
0.00 m, so bumping still uses the half size. Selftest: five emulator cases, three breaks. **Not measured:** an
enemy shot hitting or missing a docked gun live. The held goblins have no missiles.

**2. Helstorm reach on a wall: about +-30 degrees, not +-47** (run 32, `run32_helstorm_reach.txt`). Four Helstorms
were docked at x 698-713 on the 180-degree wall, with the held enemy moved round in steps, 250 m out and 90 s of game
time each. The enemy's real centroid was read at each step: `AWS.place` is clamped at the map edge near x 766, and
the first pass's "+45/+65 degree" steps had really put the enemy about 30 degrees out.

| enemy off the wall's facing | engine headings | shots per engine |
|---|---|---|
| 24.7 deg | 203-205 | 3-4 |
| 29.4 deg | 203-205 | 3-4 |
| 34.5, 39.5, 43.9, 49.3, 58.7 deg | 203-205 | 0 (the counter shows 1: its first sample is a rising edge) |

The engine turns to the window edge (`+0xd9a` +- 25) and the launcher adds about 5 degrees. §17's "+-47" assumed
22 degrees of the gun's own traverse, and that is wrong. Widening it means letting `base_step` move `+0xd9a` toward
the target on a wall. That is the author's design call: a gun turned along the walkway. The new post rule below now
holds at any angle, so the crew side of that is no longer the blocker.

**3. Every other race.**

| run, pack | race: guns | result |
|---|---|---|
| 25, `A93D` | Skaven: Plagueclaw, Warp Lightning Cannon, both Regiments of Renown, Warp-Doom Magma Cannon | all deployed straight onto the wall and fired every round (88 each); the Magma Cannon had no crew handling (bug A) |
| 26, `EB58` | Vampire Coast: Carronade, Mortar, Queen Bess | all docked and fired 18-29 each; Queen Bess radius 3.60 -> 1.80 with its 48 crew read; bump drift 0.00 m with `hitsize` in |
| 27, `EB58` | Cathay: Grand Cannon, Fire Rain Rocket Battery | **crash to desktop 2 s after the battle start** (bug B) |
| 28, `7A21` | Cathay again | no crash; cannons docked and fired, rockets docked and did not fire; then refused (C) |
| 29, `36CA` | Cathay, refused | "active, 0 wall guns at load"; a wall order is ignored, the guns stay where they stand (CA's own refusal) |
| 30, `36CA` | Chaos Dwarf: Hobgoblin Bolt Thrower x8, Magma Cannon, Deathshrieker (refused there) | Magma Cannon docked and fired 44; seven bolt throwers fired 42-49, **one fired 2** (bug D) |
| 31, `DB5E` | Chaos Dwarf again, Deathshrieker allowed | bolt throwers 11-17 each, Magma Cannon 17, Deathshrieker 19; no post in the stone |
| 32, `DB5E` | Empire: great cannon, Helstorm | the reach measurement above |

Lizardmen have no gun the mod lists. The Ogre (Ironblaster, Scraplauncher) and Kislev (Little Grom) wall guns are
all drawn by an animal, so they are refused now (C) and were not run.

**Bug A, 48 crew on one engine (FIXED in `EB58`).** `SLOT_MAX` = 32 rejected the slot table of the Warp-Doom Magma
Cannon and the Queen Bess (48 crew, one engine), logged "crew slots unreadable", and ran neither with any crew
handling. Now 128. `--check` computes the largest crew per engine over the wall guns from `land_units`/`main_units`
and fails if `SLOT_MAX` is below it. The test reads a 48-slot table.

**Bug B, a different body class (FIXED in `7A21`).** Cathay's guns are vtable `exe+390f998`, not the walked gun's
`3adee48`: about half the slots differ, and there is no crew table at `+0xc1c`. The mover ran every per-engine fix on
them anyway, writing the turn point, heading, settle point and crew gate into fields that mean something else in that
class. The script log stopped at 203.0 s, and the game died at 19:59:32 with `0xc0000005` at
`Warhammer3.exe+0x17AB18B`, a virtual call through an object whose vtable read -1 (`crash_report/D2026-11-09_T19-59-32.mdmp`). Fix: `is_gun(b)`
(the body's vtable is `CALLS.engine_vt`) gates the mover's engine list, `lay_spots` and the dock settle step. Any other
class gets no write of the mod's. The radius and hitsize caves already checked the class. Every walked race so far
is `3adee48`, the Chaos Dwarf vehicles included (run 30 read it).

**C, guns drawn by an animal are refused (the author's call, `36CA`, rule corrected in `DB5E`).** The author: no
Cathay-style engines on walls, "like chariots with cow draughts", and of the two readings, the drawn ones only, not
the ridden Chaos Dwarf vehicles. Rule: the unit's `land_units.mount` is set and that mount's `variant` is not
`dummy_variant`. That gives 8 units in the Lua's generated `DRAWN` list: Cathay x2, Ironblaster, Scraplauncher, Little
Grom x2, War Wagon x2. `wall_gun()` refuses them even when `unit:is_artillery()` is true, which Cathay's are. The first
version (`36CA`) used `battlefield_engines.draught_attachment_point` and wrongly refused the Deathshrieker: its model
names a draught point, but the unit has no mount. The Chaos Dwarf vehicles' mounts are hidden ones
(`chd_hidden_mount_*`, `dummy_variant`) that carry the vehicle. 50 vanilla wall guns remain. **Ceiling:** a modded
drawn gun admitted by `is_artillery()` is not caught, because the Lua cannot see its mount. **Unchecked:**
`OCCUPY_WALL`'s `AIUF_ARTILLERY` 0.65 also weights the AI toward ordering refused artillery (Cathay's) onto a wall.
CA ignores such an order (run 29 for the player's), but whether the AI then wastes its plan was not run.

**Bug D, a gun laid 65 degrees off its slot (FIXED in `DB5E`).** Run 30: bolt thrower e5 stood on its slot facing 115,
with `+0xd98` 115 and `+0xd9a` 180. Its deploy held at `+0xce0` = 4 for 740 s on two crew tasks 0.4-1.4 m past the
parapet face, so it never reached the deploy step that turns it into its window. The old post rule (`z <= -x tan(t)`,
`t` clamped at 30 degrees for a stale `+0xd9a`) pulled those posts back for 30 degrees, not 65. New rule: a post
(x, z) reaching `e = x sin t + z cos t` toward the face is moved straight back by `e`, and both its x and z are written
on the rows and the tasks. No post is left ahead of the gun. This holds at any angle and moves a post at most its own
distance, so the clamp is gone. Tests: the 65-degree case ends level along the wall; a post just behind the face line
on a turned gun is left alone; the stale case moves a post at most its own length. The 23-degree case's expected world
point is now 1.8 cos t along the wall (straight back) instead of 1.8 / cos t (along the gun's axis). Run 31 did not
lay a gun that far off again, so the live check is only "no post in the stone and every engine fires".

**Tools.** `make_practice_battle.py`: `--lord <key>` writes a bare `key:faction:1` general (the Skaven, Vampire Coast
and Ogre setups here lead with a hero or a mod lord), and `--unit-faction` names the faction each entry carries.
Every entry naming `wh2_main_skv_clan_pestilens` dropped the whole army; the game's own Skaven entries name
`wh2_main_skv_skaven`. The game reads the file once per launch and writes its own army back when a battle ends, so
write it with the game shut. Unexplained: run 25 loaded two Skaven Regiments of Renown the file never named. The
bridge's `wh3_click_ui` on `button_battle_start` reports "component not found" after it has clicked. 57 mutants in
the scratch runner, all caught (posts re-aimed at the new rule, plus the class gate, the drawn list and the slot cap).

## 24. Next, in order (superseded by §25-§26)

1. The author's call: widen a docked gun's reach past +-30 degrees (`base_step` turning `+0xd9a` toward the target
   within some limit), or leave it.
2. Measure a docked gun being shot at with `hitsize` in (an enemy missile unit held in range, hits counted against
   the same gun on the ground).
3. Watch an AI-defended siege with Cathay or Ogre artillery for the AI ordering a refused gun onto a wall (§23 C).
4. Still open from §16: pushers catching up on a long wall.
5. **State.** `data/derpy_artillery_walls.pack` and `Modpacks/` are `DB5E` (md5 `db5e2787252cff40eb5a61eb55f616cf`),
   verified in runs 31-32. Earlier packs `A93D`, `EB58` and `DB5E` are backed up beside the logs. Nothing is
   published. Test preferences are reverted. The practice battle is the Empire Altdorf siege again.

## 25. 2026-11-10 morning: enemy arrows on a docked gun, and a Cathay AI holding the walls (runs 33-34, pack `12F8`)

**Pack `12F8`** (md5 `12f848fccb7b11aa9a4e7631cb51db92`): the `hitsize` cave counts each test it widens. One
`lock inc dword ptr [rax + 0x74]` (block field `hit_count`, a free slot after `wall_radius`) before its `divss`.
It is in the docked branch only, so the count is exactly "a hit test against a listed engine on a wall". The selftest
expects 1 on that path and 0 on the four others, and a 39th break removes the counter. The site sits in the builder's
prologue (`exe+3165e14`: `r10`, `r11` and the flags are dead there, and the function reads `r11` only after
`lea r11, [rsp + 0xd0]` in its epilogue), so the cave's scratch registers are safe.

**Run 33, enemy arrows (`run33_hitsize_arrows.txt`, `run33_cannons_under_arrows.png`).** The enemy was the warboss
with Orc Arrer Boyz, Goblin Archers and Night Goblin Archers (`make_practice_battle.py --enemy-units`), held and
immune. Both batteries were docked through `AWE.zone`, cannons at x 569-584 and Helstorms at 703-718. The archers
were placed about 120 m out (`AWS.place(610, -460, 40)`) and each unit was given `attack_unit` on the cannon battery.

| window | enemy arrows | `hit_count` |
|---|---|---|
| docking (battle start to both batteries docked) | 0 | 9,647 |
| docked, archers held, 87 s | 0 | +56 (0.6/s) |
| archers shooting, first 72 s | 1,848 | +14,743 (205/s) |
| archers shooting, 655 s, quivers empty | 7,740 | +61,218 (about 8 per arrow) |

So the cave is in the path every enemy arrow takes past a docked gun. The count during docking comes from the
batteries' own movement and shots beside each other. No crash and no script error. All eight engines kept firing
under the arrows: cannons 21-24 shots, Helstorms 29-34. The Helstorms stopped once the archers stood more than 30
degrees off their wall, which is the §23 reach. Radius: 0 mismatches (wall 1.30 and 0.95, ground 2.60 and 1.90). No
crew post past the face. **Not measured:** how many arrows a docked gun stops compared with the same gun on the
ground. The crew was invincible, and the counter reads only docked guns. The emulator is what shows the full width
comes back.

**§16 ask 2, pushers on a long wall: caught up (run 33).** The Helstorm battery climbed at the stair near x 565 and
walked about 135 m east along the walkway to x 703-718. The crew gate moved one of its engines on once ("waited for a
pusher standing beside it", 230 s, on the ground). After the battle all 88 crewmen of both batteries stood on the wall
(`+0x920` set), each in his slot, the farthest 6.0 m from his engine.

**Run 34, the AI holding the walls with refused guns (`run34_cth_ai_defends.txt`, `run34_cth_ai_guns.png`).** The
practice battle's two alliance records each end `u8 flag, u32 8` just before the army's faction. The flag is 1 for
the side attacking the settlement and 0 for the side holding it, and the game writes the player 0. With the flags
swapped (`--player-attacks`, new) the Empire attacked Altdorf and a Cathay AI held it: the magistrate, Jade Warriors,
Grand Cannon and Fire Rain (`--enemy-faction wh3_main_cth_cathay_mp --enemy-lord
wh3_main_cth_cha_lord_magistrate_0`). Both sides were invincible, and the AI was left in control. The Jade Warriors
took the wall (wall controller `+0x3310` = 1). Both guns stayed in an open square inside the city, 220-235 m behind
the wall, and shifted less than 15 m all battle. Neither ever had the wall controller. They fired at the Empire army
outside until nearly empty: the Fire Rain 336 -> 0 by 548 s, the Grand Cannon 84 -> 6 by 602 s (from 90 s). So `OCCUPY_WALL`'s
0.65 for artillery does not cost a Cathay defender its guns. That covers one small army on one map: a campaign siege
with a full stack was not run.

**Tools.** `make_practice_battle.py`: `--enemy-units` (the enemy's own lord kept), `--enemy-faction` and
`--enemy-lord` (a bare lord of another faction), and `--player-attacks`. The selftest rebuilds the enemy block
byte for byte from its own parse and checks that the flag swap changes two bytes. The game rewrites the file when a
battle starts, and kept the swapped flags.

## 26. Next, in order (superseded by §27-§28)

1. The author's call: widen a docked gun's reach past +-30 degrees, or leave it (§23).
2. Optional: a campaign siege against a full Cathay, Ogre or Kislev stack, to watch the AI with refused guns at
   scale (§25 covers one small army).
3. **State.** `data/derpy_artillery_walls.pack` and `Modpacks/` are `12F8` (md5
   `12f848fccb7b11aa9a4e7631cb51db92`), verified in runs 33-34. `DB5E` and `12F8` are backed up beside the logs.
   Nothing is published. Test preferences are reverted. The practice battle is the Empire Altdorf siege again
   (1,273 bytes, the player defending).

## 27. 2026-11-10: a docked gun turns and fires all the way round (runs 35-41, packs `6D74` to `B6FB`)

The author, on §26's first item: "yes as much as possible 360 degrees". Two limits stood in the way. Two caves
remove them: `turn` and `wallscan`. Three caves built in between (`allround`, `cone`, `faw`) were measured inert
and are gone from the shipped script.

**1. The turn clamp (cave `turn`, pack `6D74`).** An engine turning toward a target asks set-goal `exe+308cfa0` for a
heading, clamped to `+0xd9a` +- half the fire arc. The arc is the `battle_entities` record's `+0x70` (0.8727 rad, 50
degrees), scaled at `308d09b` and rounded to a u16 half-arc in `eax` by `50d908`. The clamp is `308d0bb..308d105`.
The cave sits at `308d0a8` (displaces `lea rdx, [rsp+0xa0]`). For a listed engine (class `3adee48`) on a wall it
sets the half-arc to `0x7fff`. It cannot be `0x8000`: CA's clamp reads `-0x8000` as `+0x8000` and would pin every
heading to the back of the window. Only set-goal reads `+0xd9a` (a scan of every `[reg+0xd9a]` operand), so
`base_step`'s slot heading there now matters only to the crew-post rule.

Run 35 (`run35_turn_sweep.txt`, `run35_helstorms_turned_180.png`): the held enemy moved round the Helstorms 250 m
out in 90 s steps. The Helstorms turned and fired at every step from 30 to 180 (3-5 shots each). At 180 they stood
facing into the city and fired over the walkway. The cannons stalled at 70-85 until the mod's wall retry re-docked
them on the walkway's inner line. From there they fired at 120-180.

**2. Fire at will (cave `wallscan`, pack `B6FB`).** Run 36: with no order (`+0x2f88` 0, how a battery stands after
the wall order), a target that appeared 39 degrees off killed all four cannons' fire actions in one tick. They
turned, packed and stayed silent until an enemy was back in front. The search for the cause took four runs. For
the next person, here is what does NOT decide a docked unit's fire at will:

- **The regiment pick `exe+30297f4`** (its cone at `30298f6` / `3029919`, its second choice `3029a60`). Its gate
  `exe+30243c8` asks the wall controller (`+0x3310`, vtable `391d440`) through slot `+0x1d8`, which is `exe+8d8530`,
  `xor al, al`. Opening the gate (cave `faw`, run 39) made the pick return a target (the tick object's `+0x48` held
  the enemy). But both issuers, `302edc8` and `302ef5c`, hand the attack to the controller's slots `+0x38` /
  `+0x30`, and those are a bare `ret` (`8d8480`).
- **The per-gun step `exe+301cc0c`.** Live counters on its entry gates read 0 for both batteries, in front or not.
  The regiment's firing list (`+0x32dc`) is empty on a wall.

What does decide it was found by recording return addresses at the engine vtable's fire slot `+0x380`
(`exe+307850c`): every fire action on a docked gun came from `exe+328f27a`. That is the plan step `328ec68` of the
attack behaviour (vtable `3926458`). At the jump, that behaviour's memory was freed. A stack copy taken in its
deleting destructor (`327522c`) named the killer: the wall state's fire-at-will refresh `exe+3036384`.

- It builds one search area per wall section in `301e9f4`: a cone straight out from the section (`2f38520`), with
  half the gun's fire arc (`+0x3db0 -> +0x70`).
- It gathers the enemies inside each cone (`2f64678`, test `2f4fd94`).
- When every section comes back empty, it zeroes its target list (`+0x194`) and destroys the attack (`30dc0ec`).
  Nothing issues a new one.

The cave sits at `exe+3036668`, before the gather (displaces `lea r9, [rbp-0x49]; mov rax, [rbx+0x18]`). For a
listed unit (`rbx+0x18`) whose first man stands on a wall, it calls CA's all-round gather `exe+2f64860` into the
same list (`exe+4348fa8`): every enemy within range of the unit. The arguments are the ones fire at will's ground
pick passes at `30298f6`: the unit in `r8` and `r9`, the range in `xmm3` (here `xmm6`), and 0, -1, 1 on the stack.
It then rejoins after CA's call at `exe+3036691`, where `30335f8` picks the best of that list. The block pointer
rides on the stack across the call, and the push plus `0x38` keeps it 16-aligned. The selftest runs it under
unicorn and checks the alignment, all five argument values, the rejoin and `rsp`, plus five breaks (47 in all).
Widening the cone itself was rejected. Its shape is a box plus two edge regions at heading +- the half-arc, and at
180 degrees the two edges coincide.

A trap met on the way: a probe copy of `wallscan` crashed the game at `exe+3036693` (dump
`D2026-11-10_T09-21-58.mdmp`). The probe wrote its continuation as the Lua literal `0x3036691`. WH3's Lua numbers
are float32, so that rounded to `0x3036690`, and the `ret` landed one byte short. The shipped Lua writes every
address as a `{hi, lo}` pair, which is exact.

Run 40 (`run40_wallscan_jumps.txt`, pack `B6FB`): both batteries docked with no order, and the target JUMPED each
time.

| target | cannons (x 569-584) | Helstorms (x 698-713) |
|---|---|---|
| 45 off the cannons, 60 off the Helstorms | turned to 228 (bearing 224), 4-5 shots each in 140 s | turned to 238 (bearing 239), 6-7 each |
| 85, along the wall, 124 m from the cannons | 1 turned, 0 shots | turned to 264, 3-4 each |
| 180, inside the city | turned to 22-25 (bearing 26-29), 2-3 each | turned to 1-7, 3 each |
| back out in front | 2-3 each | 3 each |
| along the wall, 250 m from the cannons | 3 turned to 265, 1 shot in 130 s | 5-6 each |

Runs 38-39 at the first row: every gun lost its fire action and fired 0-1 times in 300 s.

**The limit that stays.** A cannon will not fire nearly along its own wall. A target 250 m along it and 28 m out
is 6 degrees off the wall line. The three cannons that turned to it sat aimed (`+0xce0` `b0034`), with fire
actions, and did not shoot. The fourth (the eastmost) would have had three guns of its battery in its line, and
stayed packed. No friendly unit stood west of them. A direct-fire shot there would cross the parapet, while the
Helstorms' arcing rockets fired at the same bearing. This was not chased. CA's clear-shot test is already answered
"clear" for these engines (`clearshot`), so whatever holds them is a later check.

Run 41 looked at it (pack `B6FB`, the same jumps, in-game frames beside the logs). At 45/60
(`run41_cannons_45.png`, `run41_helstorms_60.png`), the four cannons stand in a row on the walkway with their
barrels angled out over the parapet toward the target. The Helstorm frames are angled the same way, and rockets are
in the air (`run41_jump_45_60.png`). At 180 (`run41_cannons_180_close.png`), the cannons sit at the parapet with
their muzzles turned back into the city and their crews round them, and nothing is out of line. The headings read
23-25 against a bearing of 26-29. A Helstorm launch shows at 180 in `run41_helstorms_180_in.png`.

The tools behind this were live diagnostic caves in the eval bridge: unit-keyed counters, return-address recording
at a vtable slot, and a one-shot stack copy in a destructor. Their assembly is in the session's scratchpad, not in
`tools/`. Their pattern: assemble with keystone, write the buffer address over a placeholder, install with
`mr.patcher(name):cave(name, site, bytes)`, and write every address into the buffer as `{hi, lo}` arithmetic.

## 28. Next, in order (superseded by §29-§30)

1. The author's look at all-round fire in a real siege. The guns now turn round to whatever fire at will picks, and
   that includes targets inside the city. Whether a battery should turn its back on the field for one unit in the
   streets is a design call. CA's best-target choice (`30335f8`) weighs the candidates, and the cave does not.
2. Optional: the cannon that will not fire along its own wall (§27, "The limit that stays"). Find what holds a
   turned cannon at `b0034` with a fire action. Rockets are not held at the same bearing.
3. Optional, from §26: a campaign siege against a full Cathay, Ogre or Kislev stack.
4. **State.** `data/derpy_artillery_walls.pack` and `Modpacks/` are `B6FB` (md5
   `b6fb794c8a9c3dda6dc4ecf366adbc84`), verified in runs 40-41. `C663` (faw), `2CA5` (cone), `9F87` (allround) and
   `6D74` (turn only) are backed up beside the logs. Nothing is published. Test preferences are reverted. The
   practice battle is the Empire Altdorf siege (1,273 bytes, the player defending).

## 29. 2026-11-10: single player only, and the regression pass (pack `A862`, runs 42-44)

The author asked for the mod to be single player only, and for a regression pass on `B6FB`'s two new caves before an
upload.

**Single player only.** `install()` now returns at once in a multiplayer battle (`bm:is_multiplayer()`, the call
CA's own battle scripts use), and the script log says "multiplayer battle: single player only, walls stay vanilla".
A cave stays in the exe for the whole game session, so a multiplayer battle after a single player one would still
run every cave against the earlier battle's unit list. The gate therefore writes that list's count to 0 first (the
block is found through `hook_info` on `climb`, as `install` finds it). Every cave tests the list (`FIND`); `rear`
tests the flag `solver` sets, which `solver` clears for an unlisted unit. With a count of 0 they all fall through to
CA's code. `tools/artillery_walls_tests.lua` checks both branches through the exported `install`, and a copy without
the count write fails it. A multiplayer battle itself was not run.

**Run 42, Dwarfs on the wall (`run42_dwarfs_jumps.txt`, `run42_dwf_cannons_180.png`).** A cannon (unit 3) and an
organ gun (unit 4) were docked by `AWB.dock` at x 576 and 705. The held Greenskin target jumped every 100 s, as in run
40:

| target | cannons | organ guns |
|---|---|---|
| front | 3-4 shots each | 5-7 |
| 45 / 60 off | turned to 226-229 (bearing 222-225), 3 each | turned to 236-237, 5-6 |
| 85 off, along the wall | turned to 259-260, 0 shots | turned to 263, 5-6 |
| 180, inside the city | turned to 22-25 (bearing 26-29), 4 each | turned to 4-6, 5-6 |
| front again | 3 each | 5-6 |

The cannons' 0 at 85 is §27's along-the-wall limit. The frame shows the four cannons in a row at the parapet. There
were no script errors.

**Run 43, the Empire AI holding the walls with listed guns (`run43_emp_ai_defends.txt`).** Built with
`make_practice_battle.py --player-attacks --enemy-faction wh_main_emp_empire --enemy-lord wh_main_emp_cha_general_0
--enemy-units` swordsmen, great cannon and Helstorm. The Dwarfs attacked, both sides were invincible, and the AI was
left in control. The log read "4 wall guns at load".

- The AI kept both guns on the ground inside the city, at 98,-115, facing the Dwarfs about 475 m south, and never
  ordered them up.
- The Helstorms fired all 240 rockets.
- The great cannon engines fired 20, 16, 13 and 0 shots. The two short ones read `+0xce0` `4000030`, which is CA's
  "Clear shot failed" (see below).
- The mover logged nothing for either AI unit.

**Run 44, the same battle without the pack (`run44_emp_ai_defends_vanilla.txt`).** The attacker deployed on the other
side this time (north-west). The AI's guns stood on the hill at 65,124, facing the Dwarfs about 560 m off, and fired
nothing for 750 s. With the Dwarfs teleported to z -390, the AI moved the guns to 115-127, 52-61. Every cannon engine
then fired 16-18 shots, and no engine read `4000030` in 215 samples. The two runs differ in attacker side and gun
placement, so they do not show the AI weighting change moving the AI's guns.

**`4000030` is CA's verdict, not the mod's.**

- The fire update `exe+3092384` ORs 0x4000000 into `+0xce0` and `+0xce4` at `3092474` when the clear-shot test
  `exe+30660f0` returns false. The string beside it, at `exe+3addda8`, is "Clear shot failed".
- The `clearshot` cave sits on `30660f0` and answers only for a listed engine with a wall surface. A ground engine runs
  CA's test. The cave's miss path clobbers only rax, r10 and r11, which the function sets before it reads them.
- So a ground gun showing it has its line blocked from that spot.
- On 6acec6f4 the same flag was read as two u16 halves, `52/1024`, in memory `wh3-engine-fire-state-fields`.

**Tool trap.** `make_practice_battle.py` builds every write from the 2026-11-01 backup (the Black Pyramid, with a
Greenskin enemy), not from the file as it stands. Without `--map major_a_emp`, the battle is on the Black Pyramid. The
docstring now says so.

## 30. Next, in order

1. **Done 2026-11-10:** the author published the mod as Workshop 3837212899, "Derpy's Artillery on Walls ( Vanilla
   9.X.X )", tags `mod` and `battle`. The description is 2,829 characters with five GIFs on Imgur; all five were
   checked as animated. The page record is `docs/workshop/artillery_walls/HANDOFF_20261110_WORKSHOP_DESCRIPTION.md`.
2. **Settled by the page:** guns turning their backs on the field for a target in the city (§28 item 1). The page
   lists it as a feature: "Guns turn all the way round and fire at will, including at enemies inside the city."
3. Optional: §28 items 2 and 3.
4. Open: the mod has no public GitHub repo yet (memory `github-one-public-repo-per-mod`).
5. **State.**
   - The Workshop folder `workshop/content/1142710/3837212899/` and `Modpacks/` hold `A862` (md5
     `a862bd1007b717a68a4933910f26934f`), backed up beside the logs with `B6FB`. The `data/` copy was removed after the
     upload: a `data/` copy shadows the Workshop one.
   - Deploy any new build into the Workshop folder, never into `data/`, and check the md5 after Steam's validation
     pass. On a game patch the mod switches itself off; new addresses come from `tools/exe_migrate.py`.
   - Test preferences are reverted.
   - The practice battle is the Dwarfs defending Altdorf with Derpy's Gunpowder Units' Ironblasters and
     Mountainbreaker (the GIF capture). That needs `!!!!derpy_resources` and `derpy_gunpowder_units` in the mod list.
     Rewrite it, with `--map major_a_emp`, before the next run.
