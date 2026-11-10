# Artillery on Walls

Put artillery on settlement walls in **Total War: WARHAMMER III** siege battles. Select a battery and right-click a
wall section, as you would with infantry. The guns climb the stairs, take the wall slots and fire from the walkway.

The mod is on the Steam Workshop as
[Derpy's Artillery on Walls](https://steamcommunity.com/sharedfiles/filedetails/?id=3837212899) and needs
[memreader Plus](https://steamcommunity.com/sharedfiles/filedetails/?id=3811098873). This repository is its source:
the battle script, the generator that writes its machine code, the tests, the probes that measured the engine, and
the record of each session.

## What it does

- **Guns on walls.** 50 vanilla units can go up: every artillery unit, plus the war machines whose engine carries the
  gun, such as the Chaos Dwarf gun vehicles and the Hellcannon. A modded unit counts if the game classes it as
  artillery.
- **Animal-drawn guns stay on the ground.** That covers 8 vanilla units: Cathay's Grand Cannon and Fire Rain Rocket
  Battery, the Ogre Ironblaster and Gnoblar Scraplauncher, the Little Grom and the War Wagon (two versions each of
  the last two). Archer chariots, sleds and a character's war machine are left out too.
- **Guns turn all the way round.** On a wall a gun turns to its target and fires, under fire at will or an order,
  including at enemies inside the city behind it.
- **Batteries pass each other on the walkway.** A gun on a wall takes half its usual room, but to enemy shots it is
  as big as on the ground.
- **The AI may use walls.** Its weight for artillery holding a wall goes from -1.0 (never) to 0.65, the value melee
  and ranged units already have. In both AI tests it still kept its guns on the ground.
- **Single player only.** In a multiplayer battle it switches itself off and the walls play as in the base game.
- **Safe across game updates.** It checks the game build and the bytes it patches. On any other build it switches
  itself off and battles play as normal.
- **Battle only.** Nothing goes in the save, so it can be added or removed mid-campaign.

Known issue: a cannon will not fire almost straight along its own wall (within about 10 degrees). Rockets and organ
guns do.

## How it works

The game refuses a gun on a wall in more than one place, and its database flag for climbing stairs is only the first.
The others are in the game's code: the unit's climb checks, each crewman's own check, the planner that hands out
firing spots, the turn limit on an engine, and the wall's fire-at-will search, among others.

The battle script writes 21 small machine-code patches into the running game through memreader Plus. Each one
answers a single check differently for the units the script has listed, and hands every other unit straight back to
CA's code. The list is filled at the start of each battle, after the patches are in. `docs/history/` records what
each patch answers and the run that measured it.

The patches are written in assembly in `tools/gen_artillery_walls.py`, assembled with keystone, and stored as bytes
in a generated block of the Lua between two markers. The same tool reads the list of wall guns out of the game's
database and builds the pack.

## What is here

| Path | What |
|---|---|
| `Modding Files/source/artillery_walls/script/battle/mod/derpy_artillery_walls.lua` | the battle script (1,036 lines), with the generated patch bytes and unit lists |
| `Modding Files/source/artillery_walls/probes/` | 17 probe scripts run against the live game |
| `tools/gen_artillery_walls.py` | the generator: the 21 patches in assembly, the wall-gun lists, the AI files, the pack build, `--check` and `--selftest` |
| `tools/artillery_wall_slots_tests.py`, `tools/artillery_walls_tests.lua` | the emulator scenarios for the wall-order patches, and the checks on the shipped Lua |
| `tools/make_practice_battle.py` | writes the custom siege the live tests ran in, with any race's army |
| `tools/exe_re.py`, `tools/exe_migrate.py`, `tools/ghidra_decompile.py`, `tools/ghidra/` | reading `Warhammer3.exe` from disk, and finding every address again after a game patch |
| `docs/history/` | the handoffs written as each part was measured in game |
| `docs/BATTLE_ENGINE_RE.md` | what was found about a battle soldier inside the exe, shared with Third-Person Battles |

The tools resolve paths relative to the author's workspace (`tools/`, `Modding Files/...`). This repository keeps
that layout, so they run from a clone.

**Not here:** `battle_ai/bai_values_major.txt` and `bai_values_minor.txt`. They are CA's files with one value
changed, so they are not published. `py tools/gen_artillery_walls.py` writes them from your own game's `data.pack`.

The generated block of the Lua is committed, so the repository reads without running anything. Run
`py tools/gen_artillery_walls.py`, and `git diff` should stay empty.

## How it is tested

There is no test framework.

- **The shipped bytes run.** `--selftest` takes the patch bytes out of the shipped Lua, checks they are the
  generator's own assembly, and runs each patch under the unicorn x64 emulator through every path: the registers, the
  stack at each call, and what it returns.
- **Every break is caught.** It then breaks the assembly 47 ways, each a plausible mistake (a test inverted, a gather
  with no range, a rejoin with the stack one slot off), and fails if any broken patch still passes.
- **The unit lists.** Named units are checked in and out: the Magma Cannon, the Iron Daemon and the Deathshrieker
  in; chariots, a character's war machine, the Luminark and Cathay's drawn guns out.
- **The Lua.** `artillery_walls_tests.lua` loads the shipped script under Lua 5.1 against a stubbed battle and
  memreader. It covers the stall recovery, the wall-order queue, the crew spot rules and the multiplayer switch-off.
- **The exe.** `--check` confirms the exe on disk is the build the patches were written for (6ae2a00b, patch 9.0.5),
  and that every patched site still opens with the bytes the patch displaces.
- **Measured in game.** Every patch was found and checked against the running game with the probes, and each
  handoff in `docs/history/` records the runs, including the ones that disproved an earlier idea.

## Running it

You need Python 3 and Lua 5.1 (`lua` on the PATH), plus:

- the Python packages `keystone-engine`, `unicorn`, `capstone`, `zstandard` and `numpy`;
- a Total War: WARHAMMER III install. The paths point at the author's Steam library: `EXE` and `DATA_PACK` at the
  top of `tools/gen_artillery_walls.py`, `DB_PACK` in `tools/read_vanilla_db.py`, and `tools/exe_re.py` reads the
  `WH3_EXE` environment variable;
- [RPFM](https://github.com/Frodo45127/rpfm)'s WH3 schema (`schema_wh3.ron` in its config folder), which the database
  reader uses, and RPFM open with its MCP server to build the pack (`--pack`).

The probes run inside a live battle through the WH3 MCP bridge (`loadfile`, then call). After a game patch,
`py tools/exe_migrate.py` finds each address again from a pre-patch snapshot of the exe. It needs a Ghidra project
imported before the patch (`tools/ghidra/DumpImage.java`).

## Credits

memreader Plus is by Druwski, after the original memreader by Cpecific and squeek502.

## Licence

MIT, see `LICENSE`.

This is an unofficial fan mod. Warhammer is a trademark of Games Workshop. Total War and Total War: WARHAMMER III are
trademarks of Creative Assembly and SEGA. Nothing of theirs is published here: no art, no footage, no game files, no
database tables, and none of CA's scripts or documentation. The two AI files the pack carries are rebuilt from your
own install.
