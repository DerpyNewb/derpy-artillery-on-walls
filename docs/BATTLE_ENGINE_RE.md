# Battle engine internals - reverse-engineered, build 6acec6f4

What `Warhammer3.exe` does with one battle soldier (a "man", a model): his fields, his virtual methods, his
command, his two action slots, and the per-tick gate that decided whether a clicked swing ever played. Also the
three tools that found it, and how to use them on the next question. Every address is an RVA, written `exe+RVA`;
the image base is `0x140000000`. Everything here was read on **build 6acec6f4** (the 2026-10-16 patch) and is
marked **live** where a probe in the running game confirmed it, **code** where it is read from the
disassembly only.

The code that uses these facts is `Modding Files/source/third_person/script/derpy_tp/platform.lua`, the only
file in the third-person pack holding an address. The session record is
`docs/sessions/HANDOFF_20261016_THIRD_PERSON_MOUNTS_AND_DEATH.md`, the last section; the later third-person
handoffs (`docs/SESSION_INDEX.md`, through 2026-10-21) added to sections 3, 5 and 14 and wrote sections 12 and 13,
all on the same build.

## 1. The tools, and which question each answers

| Question | Tool | Cost |
|---|---|---|
| Who calls this function / loads this address? | `py tools/exe_re.py refs <rva>` | seconds |
| What is in this vtable? | `py tools/exe_re.py q <rva> [n]` | instant |
| Which vtable slot holds this function? | `py tools/exe_re.py ptrs <rva>` | seconds |
| Who calls the virtual at slot `+disp`? | `py tools/exe_re.py slotcalls <disp>` | seconds |
| Who writes a constant into field `+disp`, and which constant? | `py tools/exe_re.py stores <disp>` | seconds |
| Who writes field `+disp` from a register, or adds to it? | `py tools/exe_re.py writes <disp>` | seconds |
| Where exactly does the function holding this address start and end? | `py tools/exe_re.py pdata <rva>` | instant |
| Which subclass vtable is this pointer in, at which slot? | `py tools/exe_re.py vtmatch <known_vt> <rva>` | seconds |
| What does this function do? (assembly) | `py tools/exe_re.py dis <rva> [n]` / `fn <rva>` | instant |
| What does this function do? (C) | `py tools/ghidra_decompile.py <rva> [...]` | ~8 s per call |
| Is it what the game does right now? | memreader Plus probe over the wh3 bridge (section 9) | a battle |

`exe_re.py` reads the exe **on disk** with capstone and numpy, read-only, with the game shut or running. The
on-disk code is byte-identical to the live code (checked 2026-10-16), so it is the safe way to ask. `--selftest`
checks each command against a fact of this build. Two traps it works around:

- **The section names are disguised.** The code is in `.udata` at RVA 0x1000 (0x33a6000 bytes), the vtables are
  in `.xcode`, and `.text` is a 0x200-byte stub. A tool that trusts `.text` finds nothing. `exe_re.py` takes the
  section that holds a known function.
- **There is no RTTI.** Vtables run into each other with no complete-object-locator between them, so "scan back to
  where the vtable starts" is a guess. `vtmatch` aligns the region against a vtable whose base you know instead: a
  subclass keeps most of its base class's entries at the same index. That is how slot `0x4a8` was found (section 4).
- **A function's start was a guess.** Walking back to CC padding can land on an earlier function: it gave `2fd97cc`
  for `2fda558`, where the PE `.pdata` unwind range is `2fda19c..2fda624` (2026-10-20). Since 2026-10-29 `fn` and
  every "in fn" column read `.pdata` first. Only a leaf function, which has no entry, still falls back to the CC
  walk. Give Ghidra the true start: its helper makes a function at whatever RVA it is asked, mid-body included. On
  2026-10-29, three of eight hit-point writers decompiled as fragments that way.

The analysis behind this document was done with `exe_re.py` (then a scratchpad script) and live reads. **Ghidra
was set up afterwards** (section 10) and its decompile of the same five functions agrees with every line of the
reading below. Ghidra gives C, so use it to read a function's logic. For "who calls / who writes / which slot",
`exe_re.py` answers in seconds with no project.

## 2. Worked example: from "the swing never plays" to the one byte

Each step is one command, and each answer is the next step's input.

1. **Find who installs the forced clip.** The forced-clip command's vtable is `exe+3911fb0` (known). `refs 3911fb0`
   finds exactly one write: inside `exe+306e850`. Its disassembly destroys the man's command (`+0x328`), constructs
   a new one at `+0x330`, writes vtable `3911fb0` and copies a 16-byte payload to `+0x368`.
2. **Find who calls that.** `refs 306e850` finds only `exe+311bd24`, and `ptrs 311bd24` finds it stored at
   `exe+3915ec8`: a vtable slot, so it is called virtually.
