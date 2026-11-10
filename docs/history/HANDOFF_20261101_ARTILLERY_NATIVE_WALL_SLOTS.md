# Artillery native battlement slots, 2026-11-01

## Continuation: native walking and confirmed-stall recovery

The user clarified that artillery should walk and climb like infantry. **Instant placement on ordinary
orders was an overbroad prototype shortcut and has been removed.** Current maintained source defaults to
CA's physical walk setter; the placement cave requires a per-unit recovery byte, normally zero.
Candidate `AF32C88463AB7034B495EC772BE1916F` is built in Modpacks and enabled in data/.
Cold-loaded with all fifteen caves. Preview correction is integrated; descent remains unresolved as described below.
The older research record below describes the earlier ungated RAM experiments, not the intended behavior.

Implemented files: `tools/gen_artillery_walls.py`, `tools/artillery_wall_slots_tests.py`,
`tools/artillery_walls_tests.lua`, and the maintained battle runtime. The generator builds fifteen
unit-list-scoped caves: the original five plus wallgate, cursor, primary, solver, fronts, rear, placement and three preview count reads.
The pointer block now uses unit pointers at `+100`, recovery bytes at `+900`, max250, size1000 hex.
`CAVE_BLOCK_AT` records each cave's immediate offset; rear begins with push rax and therefore uses offset3.
Each battle resets recovery bytes, including rematches. The old Backup/resume.lua must not be loaded over this build.

Ordinary ascent, movement along walls and descent stay native. A500ms model callback tracks actual engine
movement/turning and the relevant crew positions. A recovery requires five seconds without material movement
(0.25m, or an engine turning1degree), a nearby destination, and an unfinished order. Ground motion is not judged
solely by straight-line distance, and partial ascent/descent no longer triggers an immediate teleport.
Wall range uses the maximum engine distance and includes pending crew; the nearest-engine check was rejected in review.

Wall recovery halts, waits100ms, transfers the complete unit with CA's unit API, then reissues the genuine
`BCQ_MULTIPLE_SELECTION_ORDER_DEFEND_BATTLEFIELD_ZONE`: constructor `2ea9754`, typed queue writer `2df5a94`.
Selection init/add are `2f2efc8`/`2f37be4`; destructor `1bcd8ac` releases command+8 and the temporary selection.
Arguments are `(command,selection,zone,point_xz,surface,0,0)`. Zone is controller+98 and surface from marker+30.
The generic MOVE constructor `2ea9a94` plus writer `1cae60c` DOES NOT restore the wall controller.
The unit stays under script control throughout the delayed recovery to avoid overwriting replacement player input.
Only its recovery flag enables engine snapping while restoring markers, then the byte clears before player control returns.
Ground recovery resumes the original movement order after bringing a stalled split battery down.

Latest live evidence (latest Lua hot-loaded over the same native flag-gated caves; cold-pack check pending):
`normal_walk_start.json` shows flag0, all eight bodies and56crew still on the ground three seconds after a real wall
click, physically turning/approaching. After77seconds all eight bodies and56crew were on walls; three engines remained
on the wrong roof/bridge positions. At model201100ms the corrected stall callback was loaded; it logged recovery
at206700ms. `normal_walk_recovered.json` records eight owned front positions, no rear positions, all headings32768,
56attached crew, flag0/pendingfalse afterwards, and continued ammunition use. Queuing the wall command while script
control remained held restored the native wall controller successfully.

Two rejected implementation traps are now covered or excluded:

- An early packed rear guard overwrote the live RAX vector count, freezing the model in `3008d80` during deployment.
  The guard now preserves RAX, and the emulator explicitly tests it. Crash `memreader_crash_report_011126_0834.txt`.
- Forcing crew through the native skip at `3078063` detached every crewman (primary count56, engine links null).
  `Backup/.../crew_test.lua` is a rejected experiment and is NOT in production. Whole-unit transfer preserves attachments.
- WH3's deterministic math table has no `math.huge`. The first normal-walking build's min accumulator therefore errored.
  The corrected max-distance accumulator starts at0; the Lua harness removes math.huge to match the game.
- The speculative "already at marker, return early" optimization was removed; recovery retains CA's native setter side effects.

Current checks: native generated-byte suite passes26 deliberate breaks, including ordinary movement remaining untouched,
per-unit flag indices0/2/249, stack/register preservation, marker ownership and the80m placement bound. The generator's
`--selftest` also runs the Lua ground/wall motion tests and the native wall queue argument contract. API/syntax checks pass.
Independent read-only review found no remaining assembly preservation defect; its range and input-race concerns were addressed.


