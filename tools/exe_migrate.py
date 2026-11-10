"""Find where a game patch moved each exe address a mod depends on (RVAs in Warhammer3.exe), from the previous
build's bytes. The game may be shut; nothing is written.

    py tools/exe_migrate.py                  every address of Artillery on Walls (ARTWALLS), old -> new, as a table
    py tools/exe_migrate.py --old <image.bin> --new <exe>   another pair of builds
    py tools/exe_migrate.py --selftest       the masking and the search on the old build against itself

The old build is a DumpImage.java dump of the Ghidra project imported before the patch
(Modding Files/Backup/exe_snapshots/image_<build>.bin, laid out by RVA): a project keeps its own copy of the exe's
bytes, so it IS the pre-patch snapshot. Three kinds of address:
    code     a function or a site inside one: the bytes from the old RVA, with every rel32 call/jump target,
             rip-relative displacement and imm64 masked, searched for in the new code section; the window grows
             until one match remains
    vtable   the first two code slots are migrated as code, then the new vtable section is searched for the pair
    data     a constant or global, found through one old instruction that reads it: that instruction is migrated
             as code and its new rip-relative target decoded
    call     a function with byte-identical twins (a template instance: the two queue writers have 150), found
             through one old call to it the same way
A result with two matches names both; one with none says so. Struct field offsets (a body's +0x910 and the like)
are not addresses and are not found here: compare the new decompile of the function that reads them.
Needs capstone.
"""
import os
import re
import struct
import sys

import capstone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLD = os.path.join(ROOT, "Modding Files", "Backup", "exe_snapshots", "image_6acec6f4.bin")
NEW = r"F:\SteamLibrary\steamapps\common\Total War WARHAMMER III\Warhammer3.exe"
BASE = 0x140000000
WINDOWS = (40, 72, 120, 200, 320)

# Artillery on Walls, build 6acec6f4: tools/gen_artillery_walls.py SITES and CALLS, the Lua's at() calls, the probes'
# anchors and the RE anchors the handoffs name. ("data", rva, ref) names an instruction that reads the datum.
ARTWALLS = [
    ("climb site / fn_climb", "code", 0x3014da8), ("links site", "code", 0x301d69c), ("man site", "code", 0x305952c),
    ("hold site", "code", 0x327ebc8), ("noarc site", "code", 0x328507c), ("clearshot site", "code", 0x305eb74),
    ("arc site", "code", 0x2f8ed98), ("wallgate site", "code", 0x301d346), ("cursor site", "code", 0x3021854),
    ("primary site", "code", 0x3045479), ("solver site", "code", 0x30249f0), ("fronts site", "code", 0x3024acc),
    ("rear site", "code", 0x3024e86), ("placement site", "code", 0x3070a48), ("preview site", "code", 0x2e0f3a8),
    ("preview_models site", "code", 0x2e0f96c), ("preview_order site", "code", 0x2e0f9bd),
    ("fn_a", "code", 0x301d214), ("fn_b", "code", 0x301d098), ("fn_inf", "code", 0x303425c),
    ("gate_cont", "code", 0x301d34b), ("cursor_cont", "code", 0x3021859), ("fn_add", "code", 0x30e54ec),
    ("prepare_cont", "code", 0x30454b3), ("candidate_next", "code", 0x3024b12), ("rear_next", "code", 0x3024ea8),
    ("fn_atan", "code", 0x1183a8c), ("fn_round", "code", 0x4eda50), ("fn_relative", "code", 0x2f775ac),
    ("preview_cont", "code", 0x2e0f3ae), ("preview_models_cont", "code", 0x2e0f973), ("preview_order_cont", "code", 0x2e0f9c3),
    ("wall_vt", "vtable", 0x3911218), ("move_vt (Lua)", "vtable", 0x390dd00), ("attack_vt (Lua)", "vtable", 0x390d2f0),
    ("Lua 2df5a94 queue", "call", 0x2df5a94, 0x2e5542f), ("Lua 2e9c154 queue push", "call", 0x2e9c154, 0x2ed8d05),
    ("Lua 2ea9754 zone order ctor", "code", 0x2ea9754), ("Lua 2ea9c88 move ctor", "code", 0x2ea9c88),
    ("Lua 2f2efc8 selection", "code", 0x2f2efc8), ("Lua 2f37be4 selection add", "code", 0x2f37be4),
    ("Lua 1bcd8ac release", "code", 0x1bcd8ac),
    ("fn_scale 10430.38", "data", 0x3922260, 0x2f8edef),
    ("battle global (Lua 4480da0)", "data", 0x4480da0, 0x2ea8de8),
    ("engine body vt (probes)", "vtable", 0x3ad3360), ("attack behaviour vt", "vtable", 0x3ae43b0),
    ("fire update 308ae34", "code", 0x308ae34), ("body update 3086224", "code", 0x3086224),
    ("engine busy 305f9c4", "code", 0x305f9c4), ("walk_stop (exe_re KNOWN_CODE)", "code", 0x306edd4),
    ("crew spot tick 308de70", "code", 0x308de70), ("spot place 3086a80", "code", 0x3086a80),
    ("spot manned 3086e0c", "code", 0x3086e0c), ("spot layout 308dde4", "code", 0x308dde4),
    ("goal writer 3065db8", "code", 0x3065db8), ("fire/relocate 30729d8", "code", 0x30729d8),
    ("crew walk 3074270", "code", 0x3074270), ("crew walk 3070950", "code", 0x3070950),
    ("go to slot 3075e7c", "code", 0x3075e7c), ("crew gate 3086f04", "code", 0x3086f04),
    ("crew gate 30690dc", "code", 0x30690dc),
]


