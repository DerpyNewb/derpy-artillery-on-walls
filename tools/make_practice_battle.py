"""Writes the player's army into the saved practice battle (`.singleplayer.battle_preferences`), so a custom siege
can be re-run with another race's artillery without the custom-battle screen. The file is what `button_battle` >
`button_practice_battle` > `button_start_battle` loads. Game SHUT: it rewrites the file when a battle starts.

    py tools/make_practice_battle.py --faction wh_main_dwf_dwarfs --units wh_main_dwf_inf_longbeards wh_main_dwf_art_cannon
    py tools/make_practice_battle.py --map major_a_emp   another siege map (the player's army kept); combinable
    ... --enemy-units wh_main_grn_inf_orc_arrer_boyz ...   the enemy's units, behind its own lord; combinable
    ... --enemy-faction wh3_main_cth_cathay_mp --enemy-lord wh3_main_cth_cha_lord_magistrate_0   another enemy army
    ... --player-attacks   the player attacks the settlement and the AI holds it
    py tools/make_practice_battle.py --faction F --lord wh2_main_skv_cha_warlord_0 --units ...   a bare lord entry
    ... --unit-faction wh2_main_skv_skaven   the faction each entry names, when it is not the block's (Skaven
        clans: an entry naming wh2_main_skv_clan_pestilens drops the whole army, 2026-11-09)
    py tools/make_practice_battle.py --restore          put the backed-up original back
    py tools/make_practice_battle.py --selftest

The lord is copied raw out of the faction's own `army_setups/last_setup_for_<faction>_classic.army_setup` (its first
entry), because a lord entry carries its ability and item list and a unit entry does not. `--lord` writes a bare
`key:faction:1` entry with no abilities instead, for a faction whose saved setup leads with a hero (`:0`) or a mod
lord (Skaven, Vampire Coast and Ogre setups on this machine, 2026-11-09). The game reads this file once per launch
(re-entering the practice battle keeps the army it has) and writes its own army back when a battle ends, so write
it with the game shut, before each launch (2026-11-09). Format, measured 2026-11-01:
a faction block is `u16 len + faction`, `u16 5 "siege"`, `u8 1`, `u32 n` entries; an entry is `u16 len +
"unit:faction:rank"`, 15 bytes, `u32 k`, k x (`u8 type`, `u16 len + key`), `u16 4 "none"`. The original is backed up
beside the artillery evidence before the first write, and EVERY write starts from that backup, not from the file as
it stands: the map, settings and enemy army are the 2026-11-01 original's (the Black Pyramid, a Greenskin enemy)
unless a flag names them. Pass `--map major_a_emp` every time for the Altdorf siege (2026-11-10).
"""
import os
import shutil
import struct
import sys

APP = os.path.join(os.environ.get("APPDATA", ""), "The Creative Assembly", "Warhammer3")
PREFS = os.path.join(APP, "battle_preferences", ".singleplayer.battle_preferences")
SETUPS = os.path.join(APP, "army_setups")
BACKUP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Modding Files", "Backup",
                      "artillery_walls", "20261101", "singleplayer.battle_preferences.orig")


def s16(b, o):
    n = struct.unpack_from("<H", b, o)[0]
    return b[o + 2:o + 2 + n].decode("latin1"), o + 2 + n


def p16(s):
    s = s.encode("latin1")
    return struct.pack("<H", len(s)) + s


def entry_end(b, o):
    """The offset just past the entry starting at o."""
    _, o = s16(b, o)
    o += 15
    k = struct.unpack_from("<I", b, o)[0]
    o += 4
    for _ in range(k):
        o += 1
        _, o = s16(b, o)
    _, o = s16(b, o)
    return o


def player_block(b, o=None):
    """(start, end, faction) of the first faction block: the player's army. o: the first block after o instead (the
    enemy's, from the player's end)."""
    if o is None:
        _, o = s16(b, 4)  # the map
    o = b.index(b"\x08\x00\x00\x00", o) + 4
    start = o
    faction, o = s16(b, o)
    mode, o = s16(b, o)
    assert mode == "siege", mode
    o += 1
    n = struct.unpack_from("<I", b, o)[0]
    o += 4
    for _ in range(n):
        o = entry_end(b, o)
    return start, o, faction


