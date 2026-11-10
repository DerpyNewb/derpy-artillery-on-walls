"""Decompile Warhammer3.exe functions by RVA with Ghidra, headless (the game may be shut; Ghidra's GUI is never opened).

    py tools/ghidra_decompile.py <rva> [<rva> ...]     C for the function holding each RVA, printed
    py tools/ghidra_decompile.py --import              (re)build the project: the exe imported with NO analysis
    py tools/ghidra_decompile.py --selftest            decompile walk_stop and check what it calls

The project is ghidra_cache/<build>/ at the workspace root, imported once WITHOUT auto-analysis: analysing 54 MB of
code would take hours, and one function's decompile does its own local analysis (tools/ghidra/DecompileAt.java makes
the function where none exists). Every run opens it -readOnly, so the functions a run creates are not kept and
runs never conflict. Callees print as FUN_<va>; their names, types and the class layouts are ours to supply
(docs/BATTLE_ENGINE_RE.md). Three traps found setting this up: Ghidra refuses a project path with an element that
starts with '.', it needs JAVA_HOME (JDK 25 in C:/tools/jdk-25 for 12.2), and the .bat waits for a key after an error, so
stdin is closed. For byte scans (who calls, who writes, which vtable) tools/exe_re.py is seconds where this is ~1 min.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GHIDRA = r"C:\tools\ghidra_12.2_PUBLIC\support\analyzeHeadless.bat"
JAVA = r"C:\tools\jdk-25"  # 12.2 needs Java 25; 12.1.4 + jdk-21 stay installed as the fallback
EXE = r"F:\SteamLibrary\steamapps\common\Total War WARHAMMER III\Warhammer3.exe"
PROJECT_DIR = os.path.join(ROOT, "ghidra_cache")
import struct


def _stamp():
    d = open(EXE, "rb").read(0x400)
    return "%08x" % struct.unpack_from("<I", d, struct.unpack_from("<I", d, 0x3c)[0] + 8)[0]


PROJECT = "wh3_" + os.environ.get("WH3_BUILD", _stamp())  # one project per exe build: --import after a game patch
# makes the new one and keeps the old, which WH3_BUILD=<stamp> selects for a decompile of the pre-patch code, and
# whose bytes tools/ghidra/DumpImage.java turns into the snapshot tools/exe_migrate.py diffs against
SCRIPTS = os.path.join(ROOT, "tools", "ghidra")


def headless(*args):
    env = dict(os.environ, JAVA_HOME=JAVA)
    r = subprocess.run([GHIDRA, PROJECT_DIR, PROJECT] + list(args), env=env, stdin=subprocess.DEVNULL,
                       capture_output=True, text=True, errors="replace")
    return r.returncode, r.stdout + r.stderr


def do_import():
    os.makedirs(PROJECT_DIR, exist_ok=True)
    code, log = headless("-import", EXE, "-noanalysis", "-overwrite")
    if code != 0:
        print(log[-3000:])
    return code


def decompile(rvas):
    if not os.path.exists(os.path.join(PROJECT_DIR, PROJECT + ".gpr")):
        print("no project yet: run with --import first (a few minutes)")
        return None
    fd, out = tempfile.mkstemp(suffix=".c")
    os.close(fd)
    try:
        code, log = headless("-process", os.path.basename(EXE), "-noanalysis", "-readOnly", "-scriptPath", SCRIPTS,
                             "-postScript", "DecompileAt.java", out, *["%x" % r for r in rvas])
        text = open(out, encoding="utf-8", errors="replace").read()
        if code != 0 or not text:
            print(log[-3000:])
            return None
        return text
    finally:
        os.remove(out)


def selftest():
    # walk_stop (exe+306edd4) on 6acec6f4 calls exe+306edf8, the stop that writes 18 to +0x324 (tools/exe_re.py refs)
    text = decompile([0x306edd4])
    assert text, "no output"
    assert "exe+306edd4" in text and "FUN_14306edf8" in text, "walk_stop's decompile names its callee:\n" + text
    print("ok: walk_stop decompiled and calls FUN_14306edf8")
    return 0


def main(argv):
    if argv[:1] == ["--import"]:
        return do_import()
    if argv[:1] == ["--selftest"]:
        return selftest()
    if not argv:
        print(__doc__)
        return 2
    text = decompile([int(a.lower().replace("exe+", ""), 16) for a in argv])
    if text is None:
        return 1
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
