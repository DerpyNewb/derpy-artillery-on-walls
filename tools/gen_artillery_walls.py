"""Artillery on Walls (derpy_artillery_walls.pack): artillery and gun war machines may stand on settlement walls in
siege battles, the player's and the AI's. Writes the generated block of the shipped battle script and the two
battle-AI weight files; the pack is built with RPFM open.

    py tools/gen_artillery_walls.py              write the Lua's generated block and battle_ai/bai_values_*.txt
    py tools/gen_artillery_walls.py --check      exit 1 when the shipped files differ from what this writes, or the exe
                                                 on disk is not build 6acec6f4 with the code the caves displace,
                                                 or a wall gun has more crew on one engine than the Lua's SLOT_MAX
    py tools/gen_artillery_walls.py --selftest   run the SHIPPED cave bytes under unicorn: every path, register, the stack
                                                 at each call; then break the assembly and prove each break is caught
    py tools/gen_artillery_walls.py --pack       build Modding Files/Modpacks/derpy_artillery_walls.pack (RPFM open)

The caves (one per check, docs/sessions/HANDOFF_20261031_ARTILLERY_ON_WALLS.md):
    climb  exe+3014da8(unit)  in the table: return unit+0x1a4 == 0, skipping the battle_entities flag and is_infantry
    links  exe+301d69c(unit)  in the table: CA's own first three tests (301d214, +0x154, 301d098), not the flag/infantry
    man    exe+305952c(man)   his unit in the table: skip his +0x2a0 (false on a vehicle body), then CA's tail, climb
and two that keep a battery firing from the wall once it is up there (rcx is the attack order's behaviour):
    hold   exe+327ebc8(beh)   a listed unit on a wall returns at once: no march toward a target out of reach, which
                              turned the battery into town and walked it off the wall
    noarc  exe+328507c(beh)   a listed unit on a wall answers false to "the target left the planned arc": no re-face,
                              whose re-plan moved the formation forward, cancelled every fire action and dropped the order
                              for good. A gun on a wall keeps its frontal arc, as wall infantry do.
    clearshot exe+305eb74(body) a listed unit's engine standing on a wall answers "clear shot": CA's trajectory test
                              from the muzzle fails on a wall section whose parapet stands in the line (Altdorf's 111.6
                              section: every cannon engine there sat in "Clear shot failed" for ever, 2026-11-02), and
                              with it passed all four fired and the shots landed (17 rounds, the target 160 -> 123 men)
    arc    exe+2f8ed98(arc, body, target) a listed unit's engine on a wall gets the half-arc of the caller's record
                              opened to the full circle; range still applies. The planner gives an engine a firing spot
                              only for an enemy man within half the arc of the FORMATION's heading, and noarc stops the
                              formation re-facing on a wall, so engines whose men lay outside it never got an order and
                              never turned (1 of 4 cannons, 2 of 4 rockets, 2026-11-03). All three callers build the
                              record on their own stack per call.
    inplace exe+2f86888(action) the fire order's dispatch: bit 8 of the action's +0xd8 sends the engine to the
                              solver's firing spot before the shot (vslot 0x5b0); cleared for a listed unit's engine
                              on a wall it shoots from where it stands (vslot 0x5a0). With the arc open the spots
                              came out permuted along the walkway, so the rocket engines walked into each other and
                              none fired (2026-11-03, 9.0.5). Measured on 2026-10-31 as the test cave 2f7f448.
    radius exe+30959d7(rbx, the entity) CA's per-tick store of battle_entities.radius into the body's +0xa0: scaled
                              by the Lua's WALL_RADIUS for a listed unit's engine (vtable exe+3adee48) standing on a
                              wall. At full size a docked cannon was shoved and packed by a battery walking past it
                              (2026-11-09 runs 13-14); at half size it stood 0.00 m.
    hitsize exe+3165e43(rcx, the entity) the hit-shape builder exe+3165e14 (a shot's path against an entity: callers
                              exe+2f765d8 / 30b1ad2 pass a segment and get back how far along it the hit lands)
                              reads the radius from the same +0xa0 and, for a shot, multiplies it by
                              battle_entities.projectile_intersection_radius_ratio (record +0xb8, vslot 0x150):
                              divided back by WALL_RADIUS for the same engines, so a docked gun is as big to a shot
                              as on the ground and only its bumping is halved (2026-11-09, static). Each widened
                              test adds 1 to the block's hit_count (+0x74): about 8 per enemy arrow (run 33).
    wallscan exe+3036668(rbx, the unit's wall fire-at-will state) a unit holding a wall picks its fire-at-will
                              targets in exe+3036384, not in the regiment pick: per wall section it gathers the
                              enemies inside a cone straight out from the section (exe+301e9f4, +- half the gun's
                              fire arc), and when every section comes back empty it drops its targets and destroys
                              the attack (exe+30dc0ec). A listed unit whose first man stands on a wall gathers every
                              enemy in range instead, with CA's all-round gather exe+2f64860 into the same list, and
                              rejoins at exe+3036691, where CA's best-target choice reads it (run 39: a target that
                              jumped 45-60 degrees off was dropped by both batteries for good).
    turn   exe+308d0a8(rsi, the body) set-goal exe+308cfa0's turn clamp: a listed engine on a wall gets a half-arc
                              of 0x7fff instead of half its fire arc around +0xd9a, so it turns all the way round to a
                              target (the author, 2026-11-10; the window had held a docked Helstorm to +-30 degrees).
Six further caves select CA's native wall order, use primary entities rather than crew in its controller,
filter sparse front markers and suppress rear chains.
Movement runs CA's walk setter. Lua retries a confirmed nearby stall once.
Three preview reads use engine count instead of crew count, preventing phantom arrow positions.
Mid-function caves preserve their live values (notably the rear loop's rax count). The two infantry call sites
explicitly run the original call or supply its listed-unit answer and jump past the displaced call.

The block holds native addresses, count and up to 250 unit pointers at +100. Each pointer is initialized
before publishing the count. Every battle resets the count, including rematches.

Which units: every artillery unit, and a war machine whose engine carries the gun or whose engine body is an
artillery-type entity (the Chaos Dwarf vehicles) - not archer chariots, sleds or a character's war machine, and not a
gun drawn by an animal (a draught mount in land_units: Cathay's two, the Ogre Ironblaster and Scraplauncher, the
Little Grom, the War Wagon - not the Chaos Dwarf vehicles' hidden mounts; the author's call, 2026-11-09, after Cathay's drawn engine class crashed the game on a
wall). Not battlefield_engines' draught attachment: the Deathshrieker names one and has no animal. Those go in the Lua's DRAWN list, which it refuses even when
unit:is_artillery() would let them in. Computed from vanilla land_units; the Lua adds any modded unit for which
unit:is_artillery() is true (a modded drawn gun is not caught: the Lua cannot see its draught attachment).

Needs keystone-engine and unicorn (pip). AI: CA's battle_ai/bai_values_major.txt and _minor.txt with OCCUPY_WALL's
AIUF_ARTILLERY raised from -1.0 (never) to the 0.65 melee and ranged units get.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "Modding Files", "source", "artillery_walls")
LUA = os.path.join(ROOT, "script", "battle", "mod", "derpy_artillery_walls.lua")
BAI = [os.path.join(ROOT, "battle_ai", n) for n in ("bai_values_major.txt", "bai_values_minor.txt")]
PACK = os.path.join(HERE, "..", "Modding Files", "Modpacks", "derpy_artillery_walls.pack")
EXE = r"F:\SteamLibrary\steamapps\common\Total War WARHAMMER III\Warhammer3.exe"
DATA_PACK = r"F:\SteamLibrary\steamapps\common\Total War WARHAMMER III\data\data.pack"
BEGIN, END = "-- generated by tools/gen_artillery_walls.py: do not edit between the markers", "-- end of the generated block"

BUILD = "6ae2a00b"
SITES = {"climb": 0x301c220, "links": 0x3024aa4, "man": 0x3060aa8, "hold": 0x328642c, "noarc": 0x328c8e0,
         "clearshot": 0x30660f0, "arc": 0x2f96234, "inplace": 0x2f86888}
CAVE_ORDER = ("climb", "links", "man", "hold", "noarc", "clearshot", "arc", "inplace")  # climb first: the man cave jumps into it
# what each cave's jump displaces, run after the cave on the way back in
SITE_BYTES = {"climb": bytes.fromhex("4053 4883ec20"),  # push rbx; sub rsp, 0x20
              "links": bytes.fromhex("4053 4883ec20"),
              "man": bytes.fromhex("4053 4883ec20"),
              "hold": bytes.fromhex("488bc4 48895808"),  # mov rax, rsp; mov [rax+8], rbx
              "noarc": bytes.fromhex("488bc4 48895818"),  # mov rax, rsp; mov [rax+0x18], rbx
              "clearshot": bytes.fromhex("48895c2408"),  # mov [rsp+8], rbx
              "arc": bytes.fromhex("488bc4 48895808"),  # mov rax, rsp; mov [rax+8], rbx
              "inplace": bytes.fromhex("488bc4 53 4881ec50010000")}  # mov rax, rsp; push rbx; sub rsp, 0x150
CALLS = {"fn_climb": 0x301c220, "fn_a": 0x302461c, "fn_b": 0x30244a0}
B = {"fn_climb": 0x00, "fn_a": 0x08, "fn_b": 0x10, "count": 0x18,
     "fn_inf": 0x20, "gate_cont": 0x28, "cursor_cont": 0x30, "fn_add": 0x38,
     "prepare_cont": 0x40, "candidate_next": 0x48, "rear_next": 0x50, "wall_vt": 0x58, "move_vt": 0x60,
     "preview_cont": 0x80, "preview_models_cont": 0x88, "preview_order_cont": 0x90,
     "units": 0x100, "max": 250, "size": 0x1000}
U = {"climb_gate": 0x1a4, "links_gate": 0x154, "unit_of_man": 0x2e8,
     # the attack behaviour (rcx of hold and noarc): +8 an owner whose +0xa10 is the unit; the unit's men at +0xa8 (count
     # +0xa4); a man's +0x920 is the wall surface he stands on, null on the ground
     "beh_owner": 0x8, "owner_unit": 0xa10, "men_count": 0xa4, "men": 0xa8, "surface": 0x920,
     # the Lua's mover: a man's engine body, and a body's position block (x, y, z floats) and heading (u16)
     "body_of_man": 0x2e0, "pos": 0x910, "heading": 0xb0}
PLACEHOLDER = 0x1122334455667788
BLOCK_AT = 2  # climb's block pointer; other caves use their generated CAVE_BLOCK_AT offset

FIND = """
    mov r10d, dword ptr [rax + {count}]