### Preview correction after the user screenshot

The excess arrows were real phantom positions, not a wall-capacity display. Both hover constructors used
`unit+a4` (crew count) after front engine positions were already emitted. Three whitelist-scoped caves now
read primary engine count `unit+184`: `2e0f3a8` (edi, unit rsi, continue `2e0f3ae`), `2e0f96c`
(r9d, unit rdi, continue `2e0f973`), `2e0f9bd` (esi, unit rdi, continue `2e0f9c3`). All preserve
live RAX; unlisted units execute the original displaced read. Block continuation fields are +80/+88/+90 hex.
No global solver-count override: sibling callers legitimately request remaining subsets.
Tests cover listed/unlisted paths, counts1/8, stack/register preservation and deliberately reverting each
read to crew count. Independent assembly review found no live-register defect. Cold pack has no native
RAM prototype overrides; it loaded cleanly. At112900ms eight engines and56crew occupied eight front/no rear
positions; ammunition176->167, later140. Recovery logged at99600ms after physical ascent.


### Final local state and remaining descent defect

Built and enabled pack MD5: `AF32C88463AB7034B495EC772BE1916F`, fifteen scoped caves.
Pack readback is byte-identical to source; BAI files are unchanged from the baseline. Not published.
`--check`, Lua syntax/API checks and `--selftest` pass (26 deliberate breaks caught).
The ALL_CAPS undeclared-name scanner reports `DERPY_AW_TEST`, the intentional `_G` test export guard;
it is not an accidental global dependency. Review of the three preview caves found no register defect.

Cold initial battle verified eight front/zero rear, eight attached guns/56crew, native ascent before recovery,
and firing (176->140 ammunition). Single-engine Deathshrieker reached one front marker after physical ascent
and confirmed-stall recovery at321600ms. Along-wall walking/recovery was verified on the preceding cold
candidate021CA; finalAF32 adds only preview count corrections to that runtime.

**Do not call descent solved.** An initial ground move eventually produced repeated down recoveries and
then56primary infantry with null engine links. Artifact `cold_descent_regression.json` retains the prior
motion record. A rematch instrumented native detach functions3065744 and3065a94 using the existing read-only
`AWH.fhook` helper. Up again succeeded with eight attached engines/56crew, then a native MOVE to(-45,-365)
left the battery circling around the inner wall edge for over900model seconds; no detach hook fired and the
five-second quiet-motion detector never triggered. This demonstrates a separate recovery limitation:
continuous congestion movement can prevent the quiet window. Do not replace it with an unverified
straight-line-progress shortcut; legitimate stair routes may first move away from the goal.

Replaying the exact whole-unit ground recovery manually (halt,100ms,teleport,goto,release) brought all eight
guns and56crew down attached, with zero detach calls. So neither a generic detach guard nor a speculative
teleport/goto delay is justified by this repeat. `rematch_descent_trace.json` records zero detach hits.
To catch the original abandonment, retain read-only telemetry at3065744/3065a94 and record the entry caller
before choosing any prevention site. Both functions change primary ownership before clearing+2e0;
3025364 appends detached crew to unit+180. They also serve death/combat/explicit abandonment and must not
be suppressed globally. No new detach guard was shipped.

Game is stopped, all research RAM hooks are gone, the temporary install mod list is removed (archived in
Backup), and original preferences restored byte-for-byte, SHA256
`C0CBCB390F1F16FA5075999BBCF700552AE2A1EEA55023040C4AB279CE698E4F`.

## Earlier research checkpoint

Continuation of [the 10-31 battlement handoff](HANDOFF_20261031_ARTILLERY_WALLS_BATTLEMENTS.md).
**Research checkpoint, not a shipped fix.** Native slot placement now works in a live prototype;
ground departure, production scoping and full regression testing remain open.

## Source and deployment

- Maintained runtime: `Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua`.
- Owning generator: `tools/gen_artillery_walls.py`; it owns the generated Lua block and two BAI weight files.
- Build destination: `Modding Files/Modpacks/derpy_artillery_walls.pack`.
- Enabled local copy: `F:/SteamLibrary/steamapps/common/Total War WARHAMMER III/data/derpy_artillery_walls.pack`.
- Both packs remained **81E8F962650463DF44BAD6207206EB5C**, 32,407 bytes, build `6acec6f4`.
  No production source, generated output or pack was changed in this session. No upload.
