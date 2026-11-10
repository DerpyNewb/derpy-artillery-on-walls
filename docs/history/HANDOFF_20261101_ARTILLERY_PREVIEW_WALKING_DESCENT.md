# Artillery walls: preview, walking and unresolved descent — 2026-11-01

## Resume here

**Superseded on descent by [the ground-recovery handoff](HANDOFF_20261101_ARTILLERY_GROUND_RECOVERY.md) (later on
2026-11-01): the installed pack is now `42F101AE`, the "down" recovery is gone and the stall detector was rewritten.**

Continue fixing artillery wall movement. The user wants artillery to walk and climb like infantry, and an eight-engine battery to show eight engine positions. They objected to ordinary orders instantly transporting the battery and repeatedly reported excess preview arrows. Do not call the whole feature resolved: descent remains open.

This is the current continuation point. [The native-slot handoff](HANDOFF_20261101_ARTILLERY_NATIVE_WALL_SLOTS.md) contains detailed assembly, structures and earlier experiments. Its **Earlier research checkpoint** section describes superseded states, including unchanged packs and ungated teleport prototypes.

## Source, generated files and deployment

| Role | Path |
|---|---|
| Owning generator | `tools/gen_artillery_walls.py` |
| Maintained runtime, including generated cave block | `Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua` |
| Generated AI weights | `Modding Files/source/artillery_walls/battle_ai/bai_values_major.txt` and `bai_values_minor.txt` |
| Native byte checks | `tools/artillery_wall_slots_tests.py` |
| Lua movement/queue checks | `tools/artillery_walls_tests.lua` |
| Build destination | `Modding Files/Modpacks/derpy_artillery_walls.pack` |
| Enabled local copy | `F:/SteamLibrary/steamapps/common/Total War WARHAMMER III/data/derpy_artillery_walls.pack` |
| Evidence and rejected probes | `Modding Files/Backup/artillery_walls/20261101/` |

Both pack copies were rechecked when writing this handoff: MD5 **AF32C88463AB7034B495EC772BE1916F**. The pack has fifteen scoped caves and targets executable build `6acec6f4`. Pack readback matched source; the BAI files did not change from the five-cave baseline. **Local deployment only; not published.** Do not edit the generated Lua block directly.

## Implemented behavior

Normal wall orders use CA's physical movement. The placement cave requires a per-unit recovery byte, normally zero. A 500ms callback allows nearby recovery only after five model seconds without material movement: over0.25m translation or approximately1degree of engine turning resets the window. Crew movement is considered too. Partial ascent/descent alone does not trigger teleport.

Wall recovery halts, waits100ms, transfers the complete unit, then queues the genuine native wall order. It keeps script control until that order restores its controller, clears the recovery byte and releases control. Whole-unit transfer preserves crew attachment in the successful tests. Recovery range uses the maximum pending distance, bounded at80m.

The excess arrows were a real preview bug. Two constructors used crew count after engine front positions were already emitted. Three scoped reads now use `unit+184` (primary entities) instead of `unit+a4` (crew):

| Site | Destination / unit register | Continuation |
|---|---|---|
| `2e0f3a8` | EDI / RSI | `2e0f3ae` |
| `2e0f96c` | R9D / RDI | `2e0f973` |
| `2e0f9bd` | ESI / RDI | `2e0f9c3` |

All preserve live RAX. Unlisted units execute the original reads. Do not globally override solver count: other callers request remaining subsets. The preview correction is integrated and cold-loaded; keep exact rendered-arrow-count verification in the next live regression pass because tooltips/occlusion obscured some captured positions.

## Evidence and limits

- `py tools/gen_artillery_walls.py --check` passed.
- `py tools/gen_artillery_walls.py --selftest` passed, catching26 deliberate assembly breaks and running the Lua movement/queue checks. Preview cases cover listed/unlisted units, counts1/8, intended count registers and live RAX preservation.
- Lua5.1 syntax and API checks passed. The ALL_CAPS scanner reports the intentional `_G.DERPY_AW_TEST` export guard; it is not an accidental runtime dependency.
- Independent read-only assembly review found no defect in the three preview caves.
- Cold AF32 battle: native ascent occurred before stall recovery at99600ms. At112900ms, eight attached engines and56crew occupied eight front/zero rear positions. Ammunition fell176→167, later140.
- Single-engine Deathshrieker reached one front marker after ascent and recovery at321600ms.
- Along-wall physical movement followed by recovery was tested on the preceding cold021CA candidate. AF32 changes its runtime only by adding the preview corrections. Along-wall roof firing was **not established**: ammunition stayed65 after the roof move despite later explicit target orders. Walkway firing was established. Retest roof line of sight and firing separately.