def lord_entry(faction):
    b = open(os.path.join(SETUPS, "last_setup_for_%s_classic.army_setup" % faction), "rb").read()
    o = 4
    _, o = s16(b, o)
    _, o = s16(b, o)
    o += 5
    e = entry_end(b, o)
    key, _ = s16(b, o)
    assert key.endswith(":1"), key
    return b[o:e]


def unit_entry(unit, faction, general=0):
    return p16("%s:%s:%d" % (unit, faction, general)) + bytes(15) + struct.pack("<I", 0) + p16("none")


def block(faction, units, lord, unit_faction=None):
    return p16(faction) + p16("siege") + b"\x01" + struct.pack("<I", 1 + len(units)) + lord + b"".join(
        unit_entry(u, unit_faction or faction) for u in units)


def build(original, faction, units, lord=None, unit_faction=None):
    a, z, _ = player_block(original)
    return original[:a] + block(faction, units, lord if lord is not None else lord_entry(faction), unit_faction) + original[z:]


def with_enemy(b, units, faction=None, lord=None):
    """The second block (the enemy's) with these units after its own lord, or after a bare `lord` of `faction`."""
    a, z, f = player_block(b, player_block(b)[1])
    o = a + len(p16(f)) + len(p16("siege")) + 5
    own = b[o:entry_end(b, o)]
    return b[:a] + block(faction or f, units, unit_entry(lord, faction or f, 1) if lord else own) + b[z:]


def player_attacks(b):
    """Each army's alliance record ends `u8 flag, u32 8` just before its faction: 1 attacks the settlement, 0 holds it.
    The game writes the player 0 and the enemy 1; swapped, the player attacks and the AI defends (2026-11-10 run 34)."""
    a1, z1, _ = player_block(b)
    a2 = player_block(b, z1)[0]
    assert (b[a1 - 5], b[a2 - 5]) == (0, 1), "not the player defending"
    return b[:a1 - 5] + b"\x01" + b[a1 - 4:a2 - 5] + b"\x00" + b[a2 - 4:]


def with_map(b, key):
    """The map key is the one `u16 len + key` at offset 4; everything after it is kept (the tile key that follows,
    `settlement_towers_level_2`, is left as it is - whether every siege map accepts it is measured, not known)."""
    _, end = s16(b, 4)
    return b[:4] + p16(key) + b[end:]


def write(faction=None, units=None, map_key=None, lord=None, unit_faction=None, enemy=None, enemy_faction=None,
          enemy_lord=None, attack=False):
    if not os.path.exists(BACKUP):
        shutil.copyfile(PREFS, BACKUP)
    out = open(BACKUP, "rb").read()
    if faction:
        out = build(out, faction, units, unit_entry(lord, unit_faction or faction, 1) if lord else None, unit_faction)
    if map_key:
        out = with_map(out, map_key)
    if enemy:
        out = with_enemy(out, enemy, enemy_faction, enemy_lord)
    if attack:
        out = player_attacks(out)
    open(PREFS, "wb").write(out)
    a, z, f = player_block(out)
    print("wrote %s: map %s, player %s, block %d..%d of %d bytes" % (PREFS, s16(out, 4)[0], f, a, z, len(out)))