class Build:
    """an exe on disk, or a DumpImage.java image: bytes addressed by RVA, plus the code and vtable sections"""

    def __init__(self, path):
        self.path = path
        self.b = open(path, "rb").read()
        image = path.lower().endswith(".bin")
        peo = struct.unpack_from("<I", self.b, 0x3C)[0]
        n = struct.unpack_from("<H", self.b, peo + 6)[0]
        opt = struct.unpack_from("<H", self.b, peo + 20)[0]
        self.stamp = "%08x" % struct.unpack_from("<I", self.b, peo + 8)[0]
        self.secs = []
        for i in range(n):
            s = peo + 24 + opt + 40 * i
            vsz, va, rsz, rptr = struct.unpack_from("<IIII", self.b, s + 8)
            self.secs.append((va, vsz, va if image else rptr, vsz if image else rsz))
        self.secs.sort()
        self.code = self.secs[0]  # the first section is the code on every build so far (RVA 0x1000)
        self.vtables = self.secs[1]  # and the second holds the vtables

    def off(self, rva):
        for va, vsz, rptr, rsz in self.secs:
            if va <= rva < va + rsz:
                return rptr + rva - va
        raise ValueError("rva %x is in no section of %s" % (rva, self.path))

    def read(self, rva, n):
        o = self.off(rva)
        return self.b[o:o + n]

    def section(self, sec):
        va, vsz, rptr, rsz = sec
        return va, self.b[rptr:rptr + rsz]

    def in_code(self, rva):
        va, vsz, rptr, rsz = self.code
        return va <= rva < va + rsz


_md = None


def md():
    global _md
    if _md is None:
        _md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        _md.detail = True
    return _md


def mask(code, rva):
    """(bytes, mask) for the instructions covering `code`: a masked byte is any that the linker moves - a rel32
    call or jump target, a rip-relative displacement, an 8-byte immediate (an absolute address)"""
    keep = bytearray(b"\x01" * len(code))
    end = 0
    for ins in md().disasm(code, BASE + rva):
        at = ins.address - BASE - rva
        end = at + ins.size
        enc = ins.encoding
        if enc.disp_size == 4 and any(op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP
                                      for op in ins.operands):
            keep[at + enc.disp_offset:at + enc.disp_offset + 4] = b"\0" * 4
        if enc.imm_size == 4 and (ins.group(capstone.CS_GRP_JUMP) or ins.group(capstone.CS_GRP_CALL)):
            keep[at + enc.imm_offset:at + enc.imm_offset + 4] = b"\0" * 4
        if enc.imm_size == 8:
            keep[at + enc.imm_offset:at + enc.imm_offset + 8] = b"\0" * 8
    return code[:end], bytes(keep[:end])


def pattern(code, keep):
    out = []
    for c, k in zip(code, keep):
        out.append(re.escape(bytes([c])) if k else b".")
    return re.compile(b"".join(out), re.DOTALL)


def find_code(old, new, rva):
    """the new RVAs whose bytes match the old function's masked bytes; the window grows until one is left"""
    va, blob = new.section(new.code)
    found = []
    for n in WINDOWS:
        code, keep = mask(old.read(rva, n + 16), rva)
        found = [va + m.start() for m in pattern(code, keep).finditer(blob)]
        if len(found) <= 1:
            break
    return found


def find_vtable(old, new, rva):
    """the new vtable whose first slots are the old ones migrated; two slots usually suffice, but the first slots of a
    class family are shared, so more are taken while the run is ambiguous"""
    va, blob = new.section(new.vtables)
    slots, found = [], []
    for k in range(8):
        v = struct.unpack_from("<Q", old.read(rva + 8 * k, 8))[0] - BASE
        if not old.in_code(v):
            return found, "slot %d is not code" % k
        got = find_code(old, new, v)
        if len(got) != 1:
            return found, "slot %d: %d matches" % (k, len(got))
        slots.append(got[0])
        run = b"".join(struct.pack("<Q", BASE + s) for s in slots)
        found = [va + m.start() for m in re.finditer(re.escape(run), blob)]
        if k >= 1 and len(found) <= 1:
            break
    note = "slots " + " ".join("%x" % s for s in slots)
    if len(found) > 1:  # twins past eight slots: the linker keeps the order, so the one nearest the old address is it
        found.sort(key=lambda r: abs(r - rva))
        note += "; nearest of %d" % len(found)
        found = found[:1]
    return found, note