find:
    test r10d, r10d
    jz miss
    dec r10d
    cmp {who}, qword ptr [rax + r10*8 + {units}]
    jne find
"""
ASM = {
    "climb": """
    mov rax, {placeholder}
""" + FIND.replace("{who}", "rcx") + """
    xor eax, eax
    cmp dword ptr [rcx + {climb_gate}], 0
    sete al
    ret
miss:
""",
    "links": """
    mov rax, {placeholder}
""" + FIND.replace("{who}", "rcx") + """
    push rbx
    push rsi
    sub rsp, 0x28
    mov rbx, rcx
    mov rsi, rax
    call qword ptr [rsi + {fn_a}]
    test al, al
    jz no
    cmp dword ptr [rbx + {links_gate}], 0
    jne no
    mov rcx, rbx
    call qword ptr [rsi + {fn_b}]
    test al, al
    jnz no
    mov eax, 1
    jmp out
no:
    xor eax, eax
out:
    add rsp, 0x28
    pop rsi
    pop rbx
    ret
miss:
""",
    "man": """
    mov rax, {placeholder}
    mov r11, qword ptr [rcx + {unit_of_man}]
""" + FIND.replace("{who}", "r11") + """
    cmp dword ptr [r11 + {links_gate}], 0
    jne one
    mov rcx, r11
    jmp qword ptr [rax + {fn_climb}]
one:
    mov eax, 1
    ret
miss:
""",
}
# the battery caves: rcx is the attack behaviour; a listed unit whose first man stands on a wall
ON_WALL = """
    mov rax, {placeholder}
    mov r11, qword ptr [rcx + {beh_owner}]
    mov r11, qword ptr [r11 + {owner_unit}]
""" + FIND.replace("{who}", "r11") + """
    cmp dword ptr [r11 + {men_count}], 0
    jz miss
    mov r11, qword ptr [r11 + {men}]
    mov r11, qword ptr [r11]
    cmp qword ptr [r11 + {surface}], 0
    jz miss
"""
# hold is for the attack behaviour's march only: the plain move behaviour falls through to CA's code
MOVE_GATE = """
    mov r11, qword ptr [rcx]
    cmp r11, qword ptr [rax + {move_vt}]
    je miss
"""
ASM["hold"] = ON_WALL.replace("    mov rax, {placeholder}\n", "    mov rax, {placeholder}\n" + MOVE_GATE, 1) + """
    ret
miss:
"""
ASM["noarc"] = ON_WALL + """
    xor eax, eax
    ret
miss:
"""
# the engine's clear-shot test: rcx is the engine body; a listed unit's body standing on a wall surface answers true
ASM["clearshot"] = """
    mov rax, {placeholder}
    mov r11, qword ptr [rcx + {unit_of_man}]
""" + FIND.replace("{who}", "r11") + """
    cmp qword ptr [rcx + {surface}], 0
    jz miss
    mov eax, 1
    ret
miss:
"""
# the planner's arc test: rcx the caller's record (u16 heading, u16 half-arc, then the ranges), rdx the engine body;
# 0x8000 is the value CA's own test reads as the full circle. Both paths run CA's test.
ASM["arc"] = """
    mov rax, {placeholder}
    mov r11, qword ptr [rdx + {unit_of_man}]
""" + FIND.replace("{who}", "r11") + """
    cmp qword ptr [rdx + {surface}], 0
    jz miss
    mov word ptr [rcx + 2], 0x8000
miss:
"""
# the fire order's dispatch: rcx the action; its engine body is [[rcx+0x10]+8]. A listed unit's engine on a wall
# loses bit 8 of the action's +0xd8 (move to the spot first) and shoots in place. Both paths run CA's code.
ASM["inplace"] = """
    push r9
    mov rax, {placeholder}
    mov r9, qword ptr [rcx + 0x10]
    mov r9, qword ptr [r9 + 8]
    mov r11, qword ptr [r9 + {unit_of_man}]
""" + FIND.replace("{who}", "r11") + """
    cmp qword ptr [r9 + {surface}], 0
    jz miss
    and byte ptr [rcx + 0xd8], 0xf7
miss:
    pop r9
"""

# Native battlement orders. The shared solver serves both cursor previews and real orders.
NATIVE_ORDER = ("wallgate", "cursor", "primary", "solver", "fronts", "rear")
CAVE_ORDER += NATIVE_ORDER
SITES.update(wallgate=0x302474e, cursor=0x3028c5c, primary=0x304c87d, solver=0x302bdfc,
             fronts=0x302bed8, rear=0x302c292)
SITE_BYTES.update({k: bytes.fromhex(v) for k, v in {
    "wallgate":"e8ed6e0100", "cursor":"e8df290100", "primary":"488b431833ff",  # both: call fn_inf (rel32 per build)
    "solver":"488bc448895818", "fronts":"488b134438bd87000000", "rear":"488b4e504885c9"}.items()})
CALLS.update(fn_inf=0x303b640, gate_cont=0x3024753, cursor_cont=0x3028c61, fn_add=0x30ecaa4,
             prepare_cont=0x304c8b7, candidate_next=0x302bf1e, rear_next=0x302c2b4,
             wall_vt=0x391d440)
# The regiment's plain move behaviour (2026-11-09, live): its move state's update exe+327b224 is the ONLY caller of
# the hold site, and it is shared with the attack behaviour. hold must not answer for this one, or a battery whose
# first man is on a wall never starts a march: the state machine flips to its halt state (enter exe+327bd74 stops
# every engine of the group) and back every tick, and only the engines already off the wall get away.
CALLS["move_vt"] = 0x3aef828
MOVE_FSM_TICK = (0x3aef838, 0x3287980)  # the vtable's +0x10 slot, checked on disk by exe_problems()

# A docked gun's collision radius (2026-11-09, live). exe+30957dc, an entity routine every man and engine runs, sets
# the body's +0xa0 = battle_entities.radius (record +0x5c) x the battle's scale every tick, and +0x9c the height; a
# Lua write to +0xa0 is gone by the next tick. Halved through the shared record, docked cannons stood 0.00 m while
# a helstorm battery walked past them (0.2-0.4 m and two packed guns at full size, runs 13-14). The cave scales the
# radius only for a listed unit's ENGINE (vtable exe+3adee48: its crewmen carry the same unit at +0x2e8) on a wall,
# before CA's own store, so the animation-driven radius later in the routine (x xmm7) follows it.
CAVE_ORDER += ("radius",)
SITES["radius"] = 0x30959d7
SITE_BYTES["radius"] = bytes.fromhex("f30f11bba0000000")  # movss [rbx+0xa0], xmm7
CALLS["engine_vt"] = 0x3adee48
ENGINE_VT_FIRST = 0x305f2f0  # the engine vtable's first slot, checked on disk by exe_problems()
B.update(engine_vt=0x68, wall_radius=0x70)  # wall_radius: a float the Lua writes at install
ASM["radius"] = """
    mov rax, {placeholder}
    mov r11, qword ptr [rbx]
    cmp r11, qword ptr [rax + {engine_vt}]
    jne miss
    mov r11, qword ptr [rbx + {unit_of_man}]
""" + FIND.replace("{who}", "r11") + """
    cmp qword ptr [rbx + {surface}], 0
    jz miss
    mulss xmm7, dword ptr [rax + {wall_radius}]