- All new hooks were in process RAM. Research scripts, captures and JSON are under
  `Modding Files/Backup/artillery_walls/20261101/` (called `research/` below).
- The shipped `decide()` teleport mover is still unwired. Do not mistake its comments for running behavior.

## Correction to the saved custom-battle setup

Player u2 is Infernal Guard (100 men); **u3 is the eight-engine Hobgoblin Bolt Thrower battery**, with 56 crew.
The previous handoff called u3 Deathshrieker. u4 is Magma Cannon and u5 the single Deathshrieker.
Read every engine; the battle unit's one position cannot prove a battery arrived.

## Native wall order: the route that matters

Infantry's wall order has vtable `390e150`, constructor `300de58`, start `302aab4`.
It creates wall controller `300aeb4`, vtable **3911218**. This is a different route from the generic
formation/attack slots (`3071360`, `327e688`, `32831bc`) suggested in the old handoff.

`301d318` is the wall capability on the unit's `+20` interface (vtable slot `48`). It checks
unit `+1a4`, calls `301d098`, then `3014da8`, then `303425c` (is_infantry).
The scoped prototype at **301d346** bypasses just that last infantry test for u3, continuing at `301d34b`.
`research/wallgate_test.lua` contains it. A similar scoped cursor call at `3021854` is in
`wall_input_test.lua`; whether that second cave is necessary has not been isolated.

**Do not globally classify the battery as infantry.** An early experiment doing that crashed the model
thread at `3282cdd` in `3282bb8` (null+8, wall shooting/slot handover). Crash report
`memreader_crash_report_011126_0645.txt`, modified 06:52. UI and bridge stayed alive after the model froze;
samples after that freeze were invalid. The process was restarted. Later prototype samples were from
a live model, and no later crash report appeared. Check `bm:time_elapsed_ms()` across calls.

## Controller, primary entities and markers

Controller fields:

| Offset | Meaning |
|---|---|
| `18` | Unit |
| `88` | FSM state pointer |
| `98` | Wall group |
| `a0/a4` | Clicked x/z |
| `d0` | Approach battle location |
| `f8`, `100` | Primary/walking AI group and other AI group |
| `150` | Front marker vector: count `154`, data `158` |
| `160` | Rear marker vector: count `164`, data `168` |

States: `3d203f8` approach (enter `3029480`, update `30272b4`); `3d20400` prepare
(enter thunk `3027924` -> **3045454**); `3d20408` on wall (update `30271c4`).
Approach normally issues generic formation movement via `327eca4` to `c+d0`.
On-wall update retries per-entity marker movement via `303b4e8`.

**Prepare iterates crew, not engines.** At `3045454`, replace three operand displacements:
`3045481: a4->184`, `3045498: a8->188`, `30454ad: a4->184` (each is a four-byte displacement).
Then the group's member count becomes eight bodies instead of 56 men.
`unit+184/+188` is the primary count/array; infantry's primary array matched its 100 men.
`wall_models_test.lua` applies these *global* operand edits for research. Production must scope them
to the shipped unit list and verify other entity types before adopting them.

Slot metadata `S` (vtable `390b208`):

| Offset | Meaning |
|---|---|
| `10` | Marker handle |
| `18` | Parent row descriptor `P` |
| `20` | Native 32-byte battle-location block (x/y/z at `20/24/28`) |
| `40` | **Assigned occupant entity pointer** |
| `50` | Linked marker behind this one |

`P+28/+2c` are the x/z normal; `P+30` is row type; `P+5c` is marker count;
`P+60` is contiguous metadata storage, stride **58 hex**. On this map type 0 rows are fronts,
type 3 rows are rears. CA recognizes additional front types (1, 2, 12..15 hex); the prototype
accepts only type 0. Marker heading comes from the normal, not the click's old bearing.
Do not use body `+968` as the assigned slot: it retained a previous marker in live reads.

## Sparse slots and the shared solver

The native route includes `3023dc4 -> 3024114 -> 30249f0`. The first function filters candidates
at `3023fb2`; `[rdi+10]` is selection, selection `+1c` count, `+20` unit pointer array.
A trace confirmed count 1 and the correct u3 pointer. Filtering here alone is insufficient:
**30249f0 also has caller 3024f38**, which assembles candidates independently. Other callers are
inside `3024114`, returning at `3024419`, `30246dc`, `302488c`; the fourth returns at `3025081`.