## Open descent defects

An initial ground move produced repeated down recoveries at777100/802100/826600ms. Later, primary count was56 and every crewman's `+2e0` engine link was null. The guns had been abandoned. This was observed, but the exact native cause was not captured. Earlier UI click/selection ambiguity also interrupted parts of that test, so do not infer a specific detach caller from it.

A rematch instrumented detach functions `3065744` and `3065a94` with the existing read-only `AWH.fhook` helper. Ascent again reached eight attached guns/56crew. An explicit native MOVE to(-45,-365) then left the engines circulating near the inner wall edge for over900model seconds. No detach hook fired; constant movement prevented the five-second quiet window. This is a confirmed limitation of the current stall detector.

Replaying the exact whole-unit ground recovery manually—halt,100ms,teleport,goto,release—brought all eight guns and56crew down attached, with zero detach calls. That repeat does not justify a generic detach guard or a speculative teleport/goto delay.

Evidence: `cold_descent_regression.json`, `rematch_descent_trace.json`, `packed_trace_up_along.json`, and the retained screenshots/probes in the evidence directory.

## Next work

1. Reproduce congestion with explicit native MOVE orders and record engine/crew trajectories, current order and model time. Distinguish circulating in place from legitimate travel toward stairs; straight-line distance alone is insufficient because a valid route can initially move away from the goal.
2. Reproduce abandonment with read-only entry telemetry at `3065744`/`3065a94`: record `[rsp]` caller, crew pointer, linked engine pointer and model time while allowing original execution. These functions update ownership before clearing `+2e0`; `3025364` appends detached crew to the primary vector. They also handle death, combat, transfers and explicit abandonment. Do not suppress them globally or guard only the final pointer clear.
3. Fix the demonstrated cause while preserving normal walking. Verify up, along, down, eight-engine and single-engine batteries, crew attachment, exact preview counts, walkway/roof firing, ordinary infantry and rematch reset.
4. Rebuild with the owning generator, verify pack/source readback, close the game before copying, and cold-load the final candidate. Update this handoff with results rather than claiming success from offline checks.

## Live test setup and traps

The saved custom siege loads through `button_battle` → `button_practice_battle` → `button_start_battle`. Player u2 is100 Infernal Guard, **u3 is eight Hobgoblin Bolt Throwers with56crew**, u4 is one Magma Cannon and u5 one Deathshrieker. The old handoff mislabeled u3.

After ending deployment, load `Backup/artillery_walls/20261101/setup_deployed.lua` in the bridge environment to initialize AWT and arrange the fixture. This uses test-only unit transfers; it is not the production movement path. `sample.lua` measures u3 engines/crew/markers and asserts engine attachment. `source/artillery_walls/probes/artwalls_hooks.lua` provides native observation helpers.

- The archived test list is `Backup/artillery_walls/20261101/used_mods_artwalls.txt`. Restore it to the install root only for testing, apply test preferences while the game is stopped, then launch `Warhammer3.exe used_mods_artwalls.txt;`.
- Game Lua numbers are float32: split RVAs into high/low16-bit parts before adding to `mr.base`. `math.huge` is absent. Native uint8 returns may be userdata; inspect with `mr.tostring`.
- Native wall controller is inline at unit+3300 when count+3310 is1. Primary engines: count+184, array+188. Crew: count+a4, array+a8; linked body at man+2e0.
- Genuine wall queue constructor/writer: `2ea9754`/`2df5a94`. Generic MOVE serialization does not restore a wall controller.
- Use a positive camera transition (1second worked); zero-time requests appeared ineffective. Do not disable camera functionality before the transition finishes. Edge hovering can pan the camera.
- Check actual unit selection. Some simulated card clicks displayed unit stats while another card remained selected. Real clicks or explicit controller movement orders removed that ambiguity.
- Always verify advancing `bm:time_elapsed_ms()`. An answering bridge/UI alone does not prove a running model.
- Do not reload old `resume.lua` over this build. Do not use `crew_test.lua`: bypassing `3078063` detached crew. Do not globally classify artillery as infantry: that prototype crashed. Rear cave must preserve live RAX; the prior omission froze deployment.

## Cleanup state

Game stopped; research RAM hooks are gone. Temporary install-root test mod list removed; archived copy retained. Original preferences restored byte-for-byte, SHA256 `C0CBCB390F1F16FA5075999BBCF700552AE2A1EEA55023040C4AB279CE698E4F`. No pending preferences backup was present when this handoff was written. The deployed AF32 pack remains installed.