miss:
"""

# The hit shape keeps the full size (2026-11-09, static). exe+3165e14 builds the volume a shot's path is tested against
# from the body's +0xa0 (just halved above) and +0x9c; its shot mode multiplies the radius by the record's
# projectile_intersection_radius_ratio. Without this a docked gun was half as wide to every shot. The site follows
# the radius load; rax holds the caller's stack frame (the displaced movaps writes through it), so it is saved.
# hit_count counts the tests it widened, so a probe can see it run (shots have no other trace on a shielded crew).
B["hit_count"] = 0x74
CAVE_ORDER += ("hitsize",)
SITES["hitsize"] = 0x3165e43
SITE_BYTES["hitsize"] = bytes.fromhex("418bf80f2978a8")  # mov edi, r8d; movaps [rax-0x58], xmm7
ASM["hitsize"] = """
    push rax
    mov rax, {placeholder}
    mov r11, qword ptr [rcx]
    cmp r11, qword ptr [rax + {engine_vt}]
    jne miss
    mov r11, qword ptr [rcx + {unit_of_man}]
""" + FIND.replace("{who}", "r11") + """
    cmp qword ptr [rcx + {surface}], 0
    jz miss
    lock inc dword ptr [rax + {hit_count}]
    divss xmm6, dword ptr [rax + {wall_radius}]
miss:
    pop rax
"""

# A docked gun turns all the way round (the author, 2026-11-10: "as much as possible, 360 degrees"). An engine turning
# toward a target asks set-goal exe+308cfa0 for a heading, clamped there to +0xd9a +- half its battle_entities fire
# arc (record +0x70, 0.8727 rad = 50 degrees for a cannon), converted to a u16 half-arc in eax by exe+50d908. On a
# wall that window is all the reach a gun has (+-30 with the launcher's own, run 32). For a listed engine on a wall the
# half-arc becomes 0x7fff, the whole circle: 0x8000 itself is wrong, CA's clamp reads -0x8000 as +0x8000 and would
# pin every heading to the back. rsi is the engine body; rdx, r10, r11 and the flags are rewritten before they are read.
CAVE_ORDER += ("turn",)
SITES["turn"] = 0x308d0a8
SITE_BYTES["turn"] = bytes.fromhex("488d9424a0000000")  # lea rdx, [rsp+0xa0]
ASM["turn"] = """
    mov rdx, {placeholder}
    mov r11, qword ptr [rsi]
    cmp r11, qword ptr [rdx + {engine_vt}]
    jne miss
    mov r11, qword ptr [rsi + {unit_of_man}]
""" + FIND.replace("{who}", "r11").replace("[rax", "[rdx") + """
    cmp qword ptr [rsi + {surface}], 0
    jz miss
    mov eax, 0x7fff
miss:
"""

# A docked battery firing at will picks targets all round (2026-11-10, runs 36-39). A unit holding a wall does not use
# fire at will's regiment pick exe+30297f4: its wall controller (+0x3310, vtable exe+391d440) answers no at that
# pick's gate (slot +0x1d8), swallows the attack it would issue (slots +0x30 / +0x38 are a bare ret), and its +0x32dc
# firing list is empty, so caves there (cone, allround and faw, built and measured on 11-10) changed nothing. Its
# targets come from the wall state's refresh exe+3036384: per wall section a cone straight out from the section
# (exe+301e9f4: +- half the fire arc, record +0x70) and the enemies inside it (exe+2f64678); when every section comes
# back empty it zeroes its targets and destroys the attack (exe+30dc0ec), and nothing issues another. Measured: a
# target that jumped 45 degrees off the cannons and 60 off the Helstorms ended both attacks within a plan tick and the
# guns packed for good. For a listed unit (rbx+0x18) whose first man stands on a wall the cave runs CA's all-round
# gather exe+2f64860 instead, every enemy within range of the unit, into the same list (exe+4348fa8), with the
# arguments fire at will's ground pick passes it (exe+30298f6: unit in r8 and r9, range in xmm3, here xmm6; 0, -1, 1
# on the stack), then rejoins after CA's call (exe+3036691), where exe+30335f8 picks the best of that list. The block
# pointer rides on the stack across the call; the push and 0x38 keep the call 16-aligned. Every register CA reads
# after exe+3036691 is callee-saved or written first.
CAVE_ORDER += ("wallscan",)
SITES["wallscan"] = 0x3036668
SITE_BYTES["wallscan"] = bytes.fromhex("4c8d4db7488b4318")  # lea r9, [rbp-0x49]; mov rax, [rbx+0x18]
CALLS.update(scan_list=0x4348fa8, fn_gather=0x2f64860, scan_after=0x3036691)
B.update(scan_list=0x98, fn_gather=0xa0, scan_after=0xa8)
ASM["wallscan"] = """
    mov rax, {placeholder}
    mov r11, qword ptr [rbx + 0x18]
""" + FIND.replace("{who}", "r11") + """
    cmp dword ptr [r11 + {men_count}], 0
    jz miss
    mov r10, qword ptr [r11 + {men}]
    mov r10, qword ptr [r10]
    cmp qword ptr [r10 + {surface}], 0
    jz miss
    push rax
    sub rsp, 0x38
    mov byte ptr [rsp + 0x20], 0
    mov dword ptr [rsp + 0x28], 0xffffffff
    mov byte ptr [rsp + 0x30], 1
    mov rdx, qword ptr [rax + {scan_list}]
    mov r8, r11
    mov r9, r11
    movaps xmm3, xmm6
    call qword ptr [rax + {fn_gather}]
    add rsp, 0x38
    pop rax
    jmp qword ptr [rax + {scan_after}]
miss:
"""

# Both preview constructors subtract their front/rear counts from the model count.
# Counting crew here adds phantom positions after the eight primary engines.
for name, site, original, who, dest, continuation in (
    ("preview", 0x2e164b4, "8bbea4000000", "rsi", "edi", 0x2e164ba),
    ("preview_models", 0x2e16a78, "448b8fa4000000", "rdi", "r9d", 0x2e16a7f),
    ("preview_order", 0x2e16ac9, "8bb7a4000000", "rdi", "esi", 0x2e16acf),
):
    NATIVE_ORDER += (name,)
    CAVE_ORDER += (name,)
    SITES[name] = site
    SITE_BYTES[name] = bytes.fromhex(original)
    CALLS[name + "_cont"] = continuation
    ASM[name] = """
    push rax
    mov rax, {placeholder}
""" + FIND.replace("{who}", who) + """
    mov r11, qword ptr [rax + {CONT}]
    mov DEST, dword ptr [WHO + 0x184]
    pop rax
    jmp r11
miss:
    pop rax
""".replace("{CONT}", "{" + name + "_cont}").replace("DEST", dest).replace("WHO", who)

for name, continuation in (("wallgate","gate_cont"),("cursor","cursor_cont")):
    ASM[name] = """
    mov rax, {placeholder}
""" + FIND.replace("{who}","rcx") + """
    mov r11, qword ptr [rax + {CONT}]
    mov al, 1
    jmp r11
miss:
    push rbx
    sub rsp, 0x28
    mov rbx, rax
    call qword ptr [rbx + {fn_inf}]
    mov r11, qword ptr [rbx + {CONT}]
    add rsp, 0x28
    pop rbx
    jmp r11
""".replace("{CONT}","{"+continuation+"}")

ASM["primary"] = """
    mov rax, {placeholder}
    mov r11, qword ptr [rbx + 0x18]
""" + FIND.replace("{who}","r11") + """
    push rsi
    sub rsp, 0x28
    mov rsi, rax
    xor edi, edi
primary_loop:
    mov rax, qword ptr [rbx + 0x18]
    cmp edi, dword ptr [rax + 0x184]
    jae primary_done
    mov rdx, qword ptr [rax + 0x188]
    mov rdx, qword ptr [rdx + rdi*8]
    mov rcx, qword ptr [rbx + 0xf8]
    mov r8b, 1
    call qword ptr [rsi + {fn_add}]
    inc edi
    jmp primary_loop
primary_done:
    mov r11, qword ptr [rsi + {prepare_cont}]
    add rsp, 0x28
    pop rsi
    jmp r11
miss:
"""

ASM["solver"] = """
    mov rax, {placeholder}
    mov dword ptr [rsp + 0x24], 0
""" + FIND.replace("{who}","r8") + """
    mov dword ptr [rsp + 0x24], 1
    mov dword ptr [rsp + 0x38], 0x42100000
    mov dword ptr [rsp + 0x40], 0x42100000
miss:
"""

ASM["fronts"] = """
    mov rax, {placeholder}
""" + FIND.replace("{who}","rsi") + """
    mov r10, qword ptr [rax + {candidate_next}]
    push rax
    push rdx
    mov rdx, qword ptr [rbx]
    mov r11, qword ptr [rdx + 0x18]
    cmp dword ptr [r11 + 0x5c], 3
    jb reject_front
    mov eax, dword ptr [r11 + 0x30]
    cmp eax, 2
    jbe front_type
    sub eax, 0x12
    cmp eax, 3
    ja reject_front
front_type:
    mov rax, rdx
    sub rax, qword ptr [r11 + 0x60]
    xor edx, edx
    mov r11d, 0x108
    div r11
    test edx, edx
    jne reject_front
    pop rdx
    pop rax
    jmp miss
reject_front:
    pop rdx
    pop rax
    jmp r10
miss:
"""

ASM["rear"] = """
    push rax
    mov rax, {placeholder}
    cmp byte ptr [rbp + 0x63], 1
    jne miss
    mov r11, qword ptr [rax + {rear_next}]
    pop rax
    jmp r11
miss:
    pop rax
