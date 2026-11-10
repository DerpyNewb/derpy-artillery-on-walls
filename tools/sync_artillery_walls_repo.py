"""Mirror Artillery on Walls into repos/derpy-artillery-on-walls, the public repo.

The workspace is the source of truth; the repo is a copy with the same layout, so every tool's relative paths
("Modding Files/...", "tools/...") work from either root. README.md, CHANGELOG.md, LICENSE, .gitignore and
.gitattributes are written in the repo itself and never touched here. The copying is sync_guilds_repo's.

    py tools/sync_artillery_walls_repo.py            # copy every changed file into the repo
    py tools/sync_artillery_walls_repo.py --check    # list drift, copy nothing; exit 1 on drift
    py tools/sync_artillery_walls_repo.py --selftest

Then commit and push from inside the repo folder.

Published: the battle script and the live-game probes (Modding Files/source/artillery_walls), the generator and its
tests with their import closure, the practice-battle writer, the exe tools (static scans, the patch migrator, Ghidra
headless), the handoffs as docs/history/ and docs/BATTLE_ENGINE_RE.md.

NOTHING OF CA'S OR GW'S IS PUBLISHED. battle_ai/bai_values_*.txt are CA's own files with one value changed: the
generator rebuilds them from the player's data.pack, so they stay out. So do the Workshop GIFs and thumbnail (frames of
the game, and one clip of CA's trailer), any file naming a Windows user profile, and decompiled exe code (a ```c block;
user ruling 2026-10-17). `refused()` checks every manifest entry, by path, extension and content, and the sync will not
run while it reports anything.
"""
import os
import re
import sys

import sync_guilds_repo as SG

ROOT = SG.ROOT
REPO = os.path.join(ROOT, "repos", "derpy-artillery-on-walls")
SRC = "Modding Files/source/artillery_walls"

TOOLS = [
    # the generator, its native-cave scenarios and the Lua checks it runs
    "gen_artillery_walls.py", "artillery_wall_slots_tests.py", "artillery_walls_tests.lua",
    # the custom siege the live tests ran in
    "make_practice_battle.py",
    # reading the exe: static scans, moving every address to a new build, Ghidra headless
    "exe_re.py", "exe_migrate.py", "ghidra_decompile.py", "ghidra/DecompileAt.java", "ghidra/DumpImage.java",
    # the import closure of the above
    "read_vanilla_db.py", "read_pack_index.py", "rpfm_client.py",
    # this file and its copier
    "sync_guilds_repo.py", "sync_artillery_walls_repo.py",
]
HISTORY = ["HANDOFF_20261031_ARTILLERY_ON_WALLS.md", "HANDOFF_20261031_ARTILLERY_WALLS_BATTLEMENTS.md",
           "HANDOFF_20261101_ARTILLERY_GROUND_RECOVERY.md", "HANDOFF_20261101_ARTILLERY_NATIVE_WALL_SLOTS.md",
           "HANDOFF_20261101_ARTILLERY_PREVIEW_WALKING_DESCENT.md", "HANDOFF_20261103_ARTILLERY_WALLS_NEXT.md",
           "HANDOFF_20261109_ARTILLERY_WALLS_STALLS.md"]
REFERENCE = ["BATTLE_ENGINE_RE.md"]

REFUSED_EXT = (".png", ".gif", ".mp4", ".dds", ".jpg", ".jpeg", ".webp", ".tga", ".pack", ".bin", ".loc", ".anim",
               ".wem", ".twui.xml", ".xlsx", ".json", ".npz", ".txt")
PRIVATE = re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s]+", re.I)
DECOMPILED = re.compile(r"^```c\s*$", re.M)


def _walk(rel, exts):
    out = []
    for dp, dns, fns in os.walk(os.path.join(ROOT, rel)):
        dns[:] = sorted(d for d in dns if d != "__pycache__")
        for fn in sorted(fns):
            if fn.endswith(exts):
                out.append(os.path.relpath(os.path.join(dp, fn), ROOT).replace("\\", "/"))
    return out


def manifest():
    out = [(p, p) for p in _walk(SRC, (".lua", ".py"))]
    out += [("tools/" + n, "tools/" + n) for n in TOOLS]
    out += [("docs/sessions/" + n, "docs/history/" + n) for n in HISTORY]
    out += [("docs/" + n, "docs/" + n) for n in REFERENCE]
    return out


def refused(m, root=ROOT):
    """Every manifest entry that must never be published, with why."""
    bad = []
    for src, _dst in m:
        if "battle_ai/" in src or src.lower().endswith(REFUSED_EXT):
            bad.append((src, "CA's file, game art or footage, a game binary or a data dump"))
            continue
        p = os.path.join(root, src)
        if os.path.isfile(p):
            with open(p, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            hit = PRIVATE.search(text)
            if hit:
                bad.append((src, "names a user profile: %s" % hit.group(0)))
            elif DECOMPILED.search(text):
                bad.append((src, "holds a C block: decompiled exe code is never published"))
    return bad


def _selftest():
    import tempfile
    m = manifest()
    assert not refused(m), refused(m)
    if os.path.isdir(os.path.join(ROOT, "docs", "sessions")):  # the workspace, not a clone of the repo
        missing = [s for s, _d in m if not os.path.isfile(os.path.join(ROOT, s))]
        assert not missing, "manifest names files that do not exist: %s" % missing
    assert len({d for _s, d in m}) == len(m), "two entries land on one repo path"
    assert SRC + "/script/battle/mod/derpy_artillery_walls.lua" in {s for s, _d in m}, "the battle script is not published"
    for probe in (SRC + "/battle_ai/bai_values_major.txt", "docs/workshop/artillery_walls/derpy_artillery_walls.gif",
                  "docs/workshop/artillery_walls/description/thorgrim_trailer_237_243.gif",
                  "Modding Files/Modpacks/derpy_artillery_walls.pack", SRC + "/probes/races_emp_29D2.txt"):
        assert refused([(probe, probe)]), "refused() let %s through" % probe
    with tempfile.TemporaryDirectory() as td:
        with open(os.path.join(td, "a.lua"), "w") as fh:
            fh.write("-- see C:" + "\\Users\\someone\\notes.md")
        assert refused([("a.lua", "a.lua")], td), "refused() let a user-profile path through"
        with open(os.path.join(td, "b.md"), "w") as fh:
            fh.write("notes\n```c\nif (h->has != 1) return 0;\n```\n")
        assert refused([("b.md", "b.md")], td), "refused() let a decompiled C block through"
    print("selftest ok: %d files, nothing refused" % len(m))


if __name__ == "__main__":
    unknown = [a for a in sys.argv[1:] if a not in ("--check", "--selftest")]
    if unknown:
        print("unknown argument(s): %s" % " ".join(unknown))
        sys.exit(2)
    m = manifest()
    bad = refused(m)
    if bad:
        for s, why in bad:
            print("REFUSED  %s  (%s)" % (s, why))
        sys.exit(1)
    if "--selftest" in sys.argv:
        _selftest()
    elif "--check" in sys.argv:
        found = SG.drift(ROOT, REPO, m)
        for s, _d, why in found:
            print("%-22s %s" % (why, os.path.relpath(s, ROOT)))
        print("%d file(s) drift" % len(found))
        sys.exit(1 if found else 0)
    else:
        found = SG.sync(ROOT, REPO, m)
        for s, _d, why in found:
            print("%-22s %s" % (why, os.path.relpath(s, ROOT)))
        print("synced %d file(s) into %s" % (len(found), REPO))