3. **Which slot?** `vtmatch 3912950 3915ec8` (3912950 is an infantry man's vtable, read live) gives the subclass
   vtable `exe+3915a20` and slot 149, `+0x4a8`. The base class holds `306e850` itself at that slot.
4. **Who calls slot 0x4a8?** `slotcalls 4a8` finds three sites. The battle one, `exe+2f7809a`, is in
   `exe+2f7805c`: it builds the payload from its own object's `+0x40` and calls the man's `+0x4a8`.
5. **What object is that?** `ptrs 2f7805c` gives slot 1 of vtable `exe+390c0b8`, and `refs 390c0b8` finds its
   constructor `exe+2f641b8`. That constructor has two callers. One is `exe+2ecf4dc`, the command-stream reader for
   the pack's play command (tag 0x28). It builds this object in the man's `+0x5c8` slot. **So the play command does
   not start a clip: it parks an action.**
6. **Who runs parked actions?** Searching the battle code for instructions that test `+0x6f8` (the slot's "has"
   byte) led to the runner `exe+3088218`. `refs 3088218` gives the man's action update `exe+3075e7c`, and
   `refs 3075e7c` its regular caller, the gate in `exe+3086f04`.
7. **What does the gate test?** `+0x324`. `stores 324` lists every writer with its value. They are all
   command-start routines, one code each, so `+0x324` is the kind of order he got **this tick** (section 7).
8. **Live**, per frame (section 9): every failed swing sat parked and never started, while `+0x324` flipped 1/0
   tick by tick. The fix is the gate's one branch byte (section 8).

## 3. The man: field map

Offsets on the model object (the man; for a rider, his mount is a model too, at `+0x2e0`).

| Offset | What | Source |
|---|---|---|
| `+0x0` | vtable: `exe+3912950` an infantry man; `exe+3915a20` a subclass with children (overrides `+0x4a8`) | live / code |
| `+0x58` | -> object whose `+0x440` is the battle; the battle's `+0x98` is the tick count | code |
| `+0x88` / `+0x8c` / `+0x90` | position x, y, z (float) | live |
| `+0xb0` | facing, u16 (0x10000 = full turn) | live |
| `+0x108` | flags: bit 0x10 reaches the command/action path, bit 8 and bit 4 take other branches (read 0x33 in melee) | live / code |
| `+0x128` | an object whose `+0x78` check also sends him to the gate (null in every melee frame measured) | live |
| `+0x194/+0x198`, `+0x1e0/+0x1e8` | steering point copies x, z | live |
| `+0x1e4` | the walk's destination y (read his own height, 654.7, on a siege wall) | live, 2026-10-21 |
| `+0x278` | current animation slot, u16; valid while `+0x898` is set or `+0x284` is not 0 | live |
| `+0x2e0` | mount parent (rider -> horse); null on foot. A crew shares one: all 5 of a Necrofex Colossus's men and all 4 of a Warsphinx's point at the same body, and a clip sent to any of them shows on the first | live, 2026-10-18 |
| `+0x2e8` | his unit | live |
| `+0x308` | animation fragment: u16 clip index per slot from `+0x50`, `0xffff` none, shared per regiment and skeleton | live |
| `+0x324` | **the kind of order issued to him this tick** (section 7); `3075e7c` zeroes it | live / code |
| `+0x328` | command holder; the command object itself is embedded at `+0x330` | live |
| `+0x330` | the command's vtable (section 5) | live |
| `+0x340` | his own walk's done byte (`+0x10` of the command; `+0x360` is its `+0x30`), set when a walk with no path ends itself (section 5) | live / code, 2026-10-18 |
| `+0x368..` | the command's payload: a walk's target x/z (`+0x368/+0x370`), run flag `+0x390`, speed `+0x394`; a forced clip's 16-byte clip payload | live |
| `+0x378` / `+0x380` | a walk's goal **surface** ref, two qwords (the walk builder copies its block's `+0x10/+0x18` here). Null is the terrain: a goal on a wall or bridge deck needs the section's object, else path state 7 and no move. `+0x3c0` cleared re-sets the goal from them | live, 2026-10-29 |
| `+0x7f8..+0x817` | the goal the pathfinder works to: x/y/z, then its surface ref at `+0x808/+0x810` | live, 2026-10-29 |
| `+0x910..+0x92f` | **his own location**: x/y/z, then the surface he stands on at `+0x920` (null on the ground; a per-section object, vtable `exe+3ad7190`, on a wall walk or bridge deck; it changes at each section) and `+0x928` (0 in every read) | live, 2026-10-29 |
| `+0x3ae` | his walk's gait byte (stayed 0 through the engine's charge, section 5); the mailbox cave reads and writes it | live / code |
| `+0x490` | **running** action holder: action object `+0x4a8`, its done byte `+0x4c8`, has `+0x5c0`, started `+0x5c1` | live |
| `+0x5c8` | **queued** action holder: action object `+0x5e0`, its done byte `+0x600`, has `+0x6f8`, started `+0x6f9` | live |
| `+0x710` | path state: 7 = the pathfinder found no way (set in `exe+3077009`); 6 = a walk reached its point (he coasts on until the command is replaced, 2026-10-14); a walk that moves him goes 2, then 4 | live, 2026-10-14 / 10-18 / 10-21 |
| `+0x884` | the tick his wait ends (compared with the battle's `+0x98`) | live |
| `+0x88a` | read 1 in every melee frame; non-zero sends the action update straight to the runner | live / code |
| `+0x898` | with `+0x284`, whether `+0x278` holds a clip (`P.anim_slot`: neither set, no clip). While it is null the update counts `+0x27c` up a tick; all three clear cancels a pending hit | live / code |
| `+0x27c` | ticks into his clip; a pending hit lands when it reaches the impact frame (section 12) | live / code, 2026-10-29 |
| `+0xaf0..+0xb08` | **the pending hit** (section 12): `+0xaf0` result type, `+0xaf4` damage, `+0xaf8` the swing's slot u16, `+0xb00` the victim, `+0xb08` pending | live / code, 2026-10-29 |
| `+0xb18` / `+0xb1c` | hit points max / current, int32. Subtracted by `exe+310157c(man + 0xb18, n)` | live / code |
| `+0xb20` | when set, the update calls his virtual `+0x490` instead of the command/action path | code |
| `+0xb64` / `+0xb68` | child count / array (the subclass's `+0x4a8` repeats the clip on them) | code |

## 4. The man's virtual methods

Slot offsets into the vtable at `+0x0`, for vtable `3912950`.

| Slot | Function | What |
|---|---|---|
| `+0x18` | `exe+3086f04` | **main update**, once per tick; holds the gate (section 7) |
| `+0x490` | `exe+30915a8` | the update's other branch, taken when `+0xb20` is set |
| `+0x4a0` | `exe+30751e4` | "an action was posted": notifies `+0xb20`, sets `+0x8b0` = 2, clears order kind 0x13 |
| `+0x4a8` | `exe+306e850` | **start a forced clip**: replace his command with `3911fb0` carrying the 16-byte payload |
| `+0x4b0` | `exe+306e89c` | **issue an order** (section 7): sets order kind 1 |
| `+0x4b8` | `exe+306e9a0` | installs a command and sets order kind 0x13 |

`exe+311bd24` is the subclass's `+0x4a8`: `306e850`, then for each child at `+0xb64/+0xb68` either the same
start or command `3918e90`, chosen by its fragment's `+0x127c` bit 2.

## 5. Commands at `+0x330`

| Vtable | Command | Notes |
|---|---|---|
| `3911fb0` | forced clip | installed by `306e850`; **no order arrives while it runs** (live) |
| `3ae2400` | his own walk | built by `walk_start` `exe+306f954`; speed from `exe+303b744`. Built from the mailbox's block it has no path of its own (`+0x88` of the command null): to a point the pathfinder cannot reach (path state 7) its update `exe+3262850` ends it, done byte `+0x340`, and it **stays on him**, so writing its point in place moves him no more. A walk with a path re-plans instead (`+0x91`). Measured 2026-10-18 in a dwarf hold; `P.walk_ended` reads it |
| `3919350` | the regiment's walk | the pack's guard stops it |
| `39199f8`, `3ae1928` | the engine's moves | guard stops |
| `3ad24b8` | the engine's melee attack | guard stops. Its target is at `+0x38`; vtable `+0xc0`, the target getter, is `mov rax, [rcx+0x38]`, and every other command here returns null from it. Per swing it builds an attack object at `+0x80` (section 12) |
| `3ad2d18` | the engine's charge | measured 2026-10-18 (`probes/zz_tp_charge_gait.lua`, Harald on CA's `attack_unit` from 45 m): his own walk for 0.4 s, then this for 5.4 s at 4.0 m/s against his run's 3.3, **no forced clip on him** (the charge cycle is his locomotion and loops), then MOVING_ATTACK_2 (485) at contact. The walk's gait byte `+0x3ae` stayed 0 throughout. The pack's sprint fakes it with the CHARGE clip (135), 0.8 s and not looping on Harald; re-sent every 0.6 s until 2026-10-18, now at its own length (data.lua `charges`). **Built by** `exe+30538b4`, whose only caller is `exe+306eb24(man, target)` (vslot `+0x4f8`): if `+0x324 < 2` it clears `+0x328` and builds the charge at `+0x330`. `target` is a 0x38-byte block copied to the command's `+0x90`: an entity at `+0x18`, a group at `+0x20` (one of its men picked at random), a position object at `+0x28` used when `+0x18` is null; the engine builds one in `exe+2eab460`. `exe+311bf9c(body, target)` charges a body and puts each rider on a ride-along command (`3ae1ce0`) - a chariot's or a mounted man's charge (code, 2026-10-20). **Called through the mailbox cave it crashed the game, with no dump, on a Seeker Chariot body and on an infantry man** (live, 2026-10-20); the cave went back to its 410-byte form, the charge version is in `Modding Files/Backup/third_person_charge_cave_20261020/` |
| `39126f0` | stand in his state | what `walk_stop` `exe+306edd4` leaves |
| `3919b28` | idle | |
| `3ae2de8` | defend (block) | order kind 18 under it, measured |
| `3ae2a08`, `3912820`, `3ae2b38` | fight states | kind 14 under `3ae2b38`, measured |

**Ground fire, from script** (`uc:attack_location`; measured 2026-10-18, `probes/zz_tp_ground_fire_free.lua` and
`zz_tp_reaim_free.lua`, no pack logic after the order). The unit waits out its reload, then plays its fire clip, and
the shot leaves at the clip's FIRE_POS: Ku'gath's RIDER_FIRE 3.6 s into 5.7, the Necrofex Colossus's own FIRE_LEVEL
2.66 s into 9.5 (on the RoR the crewman plays RIDER_FIRE beside it). **A new `attack_location` while the clip plays
restarts it**: re-sent 10 m to either side every 0.6 s, the colossus started FIRE_LOW 1556 eleven times in 12 s, each
cut 0.2 s in, and never fired. Re-sent during the reload it did not visibly delay the shot.

**A blank clip** is CA data, not the engine: `hu09b_sw_jump_attack_01.anim` (the Great Unclean One's JUMPING_ATTACK
489) is a 0-byte file, so the slot is in his fragment and nothing plays. It is the only such slot the pack plays across
1,899 bins; data.lua `blanks` lists them.

## 6. Actions: the two slots, the runner, the play command

An **action** is a script-like unit of work the man carries beside his command. He has two holders, running
(`+0x490`) and queued (`+0x5c8`), with the same layout:

| Holder offset | What |
|---|---|
| `+0x0` | holder vtable `exe+3917f80`; slot 0 `exe+32613f4` is **reset**: started = 0 and the action's done = 0 |
| `+0x8` | the man |
| `+0x10` | handed to `exe+2db5a20`, the routine that destroys a command, on start when `+0x132` is 1: by that use, his command holder (code only) |
| `+0x18` | the action object (vtable: slot 0 destructor, 1 **start**, 2 **update**; `+0x80` "blocks orders"; `+0x20` done; `+0x24` ticks run) |
| `+0x130` | has an action |
| `+0x131` | started |
| `+0x132` | destroy his command when it starts |
| `+0x133` | clear the holder when it is done |

**The runner**, `exe+3088218(holder)`, does nothing without an action. Otherwise, while the action is not done:
on its first run it destroys his command if `+0x132` asks (`exe+2db5a20`), zeroes the tick count, calls the
action's start (slot 1) and marks it started; then it calls the update (slot 2) and counts the tick. Once the
action is done it clears the holder if `+0x133` asks (`exe+2db5ac4`).

**The play command** (tag 0x28 in the deterministic command stream; reader `exe+2ecf4dc`; what `P.play` pushes):
it reads the man, the slot (a four-byte integer for version 0, a name for version 1; kept as a u16), the mask and one byte, then builds a **clip action** (vtable `exe+390c0b8`,
constructor `exe+2f641b8`, base constructor `exe+3250f9c`) in the **queued** holder. For a rider
(`exe+306e490` true and `+0x2e0` set) it goes on the mount's holder with the rider flag 1. Its 16-byte payload at
`action+0x40`, which its start (`exe+2f7805c`) passes to the man's `+0x4a8`:

| Payload offset | What |
|---|---|
| `+0x0` | u16 animation slot |
| `+0x4` | u32 `0x81` (constant from the reader; meaning not traced) |
| `+0x8` | u32 body mask (the pack sends 0, or 6 to hold a full-body clip that has no event metadata) |
| `+0xc` | u8, the stream's byte (the pack sends 0) |
| `+0xd` | u8 rider flag |
| `+0xe` | u8 0 |

Other command-stream readers beside it (`exe+2ecf644` and its neighbours) park their actions in the same queued
holder, so they meet the same gate.

## 7. The man's update and the gate

`exe+3086f04`, the branch a fighting man takes (`+0x108` bit 0x10 set, bits 8 and 4 clear, `+0xb20` null), goes
one of two ways each tick:

- **His action update**, `exe+3075e7c`, which runs a queued action first. He gets it when no order reached him
  this tick (`+0x324` is 0, and `+0x128` is null or passes its `+0x78` check), or when **nothing is parked**
  (queued has is not 1, or its done is 1: the bytes at `exe+3087378 .. exe+3087388`, **the gate**) and a running
  action says it blocks orders (its `+0x80`).
- **The reset**, `exe+306d1ac`, which resets parked actions and runs his command. He gets it otherwise, and also
  whenever the order kind is 4, 0xc-0x12, 0x14 or 0x15.

So a parked action plus any order that tick means the reset. (The decompiled C of both functions is kept in a
local file, `BATTLE_ENGINE_RE_DECOMPILED.md`, and is not published.)

`+0x324`, `order_kind`, is written by each command-start routine (`exe_re.py stores 324` lists them):

| Kind | Writer | What |
|---|---|---|
| 1 | `306e89c` (`+0x4b0`, issue an order), `3070660` | an order of kind 0 reached him |
| 3 | `3084b2c` (vtable slot `+0x158`) | |
| 4 | `306f0d8` | |
| 5, 7 | `3075e7c` itself | |
| 12, 19 | `306ebd4` | |
| 13 | `306fea0` | |
| 14 | `306f1a0` | measured under fight state `3ae2b38` |
| 15, 16, 20 | `306f37c` | |
| 17 | `306ed94` | |
| 18 | `306edf8` | **the stop that `walk_stop` calls**; measured under defend `3ae2de8` |
| 19 | `306e89c`'s neighbour `306e9a0` (`+0x4b8`) | |
| 21 | `324e7e4` | |

`306e89c`, the order issuer, returns without ordering when a **running** action's `+0x80` says it blocks orders,
and it only replaces his command when the order differs from it. Either way it sets kind 1. In a melee his regiment
orders him **every tick**, so with a swing parked in the queued holder the update took the reset branch every
tick, and the swing never started. While his own forced clip plays, no order comes, which is why a swing sent
inside the previous swing always started in 200 ms. **Live** (`probes/zz_tp_melee_spam.lua`, ordered per-frame
timeline): every failed swing read "has, not started" (`c00`) for its whole 2 s. `+0x324` flipped 1/0 tick by
tick under stand, read 18 under defend and 14 under fight state `3ae2b38`. The one time the engine did start it
(`c10`), the next tick's order reset it.

## 8. The fix: one branch byte

At `exe+3087388` is `75 5c`: jne to `exe+30873e6`, the reset. Changing it to `75 52` sends a man with a parked
action to `exe+30873dc`, `call exe+3075e7c`, his action update, which starts it. The bytes checked first are
`exe+3087378`, 18 bytes: `44 38 bf f8 06 00 00 75 09 44 38 bf 00 06 00 00 75 5c`.

`platform.lua` `P.gate(on)` writes it with memreader Plus `mr.patch(address, expected, bytes)`, which writes only
when the bytes there are the expected ones, and answers the same when they already are the new ones. `main.lua`
puts it in while a man is played alone and takes it out at the stop. The platform takes it out as it loads, in
case a battle was left mid-control. A build without the `queued_gate` row gets no patch and one log line.

**In multiplayer** nobody toggles it. The gate changes the simulation (measured: a parked melee MOVE starts with it and
is reset without it), so a machine that toggled it at a key press would start or reset that MOVE differently from the
machines that did not, and the battle would desync (inferred; no two machines have run it). `install_net` checks its
bytes at build and proves its write by putting it in and out again before the battle's first tick; the HELLO handshake
(section 13, "As built") puts it in on every machine once the last player's HELLO has landed (one tick everywhere is
inferred, section 14), `main.lua` leaves it alone, and it stays in for the rest of the battle and after it, until the
next build takes it out as it loads. A machine whose gate bytes are not the expected ones, or whose write is refused,
gets no net mode, and so never says HELLO. So once a player has pressed F2 and every player has the pack, the ceiling
below covers every man of every army for the rest of the battle, whether anyone plays or not, and `P.play` is no longer
the only thing that parks an action there: the forged MOVE, HALT and FOLLOW park one too.
Whether a vanilla man ever parks an action is open (section 14).