"""


def fields():
    f = {"placeholder": "0x%x" % PLACEHOLDER}
    f.update({k: "0x%x" % v for k, v in B.items()})
    f.update({k: "0x%x" % v for k, v in U.items()})
    return f


def assemble(src):
    import keystone
    ks = keystone.Ks(keystone.KS_ARCH_X86, keystone.KS_MODE_64)
    code, _ = ks.asm(src.format(**fields()), 0)
    code = bytes(code)
    assert code.count(struct.pack("<Q", PLACEHOLDER)) == 1, "the placeholder appears twice"
    return code


def wall_guns(drawn=False):
    """the wall guns; drawn=True: the candidates refused because an animal draws them"""
    sys.path.insert(0, HERE)
    from read_vanilla_db import load, DB_PACK
    lu = load(DB_PACK, "land_units_tables")[0][2]
    en = {r["key"]: r for r in load(DB_PACK, "battlefield_engines_tables")[0][2]}
    be = {r["key"]: r for r in load(DB_PACK, "battle_entities_tables")[0][2]}
    mn = {r["key"]: r for r in load(DB_PACK, "mounts_tables")[0][2]}
    out = []
    for r in lu:
        if r["class"] == "com" or r["category"] not in ("artillery", "war_machine"):
            continue
        e = en.get(r["engine"]) if r["engine"] else None
        if r["category"] == "war_machine":
            if not e:
                continue
            body_is_artillery = be[e["battle_entity"]]["type"] == "artillery"
            if not (e["missile_weapon"] or (body_is_artillery and r["primary_missile_weapon"])):
                continue
        # a draught animal: a mount with a model. The Chaos Dwarf vehicles' mounts are hidden (dummy_variant) and carry
        # the vehicle; the engine's draught attachment alone is not an animal either (the Deathshrieker names one)
        animal = bool(r["mount"]) and mn[r["mount"]]["variant"] != "dummy_variant"
        if animal == drawn:
            out.append(r["key"])
    return sorted(out)


def most_crew():
    """(crew, unit) for the wall gun with the most men on one engine, at the largest unit size main_units states"""
    sys.path.insert(0, HERE)
    from read_vanilla_db import load, DB_PACK
    lu = {r["key"]: r for r in load(DB_PACK, "land_units_tables")[0][2]}
    mu = {r["land_unit"]: r for r in load(DB_PACK, "main_units_tables")[0][2]}
    return max((-(-mu[g]["num_men"] // max(1, lu[g]["num_engines"])), g) for g in wall_guns() if g in mu)


def hl(rva):
    return "{0x%x, 0x%04x}" % (rva >> 16, rva & 0xffff)


def lua_block(caves, guns, drawn):
    lines = [BEGIN,
             'local BUILD = "%s"' % BUILD,
             "local SITES = {%s}" % ", ".join("%s = %s" % (k, hl(SITES[k])) for k in CAVE_ORDER),
             "local CAVE_ORDER = {%s}" % ", ".join('"%s"' % k for k in CAVE_ORDER),
             "local SITE_BYTES = {%s} -- what each cave's jump displaces" % ", ".join(
                 "%s = {%s}" % (k, ", ".join("0x%02x" % b for b in SITE_BYTES[k])) for k in CAVE_ORDER),
             "local CALLS = {%s}" % ", ".join("%s = %s" % (k, hl(v)) for k, v in CALLS.items()),
             "local B = {%s}" % ", ".join("%s = 0x%x" % (k, v) if k != "max" else "%s = %d" % (k, v) for k, v in B.items()),
             "local BLOCK_AT = %d -- the block's address: the first instruction's imm64" % BLOCK_AT,
             "local CAVE_BLOCK_AT = {%s}" % ", ".join("%s = %d" % (k,caves[k].index(struct.pack('<Q',PLACEHOLDER))) for k in CAVE_ORDER),
             "local U = {%s} -- game object offsets" % ", ".join("%s = 0x%x" % (k, U[k]) for k in sorted(U)),
             "local CAVES = {"]
    for k in CAVE_ORDER:
        b = caves[k]
        rows = [", ".join("0x%02x" % x for x in b[i:i + 24]) for i in range(0, len(b), 24)]
        lines.append("\t%s = {%s}," % (k, (",\n\t\t").join(rows)))
    lines.append("}")
    lines.append("-- %d vanilla units: every artillery unit and the war machines whose engine is the gun" % len(guns))
    lines.append("local WALL_GUNS = {")
    for g in guns:
        lines.append('\t["%s"] = true,' % g)
    lines.append("}")
    lines.append("-- %d vanilla guns drawn by an animal: never on a wall, unit:is_artillery() or not" % len(drawn))
    lines.append("local DRAWN = {")
    for g in drawn:
        lines.append('\t["%s"] = true,' % g)
    lines.append("}")
    lines.append(END)
    return "\n".join(lines)


def bai_texts():
    import zstandard
    sys.path.insert(0, HERE)
    from read_pack_index import read
    out = {}
    for path, comp, b in read(DATA_PACK, "battle_ai/bai_values_"):
        if comp:
            b = zstandard.ZstdDecompressor().decompress(b[4:], max_output_size=struct.unpack_from("<I", b, 0)[0])
        text = b.decode("ascii")
        new, n = re.subn(r"(OCCUPY_WALL\r\n(?:\t[^\r\n]*\r\n)*?\tAIUF_ARTILLERY=)-1\.0", r"\g<1>0.6500", text)
        assert n == 1, "%s: OCCUPY_WALL's AIUF_ARTILLERY is not -1.0 (%d matches)" % (path, n)
        out[os.path.basename(path)] = new.encode("ascii")
    assert sorted(out) == sorted(os.path.basename(p) for p in BAI), sorted(out)
    return out


def exe_problems():
    sys.path.insert(0, HERE)
    import exe_re as e
    d = e.pe()
    peo = struct.unpack_from("<I", d, 0x3C)[0]
    stamp = "%08x" % struct.unpack_from("<I", d, peo + 8)[0]
    out = [] if stamp == BUILD else ["exe build %s, the caves are for %s" % (stamp, BUILD)]
    for k in CAVE_ORDER:
        o = e.off(SITES[k])
        if d[o:o + len(SITE_BYTES[k])] != SITE_BYTES[k]:
            out.append("%s: exe+%x opens with %s" % (k, SITES[k], d[o:o + 8].hex()))
    for k, rva in CALLS.items():
        if not k.startswith("fn_"):
            continue
        if e.pdata(rva) is None or e.pdata(rva)[0] != rva:
            out.append("%s: exe+%x is not a function start" % (k, rva))
    slot, tick = MOVE_FSM_TICK
    if struct.unpack_from("<Q", d, e.off(slot))[0] != e.BASE + tick:
        out.append("move_vt: exe+%x's +0x10 slot is not the state-machine tick exe+%x" % (CALLS["move_vt"], tick))
    if struct.unpack_from("<Q", d, e.off(CALLS["engine_vt"]))[0] != e.BASE + ENGINE_VT_FIRST:
        out.append("engine_vt: exe+%x's first slot is not exe+%x" % (CALLS["engine_vt"], ENGINE_VT_FIRST))
    return out


def generated():
    caves = {k: assemble(ASM[k]) for k in CAVE_ORDER}
    return caves, lua_block(caves, wall_guns(), wall_guns(drawn=True))


def write():
    _, block = generated()
    text = open(LUA, encoding="utf-8").read()
    a, b = text.index(BEGIN), text.index(END) + len(END)
    open(LUA, "w", encoding="utf-8", newline="\n").write(text[:a] + block + text[b:])
    for p, data in zip(BAI, [bai_texts()[os.path.basename(p)] for p in BAI]):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(data)
    print("wrote", os.path.normpath(LUA), "and", len(BAI), "bai_values files")


def check():
    problems = exe_problems()
    _, block = generated()
    text = open(LUA, encoding="utf-8").read()
    if block not in text:
        problems.append("the shipped Lua's generated block is stale: run gen_artillery_walls.py")
    for p, data in bai_texts().items():
        f = [x for x in BAI if os.path.basename(x) == p][0]
        if not os.path.exists(f) or open(f, "rb").read() != data:
            problems.append("%s differs from CA's file with the one weight raised" % p)
    crew, gun = most_crew()
    slot_max = int(re.search(r"local SLOT_MAX = (\d+)", text).group(1))
    if crew > slot_max:
        problems.append("%s has %d crew on one engine, over the Lua's SLOT_MAX %d: its crew go unhandled" % (gun, crew, slot_max))
    for x in problems:
        print("PROBLEM:", x)
    print("check: %s" % ("ok" if not problems else "%d problems" % len(problems)))
    return not problems


# --- selftest: the shipped bytes under unicorn --------------------------------------------------------------------
CODE, STACK, BLOCK, MEM = 0x10000, 0x200000, 0x300000, 0x400000
UNIT_IN, UNIT_OUT, MAN = MEM + 0x1000, MEM + 0x9000, MEM + 0x11000
BEH, OWNER, MENS, MAN0 = MEM + 0x19000, MEM + 0x1a000, MEM + 0x1b000, MEM + 0x1c000  # the battery caves' chain
ARC = MEM + 0x30000  # the arc cave's record: heading 180, half-arc 25 degrees, two ranges
ARC_RECORD = struct.pack("<HHff", 0x8000, 0x11c7, 100.0, 400.0)
ACT, ACTP = MEM + 0x31000, MEM + 0x32000  # the inplace cave's action: +0x10 -> ACTP, whose +8 is the body MAN0
ACT_FLAGS = 0x0f  # the action's +0xd8 before the cave: bit 8 set
FN_CLIMB, FN_A, FN_B = 0x500000, 0x501000, 0x502000  # stand-ins: the code hook answers them
RET = 0x600000
MOVE_VT, OTHER_VT = 0x7000000, 0x7001000  # the behaviour's vtable word: the move behaviour's, or any other


def shipped_caves():
    text = open(LUA, encoding="utf-8").read()
    body = text[text.index("local CAVES = {"):text.index("-- ", text.index("local CAVES = {"))]
    out = {}
    for k in CAVE_ORDER:
        m = re.search(r"\b%s = \{([^}]*)\}" % k, body)
        out[k] = bytes(int(x, 16) for x in re.findall(r"0x[0-9a-f]{2}", m.group(1)))
    return out


def run(code, rcx, units, gate=0, links_gate=0, fn_a=1, fn_b=0, unit_of_man=UNIT_IN, beh_unit=UNIT_IN, men=1, surface=1,
        rdx=0xDD, beh_vt=OTHER_VT):
    """Run one cave from its first byte. Returns how it left: ('ret', eax) for a return to the caller, ('miss',) for a
    fall-through into the displaced bytes, ('jmp', target, rcx) for the tail jump, plus a record of every call. With
    rcx at ARC, the record there after the run is appended."""
    import unicorn
    from unicorn import x86_const as R
    uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
    for a, n in ((CODE, 0x10000), (STACK, 0x20000), (BLOCK, 0x10000), (MEM, 0x100000), (FN_CLIMB, 0x10000), (RET, 0x10000)):
        uc.mem_map(a, n)
    code = code.replace(struct.pack("<Q", PLACEHOLDER), struct.pack("<Q", BLOCK))
    end = CODE + len(code)  # where the displaced bytes would run: a miss
    uc.mem_write(CODE, code + b"\x90" * 16)
    q = lambda a, v: uc.mem_write(a, struct.pack("<Q", v))
    d = lambda a, v: uc.mem_write(a, struct.pack("<I", v))
    q(BLOCK + B["fn_climb"], FN_CLIMB)
    q(BLOCK + B["fn_a"], FN_A)
    q(BLOCK + B["fn_b"], FN_B)
    d(BLOCK + B["count"], len(units))
    for i, u in enumerate(units):
        q(BLOCK + B["units"] + 8 * i, u)
    for u in (UNIT_IN, UNIT_OUT):
        d(u + U["climb_gate"], gate)
        d(u + U["links_gate"], links_gate)
    q(MAN + U["unit_of_man"], unit_of_man)
    q(MAN0 + U["unit_of_man"], unit_of_man)  # MAN0 doubles as an engine body: its unit at +0x2e8, its surface at +0x920
    q(BEH, beh_vt)
    q(BLOCK + B["move_vt"], MOVE_VT)
    q(BEH + U["beh_owner"], OWNER)
    q(OWNER + U["owner_unit"], beh_unit)
    for u in (UNIT_IN, UNIT_OUT):
        d(u + U["men_count"], men)
        q(u + U["men"], MENS)
    q(MENS, MAN0)
    q(MAN0 + U["surface"], surface)
    uc.mem_write(ARC, ARC_RECORD)
    q(ACT + 0x10, ACTP)
    q(ACTP + 8, MAN0)
    uc.mem_write(ACT + 0xd8, bytes([ACT_FLAGS]))
    for a in (FN_A, FN_B, FN_CLIMB, RET):
        uc.mem_write(a, b"\x90" * 16)
    sp = STACK + 0x10000 - 8  # 8 past a 16-byte boundary, as at any function entry
    q(sp, RET)
    keep = {R.UC_X86_REG_RBX: 0xB0B0, R.UC_X86_REG_RSI: 0x5151, R.UC_X86_REG_RDI: 0xD1D1, R.UC_X86_REG_RBP: 0xBEBE,
            R.UC_X86_REG_R12: 0x1212, R.UC_X86_REG_RDX: rdx, R.UC_X86_REG_R8: 0x88, R.UC_X86_REG_R9: 0x99}
    for r, v in keep.items():
        uc.reg_write(r, v)
    uc.reg_write(R.UC_X86_REG_RSP, sp)
    uc.reg_write(R.UC_X86_REG_RCX, rcx)
    calls, answers, state = [], {FN_A: fn_a, FN_B: fn_b}, {}

    def on_code(u, addr, size, _):
        if addr in answers:  # a call into a stand-in: record rcx and the alignment its caller left, answer, return
            rsp = u.reg_read(R.UC_X86_REG_RSP)
            calls.append((addr, u.reg_read(R.UC_X86_REG_RCX), (rsp + 8) % 16))
            u.reg_write(R.UC_X86_REG_RAX, answers[addr])
            u.reg_write(R.UC_X86_REG_RSP, rsp + 8)
            u.reg_write(R.UC_X86_REG_RIP, struct.unpack("<Q", u.mem_read(rsp, 8))[0])
        elif addr in (RET, end, FN_CLIMB):
            state["at"] = addr
            u.emu_stop()
    uc.hook_add(unicorn.UC_HOOK_CODE, on_code)
    try:
        uc.emu_start(CODE, 0, count=2000)
    except unicorn.UcError as e:
        return ("fault", str(e), None, None, calls)
    at, rsp = state.get("at"), uc.reg_read(R.UC_X86_REG_RSP)
    kept = all(uc.reg_read(r) == v for r, v in keep.items())
    if at == RET:
        return ("ret", uc.reg_read(R.UC_X86_REG_RAX) & 0xffffffff, rsp == sp + 8, kept, calls)
    if at == end:
        r = ("miss", None, rsp == sp and uc.reg_read(R.UC_X86_REG_RCX) == rcx, kept, calls)
        if rcx == ARC:
            return r + (bytes(uc.mem_read(ARC, len(ARC_RECORD))),)
        if rcx == ACT:
            return r + (uc.mem_read(ACT + 0xd8, 1)[0],)
        return r
    if at == FN_CLIMB:
        return ("jmp", uc.reg_read(R.UC_X86_REG_RCX), rsp == sp, kept, calls)
    return ("lost", hex(uc.reg_read(R.UC_X86_REG_RIP)), None, kept, calls)


ENGINE_VT, MAN_VT = 0x7002000, 0x7003000


def run_radius(code, units, vt=ENGINE_VT, surface=1, unit=UNIT_IN, hit=False):
    """The radius cave from its first byte with rbx the body and xmm7 = 2.6, xmm8 = 2.0 (radius, height). Returns
    (reached the displaced store, xmm7, xmm8, every register it may not touch kept). hit: the hitsize cave instead,
    rcx the body, xmm6 = 1.3 (the halved radius it reads) and rax a stack frame it must keep; xmm6 comes back as the
    second value and the block's hit_count as a fifth."""
    import unicorn
    from unicorn import x86_const as R
    uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
    for a, n in ((CODE, 0x10000), (STACK, 0x20000), (BLOCK, 0x10000), (MEM, 0x100000)):
        uc.mem_map(a, n)
    code = code.replace(struct.pack("<Q", PLACEHOLDER), struct.pack("<Q", BLOCK))
    end = CODE + len(code)
    uc.mem_write(CODE, code + b"\x90" * 16)
    uc.mem_write(BLOCK + B["engine_vt"], struct.pack("<Q", ENGINE_VT))
    uc.mem_write(BLOCK + B["wall_radius"], struct.pack("<f", 0.5))
    uc.mem_write(BLOCK + B["count"], struct.pack("<I", len(units)))
    for i, u in enumerate(units):
        uc.mem_write(BLOCK + B["units"] + 8 * i, struct.pack("<Q", u))
    uc.mem_write(MAN0, struct.pack("<Q", vt))
    uc.mem_write(MAN0 + U["unit_of_man"], struct.pack("<Q", unit))
    uc.mem_write(MAN0 + U["surface"], struct.pack("<Q", surface))
    f = lambda v: struct.unpack("<I", struct.pack("<f", v))[0]
    keep = {R.UC_X86_REG_RBX: 0xB0B0 if hit else MAN0, R.UC_X86_REG_RCX: MAN0 if hit else 0xC1C1,
            R.UC_X86_REG_RDX: 0xD0D0, R.UC_X86_REG_RSI: 0x5151,
            R.UC_X86_REG_RDI: 0xD1D1, R.UC_X86_REG_RBP: 0xBEBE, R.UC_X86_REG_R8: 0x88, R.UC_X86_REG_R9: 0x99,
            R.UC_X86_REG_R12: 0x1212, R.UC_X86_REG_R13: 0x1313, R.UC_X86_REG_R14: 0x1414, R.UC_X86_REG_R15: 0x1515,
            R.UC_X86_REG_RSP: STACK + 0x8000, R.UC_X86_REG_XMM8: f(2.0)}
    if hit:
        keep[R.UC_X86_REG_RAX] = STACK + 0x9000
        keep[R.UC_X86_REG_XMM7] = f(2.6)
    for r, v in keep.items():
        uc.reg_write(r, v)
    uc.reg_write(R.UC_X86_REG_XMM6 if hit else R.UC_X86_REG_XMM7, f(1.3 if hit else 2.6))
    state = {}

    def on_code(u, addr, size, _):
        if addr == end:
            state["end"] = True
            u.emu_stop()
    uc.hook_add(unicorn.UC_HOOK_CODE, on_code)
    try:
        uc.emu_start(CODE, 0, count=200)
    except unicorn.UcError:
        return (False, None, None, False) + ((None,) if hit else ())
    x = lambda r: struct.unpack("<f", struct.pack("<I", uc.reg_read(r) & 0xffffffff))[0]
    kept = all(uc.reg_read(r) == v for r, v in keep.items())
    out = (state.get("end", False), round(x(R.UC_X86_REG_XMM6 if hit else R.UC_X86_REG_XMM7), 4),
           round(x(R.UC_X86_REG_XMM8), 4), kept)
    return out + struct.unpack("<I", uc.mem_read(BLOCK + B["hit_count"], 4)) if hit else out