Working research filters:

- Front type 0, row count >=3, every third marker: `(S-[P+60]) % 0x108 == 0`.
  Native spacing is 1.8 m; most retained gaps are 5.4 m. A row boundary on the walkway leaves a
  **3.8 m** gap, so this is not yet a general minimum-clearance solution.
- Filter the shared solver's candidate loop at **3024acc**, where rsi is the unit and `[rbx]` the slot;
  reject to `3024b12`. `solver_filter.py` assembles it, runs six Unicorn cases, and writes
  `solver_filter.lua`. Earlier preview filters are still installed in the live prototype; they
  have not been removed and tested independently.
- At solver entry **30249f0**, u3's float arguments 7/8 (`[rsp+38]`, `[rsp+40]`) become 36.0
  (6 m squared connection distance). `front_slots_test.lua` includes this cave.
- Filtering candidates does not suppress the rear chain: at **3024e86**, CA follows `S+50` and
  adds rear markers. Skip to `3024ea8` for the battery.
- The first rear guard inferred the unit from saved caller r14/rbx (`[rbp+f]`, `[rbp+57]`). It
  missed a call path. A later saved-rbp guess at `+37` also failed to prevent rear allocation.
  **Do not promote these stack guesses.**
- The working replacement at **3024a20** writes a per-call u3 flag in `[rbp+63]`, which is entry
  rsp+24: the unused upper four bytes of the fourth argument home slot. This function stores r9d
  at entry+20, reads its count as a dword at rbp+5f, and its full disassembly does not use +63.
  The rear cave tests this byte instead. `solver_rear_flag_test.lua` installs the flag cave and
  updates the first four-byte comparison in the existing research rear cave's allocation.
  This was tested live, **not covered by the six candidate-filter emulator cases**.

## Native teleport command, retaining the assigned location and normal

Walking the physical battery still jams at stairs. Per-body native teleport requests can place it
on the fixed markers, with crew, without raw position writes.

- Body vtable slot `368` is **3070a24**, forwarding its parent at +d08 and then the body at **3070a48**.
- Ordinary walk command ctor `2f648e4`; teleport ctor `2f64870`. Walk setter takes command in rdx;
  command `+50 & 20 hex` selects CA's teleport branch. Prototype sets byte50 to **26 hex**.
- Copy the marker's 32-byte battle location `S+20` into command+0. Calculate heading with native
  `1183a8c` (xmm0 normal x, xmm1 normal z), multiply by float `3922260`, round through `4eda50`;
  write ax at command+40. Set byte51 to `(old & fd)|1`, then call **2f775ac(command,body)**.
  Set r8b=1 for the walk setter's third parameter.
- Index mapping is useful only before assignment: body ordinal in `unit+188` -> front marker ordinal.
  Once assigned, search the front vector for **S+40 == body**. Index-only movement put bodies in
  other bodies' markers and generated repeated mismatches.
- The live experiment uses layered caves: `snap_slots_test.lua` at `3070a24`,
  `place_all_slots_test.lua` at `3070a48` (index mapping for approach), and
  `place_owned_slot_test.lua` at `3070a52` (assigned-occupant override).
  They must be consolidated before production; the first prototype's +968 guard is obsolete.
- Native calls preserve rcx/rdx/r8/r9 via four pushes and sub rsp,28 hex. The body setter entry's
  alignment is maintained. These new placement caves still need a proper emulator/register suite.

## Live evidence and its limits

Saved raw bridge results: `research/final_roof.json`, `roof_transition.json`, `down_start.json`,
`down_later.json`; earlier `owned_outer.json`. Each file wraps the JSON in the tool's text content.
`sample.lua` reads every unique body, all crew, controller state, marker occupants and ammunition.

- Gatehouse outer edge at model time **1,860,800 ms**: eight front markers, zero rear, eight AI members;
  all eight bodies exactly matched their assigned marker's x/y/z, heading **32768** (outward),
  all 56 crew on wall. x -18.0005..19.7995, z approximately -321, y approximately 629.08.
- A real right click then moved the battery to the outer walkway: eight front, zero rear,
  eight bodies on wall, all 56 crew on wall, all headings32768. Markers x -67.2005..-31.0005,
  y624.084, z approximately -321. One body drifted ~0.64 m along x after placement; other bodies
  matched exactly. Do not claim all eight remain exactly fixed under collisions.