def selftest():
    original = open(BACKUP if os.path.exists(BACKUP) else PREFS, "rb").read()
    a, z, faction = player_block(original)
    assert faction == "wh3_dlc23_chd_legion_of_azgorh", faction
    # the block re-emitted from its own parse is the block
    o = a
    _, o = s16(original, o)
    _, o = s16(original, o)
    o += 1
    n = struct.unpack_from("<I", original, o)[0]
    o += 4
    lord_end = entry_end(original, o)
    lord = original[o:lord_end]
    units = []
    for _ in range(n - 1):
        e = entry_end(original, lord_end)
        key, _ = s16(original, lord_end)
        units.append(key.split(":")[0])
        lord_end = e
    assert units == ["wh3_dlc23_chd_inf_infernal_guard", "wh3_main_chd_art_hobgob_bolt_thrower",
                     "wh3_dlc23_chd_veh_magma_cannon", "wh3_dlc23_chd_veh_deathshrieker_rocket_launcher"], units
    assert build(original, faction, units, lord) == original, "a rebuilt block must be byte-identical"
    # a foreign faction's block parses back to what was asked for
    out = build(original, "wh_main_dwf_dwarfs", ["wh_main_dwf_inf_longbeards", "wh_main_dwf_art_cannon"])
    a2, z2, f2 = player_block(out)
    assert f2 == "wh_main_dwf_dwarfs" and out[z2:] == original[z:] and out[:a] == original[:a]
    assert b"wh_main_dwf_art_cannon:wh_main_dwf_dwarfs:0" in out[a2:z2] and b"hobgob" not in out
    assert s16(out, a2 + len(p16(f2)) + len(p16("siege")) + 1 + 4)[0].endswith(":wh_main_dwf_dwarfs:1"), "the lord leads"
    # a bare lord leads as the general and the block still parses to its end
    out = build(original, "wh_x", ["u_a"], unit_entry("lord_x", "wh_x", 1))
    a3, z3, _ = player_block(out)
    assert s16(out, a3 + len(p16("wh_x")) + len(p16("siege")) + 1 + 4)[0] == "lord_x:wh_x:1" and out[z3:] == original[z:]
    out = build(original, "wh_x", ["u_a"], unit_entry("lord_x", "wh_y", 1), "wh_y")
    assert b"u_a:wh_y:0" in out and player_block(out)[2] == "wh_x"
    # the map swap touches only the one string, and the player block still parses after it
    m = with_map(original, "major_a_emp")
    assert s16(m, 4)[0] == "major_a_emp" and m[s16(m, 4)[1]:] == original[s16(original, 4)[1]:]
    assert player_block(m)[2] == faction and with_map(m, s16(original, 4)[0]) == original
    # the enemy's units swapped behind its own lord; the player's block and everything else kept
    e = with_enemy(original, ["wh_main_grn_inf_orc_arrer_boyz"])
    a4, z4, f4 = player_block(e, player_block(e)[1])
    _, ez, _ = player_block(original, player_block(original)[1])
    assert e[:a4] == original[:a4] and e[z4:] == original[ez:] and player_block(e) == player_block(original)
    assert b"wh_main_grn_inf_orc_arrer_boyz:%s:0" % f4.encode() in e[a4:z4]
    assert s16(e, a4 + len(p16(f4)) + len(p16("siege")) + 5)[0].endswith(":1"), "the enemy lord leads"
    eo = player_block(original, player_block(original)[1])
    keys = []
    o = eo[0] + len(p16(eo[2])) + len(p16("siege")) + 5
    while o < eo[1]:
        keys.append(s16(original, o)[0])
        o = entry_end(original, o)
    assert with_enemy(original, [k.split(":")[0] for k in keys[1:]]) == original, "a rebuilt enemy block is identical"
    e = with_enemy(original, ["u_b"], "wh_e", "lord_e")
    a5 = player_block(e, player_block(e)[1])[0]
    assert player_block(e, player_block(e)[1])[2] == "wh_e" and s16(e, a5 + len(p16("wh_e")) + len(p16("siege")) + 5)[0] == "lord_e:wh_e:1"
    s = player_attacks(original)
    assert len(s) == len(original) and sum(x != y for x, y in zip(s, original)) == 2, "two flag bytes and nothing else"
    assert player_block(s) == player_block(original) and s[player_block(s)[0] - 5] == 1
    print("selftest ok")


def flag_list(a, flag):
    """The words after flag up to the next flag: a later --map's key is not a unit (2026-11-09, five battles)."""
    if flag not in a:
        return None
    rest = a[a.index(flag) + 1:]
    return rest[:next((i for i, u in enumerate(rest) if u.startswith("--")), len(rest))]


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    elif "--restore" in sys.argv:
        shutil.copyfile(BACKUP, PREFS)
        print("restored", PREFS)
    elif any(f in sys.argv for f in ("--faction", "--map", "--enemy-units", "--player-attacks")):
        a = sys.argv
        faction = a[a.index("--faction") + 1] if "--faction" in a else None
        units = flag_list(a, "--units")
        write(faction, units, a[a.index("--map") + 1] if "--map" in a else None,
              a[a.index("--lord") + 1] if "--lord" in a else None,
              a[a.index("--unit-faction") + 1] if "--unit-faction" in a else None, flag_list(a, "--enemy-units"),
              a[a.index("--enemy-faction") + 1] if "--enemy-faction" in a else None,
              a[a.index("--enemy-lord") + 1] if "--enemy-lord" in a else None, "--player-attacks" in a)
    else:
        print(__doc__)