def run_turn(code, units, vt=ENGINE_VT, surface=1, unit=UNIT_IN):
    """The turn cave from its first byte with rsi the body and eax CA's half-arc (25 degrees). Returns (reached the
    displaced lea, eax, every register it may not touch kept)."""
    import unicorn
    from unicorn import x86_const as R
    uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
    for a, n in ((CODE, 0x10000), (STACK, 0x20000), (BLOCK, 0x10000), (MEM, 0x100000)):
        uc.mem_map(a, n)
    code = code.replace(struct.pack("<Q", PLACEHOLDER), struct.pack("<Q", BLOCK))
    end = CODE + len(code)
    uc.mem_write(CODE, code + b"\x90" * 16)
    uc.mem_write(BLOCK + B["engine_vt"], struct.pack("<Q", ENGINE_VT))
    uc.mem_write(BLOCK + B["count"], struct.pack("<I", len(units)))
    for i, u in enumerate(units):
        uc.mem_write(BLOCK + B["units"] + 8 * i, struct.pack("<Q", u))
    uc.mem_write(MAN0, struct.pack("<Q", vt))
    uc.mem_write(MAN0 + U["unit_of_man"], struct.pack("<Q", unit))
    uc.mem_write(MAN0 + U["surface"], struct.pack("<Q", surface))
    keep = {R.UC_X86_REG_RBX: 0xB0B0, R.UC_X86_REG_RCX: 0xC1C1, R.UC_X86_REG_RSI: MAN0, R.UC_X86_REG_RDI: 0xD1D1,
            R.UC_X86_REG_RBP: 0xBEBE, R.UC_X86_REG_R8: 0x88, R.UC_X86_REG_R9: 0x99, R.UC_X86_REG_R12: 0x1212,
            R.UC_X86_REG_R13: 0x1313, R.UC_X86_REG_R14: 0x1414, R.UC_X86_REG_R15: 0x1515,
            R.UC_X86_REG_RSP: STACK + 0x8000, R.UC_X86_REG_XMM6: 0x40266666}
    for r, v in keep.items():
        uc.reg_write(r, v)
    uc.reg_write(R.UC_X86_REG_RAX, 0xFFFF00001C71)
    state = {}

    def on_code(u, addr, size, _):
        if addr == end:
            state["end"] = True
            u.emu_stop()
    uc.hook_add(unicorn.UC_HOOK_CODE, on_code)
    try:
        uc.emu_start(CODE, 0, count=200)
    except unicorn.UcError:
        return (False, None, False)
    return (state.get("end", False), uc.reg_read(R.UC_X86_REG_RAX), all(uc.reg_read(r) == v for r, v in keep.items()))