- Ammo fell **139 ->132 ->126** during the roof/walkway sequence. Firing occurs, but this is not
  a full sustained-fire/reload regression test. Repeated teleport walk requests may reset attacks;
  production should avoid unnecessary repeats and test an explicitly held target.
- A real outer-ground click gave controller count0. Fifteen model seconds later, two bodies were
  on the ground and six on wall, with 55 crew still on wall. This is a partial descent, not by
  itself proof of a permanent jam. Earlier sessions already established stair/roof jams.
- An attempted inner-ground click subsequently produced an inner-roof wall order instead. The
  immediately returned `ordered_position()` was misleading while the native order was being queued.
  Wait model ticks and inspect the controller and all bodies before interpreting a click.
- Later inner-roof placement had eight front markers, zero rear, all eight bodies aligned inward
  (heading0), but only55 crew on wall. Crew recovery under repeated wall changes remains open.
- Final outer-ground order from that inner roof: at model time **2,133,200 ms**, more than two model
  minutes after the click, controller count was0 but **all eight bodies remained on the roof**.
  Six stayed at their former marker; two shifted/turned on the roof. All56 crew had recovered to
  the wall. `research/last_down.json` records this roof-exit failure; do not count the earlier
  partial descent as a solved ground exit.

## Reproduction and input traps

`research/resume.lua` compiles and assembles the recorded probe order for a **fresh process** in the saved
five-unit siege. It initializes AWT and controllers, but does not position armies. The complete loader
has not itself been cold-run as a unit; its component probes were installed incrementally live.
Its pointer-embedded caves are **not safe to reuse after rematch**. Restart the game.
Run `py "Modding Files/Backup/artillery_walls/20261101/solver_filter.py"` first.

The test kit's initial positioning still applies: after deployment has settled, move u2 off the
walkway, set u3 inside the wall, hold the enemy well outside. Use the previous handoff's launch/setup
instructions. For selection, documented `bm:clear_selection()` followed by the card's SimulateLClick
gives one selected unit. Do not repeatedly click an already selected card (camera jump).

The game reports UI1600x900 while the test client is1280x720. A backup mouse helper adding per-monitor
DPI awareness (`research/mouse_dpi.ps1`) returned the same screen coordinates; **no DPI fix was proved**.
Desktop captures showed the actual view differed from earlier game screenshots. Aim using a fresh
foreground capture, inspect the eventual controller, and verify model time. Camera movement plus
screenshot in the same eval can capture the preceding frame. A separate frame/focus step is needed.
The camera was temporarily locked with documented
`camera:enable_functionality('CAMERA_ALL_FUNCTIONS',false,true)` to stop drift.
Examples of the observed actual-window view are `research/desktop_click.png` and `roof_window.png`;
these include the desktop. Other older game screenshots are not proof of final candidate behavior.

No maintained mouse helper was edited. Invalid experiments and captures remain under Backup for diagnosis.

## Validation and next work

- `py tools/gen_artillery_walls.py --check`: passed.
- `py tools/gen_artillery_walls.py --selftest`: passed, 12 deliberate breaks caught. This tests
  the unchanged shipped five caves, **not** the research additions.
- `solver_filter.py`: six shared candidate-filter cases passed (listed/unlisted, front/rear,
  small row and column spacing; stack restored).
- All13 research Lua chunks compiled with the game's Lua `loadfile`, without executing the loader.
- No new pack build/deployment was attempted.
- Test cleanup: game closed, original preferences restored byte-for-byte (SHA256 compared with
  the pre-test backup), and install-root `used_mods_artwalls.txt` archived under research/ then removed.
  All RAM hooks are gone. Recreate the archived test mod list and apply test preferences before relaunch.

Next: consolidate the native route into generated, unit-list-scoped caves with original-byte/build
guards and emulator checks. Remove duplicate preview/placement caves only after equivalence checks.
Resolve crew recovery and minimum clearance across row boundaries; test other maps, directions,
one-engine artillery, unlisted infantry/vehicles, AI, replay and multiplayer scope.
For the stair fallback, use the existing `decide` rules as a starting point, not as working runtime.
Halt and allow a model tick before whole-unit teleport, otherwise an old order can reorient/replan it.
Real-click up/along/down and sustained firing must pass before updating a pack. Keep Workshop publication separate.