Result, live (Teutogen Guard under two Clanrat units, a click every 2.4 s): 4 and 0 of 10 swings started before;
10, 10 and 10 with it, in 200-400 ms; the same code with only the patch stubbed out, 10, 7 and 9 with waits to
1.8 s. Shots, the horse's run speed and the no-auto-attack fragment were re-measured with it in and are unchanged.

**A unit of one needs it too** (2026-10-18, `probes/zz_tp_one_timeline.lua`, the Mutalith, a jump then a click every
0.4 s for 8 s, in melee with two Skaven units). Ungated, against Skavenslaves: the engine's melee order came back every
tick and the guard stopped it (`melee` / stand alternating, `+0x324` = 1 on 234 frames), and the jump and four swings
all read `c00` for 11 s, none started. With the gate in: 6 of 6, then 4 of 4 and 5 of 5 against Stormvermin, each 0.2 s
after its send. **One gated run stalled**: right after a fresh engage, 7.4 s of stand (`39126f0`) with `+0x324` stuck
at 1 and the queued action `c00`, until the engine's next melee order, when the parked swing started. `+0xb20` was
not read in that run; set, it sends his update to vtable `+0x490` and past the gate. Not reproduced in two retries.

**Ceiling:** while it is in, a parked action on **any** man beats that tick's order, not only his. In a battle the
pack plays, only `P.play` parks one. A per-man version needs a code cave (memreader `code_cave`) comparing the man
with a stored pointer. Caves cannot be removed for the session, which is why the one-byte version shipped. Since
2026-10-17 the mailbox (section 9) is such a cave at the top of the same update, with the man played in its block.

## 9. Threads, and measuring it live

**The battle runs on worker threads** (fiber jobs), at the same time as the script thread. Evidence: a crash
dump's faulting thread (index 7 of 91, `exe+305B39A`, a fiber job) while the script thread kept answering the
bridge; and a guard that read `stand` at `+0x330` while its own second read, microseconds later, found an engine
command. So:

- **Do not destroy or build engine objects from Lua.** `walk_stop` / `walk_start` from the script did, and it
  crashed (exe+7AB1DA and exe+305B39A in play). Reproduced on 2026-10-17: the stop from the script on every man of a
  171-man regiment in melee, every 30 ms, crashed in 3 s (`exe+305FA54`, a man pointer of `0xc` in code comparing two
  models' units). Calling `306e850` from Lua would be the same mistake.
- **memreader Plus Lua hooks never run on other threads** (its README: "Other threads never reach links"; calls from
  other threads run the original). A Lua hook on a battle function therefore sees only script-thread calls.
- **A code byte is executed by whichever thread reaches it.** A patch moves the decision onto the battle thread with
  nothing to race. Caves likewise, but they stay for the session.

**The mailbox** (2026-10-17, the fix): a memreader Plus code cave (`p:cave`) at the top of a man's update
`exe+3086f04`. It makes the stop, the walk builder and the in-place walk writes for the one man played, on the
battle thread inside his own update, where the engine changes his command itself. The script posts requests
into a `game_alloc` block. The cave's bytes run first, then a copy of the 7 bytes its jump displaced
(`mov rax, rsp; mov [rax+0x10], rbx`), then back into the game. At that entry rax and the flags are dead, so the
fast path (not him) touches nothing else. On his path the cave saves rcx/rdx/r8/r9 and xmm0-3 and calls with rsp
16-aligned.

A cave cannot be removed, and a second one at an address is refused. `p:cave` with the same name and bytes
answers the existing cave, so a later battle reads its block pointer back out of the cave's first instruction
(`hook_info(site).cave`, offset 2) and asks again with identical bytes.

Every model class's update reaches `3086f04`: the subclass `312de40` calls it first, and so do seven other
updates. Measured on a horse. `tools/third_person_cave.py` assembles the cave with keystone and runs the shipped
bytes under unicorn: every path, register and stack alignment, plus 8 broken variants (22 now, with 18 more for the
carrier cave, section 13). Live, 795 stops with no
fault (session handoff 2026-10-17 section 10).

**The strike** (2026-10-29, section 12) is the second request the update cave serves. Its entry compares rcx with the
block's `strike_man` (`+0x70`) before the played man's path, so the struck man's own update does the work. It
`xchg`s the `strike` flag (`+0x6c`) to take the request once. It rolls only when his hit points are above 0, the
victim (`+0x78`) is non-null with hit points above 0, `+0x278` equals `strike_slot` (`+0xe0`), and `+0x898` or `+0x284`
is set. The roll is `call [block+0xf8]` (`exe+30a8ab0`) with a 0x20-byte result block on its own stack frame and
xmm0-3 saved. Then it writes the record and counts the roll at `struck` (`+0xe4`). It ends by jumping back to the
played man's path, so a strike and a stop on one update both run.

**Recipes that made the measurement work** (all in `Modding Files/source/lord_control/probes/`, test scaffolding):

- **An ordered timeline, not counts.** Per frame, the state you suspect (`+0x6f8/+0x6f9/+0x600`, `+0x324`, the
  command vtable, the clip), appended only when it changes. A count of frames per state hid that the action had
  been started and then reset.
- **The hard case.** Clicks every 0.25 s land inside the previous swing and always work. Spaced at 2.4 s
  (`PERIOD=2.4 DURATION=24 sh ms_ab.sh <tag> <modes...>`), each lands under the engine's orders.
- **Make the test last.** `zz_tp_freeze.lua` (the author's idea): every unit invincible, fearless and holding fire,
  every enemy unit halted under a script controller. `zz_tp_engage.lua` then sets two enemy units on the subject.
- **A control in the same battle.** A probe mode that stubs only the change (`nogate` stubs `P.gate`), alternated
  with the shipped path.
- **Test source before building.** `py tools/build_third_person.py --bridge <unit types>` writes `zz_tp_load_NN.lua`
  parts; sent in order with `send.py`, then `zz_tp_load_run.lua`, they load the source into the running battle. A
  battle restart (`q_restart.lua`, then `x1_start.lua` once in deployment) goes back to the deployed pack.
- **Keep the clock honest.** A battle can be left in slow motion; `zz_speed.lua` with `_G.TP_SPEED = 1` puts it
  back. The pack switches off at the battle's Complete phase, so a long test needs a restart.
- One bridge command at a time; one Lua error in an eval wedges the bridge, so every probe runs in `pcall`.

## 10. Ghidra: setup and use

`tools/ghidra_decompile.py` runs Ghidra 12.2 (`C:\tools\ghidra_12.2_PUBLIC`) on Temurin JDK 25 (`C:\tools\jdk-25`) since
2026-11-08. 12.1.4 and JDK 21 stay installed for REA, which accepts Ghidra 12.1.x only. REA's Ghidra
provider works since REA 6.7.0 (`tools/external/README.md`); Ghidra itself also works headless without it.

```powershell
py tools\ghidra_decompile.py --import          # once per game build: 56 s, a 333 MB project in ghidra_cache\
py tools\ghidra_decompile.py 3086f04 3088218   # C for the function holding each RVA, ~8 s
py tools\ghidra_decompile.py --selftest        # walk_stop decompiles and names its callee
```

How it works and why:

- **Imported with `-noanalysis`.** Auto-analysis of 54 MB of code would take hours, and one function's decompile
  does its own local analysis. `tools/ghidra/DecompileAt.java` disassembles at each RVA, makes a function there if
  none holds it, and decompiles it. Callees print as `FUN_14xxxxxxx` (the VA; subtract `0x140000000` for the RVA).
- **Opened `-readOnly`**, so what a run creates is not saved, and runs never conflict.
- **Three setup traps:** Ghidra refuses a project path with any element starting with `.` (hence `ghidra_cache`,
  not `.ghidra_cache`); it needs `JAVA_HOME`; `analyzeHeadless.bat` waits for a key after an error, so the wrapper
  closes stdin.
- **Reading its output:** a struct pointer typed `longlong *` indexes in qwords (`param_1[0xdf]` is `+0x6f8`); a
  virtual call prints as `(**(code **)(*plVar + 0x80))()`, the slot offset in plain sight; a byte flag compares
  with `'\x01'`. Rename nothing in the project (it is read-only); carry names in this document instead.
- **The GUI** (`ghidraRun.bat`, open `ghidra_cache\wh3_6acec6f4.gpr`) is for browsing around one function. Analyse
  a selection, never the whole program.
- **After a game patch** the project is for the old exe: re-run `--import` (it overwrites), and rename
  `PROJECT` in the wrapper to the new build.

## 11. After a game patch

1. `py tools/third_person_patterns.py` prints the new build stamp and the play command's fields.
2. Find the gate again: search the code for the 18 bytes in section 8. A patch can move them, and the `75 5c`
   displacement can change too. If the bytes are gone, `refs <action update>` on the new build finds the update's
   caller, and its two `cmp byte ptr [rdi+...]` lines are the queued holder's has/done bytes.
3. Re-check the fields in section 3 with a live probe before shipping. `P.gate` refuses on an unknown build, and
   does nothing when the bytes differ.
4. The mailbox: `py tools/third_person_cave.py --check` fails when his update moved or starts differently. The
   update is slot `+0x18` of the infantry man's vtable (`exe_re.py q <vtable+0x18> 1`). Set `SITE_RVA` and
   `SITE_BYTES` (the cave needs 5+ bytes of whole instructions, no jump or rip-relative operand among them) and
   the build row's `update`, re-check the field offsets in `MAN`, then `py tools/third_person_cave.py` and
   `--selftest`. Without a known update the pack plays regiments whole.

## 12. Beyond the man: the camera's floor, the projectile launch

**The camera's floor** (2026-10-18, `probes/zz_tp_cam_sweep.lua`; session
`HANDOFF_20261018_THIRD_PERSON_SIEGE_WALK_ARTILLERY.md` section 4). Camera system S =
`*(*(*(exe+4480da0))+0x468)+0x64558`, current mode M = `*(S+0xc08)` (vtable `exe+3ab9498`). The floor `exe+2ebf734`
(sibling `exe+2ebf9e4`) puts the eye at `max(A + min, B + h)`: A = vslot `+0x2e0`, `exe+2ee841c`, a raycast under the
eye that counts roofs and walls; B = vslot `+0x2f0`, `exe+2ec2710`, the terrain heightfield; min/max vslots
`+0x2c8`/`+0x2d0`, h = `M+0x450`. All 18 camera vtables hold A and B side by side. An eye asked 2 m over the road went
18.7-24.0 m up under a gatehouse, 4.3 in the open (**live**). Redirecting one call site (`exe+2ebf916`) was not enough;
a 5-byte `jmp exe+2ec2710` at A's entry (`48 8B C4 48 89` -> `E9 EF A2 FD FF`) gave +2.0 at all 11 points.
`platform.lua` `P.terrain_floor(on)` writes it (BUILDS row `cam_collide` / `cam_terrain`) while third person is on;
while it is in, every battle camera ignores buildings.

**The projectile launch** (2026-10-20, Ghidra and live reads, while chasing the upward Irondrake flame; session
`HANDOFF_20261020_THIRD_PERSON_FLAMETHROWER_PROBES.md`, which has the hooks, offsets and the open visual):
`bm:trigger_projectile_launch` binds `2f1aef8 -> 2f1ad84` and queues through `2e9b9e4`; the real BCQ_FIRE_PROJECTILE
handler is `2ecfd54` (command `+48` an optional firing entity, `+50` the **spread, not a yaw**); it spawns through
`309eea4`, which publishes a 0x38-byte launch event (velocity at `+0x28`). The render consumer `2fe68b8` orients the
launch FX from that velocity alone and does not branch on the beam flag (record `+f0`). Effect lookup `14f5e54`
searches loaded effects only, so a new effect key with a `particle_effects` row still reads -1. The native velocity
of a level Drakegun shot was forward, `(0, 1.50, 29.96)`. **Withdrawn:** the earlier chain `2efaa20 -> 2f19874 ->
2f1a4bc -> 2ea7298` is a camera path read from metadata beside the serialiser, not the projectile's.

**Melee damage: the pending hit** (2026-10-29; `sessions/THIRD_PERSON_FIXES_20261029.md` has the runs). A clip's
`IMPACT_POS` deals no damage on its own. A blow is a record on the man, at `+0xaf0..+0xb08` (section 3):

- **The attack object.** Each swing, the melee command (`3ad24b8`) builds an attack object in `exe+3081f18`. There are
  four kinds, made by factories `3255edc`, `3256008`, `3256134` and `3255db0`, with vtables `3918230`, `3918278`,
  `39182c0` and `3918308`. Each is pool-allocated with base constructor `3250e60(obj, man, cmd)`, and stored at
  `cmd+0x80`. Its fields are `obj+0x8` the man, `+0x10` the command, `+0x18` the animating entity, `+0x20` the slot
  u16 and `+0xc8` the flags. Its vtable `+0x28` picks a weighted slot (`exe+3050578`) and starts it; `+0x30` is the
  update, and `+0x38` ends it (and clears the man's `+0x298`).
- **The arm.** The update (`325fca4` in kind 4) calls `exe+3251af8`, which plays the slot (`exe+3081d40`) and then
  rolls the blow with `exe+30a8ab0(*(battle+0xf8), &result, man, victim, 0)`, where battle is
  `*(*(man+0x58)+0x440)` (section 3). The roll
  covers melee attack against defence, the damage after armour and the result type, from the battle's RNG at battle
  `+0x90`; it also uses a shared scratch block at `exe+433fdb0`. The result is `[0]` type and `[2]` damage. The arm
  then writes `+0xaf8` the slot, `+0xaf0/+0xaf4` the type and damage, `+0xb08` = 1 and `+0xb00` the victim.
- **The landing.** The man's update (`exe+3086f04`, vslot `+0x18`) calls `exe+32654d0(man + 0xaf0, man)` every tick.
  The impact frame comes from the clip in that slot: its first event's time, or its frame count - 1. When `+0x27c`
  reaches it, the landing builds a hit (`exe+3250ef0`) and branches on type:
  - 0 calls the victim's vslot `+0x3a8`, a reaction with no damage.
  - 1 calls `exe+3253204`.
  - 3, 4 and 5 call `exe+3253204` and then a knock (`325369c`, `3253864`, `32539ac`).

  `exe+3253204` goes to `exe+3260a34`, which runs the damage through `exe+2e3ce30` (not read) and keeps the damage
  and kill counts, then `exe+3075b20`, then `exe+310157c`. **No range or
  facing check**: the arm's caller did that (`325fca4`). A lethal blow goes on through `exe+325b75c` to the man's
  vslot `+0x470`, death (`exe+3071dc8`).
- **The cancel.** The record is zeroed if `+0x898` is null, `+0x284` is 0 and `exe+306ba98` (the `+0xb20` check) is
  false.

Measured on 100 Dragon Guard in melee: 42 arms in 8 s, `+0xaf8` the playing slot in 42 of 42, `+0x898` set in every
pending frame. The forced clip has no attack object, so nothing arms the record. Written by hand from Lua on the
played man (type 1, damage 35, his slot, a victim) under the forced clip, it landed 4 of 4, exactly 35 each.

**Built** (2026-10-29): the pack rolls and arms it through the update cave (section 9, "The strike").

- The script supplies the slot and the victim: the enemy man nearest the clip's `IMPACT_POS` turned with his heading,
  inside the blow's reach plus 0.5 m and 60 degrees of its direction.
- Live, the roll answered about 0.1 s after the post. The struck man lost exactly the rolled damage at the impact
  frame (a hit for 32: 81 -> 49), and a blocked roll moved no hit points.
- Single player only. In multiplayer the roll would advance one machine's RNG.

## 13. Multiplayer and the command queue

(2026-10-21, code only; decision record `docs/sessions/MP_FEASIBILITY_20261021_THIRD_PERSON.md`.) A battle
runs in lockstep and the battle command queue (CA's names are `BCQ_*`) carries a change to every machine. That is
inferred from the tick-bundle path under "One frame, one tick" below, which is one link short, and no two machines
have run it. Addresses below are `exe+` RVAs; "battle" is the object `P.play` reaches as `[[exe+4480da0] + 0x468]`.

**The registry.** 251 static initialisers (counted 2026-10-21 with the regex below) each call
`exe+668a14(global, name, version, handler)`, which files the command under the id held in `global` (zero on disk, set
at start-up); `exe+668ad4(&id)` finds the entry: name at `+0x0`, version at `+0x10`, handler at `+0x18`. A table of all 251 (name, global, handler, version) is one regex over
the code, `lea r9,[handler]; xor r8d,r8d or mov r8d,imm; lea rdx,[name]; lea rcx,[global]; jmp 668a14`. The play
command is `BCQ_ENTITY_USER_OVERRIDE_ORDER_ANIMATE`, global `exe+406cc98`, handler `exe+2ecf4dc`, **version 1**;
`BCQ_FIRE_PROJECTILE` is global `exe+406cef8`, handler `exe+2ecfd54`, version 0.

**Pushing.** Every pusher read has `cmd_push`'s shape (`exe+2e9b974` is the play command's; the player's move is
`exe+1cae60c`): look the id up, write a 7-byte header into the queue with `exe+1bca278` (u16 length, the four id
bytes, the version byte), call the command object's slot 0 to serialize its fields, then patch the length in
`exe+1bcd5e4`. The queue is battle `+0x644e8`, vtable `exe+3904438` (slot 1 returns its buffer at `+0x8`, slot 2 empties
it), 0x5000 bytes long with the write cursor at `+0x5008`. Fields are type-tagged: `exe+1bb1924` writes the tag, then
the bytes raw, and `exe+1bab24c` reads them; the tags are listed under "The override commands" below. The writer checks
the 0x5000 limit and flags the record instead of overrunning.

The script wrappers `exe+2e9de34` to `exe+2e9e2ac` (27, each 0x2c bytes) push only when the battle's `+0x3b0` and
`+0x3b1` are both 0; `+0x3b0` is what `battle:is_spectator()` (`exe+2eeb604`) returns, `+0x3b1` has no binding of its
own. `battle:is_replay()` is the byte at `+0x645e0` (binding-table entry `exe+3d3ffd8`, handler `exe+2eeb29c`) and
`battle:is_multiplayer()` is `+0x645c8` not null (handler `exe+2eea97c`); both were read with `exe_re.py ptrs` and `dis`
on 2026-10-21.

**The play command on the wire.** Its serializer `exe+2eecc50` writes the man's id (his `+0x258`), the slot as its
**name** from the table at `exe+36ccb18` (32-byte rows, 2,260 names; row 2260 is `null`), the byte, and the mask as
its **name** from `exe+3926220` (`NONE`, `TORSO_AND_ARMS`, `SPINE_AND_CHILDREN`, `NECK_AND_CHILDREN`, `LEFT_ARM`,
`RIGHT_ARM`, `FULL_BODY` for 0 to 6; any other value writes `null`). The reader `exe+2ecf4dc` resolves the id
through `exe+2eaf094` (the battle's `+0x1b8`, its map at `+0x80`), reads the slot as a four-byte integer (tag `4`) for
version 0 or a name for version 1 (`exe+15861c4`, 2260 when unknown), reads the byte (`exe+1b9fc58`, called at
`exe+2ecf55d`) and keeps only `byte != 0`, and reads the mask name back to 0..7 (`exe+1588f44`, 7 for `null`). The byte
crosses the network whole (`exe+1ba06e8` writes all eight bits); only the reader narrows it. So a named slot below
2260, eight bits and eight mask values arrive, but code after `exe+2ecf55d` sees one bit of the eight. The raw byte
stays in the record's buffer (`+0x10`, read cursor `+0x20`; the field is tag `1` then the value), where a hook at
`exe+2ecf556` or `exe+2ecf562` can still find it. The narrowed bit is the loop flag of `unit:play_anim_for_captain`
(`exe+2f01278`, the binding `P.play` copies): the forced clip's update `exe+308779c` replays the slot every tick while
it is 1.

**One frame, one tick.** `exe+2d7b4a8` hands the queue's buffer to the tick manager's slot `+0x10` with the battle speed
(`exe+2ddae64`), and empties the queue only when that returns true, so a full send buffer delays commands rather than dropping
them. Single player's tick manager (vtable `exe+3a2e0c0`) copies it into its pending list (`exe+1bacab4`) and its
slot 0 (`exe+1baa7b0`) returns a tick bundle holding it. The factory `exe+2db833c` chooses: a single-player battle
(`+0x645c8` null) gets that local manager (`exe+1b9c678`); a multiplayer one gets `[battle+0x645c8] + 0x140`, and
EMPIRE_MP's constructor `exe+2196d24` puts vtable `exe+3a5c888` at its own `+0x140`. One link was not followed: that
`+0x645c8`, a battle constructor argument, holds the EMPIRE_MP object. So in multiplayer the tick manager is EMPIRE_MP's
interface **by inference, one link short**; the two-machine run (Task 3 of the multiplayer plan) confirms it. Its
submit `exe+21d7290` appends the buffer to the outgoing tick data (`exe+21a3a9c`, capped at
0x5000), `EMPIRE_MP::submit_tick_data` (`exe+21d9280`) writes it as network message `0xa2` (or `0xa1`), and
`EMPIRE_MP::p_get_tick` (`exe+21c8188`, the interface's slot 0) decodes `0xa1`/`0xa2` messages through `exe+21aff1c`
into the next bundle. A bundle is `0x64058` bytes, the stride of the tick manager's pool (`exe+1baa883`): a time step
and up to 20 buffers of `0x5004` (bytes, then length), since 8 + 20 x `0x5004` is `0x64058`. The callback `exe+2d804ec` passes it to `exe+2ddaaf0`, which copies it into the battle's `+0x468`, and
`exe+2dd3910` runs each buffer through the executor `exe+2f041c0`: parse a record (`exe+288f9d0`), look its id up,
call the handler with the record and the battle's `+0x440`. **Neither the executor nor a handler is told which
player's buffer a record came from**, and the version byte is the only header field a handler sees. EMPIRE_MP learns
the queue from `notify_battle_env_created` (`exe+21c42ec`, its vtable `exe+3a5bce0` slot `+0x78`), which the battle's
constructor `exe+2d98420` calls with the queue. The `BNCQ_PLAYER_LEFT_GAME` command is pushed by EMPIRE_MP itself
(`exe+21b7454`) into the same queue.

**Model time.** `bm:time_elapsed_ms()` (`exe+2f17fb8`) returns the u32 at `[exe+4480da0] + 0x4a4`, which
`exe+2f17df0` sets each tick (from the tick step at `exe+2dd3613`) to the tick count, the u32 at
`[battle + 0x440] + 0x98`, times the u32 at `exe+3d0e294` (100 on disk). `model_tick_time_ms` (`exe+2ef5928`) returns
that tick length.

**Every `uc:` call the third-person pack makes is a queued command**: the record lists each binding and its `BCQ_*`.
So is `army:use_special_ability` (binding `exe+2f263ac`, read 2026-10-29): it tests `+0x3b0`/`+0x3b1` and pushes
through `exe+1bc2a40` on the queue at `+0x644e8`, carrying the binding's own `+0x8` and `+0x20` of the record its key
looked up. The army-ability page casts through it.
The pack's direct memory writes (steer, hold, face, the disarm's fragment pointer, the gate patch) are not `uc:` calls,
and they do not travel (measured for `P.steer` in Task 2, where it was not recorded; inferred for the rest). **A slot
without a clip is not a no-op:** the reader parks the action without looking at the
fragment, and its start replaces the man's command with a forced clip (`exe+306e850`), whose play asks `exe+14828c0`
(slot below 2260, fragment `+0x50 + 2*slot` not `0xffff`) and plays nothing.

**The override commands** (2026-10-21, Task 1b, code only; the decision record's "Override commands" section has a row
per type, the forging recipes and the carrier recommendation). Beside the play command, CA registered nine more per-man
or per-battle overrides; every field of theirs crosses the wire raw (no names), and a handler that takes a man checks
only the read-error byte and that the man resolved. Tags: `1` byte, `4` int32, `0xa` float, `0xc` three floats, `0xd` u16, `0xe` string (length,
then characters), and four-byte ids resolved in battle `+0x1b8`: `0x23` a model (map `+0x80`), `0x21` (`+0x40`), `0x25`
(`+0xe0`), `0x26` (`+0x100`), `0x27` (`+0x120`), `0x28`. A "position" is `0xc`, `0x26`, `0x27` (`exe+30f809c` reads,
`exe+2eafa2c` writes). Each handler clears the man's queued holder (`exe+2db5ac4`) and parks its own action there, so
one override or clip per man is parked at a time, and each meets the gate of section 7.

| Command (`BCQ_ENTITY_USER_OVERRIDE_*`) | Handler, version | Wire | Action, and what it does |
|---|---|---|---|
| `_ORDER_MOVE`, global `exe+406c798` | `exe+2ecfb0c`, 0 | model; position; int32; float | vtable `exe+390bea8`. With his `+0x890` null: the walk parameter block from `exe+324e05c` (int32 as the run flag `+0x28`, float as the speed `+0x2c`, heading `+0x30` 0) into `walk_start` `exe+306f954`, so his own walk `3ae2400`, as the mailbox builds it. With `+0x890` set: `exe+324e8bc` and vslot `+0x5b0` (`exe+306fd58`) at the unit's own speed, rebuilt every tick. Done when his command's `+0x340` is set |
| `_ORDER_HALT`, `exe+406cea8` | `exe+2ecf98c`, 0 | model | vtable `exe+390ba88`; after a draw of up to 2 ticks from the battle's generator (`exe+1bab1b0`), the stop `exe+306edf8` with state `0x81` (what `walk_stop` calls with his `+0x318`) |
| `_ORDER_JUMP`, `exe+406cd64` | `exe+2ecf9e8`, 0 | model; point | vtable `exe+390b980`; vslot `+0x538` (`exe+306f158`) with a jump block from `exe+2d9f998` |
| `_ORDER_TELEPORT`, `exe+406cd30` | `exe+2ecfbd4`, 0 | model; position; byte | vtable `exe+390b5e8`; vslot `+0xe8` (`exe+3078268`): byte 1 puts him at the point, byte 0 turns him toward it; then the stop with `0x81`. Never marks itself done (`exe+8f5a70`) |
| `_ORDER_ATTACK`, `exe+406c82c` | `exe+2ecf644`, 0 | model; target model | vtable `exe+390c2c8`; target block `exe+2eab460`, then the order issuer `exe+306e89c` (or vslot `+0x580`). The action waits out a delay (slot 1 `exe+2f780a8`), then `exe+2f7ec44` calls the man's vslot `+0x4b0` (or `+0x580`). **Forged live 2026-10-29 on one man of a regiment: within 93 ms he stood idle beside his regiment, 53-287 m away, in one frame, and no melee command ran on him** (guard on or off; `sessions/THIRD_PERSON_FIXES_20261029.md`) |
| `_ORDER_FOLLOW_FIRST_PERSON`, `exe+406cc88` | `exe+2ecf6d0`, 1 | model; position; u16 heading; `0x25`; `0x21`; byte; point, model, `0x28`; int32; float; int32 state; byte; float; v1: byte, byte | vtable `exe+390bc98`; starts only on its own tick (`exe+2f783f0`); turns him to the heading (vslot `+0x5f8`, `exe+30702b8`) unless his command is busy, or stops him with the state, or attacks when the target byte and a weapon index are set; 10 ticks |
| `_AIM_DELAY_TIME`, `exe+406c784` | `exe+2ecf498`, 1 | float | no action: the global `exe+3d10790` (default -1.0), read at `exe+32580b1` instead of the unit's value |
| `_RELOAD_TIME`, `exe+406cda4` | `exe+2ecfc88`, 1 | float | no action: the global `exe+3d10794` (default -1.0); no reader found by a full rip-relative operand scan (`exe_re.py refs` misses `movss`) |
| `BCQ_ENTITY_OVERRIDE_REMAINING_RELOAD_TIME`, `exe+406c85c` | `exe+2ecf43c`, 1 | model; float | no action: his `+0xad0` |

**Serializers and pushers.** Only three of these have them: the play command (`exe+2eecc50`, `exe+2e9b974`), FOLLOW
(serializer `exe+2eecd44` in vtable `exe+3ab25a8`, builder `exe+2d9b4ec`, pusher `exe+2d919dc`) and REMAINING_RELOAD_TIME
(`exe+2eecbe4` in `exe+3904430`, pusher `exe+2d9196c`). Both of the latter are pushed by CA's own per-man control: the
battle constructor builds a 0x820-byte object at battle `+0x647a0` (`exe+2d99995`), whose per-frame update `exe+2dcb644`
(from `exe+2ef594c` through `exe+2dcb3a8`) pushes a FOLLOW while its `+0x518` holds a man, and whose exit `exe+2db96b4`
pushes the reload time. No code loads the other globals except their registration. A command with no pusher is forged
with three calls: `exe+1bca278(writer, queue + 8, &id, version)` (the 7-byte header; the id is read from the global at
run time), one `exe+1bb1924(writer, tag, bytes, size)` (it writes the tag and then `size` raw bytes, so a blob of the
first value followed by every later tag and value writes the whole record), and `exe+1bcd5e4(writer)` (patches the
length, or rewinds an overflowed record). MOVE is 45 bytes, HALT 12, FOLLOW 99. HALT's one field is also exactly what
`BCQ_ENTITY_INSTANT_KILL`'s serializer `exe+2eecb50` writes.

**MOVE against the gate.** Vanilla: a parked MOVE is reset on every tick an order reaches him, so in a melee it never
starts, like the swing in section 7 (measured: parked and unstarted on 48 of 49 ticks of a lasting melee, a MOVE sent
every 0.1 s). With the gate byte it starts at his next update (measured: his own walk on him on 47 of 49 ticks). Read
from the code, not measured: the regiment's order that tick still replaces the walk it built (the order issuer refuses
only for a running action that blocks orders, and MOVE's `+0x80` slot, `exe+8f5810`, reads 0), and on the walk_start
branch MOVE never rebuilds it, so a steered man in a melee needs a MOVE every tick. Even so, with the gate in and a MOVE
every 0.1 s, one front man covered 1.2 m in 5 s, cause not isolated (the record, "The overrides, live"; section 14).
The start's clip test is the man's vslot `+0x260`, a constant false on `exe+3912950` and `exe+3915a20`, the two
infantry vtables read: a MOVE that reaches an infantry man mid-swing is read to replace the forced clip and cut the
swing, which no probe has shown.

### As built (2026-10-21)

The third-person pack's multiplayer net mode, built and tested offline only: no two machines have run it. Code:
`Modding Files/source/third_person/script/derpy_tp/platform.lua` (`install_net`, `M.net_rules`, `M.carrier`),
`main.lua`, `combat.lua`, the entry `script/battle/mod/derpy_third_person.lua`, and `tools/third_person_cave.py`, which
assembles both caves and runs the shipped bytes under unicorn (`--selftest`: every path, a lost race on each free, and
29 broken variants, 11 of the update cave and 18 of the carrier cave, each caught; `--check` prints the two sizes below,
599 and 613 bytes on 2026-10-22). The sending rules also run in a two-machine lockstep simulation
(`tools/third_person_lockstep.lua`). One-machine live facts are Task 2's (the record's "Replay"). The decisions are the
record's "Rulings"; what only two machines can answer is its "Live session checklist".

**What travels how.** With `bm:is_multiplayer()` true, every change the pack makes is a queued command: steer is one
forged MOVE, hold one HALT, a standing turn one FOLLOW_FIRST_PERSON (CA's pusher), a clip the play command as in single
player, and the guard, disarm, arm and HELLO a carrier word in a forged RELOAD_TIME. Nothing writes the steering copies,
`+0xb0`, `+0x308` or the mailbox's man, guard and walk fields, so the update cave's single-player half never matches.
MOVE, HALT, FOLLOW and the guard name a rider's mount, as `P.steer` always did; DISARM and ARM go for the mount and
then the man.

**The carrier word.** 32 bits: 31-24 the magic `0xD7`; 23-20 the op, 1 GUARD_ON, 2 GUARD_OFF, 3 DISARM, 4 ARM, 5
HELLO; 19-16 flags, bit 16 shots and bit 17 charge, bits 18-19 unassigned and ignored by both sides (a HELLO's flags are
not read); 15-0 the body's id, his `+0x258`, or for HELLO the protocol version in 15-8 (`HELLO_VERSION`, 2 since
2026-10-22, in `platform.lua` and in `tools/third_person_cave.py`; version 1 carried an army slot) and the sender's
player slot in 7-0, 0 to 31. Game Lua numbers are float32, so the word is never one Lua number:
`M.carrier` returns two u16 halves, `hi = 0xD7 * 256 + op * 16 + flags` and `lo = id`, and `out.carrier` writes `lo`
then `hi` as the four raw bytes of RELOAD_TIME's float field (tag `0xa`), so the u32 on the wire is `hi << 16 | lo`. As
a float it is a normal negative number between -1.4e14 and -2.8e14, never a NaN or a denormal. An id over 0xFFFF is
refused, never wrapped: that body is left out of guarding, with one log line (`a man is left out of multiplayer
guarding`). Task 2 read ids 1 to 4,265 in a 20-against-20 battle. A HELLO slot past 31 is refused the same way.
`M.uncarrier` decodes the same layout, and a HELLO of another version or past the mask to nil; the selftest runs it
under `lua.exe` against the cave over every op, every flag nibble and nine ids, HELLO's version and its neighbours, slots in and
past the mask among them, so a version changed on one side alone fails it.

**The carrier cave** (code; 613 bytes) sits on the RELOAD_TIME handler's `movss xmm0, [rsp+0x30]` at `exe+2ecfcb7`, past
the read-error test, and goes in at build on every machine. It reads the word at `[rsp+0x30]`:

- top byte not `0xD7`: memreader's epilogue re-runs the displaced `movss` and resumes at `exe+2ecfcbd`, so any other
  value is stored as vanilla stores it;
- the magic with an op outside 1-5: it jumps to the handler's epilogue `exe+2ecfcc5`, skipping the store, and does
  nothing else;
- HELLO (5): no man is resolved. Version 2 and a slot below 32 set the slot's bit of the block's 32-bit mask at `+0x5c`
  with `lock or`; anything else sets nothing. Either way it skips the store;
- ops 1-4: it resolves the 16-bit id as the MOVE handler's resolver `exe+2eaf094` does (the battle object at the
  command record's `+0x30`, its map at `+0x80`, `exe+17aece4(map, &id)`; id 0 is no man), acts, then skips the store.
  A carrier never changes `exe+3d10794`.

| Op | Live man | Man gone or dead (`+0xb1c <= 0`) |
|---|---|---|
| GUARD_ON | an entry holding his id gets his pointer again; else he claims the first free entry and `count` goes up; a full table drops it | frees his id's entry |
| GUARD_OFF | frees the entry holding the id; no model is read | the same |
| DISARM | the copy-table row with any column equal to his `+0x308`; writes the column the flags pick (plain, shots, charge, both) to `+0x308` | nothing |
| ARM | the same row's original back to `+0x308` | nothing |

The two pointers it jumps or calls through, `skip` (`exe+2ecfcc5`) and `map_lookup`, sit at block `+0xe8` and `+0xf0`,
written before the cave goes in and never zeroed by a later build: a cave already past its match goes through them.

**The guard table** (code). 16 entries of `{man pointer, u32 id at +8}` at mailbox block `+0x100`, `count` at `+0x54`.
The update cave (section 9; now 599 bytes) has a second half: on every man's update while `count > 0`, it looks for his
pointer among the 16. Found and alive, it stops the engine's four orders on him as the single-player guard does (the
regiment's walk, the two moves, the melee attack, through `walk_stop`); found and dead, it frees his entry. Single
player never sets `count`, so that half costs it one compare. Both free paths take the entry with `lock cmpxchg` of the
pointer as read against 0, and `lock dec` the count only when the exchange won, so a dead man's update and his
GUARD_OFF freeing one entry at once count it down once (the emulator runs that race). `M.net_rules` keeps the id each
GUARD_ON went with, and `P.unguard()` sends GUARD_OFF by that kept id without reading the man, alive or dead: at the
stop, and whenever the guarded body changes (he died and the next man is played). The update cave's free is the
backup. Every build zeroes the entries, `count`, `nfrags`, `fragtab` and the HELLO mask (`check_mailbox`), so nothing
survives from the battle before.

**The copy table** (code). Built at "Deployed" on every machine (`build_copy_table`, a phase callback): every army in
`bm:alliances()` order, every man and then his mount, deduped by fragment address, one 0x28-byte row `{orig, plain,
shots, charge, shots_charge}` per fragment. Each copy is the one single player's disarm makes (`build_copy`): the
fragment with its attack slots read none; `shots` blanks the shot clips too, `charge` keeps MOVING_ATTACK 484-493. The
rows are their own `game_alloc`; the block holds their count at `+0x58` and the pointer at `+0x60`. Every army, not the
human ones, because what `is_player_controlled()` returns on each machine is unmeasured. A unit that cannot be read (a
null object, a read that faults, a reinforcement army not yet on the field) is left out, not the table; anything else
that throws leaves net play off for that battle. Numeric loops and `ipairs` only, so the rows are the same on every
machine; only the addresses differ, and the cave matches by pointer. A unit spawned later (a summon, a reinforcement)
has no row, so a DISARM naming its fragment is dropped, on every machine alike.

**The HELLO handshake** (code; the record's Rulings 25 to 27 and 30). A peer without the pack, without memreader Plus
or on another build would run a different simulation from the first forged command, or from the gate alone, so net
play and the gate wait until every machine in the battle has said HELLO. `M.handshake` (pure Lua, so the simulation's
fake platform runs the same lines) is a model callback, every 100 model ms on every machine, a replay too:

- **The players.** CA's network player list, `MultiplayerRootContext.PlayerList` (a CCO global function, read with
  `common.get_context_value("CcoBattleRoot", "", ...)`; CA's battle UI reads the same list in `mp_team_list.twui.xml`),
  through `M.players`: every entry online, with its `Id` (CA's "unique mp client id"), `Name`, `IsLocalPlayer`, and
  `IsSpectating` or `IsPassiveParticipant` ("spectating but can receive units from active players to join in"; bit
  `0x10` and all of `0x25` of the network player's `+0x138`, getters `exe+1f07930` and `exe+1f076e8`). A player reading
  either is watching: listed and given a slot, but not waited for, and its machine sends nothing, since every queued
  push is dropped on a machine whose battle `+0x3b0` (`is_spectator()`) is set (Ruling 34, 2026-10-24: waiting for it,
  no battle a partner watched ever started). Until 2026-10-22 it counted human armies through
  `army:is_player_controlled()`, which refused every battle with one human army and told both players to get the pack
  (Ruling 30).
- **The slot.** A player's place in the list sorted by `Id`, from 0: the same on every machine that sees the same
  players, whatever order its own list is in. A list that does not read, names one player (this machine would start
  alone), lacks this machine, repeats an id, names more than 32, or has everyone watching is not used: no HELLO goes
  and the gate stays out.
- **The send.** Nothing goes until someone wants to play: this machine says HELLO once its player has pressed F2 in net
  mode (`P.net_asked`, set by `main.lua`) or another player's HELLO has landed, so a modded peer answers by itself; a
  watching machine never does. Either way only once its own copy table is built (`P.net_ready`), so a HELLO that executed also says
  that machine's table is there. One HELLO, for its own slot, through the carrier route. A push that did not go goes
  again the next tick. None goes in a replay, whose recorded HELLOs land again (a throw from `bm:is_replay()` sends
  none and is logged). A lobby where nobody presses F2 therefore carries nothing at all. At the first step under way
  one line names the list by slot: `multiplayer: players <slots> of <n>, this machine <slot>, watching <slots>,
  offline <slots>, waits for <slots>`. `HELLO_VERSION` is 3 since Ruling 34.
- **Late.** Once a handshake is under way here, it may take `HELLO_WAIT`, 5,000 model ms: a press needs two queue
  delays and three callbacks, 300 ms, and 5 s allows 2.3 s a trip. Past it, with the list unusable or a player missing,
  `P.net_late` is set with `P.net_why`: `players` (`multiplayer waits: the player list cannot be used: <why>`); `self`,
  this machine's own HELLO has not landed, which no missing pack explains and says the forged command did not come
  back through the queue; or `missing`, with the others' names in `P.net_missing`. Both of the last log `multiplayer
  waits: players <slots> of <n>, no HELLO from <slots> after 5000 model ms`. The log names players by slot only: a
  player posts it, and the names are their friends'. A completion in that same step is not late.
- **The gate.** Once every playing player's bit is set in the mask, it puts the gate in (`P.gate(true)`), sets `P.net_play`
  and logs once `players <slots> of <n> all said HELLO by <ms> model ms: the order gate is in`. The bits are set by
  commands, so the callback that first sees the last one is inferred to run at the same model tick on every machine;
  where in the tick it runs is untraced (section 14), and the equal model ms in both logs is the evidence the live
  session reads. The gate then stays in to the battle's end (section 8). A gate that does not go in is logged and
  tried again the next tick; the build's proof makes that unlikely.

`main.lua` starts net play only with `P.net_play`. A press before it, after "Deployed", is kept rather than refused: it
sets `P.net_asked`, third person starts by itself when the handshake completes, with no second press, and once
`P.net_late` is set the player is told why, by `P.net_why`: `derpy_tp_mp_needs_everyone` with the missing players'
names in place of its `%s` (`E.say` sets them on the line CA's `show_subtitle` has just set), `derpy_tp_mp_no_route`,
or `derpy_tp_mp_no_players`. A second press while one is kept is ignored (the record's Ruling 29): it sends no HELLO,
restarts no clock and adds no message, and the kept press still starts third person when the handshake completes. A
kept press is dropped 15 model s after it (`NET_DROP`), three times the handshake's allowance, because a camera taken
over later than that lands on a player who has gone back to commanding the battle. Any start spends a kept press,
including a key press that starts directly in the frame the handshake completes, so F2 stops a session as before and
it stays stopped. A spectator (`bm:is_spectator()` true, or a throw) and a partner given units (`P.net_me.watching`)
never start: `M.start` refuses them with one log line, `multiplayer: a spectator or a partner with units given to them
plays no army, so third person stays off`, and keeps no press; their machines send nothing and put the gate in at the
players' tick. A watcher without the pack or memreader Plus is not caught: its machine runs without the gate and
desyncs (Ruling 34's cost). A machine without the pack stores a HELLO in RELOAD_TIME's global, which no code is known to read, so a
HELLO alone is taken to leave a mixed lobby in step (the record's checklist item 12 measures it), and one goes only
when a player presses F2. Single player has no handshake.

**The sending rules** (`M.net_rules`, pure Lua, the same lines the simulation's fake platform runs):

- **One action a body a tick.** MOVE, HALT and FOLLOW for a body share one slot per model tick, since the engine keeps
  one parked action per man and the later command in a tick wins (the record, "The overrides, live").
- **A clip holds his steps back.** From a clip's send, no MOVE, HALT or FOLLOW goes for that body until the clip shows
  (`P.anim_slot` reads its slot; `R.watch`, called by `main.lua` every frame for the man played, notices it while
  nothing else is sent) or its give-up passes: `LOCK_MAX + late()`, 3.2 s, for a swing or a cheer; `LOCK_WAIT +
  late()`, 1.2 s, for each shot phase (combat.lua); its own tick for a clip with none (a WALK_1 unstick, the CHARGE
  loop, a unit of one's defend). The queue's delay cancels out of this window: a later command arrives as far behind
  the clip as it was sent. The cost: a swing is not re-aimed while it waits, and one that never plays roots him to its
  give-up, about 2 s longer than single player.
- **Steer** sends a MOVE each tick it is free; **hold** one HALT, then a FOLLOW each time his heading changes; the
  **guard** one GUARD_ON per body; **disarm** and **arm** a carrier only when a body's kind changes (armed, or disarmed
  with its two flags), the mount's before the man's.
- **The ARM goes ahead of every attack or shot clip.** `R.play` pushes the ARM (when that body is disarmed) and then the
  clip in one Lua call, so the clip's slot is looked up armed on every machine. In net mode `P.play` never writes
  `+0x308`; single player still points him back at his own fragment directly.
- A push refused (the gate bytes set, no queue) is not marked sent, so it goes again.

**Refusals, and what the player sees.** The entry passes `bm:is_multiplayer()` to `M.build`. Net mode needs build
`6acec6f4` and its `BUILDS` row, then `install_net`, which refuses in this order: the MOVE, HALT and RELOAD_TIME ids
not registered or with no registry entry; no mailbox block; the six bytes at `exe+2ecfcb7` not the expected ones; the
carrier cave refused; the gate's bytes not the game's own branch (read, not patched: the build has just taken out a gate
a battle before left in); the gate's write refused, in or then out (`the order gate cannot be written`, `the order gate
went in and cannot be taken out`). The proof runs as the battle loads, before its first tick, so its moment with the
gate in changes no man's update. Each refusal, or a throw, is recorded as `net: <why>` and leaves single player's
functions in place and the gate out, except an out-write refused after the in-write went, which leaves it in and says
so; a refused machine has no handshake, so it never says HELLO. A carrier cave that went in stays
for the session (section 9). Inferred, not run: against a peer in net mode it still claims that peer's guard entries and stops that
man's orders on this machine only.

The entry then finds multiplayer with no net mode: it logs once `derpy_tp: multiplayer is off: <the platform's
problems>`, loads nothing else, and F2 shows `derpy_tp_multiplayer` ("Third-Person Battles is off in replays. In
multiplayer it needs an up-to-date memreader Plus and a supported game version on every machine; the
script log has the details."). A replay is always off; in a replay of a multiplayer battle `install_net` still
runs if `bm:is_multiplayer()` is true there, so the recorded carriers meet a cave, and the recorded HELLOs are inferred
to put the gate in at the tick they did in the battle, if the replay's player list names the battle's players; an
empty one leaves the gate out for the whole replay (checklist item 13).

In net mode, F2 before "Deployed" does nothing and says nothing: `P.net_ready` is set only once this machine's copy
table is built. A table that threw leaves it unset for the battle, F2 silent, this machine's HELLO unsent (so no peer
starts either), and one line, `derpy_tp: multiplayer is off for this battle: the fragment table did not build:
<error>`. At "Deployed" each machine logs once `derpy_tp: the fragment table took <n> model ms (<r> real ms), <k>
fragments`; the model figure reads 0 if the battle waited for the build.

**The delay.** `P.net_delay = 0.2` s, provisional: two ticks, the one-machine figure (in Task 2 every queued command
whose effect a getter shows changed it 200 ms after the script call; aiming, a weapon change and a projectile's first
casualty showed later, at +500 to +1200 ms, with a lead time of their own). It is used only by `late()` in `combat.lua`,
which lengthens the windows that wait for a clip to show; the simulation uses `DELAY_TICKS = 2`
(`tools/third_person_lockstep.lua`). Both take the two-machine figure.

## 14. Open

- Which formation routine issues him an order every melee tick (the caller of `+0x4b0`): not traced. Not needed
  for the fix.
- The `0x81` in the clip payload.
- A per-man gate. The mailbox's cave (section 9) already knows the man played, so the gate's decision could move
  into it. In multiplayer the guard table already lists, on every machine, every body the pack guards.
- The post-fire `nil` then `1557` frame after a shot.
- Which installer puts each engine command on him: the melee attack `3ad24b8` is built in the order issuer
  `306e89c` (constructor `3053684`), the regiment walk `3919350` and move `3ae1928` in `324e9dc` (from `306fea0`),
  move `39199f8` in `324e2c8` (five callers). Refusing them at the source would need a cave at each.
- A charge for one man or one chariot: the engine's charge (section 5) through the cave crashed twice (2026-10-20).
  Not to be reused for the flamethrower work either.
- **Melee damage in multiplayer** (section 12): the strike rolls through the update cave in single player. In
  multiplayer the roll has to go through the carrier cave, so every machine rolls at the same tick; not tried. The
  reach and facing test is the pack's own guess (0.5 m slack, 60 degrees), not `325fca4`'s thresholds.
- ~~Walls~~ **Closed 2026-10-29** (`sessions/THIRD_PERSON_WALLS_ARMY_ABILITIES_20261029.md`): the field was the walk's
  goal surface (`+0x378`, from the block's `+0x10`), left null by the mailbox, so a goal on a wall or deck was the
  terrain under it (state 7). The native move of 10-21 had built a walk with a real surface and the pack only rewrote
  its point. `P.steer` now copies his own `+0x920/+0x928` into the block, and the cave into his walk in place.
- The Irondrake flame drawn upward from `trigger_projectile_launch` (section 12): which effect is wrong is not
  isolated; first run the nulled launch-FX discriminator in the handoff.
- Multiplayer (section 13), code only and not on the live checklist: whether the host checks a relayed buffer against
  its sender; when `0xa1` is sent instead of `0xa2`; what sets the control object's `+0x518`.
- Multiplayer, the HELLO handshake: the gate goes in from a model callback mid-battle, not at build, while the battle's
  workers may be updating men (section 9). Whether CA's model timer runs between ticks, so the patch lands at the same
  point of the battle on every machine, is not traced; the record's checklist item 10 compares the two machines there.
- Multiplayer, also not on the live checklist: why a steered man in a melee covered 1.2 m in 5 s with the gate in and a
  MOVE every 0.1 s (the record, "The overrides, live", third row). The key press, his own fight clips and the gate were
  not separated; the open-ground control rules out the re-sending itself. One man, one 5 s run.
- Multiplayer, for the two-machine session. The record's "Live session checklist" holds how each is measured; its item
  numbers are in brackets.
  - That `+0x645c8` is EMPIRE_MP's object and a forged command pushed on one machine runs on the other at the same
    tick, its fields intact (1, 17). How many ticks a push waits across machines, which sets `P.net_delay` (2); one
    machine is two (Task 2).
  - The battle's `+0x3b0` and `+0x3b1` on a client, and what `+0x3b1` is (3). Either set there refuses every push,
    CA's script wrappers included.
  - Whether a dead man's update still runs, which decides whether the update cave's free ever fires; and what a MOVE,
    HALT or clip in flight does to a dying model, since every handler checks only that the id resolved (6). Whether the
    engine ever hands a freed model id to a new model, which a GUARD_OFF in flight would then reach (unmeasured: Task 2
    read a dense range of ids, 1 to 4,265 across 4,185 bodies, once at the start; reuse after a death was not looked at).
  - Whether a vanilla man ever parks an action in his queued holder. If none does, the gate, in from the handshake to
    the battle's end, is inert where nobody plays; if one does, it changes the battle from the handshake on, and a
    per-man gate keyed off the guard table is the redesign (10).
  - What CA's player list reads from Lua in battle, and whether every machine lists the same players (8, 21). The
    handshake's slots come from it (Ruling 30). Whether a campaign partner who is not in the battle is still listed:
    then the handshake never completes, safe, and the message names them.
  - What `bm:is_spectator()` returns on a watching partner, and what a watcher's desync does to the others (Ruling 34:
    a watcher is not waited for, so one without the pack desyncs).
  - Whether HALT cuts a clip that is playing: its stop replaces any command (15). How far FOLLOW turns a standing man
    toward the crosshair before a shot (14; Task 2: 55 of 90 degrees in 1.3 s).
  - Whether `bm:disable_orders(true)` is local (11); whether a lobby starts when one player lacks the pack (12); what
    `bm:is_multiplayer()` reads in a multiplayer battle's replay, and whether the replay reproduces it (13); whether
    commands execute before "Deployed" (16).