FN_PICK = 0x503000  # stand-in for CA's all-round gather; FN_PICK + 0x100 stands for CA's code after it
LIST, OWNER = MEM + 0x50000, MEM + 0x60000


def run_scan(code, units, surface=1, unit=UNIT_IN, men=1):
    """The wallscan cave with rbx the wall state, whose +0x18 is the unit. Returns (where it left: 'after' for CA's
    code past its gather, 'miss', or None on a fault; the gather's view at entry - rsp mod 16, rdx, r8, r9, xmm3, its
    three stack arguments - or None when it was not called; every register it may not touch kept, rsp included)."""
    import unicorn
    from unicorn import x86_const as R
    uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
    for a, n in ((CODE, 0x10000), (STACK, 0x20000), (BLOCK, 0x10000), (MEM, 0x100000), (FN_PICK, 0x1000)):
        uc.mem_map(a, n)
    code = code.replace(struct.pack("<Q", PLACEHOLDER), struct.pack("<Q", BLOCK))
    end, after = CODE + len(code), FN_PICK + 0x100
    uc.mem_write(CODE, code + b"\x90" * 16)
    uc.mem_write(FN_PICK, b"\xc3")
    uc.mem_write(STACK + 0x7000, b"\xaa" * 0x2000)  # an argument the cave forgets to write reads 0xaa, not 0
    for k, v in (("scan_list", LIST), ("fn_gather", FN_PICK), ("scan_after", after)):
        uc.mem_write(BLOCK + B[k], struct.pack("<Q", v))
    uc.mem_write(BLOCK + B["count"], struct.pack("<I", len(units)))
    for i, u in enumerate(units):
        uc.mem_write(BLOCK + B["units"] + 8 * i, struct.pack("<Q", u))
    uc.mem_write(OWNER + 0x18, struct.pack("<Q", unit))
    for u in (UNIT_IN, UNIT_OUT):
        uc.mem_write(u + U["men_count"], struct.pack("<I", men))
        uc.mem_write(u + U["men"], struct.pack("<Q", MENS))
    uc.mem_write(MENS, struct.pack("<Q", MAN0))
    uc.mem_write(MAN0 + U["surface"], struct.pack("<Q", surface))
    keep = {R.UC_X86_REG_RBX: OWNER, R.UC_X86_REG_RCX: 0xC1C1, R.UC_X86_REG_RSI: 0x5151, R.UC_X86_REG_RDI: 0xD1D1,
            R.UC_X86_REG_RBP: 0xBEBE, R.UC_X86_REG_R12: 0x1212, R.UC_X86_REG_R13: 0x1313, R.UC_X86_REG_R14: 0x1414,
            R.UC_X86_REG_R15: 0x1515, R.UC_X86_REG_RSP: STACK + 0x8000, R.UC_X86_REG_XMM6: 0x43960000}
    for r, v in keep.items():
        uc.reg_write(r, v)
    uc.reg_write(R.UC_X86_REG_XMM3, 0x3F800000)
    state = {}

    def on_code(u, addr, size, _):
        if addr == FN_PICK:
            sp = u.reg_read(R.UC_X86_REG_RSP)
            m = bytes(u.mem_read(sp + 0x28, 0x18))
            state["call"] = (sp % 16, u.reg_read(R.UC_X86_REG_RDX), u.reg_read(R.UC_X86_REG_R8),
                             u.reg_read(R.UC_X86_REG_R9), u.reg_read(R.UC_X86_REG_XMM3) & 0xFFFFFFFF, m[0],
                             struct.unpack_from("<I", m, 8)[0], m[0x10])
        elif addr in (end, after):
            state["at"] = "miss" if addr == end else "after"
            u.emu_stop()
    uc.hook_add(unicorn.UC_HOOK_CODE, on_code)
    try:
        uc.emu_start(CODE, 0, count=300)
    except unicorn.UcError:
        return (None, None, False)
    return (state.get("at"), state.get("call"), all(uc.reg_read(r) == v for r, v in keep.items()))


