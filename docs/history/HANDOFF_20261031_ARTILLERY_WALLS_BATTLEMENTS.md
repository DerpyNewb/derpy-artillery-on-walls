# Artillery on Walls: battlement positions for batteries - handoff, 2026-10-31 (late)

Follows `HANDOFF_20261031_ARTILLERY_ON_WALLS.md` (read its 4c and 4d first). Build `6acec6f4`.

## Where it stands

- **Deployed pack** (`data/derpy_artillery_walls.pack`, md5 `81e8f962...`): five caves. The three climb checks, plus
  `hold` (327ebc8) and `noarc` (328507c). Batteries on a wall FIRE correctly, on fire at will and on orders. Backup of
  the previous pack: `Modding Files/Backup/artillery_walls/derpy_artillery_walls_20261031_before_battery_caves.pack`.
- **Source, not packed:** `derpy_artillery_walls.lua` holds an unwired teleport mover. `decide()` and its constants are
  near `WALL_RISE`, and the scan never calls it. The generated block now also carries `local U = {...}`, the engine
  offsets. `--check` and luac pass. Either wire the mover or delete it, per the direction below.
- **Not fixed: batteries cannot move on walls properly.** The author's direction (21:39): **multi-engine units must
  get FIXED battlement positions, like infantry** (the green wall markers): one engine per position, facing outward.
  The teleport mover is a workaround; it places a straight line at the clicked point and does not use those positions.

## Measured this round (real mouse clicks, every engine read)

The unit's position is ONE engine's. Read each body: `unit+0xa8` men (count `+0xa4`), `man+0x2e0` body, body `+0x910`
x,y,z, `+0x920` wall surface (null on the ground), `+0xb0` heading u16.

1. **Up, right-click on the walkway** (battery 44 m inside, 4x2):
   - The engines climb by two stairs, the walkway's (x≈-32) and the gatehouse's (x≈-15).
   - By 36 s all 8 are on wall surfaces, but the line runs from x -50 to 14. The 8 engines at ~6 m need ~56 m and
     this walkway section is ~46 m, so 3 engines end on the gatehouse roof (y 629, walkway 624).
   - Crew are left behind: each engine has 7 men (56 in all), and some stay on the ground.
2. **Down, right-click on the ground inside:**
   - Engine 2 drops at the walkway's drop point. Three of its men stay at that exact spot (-30, 624, -305) and plug it.
   - Engines 1, 3 and 7 queue there for good.
   - The gatehouse-roof engines never move.
   - Engine 4 is split: its body is on the roof and 4 of its men are on the ground.
3. **Scripted `goto_location` down from a clean walkway line:** all 8 down in ~26 s, one at a time.
4. **`uc:teleport_to_location` mid-battle works both ways:**
   - To the ground: 8/8 bodies and 56/56 men down, in a 4x2 block.
   - To (-45, -319) on the walkway with width 46: 8/8 on the wall, 56/56 men, one line x -66..-24,
     `is_on_top_of_wall` true.
   - The unit still takes orders after either. A battery pivots ~30 s before it sets off, which is normal, not a
     wedge.
5. **`unit:ordered_position()` detects a wall order:** y 624.1 against `bm:get_terrain_height` 609.3. Also:
   - `ordered_bearing` keeps the old facing when the click is not dragged.
   - `ordered_width` was 8 for a plain click.

## Next: battlement positions for batteries

1. Trace how an infantry unit ordered onto a wall gets its fixed positions. Suggested route:
   - Put an `AWH.fhook` trace on the slot setter `3071360` and the assigner `327e688` (and `32831bc`) for an INFANTRY
     unit given a real right-click onto the walkway. Compare its stack with the battery's for the same click.
   - Where the stacks diverge is the wall-position branch, and probably where it asks `is_infantry` or similar.
   - The positions are likely data on the wall section, the surface object at `+0x920`.
2. Make a listed battery take that branch:
   - One engine per position, spaced to fit the section, facing outward. This also closes "facing on arrival".
   - A cave, as the climb checks were done.
3. Re-test with REAL clicks: up, along (onto the gatehouse), down. Take a screenshot each time (below).
4. Only if engines still jam at the stair: wire the teleport mover (rules: first engine up -> whole unit to the
   ordered wall point; first engine down -> whole unit to it, then on to the order; stuck 5 s near a wall -> to the
   order).

## Test kit (scratchpad, NOT kept; rebuild from this)

- **Mod list and launch:**
  - Mod list: `used_mods_artwalls.txt` in the install. It is still there; delete it when testing ends.
  - Launch with `py tools/wh3_test_prefs.py --apply`, then `Warhammer3.exe used_mods_artwalls.txt;`.
  - Then `button_battle` -> `button_practice_battle` -> `button_start_battle`. The custom siege is saved in the
    battle preferences.
  - Rematch: menu -> concede -> tick -> `button_rematch` -> tick.
- **Setup in deployment.** Wait ~8 s first; a setup at 0.7 s is ignored.
  - u3 is the Deathshrieker battery: `uc:teleport_to_location(battle_vector:new(-37, 0, -275), 180, 50)`.
  - u2, the Infernal Guard, starts ON the walkway at x -66..-24, z -319. Move it off before a battery test there.
  - The enemy: take control, teleport to (-40, -520), halt.
- **Real clicks:**
  - Select the battery with its card: `battle_orders > cards_panel > review_DY > 1003`, `SimulateLClick`.
  - Clicking a card that is ALREADY selected is a double-click and jumps the camera to the unit, which ruins the aim.
  - Aim with `bm:camera():move_to(pos, target, 0, false, 0)`; the target is the screen centre.
  - Click: `Modding Files/source/lord_control/probes/tp_mouse.ps1 -fx 0.5 -fy 0.5 -button right`. Check the aim with
    a screenshot first: at that camera the walkway floor was at fy 0.54.
- **Screenshots:** start `Modding Files/Backup/terrain_routes_20261022/scripts/focus_shots.ps1 -pattern "x*.tga"` in
  the background, then `common.take_screenshot("x_1.tga")`. Files land in the install's `screenshots/`. The shot has
  no UI.
- **Traces and state:** `Modding Files/source/artillery_walls/probes/artwalls_hooks.lua` (`AWH.hook` / `fhook` /
  `poll`). The attack FSM state is behaviour `+0x38`, with state names in the 4c table of the main handoff.
- **Never skip a state's enter in a cave.** It crashed the battle thread (main handoff 4c).
