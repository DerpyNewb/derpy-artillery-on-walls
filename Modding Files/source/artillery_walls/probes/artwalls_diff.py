"""Diff AWD body dumps: fields stable in the MOVING snapshots of every engine, stable in the STUCK snapshots of
the stuck engine, and different between the two. argv: dumpfile moving_tags stuck_tags stuck_body"""
import struct
import sys

path, moving, stuck, body = sys.argv[1], sys.argv[2].split(","), sys.argv[3].split(","), sys.argv[4].upper()
snaps = {}  # (tag, body) -> {('B'|'C', off): word}
cur = None
for line in open(path):
    if line.startswith("#"):
        f = dict(p.split("=", 1) for p in line.split()[2:] if "=" in p)
        tag = line.split()[1]
        cur = snaps.setdefault((tag, f["body"].upper()), {})
        cur["head"] = line.strip()
    elif cur is not None and line[:1] in "BC":
        parts = line.split()
        base = int(parts[1], 16)
        for i, w in enumerate(parts[2:]):
            cur[(parts[0], base + 4 * i)] = int(w, 16)


def fl(w):
    return struct.unpack("<f", struct.pack("<I", w))[0]


mov = [v for (t, b), v in snaps.items() if t in moving]
stk = [v for (t, b), v in snaps.items() if t in stuck and b == body]
print(len(mov), "moving snaps,", len(stk), "stuck snaps")
keys = set(stk[0]) - {"head"}
for k in sorted(keys):
    sv = {s.get(k) for s in stk}
    mv = {s.get(k) for s in mov}
    if len(sv) != 1 or None in mv or None in sv:
        continue
    s = sv.pop()
    if s in mv:
        continue
    if len(mv) > 2:  # varies freely while moving: position, timers, pointers
        continue
    print("%s+%04x stuck %08x (%g)  moving %s" % (k[0], k[1], s, fl(s), " ".join("%08x(%g)" % (m, fl(m)) for m in sorted(mv))))