def find_data(old, new, rva, ref):
    """the new address of a datum through one old instruction that reads it rip-relative"""
    ins = next(md().disasm(old.read(ref, 16), BASE + ref))
    target = next(op.mem.disp for op in ins.operands if op.type == capstone.x86.X86_OP_MEM) + ins.address + ins.size - BASE
    if target != rva:
        return [], "exe+%x reads exe+%x, not this" % (ref, target)
    got = find_code(old, new, ref)
    if len(got) != 1:
        return [], "the reading instruction: %d matches" % len(got)
    ins = next(md().disasm(new.read(got[0], 16), BASE + got[0]))
    disp = next(op.mem.disp for op in ins.operands if op.type == capstone.x86.X86_OP_MEM)
    return [disp + ins.address + ins.size - BASE], "read at exe+%x" % got[0]


def find_call(old, new, rva, site):
    """the new address of a function with many byte-identical twins (a template instance), through one old call to it:
    the call site is migrated as code and its new rel32 decoded"""
    ins = next(md().disasm(old.read(site, 16), BASE + site))
    if not ins.group(capstone.CS_GRP_CALL) or ins.operands[0].type != capstone.x86.X86_OP_IMM:
        return [], "exe+%x is not a direct call" % site
    if ins.operands[0].imm - BASE != rva:
        return [], "exe+%x calls exe+%x, not this" % (site, ins.operands[0].imm - BASE)
    got = find_code(old, new, site)
    if len(got) != 1:
        return [], "the call site: %d matches" % len(got)
    ins = next(md().disasm(new.read(got[0], 16), BASE + got[0]))
    return [ins.operands[0].imm - BASE], "called at exe+%x" % got[0]


def migrate(old, new, items):
    rows = []
    for item in items:
        name, kind, rva = item[:3]
        note = ""
        if kind == "code":
            got = find_code(old, new, rva)
        elif kind == "vtable":
            got, note = find_vtable(old, new, rva)
        elif kind == "call":
            got, note = find_call(old, new, rva, item[3])
        else:
            got, note = find_data(old, new, rva, item[3])
        rows.append((name, kind, rva, got, note))
    return rows


def report(rows):
    print("%-34s %-7s %-9s %-20s %s" % ("name", "kind", "old", "new", "note"))
    for name, kind, rva, got, note in rows:
        new = ", ".join("%x" % g for g in got) if got else "NOT FOUND"
        shift = (" (%+#x)" % (got[0] - rva)) if len(got) == 1 else ""
        print("%-34s %-7s %-9x %-20s %s" % (name, kind, rva, new + shift, note))
    bad = [r for r in rows if len(r[3]) != 1]
    print("%d of %d found once" % (len(rows) - len(bad), len(rows)))
    return not bad


def selftest():
    old = Build(OLD)
    fails = []
    code, keep = mask(old.read(0x2f8edef, 13), 0x2f8edef)  # mulss xmm0, [rip+x]; call rel32
    if keep != b"\x01\x01\x01\x01\0\0\0\0\x01\0\0\0\0":
        fails.append("mask: the rip-relative displacement and the rel32 are what is masked: %r" % keep)
    code, keep = mask(old.read(0x3014da8, 16), 0x3014da8)
    if 0 in keep[:6]:
        fails.append("mask: plain bytes are kept")
    rows = migrate(old, old, [("arc", "code", 0x2f8ed98), ("wall_vt", "vtable", 0x3911218),
                              ("fn_scale", "data", 0x3922260, 0x2f8edef), ("clearshot", "code", 0x305eb74)])
    for name, kind, rva, got, note in rows:
        if got != [rva]:
            fails.append("%s on the same build: %r, not [%x] (%s)" % (name, got, rva, note))
    rows = migrate(old, old, [("not a function", "code", 0x2f8ed9b)])  # mid-prologue: more than one match is honest
    if len(rows[0][3]) < 1:
        fails.append("a mid-prologue site finds itself at least")
    for f in fails:
        print("FAIL:", f)
    print("selftest:", "ok" if not fails else "%d failures" % len(fails))
    return not fails


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--selftest" in args:
        sys.exit(0 if selftest() else 1)
    old_path = args[args.index("--old") + 1] if "--old" in args else OLD
    new_path = args[args.index("--new") + 1] if "--new" in args else NEW
    old, new = Build(old_path), Build(new_path)
    print("old build %s -> new build %s" % (old.stamp, new.stamp))
    sys.exit(0 if report(migrate(old, new, ARTWALLS)) else 1)