def scenarios(caves):
    bad = []

    def expect(cond, what):
        if not cond:
            bad.append(what)
    c, li, m = caves["climb"], caves["links"], caves["man"]
    for name, code in (("climb", c), ("links", li)):
        r = run(code, UNIT_OUT, [UNIT_IN])
        expect(r[0] == "miss" and r[2] and r[3] and not r[4], "%s: a unit not listed falls through untouched" % name)
        r = run(code, UNIT_OUT, [])
        expect(r[0] == "miss" and r[2] and r[3], "%s: an empty table falls through" % name)
        r = run(code, UNIT_IN, [UNIT_OUT, MEM + 0x5000, UNIT_IN])
        expect(r[0] == "ret", "%s: the last of three entries is found" % name)
        r = run(code, UNIT_IN, [UNIT_IN, UNIT_OUT, MEM + 0x5000])
        expect(r[0] == "ret", "%s: the first of three entries is found" % name)
    r = run(c, UNIT_IN, [UNIT_IN])
    expect(r == ("ret", 1, True, True, []), "climb: a listed unit with +0x1a4 == 0 may climb")
    r = run(c, UNIT_IN, [UNIT_IN], gate=3)
    expect(r[:2] == ("ret", 0), "climb: +0x1a4 set still refuses, as CA's check does")
    r = run(li, UNIT_IN, [UNIT_IN])
    expect(r[:4] == ("ret", 1, True, True), "links: a listed unit passing CA's three tests may")
    expect([x[0] for x in r[4]] == [FN_A, FN_B], "links: calls 301d214 then 301d098")
    expect(all(x[1] == UNIT_IN for x in r[4]), "links: both calls get the unit in rcx")
    expect(all(x[2] == 0 for x in r[4]), "links: rsp is 16-aligned at both calls")
    r = run(li, UNIT_IN, [UNIT_IN], fn_a=0)
    expect(r[:2] == ("ret", 0) and len(r[4]) == 1, "links: 301d214 false refuses without calling 301d098")
    r = run(li, UNIT_IN, [UNIT_IN], links_gate=1)
    expect(r[:2] == ("ret", 0) and len(r[4]) == 1, "links: +0x154 set refuses")
    r = run(li, UNIT_IN, [UNIT_IN], fn_b=1)
    expect(r[:2] == ("ret", 0) and len(r[4]) == 2, "links: 301d098 true refuses")
    r = run(m, MAN, [UNIT_IN])
    expect(r[0] == "jmp" and r[1] == UNIT_IN and r[2] and r[3], "man: a listed unit's man tail-jumps to climb(unit)")
    r = run(m, MAN, [UNIT_IN], links_gate=1)
    expect(r[:2] == ("ret", 1), "man: +0x154 set returns 1, as CA's tail does")
    r = run(m, MAN, [UNIT_OUT])
    expect(r[0] == "miss" and r[2] and r[3], "man: a man of an unlisted unit falls through untouched")
    r = run(m, MAN, [UNIT_IN], unit_of_man=0)
    expect(r[0] == "miss" and r[2], "man: a man with no unit falls through")
    for name in ("hold", "noarc"):
        code = caves[name]
        r = run(code, BEH, [UNIT_OUT, UNIT_IN])
        expect(r[0] == "ret" and r[2] and r[3] and not r[4], "%s: a listed unit on a wall returns to the caller" % name)
        r = run(code, BEH, [UNIT_IN], surface=0)
        expect(r[0] == "miss" and r[2] and r[3], "%s: a listed unit on the ground runs CA's code" % name)
        r = run(code, BEH, [UNIT_OUT])
        expect(r[0] == "miss" and r[2] and r[3], "%s: an unlisted unit runs CA's code" % name)
        r = run(code, BEH, [UNIT_IN], men=0)
        expect(r[0] == "miss" and r[2], "%s: a unit with no men runs CA's code" % name)
    r = run(caves["hold"], BEH, [UNIT_IN], beh_vt=MOVE_VT)
    expect(r[0] == "miss" and r[2] and r[3], "hold: a plain move on a wall runs CA's code (the march starts)")
    r = run(caves["noarc"], BEH, [UNIT_IN], beh_vt=MOVE_VT)
    expect(r[:2] == ("ret", 0), "noarc: keeps answering for any behaviour")
    r = run(caves["noarc"], BEH, [UNIT_IN])
    expect(r[:2] == ("ret", 0), "noarc: answers false, the target is never off the arc")
    cs = caves["clearshot"]
    r = run(cs, MAN0, [UNIT_OUT, UNIT_IN])
    expect(r[:2] == ("ret", 1) and r[2] and r[3] and not r[4], "clearshot: a listed engine on a wall answers clear")
    r = run(cs, MAN0, [UNIT_IN], surface=0)
    expect(r[0] == "miss" and r[2] and r[3], "clearshot: a listed engine on the ground runs CA's test")
    r = run(cs, MAN0, [UNIT_OUT])
    expect(r[0] == "miss" and r[2] and r[3], "clearshot: an unlisted engine runs CA's test")
    a = caves["arc"]
    full = ARC_RECORD[:2] + struct.pack("<H", 0x8000) + ARC_RECORD[4:]
    r = run(a, ARC, [UNIT_OUT, UNIT_IN], rdx=MAN0)
    expect(r[0] == "miss" and r[2] and r[3] and not r[4], "arc: a listed engine on a wall runs CA's test after")
    expect(r[-1] == full, "arc: a listed engine on a wall gets the full circle, heading and ranges untouched")
    r = run(a, ARC, [UNIT_IN], rdx=MAN0, surface=0)
    expect(r[0] == "miss" and r[2] and r[3] and r[-1] == ARC_RECORD, "arc: a listed engine on the ground keeps CA's arc")
    r = run(a, ARC, [UNIT_OUT], rdx=MAN0)
    expect(r[0] == "miss" and r[2] and r[3] and r[-1] == ARC_RECORD, "arc: an unlisted engine keeps CA's arc")
    ip = caves["inplace"]
    r = run(ip, ACT, [UNIT_OUT, UNIT_IN], rdx=0xDD)
    expect(r[0] == "miss" and r[2] and r[3] and not r[4], "inplace: a listed engine on a wall runs CA's dispatch after")
    expect(r[-1] == ACT_FLAGS & 0xf7, "inplace: a listed engine on a wall loses the move-first bit only")
    r = run(ip, ACT, [UNIT_IN], surface=0)
    expect(r[0] == "miss" and r[2] and r[3] and r[-1] == ACT_FLAGS, "inplace: a listed engine on the ground keeps the bit")
    r = run(ip, ACT, [UNIT_OUT])
    expect(r[0] == "miss" and r[2] and r[3] and r[-1] == ACT_FLAGS, "inplace: an unlisted engine keeps the bit")
    rd = caves["radius"]
    expect(run_radius(rd, [UNIT_OUT, UNIT_IN]) == (True, 1.3, 2.0, True),
           "radius: a listed engine on a wall stores half its radius, its height untouched")
    expect(run_radius(rd, [UNIT_IN], surface=0) == (True, 2.6, 2.0, True), "radius: a listed engine on the ground keeps it")
    expect(run_radius(rd, [UNIT_OUT]) == (True, 2.6, 2.0, True), "radius: an unlisted engine keeps it")
    expect(run_radius(rd, []) == (True, 2.6, 2.0, True), "radius: an empty table keeps it")
    expect(run_radius(rd, [UNIT_IN], vt=MAN_VT) == (True, 2.6, 2.0, True), "radius: a listed unit's crewman keeps his")
    hs = caves["hitsize"]
    expect(run_radius(hs, [UNIT_OUT, UNIT_IN], hit=True) == (True, 2.6, 2.0, True, 1),
           "hitsize: a listed engine on a wall is full size to a shot, rax kept, counted once")
    expect(run_radius(hs, [UNIT_IN], surface=0, hit=True) == (True, 1.3, 2.0, True, 0), "hitsize: on the ground, untouched")
    expect(run_radius(hs, [UNIT_OUT], hit=True) == (True, 1.3, 2.0, True, 0), "hitsize: an unlisted engine untouched")
    expect(run_radius(hs, [], hit=True) == (True, 1.3, 2.0, True, 0), "hitsize: an empty table untouched")
    expect(run_radius(hs, [UNIT_IN], vt=MAN_VT, hit=True) == (True, 1.3, 2.0, True, 0), "hitsize: a crewman untouched")
    ws, gone = caves["wallscan"], ("miss", None, True)
    expect(run_scan(ws, [UNIT_OUT, UNIT_IN]) == ("after", (8, LIST, UNIT_IN, UNIT_IN, 0x43960000, 0, 0xFFFFFFFF, 1), True),
           "wallscan: a listed unit on a wall gathers all round, aligned, and rejoins CA past its gather")
    expect(run_scan(ws, [UNIT_IN], surface=0) == gone, "wallscan: on the ground, CA's cone")
    expect(run_scan(ws, [UNIT_OUT]) == gone, "wallscan: an unlisted unit keeps the cone")
    expect(run_scan(ws, []) == gone, "wallscan: an empty table keeps the cone")
    expect(run_scan(ws, [UNIT_IN], men=0) == gone, "wallscan: a unit with no men keeps the cone, no read")
    tn = caves["turn"]
    # a 32-bit write zeroes rax's top half: what CA reads next is r8d = eax
    expect(run_turn(tn, [UNIT_OUT, UNIT_IN]) == (True, 0x7fff, True), "turn: a listed engine on a wall turns all round")
    expect(run_turn(tn, [UNIT_IN], surface=0) == (True, 0xFFFF00001C71, True), "turn: on the ground, CA's window")
    expect(run_turn(tn, [UNIT_OUT]) == (True, 0xFFFF00001C71, True), "turn: an unlisted engine keeps CA's window")
    expect(run_turn(tn, []) == (True, 0xFFFF00001C71, True), "turn: an empty table keeps CA's window")
    expect(run_turn(tn, [UNIT_IN], vt=MAN_VT) == (True, 0xFFFF00001C71, True), "turn: another body class keeps it")
    return bad


BREAKS = [
    ("climb", "    sete al\n", "    setne al\n", "climb's gate inverted"),
    ("climb", "    jne find\n", "    je find\n", "the search compares the wrong way"),
    ("links", "    jz no\n", "    jnz no\n", "301d214's answer inverted"),
    ("links", "    jnz no\n", "    jz no\n", "301d098's answer inverted"),
    ("links", "    sub rsp, 0x28\n", "    sub rsp, 0x20\n", "the calls misaligned"),
    ("links", "    pop rsi\n    pop rbx\n", "    pop rbx\n    pop rsi\n", "rbx and rsi swapped"),
    ("man", "    mov rcx, r11\n", "", "the tail jump without the unit in rcx"),
    ("man", "    cmp dword ptr [r11 + {links_gate}], 0\n", "    cmp dword ptr [rcx + {links_gate}], 0\n",
     "the man's field read for his unit's"),
    ("hold", "    cmp qword ptr [r11 + {surface}], 0\n    jz miss\n", "    cmp qword ptr [r11 + {surface}], 0\n    jnz miss\n",
     "hold: the wall test inverted"),
    ("hold", "    mov r11, qword ptr [r11 + {owner_unit}]\n", "", "hold: the owner searched for, not the unit"),
    ("hold", "    cmp dword ptr [r11 + {men_count}], 0\n    jz miss\n", "", "hold: no guard on a unit with no men"),
    ("hold", "    je miss\n", "", "hold: blocks the plain move again (the 2026-11-09 stall)"),
    ("hold", "    je miss\n", "    jne miss\n", "hold: the behaviour test inverted"),
    ("noarc", "    xor eax, eax\n", "", "noarc: returns the block address, which reads as true"),
    ("clearshot", "    jz miss\n    mov eax, 1\n", "    jnz miss\n    mov eax, 1\n", "clearshot: the wall test inverted"),
    ("clearshot", "    mov eax, 1\n", "    xor eax, eax\n", "clearshot: answers blocked"),
    ("arc", "    jz miss\n    mov word", "    jnz miss\n    mov word", "arc: the wall test inverted"),
    ("arc", "[rcx + 2], 0x8000", "[rcx], 0x8000", "arc: writes the heading, not the half-arc"),
    ("arc", "[rdx + {unit_of_man}]", "[rcx + {unit_of_man}]", "arc: the unit read off the record, not the engine"),
    ("inplace", "    jz miss\n    and byte", "    jnz miss\n    and byte", "inplace: the wall test inverted"),
    ("inplace", "and byte ptr [rcx + 0xd8], 0xf7", "and byte ptr [rcx + 0xd8], 0xfb", "inplace: clears the wrong bit"),
    ("inplace", "    cmp qword ptr [r9 + {surface}], 0\n", "    cmp qword ptr [rcx + {surface}], 0\n",
     "inplace: the surface read off the action, not the engine"),
    ("wallgate", "    mov al, 1\n", "    xor al, al\n", "wallgate: refuses a listed battery"),
    ("cursor", "    sub rsp, 0x28\n", "    sub rsp, 0x20\n", "cursor: unlisted native call misaligned"),
    ("primary", "    mov rdx, qword ptr [rax + 0x188]\n", "    mov rdx, qword ptr [rax + 0xa8]\n",
     "primary: iterates crew instead of engines"),
    ("solver", "    mov dword ptr [rsp + 0x24], 1\n", "    mov dword ptr [rsp + 0x24], 0\n",
     "solver: forgets the rear-chain guard"),
    ("fronts", "    mov r11d, 0x108\n", "    mov r11d, 0xb0\n", "fronts: selects every second marker"),
    ("rear", "    jne miss\n", "    je miss\n", "rear: wrong unit gets the guard"),
    ("rear", "    push rax\n", "    push rcx\n", "rear: overwrites the native vector count"),
    ("preview", "[rsi + 0x184]", "[rsi + 0xa4]", "preview: adds crew positions"),
    ("preview_models", "[rdi + 0x184]", "[rdi + 0xa4]", "preview_models: requests crew positions"),
    ("preview_order", "[rdi + 0x184]", "[rdi + 0xa4]", "preview_order: adds crew positions"),
    ("radius", "    jne miss\n", "", "radius: a crewman shrunk too"),
    ("radius", "    jz miss\n    mulss", "    jnz miss\n    mulss", "radius: the wall test inverted"),
    ("radius", "mulss xmm7", "mulss xmm8", "radius: shrinks the height"),
    ("hitsize", "    pop rax\n", "", "hitsize: rax lost on the way out"),
    ("hitsize", "    jz miss\n    lock inc", "    jnz miss\n    lock inc", "hitsize: the wall test inverted"),
    ("hitsize", "divss xmm6", "mulss xmm6", "hitsize: shrinks the hit size again"),
    ("turn", "    mov eax, 0x7fff\n", "    mov eax, 0x8000\n", "turn: 0x8000, which CA's clamp reads as the back"),
    ("wallscan", "    jz miss\n    push rax", "    jnz miss\n    push rax", "wallscan: the wall test inverted"),
    ("wallscan", "    sub rsp, 0x38\n", "    sub rsp, 0x30\n", "wallscan: calls CA on a misaligned stack"),
    ("wallscan", "    movaps xmm3, xmm6\n", "", "wallscan: gathers with no range"),
    ("wallscan", "    mov byte ptr [rsp + 0x30], 1\n", "", "wallscan: the gather's last argument unset"),
    ("wallscan", "    pop rax\n", "", "wallscan: rejoins with the stack one slot off"),
    ("turn", "    jz miss\n    mov eax", "    jnz miss\n    mov eax", "turn: the wall test inverted"),
    ("turn", "    jne miss\n    mov r11, qword ptr [rsi + {unit_of_man}]", "    mov r11, qword ptr [rsi + {unit_of_man}]",
     "turn: any body class"),
    ("hitsize", "    lock inc dword ptr [rax + {hit_count}]\n", "", "hitsize: the probe's counter never counts"),
]


def selftest():
    import subprocess
    from artillery_wall_slots_tests import scenarios as native_scenarios
    caves = shipped_caves()
    built = {k: assemble(ASM[k]) for k in CAVE_ORDER}
    fails = [] if caves == built else ["the shipped bytes are not this file's assembly: run gen_artillery_walls.py"]
    fails += scenarios(caves)
    fails += native_scenarios(sys.modules[__name__], caves)
    for k, old, new, what in BREAKS:
        assert old in ASM[k], (k, old)
        broken = dict(caves)
        broken[k] = assemble(ASM[k].replace(old, new, 1))
        check_broken = native_scenarios(sys.modules[__name__], broken) if k in NATIVE_ORDER else scenarios(broken)
        if not check_broken:
            fails.append("a broken cave passed: " + what)
    guns = wall_guns()
    for k in ("wh3_dlc23_chd_veh_magma_cannon", "wh3_main_chd_art_hobgob_bolt_thrower", "wh_main_emp_art_great_cannon",
              "wh_main_dwf_art_cannon", "wh3_dlc23_chd_veh_iron_daemon", "wh3_dlc23_chd_veh_deathshrieker_rocket_launcher"):
        if k not in guns:
            fails.append("%s is not a wall gun" % k)
    for k in ("wh_main_grn_cav_goblin_wolf_chariot", "wh2_dlc09_tmb_cha_khatep_3", "wh2_dlc10_hef_cav_tiranoc_chariot",
              "wh_main_emp_veh_luminark_of_hysh_0", "wh3_dlc23_chd_veh_skullcracker", "wh3_main_cth_art_grand_cannon_0",
              "wh3_main_ogr_veh_ironblaster_0"):
        if k in guns:
            fails.append("%s is a wall gun" % k)
    drawn = wall_guns(drawn=True)
    if not {"wh3_main_cth_art_grand_cannon_0", "wh3_main_cth_art_fire_rain_rocket_battery_0",
            "wh3_main_ksl_veh_little_grom_0"} <= set(drawn) or set(drawn) & set(guns):
        fails.append("the drawn list misses Cathay's or the Little Grom, or shares a unit with the wall guns")
    for f in fails:
        print("FAIL:", f)
    lua = subprocess.run(["lua", os.path.join(HERE,"artillery_walls_tests.lua")],
                         cwd=os.path.dirname(HERE),capture_output=True,text=True)
    if lua.returncode:
        fails.append("Lua movement/queue checks failed")
        print(lua.stdout + lua.stderr)
    else:
        print(lua.stdout.strip())
    print("selftest: %s (%d breaks caught)" % ("ok" if not fails else "%d failures" % len(fails), len(BREAKS)))
    return not fails


def pack():
    sys.path.insert(0, HERE)
    from rpfm_client import call, ensure_game, new_pack
    assert check(), "fix the check first"
    ensure_game()
    key = new_pack()
    files = [(LUA, "script/battle/mod/derpy_artillery_walls.lua")] + [(p, "battle_ai/" + os.path.basename(p)) for p in BAI]
    call("add_files_from_disk", {"pack": key, "paths": [os.path.abspath(f) for f, _ in files],
                                 "pack_paths": [dst for _, dst in files]})
    call("save_pack", {"pack": key, "path": os.path.abspath(PACK)})
    call("close_pack", {"pack": key})  # so the check below reads the saved file
    from read_pack_index import read
    got = {p.replace("\\", "/"): data for p, _, data in read(PACK, "") if not p.endswith(".rpfm_reserved")}
    want = {dst: open(src, "rb").read() for src, dst in files}
    assert got == want, sorted(got)
    print("saved", os.path.normpath(PACK), "- every file byte-identical to its source:", sorted(got))


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(0 if check() else 1)
    if "--selftest" in sys.argv:
        sys.exit(0 if selftest() else 1)
    if "--pack" in sys.argv:
        pack()
        sys.exit(0)
    write()
