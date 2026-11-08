#!/usr/bin/env python3
"""Compare octet par octet les contenus OOL SBIO des tentatives doigt d'une capture (lecture seule).

- Tentatives : lock_cycles.attempts() (de `> 0xfc 0x23` à `< 0xfc 0x21`).
- Classe d'une tentative : `abort` si pas de `> 0xfc 0x09` ; sinon `good` si la marque en cours
  commence par fp_good, `bad` si fp_bad (résultat rapporté par Albert dans notes.txt : à vérifier
  à la main pour chaque capture), `?` sinon.
- Contenu : en-tête observé de 0x1c octets (u32 LE : +0x00, +0x04 longueur totale, +0x08 offset du
  morceau, +0x0c, +0x10, +0x14 TYPE, +0x18 longueur du morceau), puis la charge utile. Les morceaux
  0xfc/0xfd de même TYPE et même buffer sont recollés à leur offset (+0x08). STRUCTURE OBSERVÉE
  dans C8, pas une spécification.
- Pour chaque (dir, buf, TYPE) : longueurs, puis par octet de la charge : constant partout /
  constant dans chaque classe mais différent entre good et bad (« discriminant ») / variable.
  Plages et entropie (bits/octet, fenêtres de 64 octets) ; une entropie > ~5.5 sur 64 octets
  = proche de l'aléatoire pour cette taille d'échantillon (pas d'interprétation).

Usage :
    python3 analysis/ool_attempts.py traces/<capture>/ [--dump-dir analysis/out/<x>/] [-o analysis/out/x.txt]
"""

import argparse
import math
import os
import struct
import sys
from collections import Counter, OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, write_output, load_marks, marks_path_for, safe_output_path  # noqa: E402
from lock_cycles import attempts, label_at  # noqa: E402
from ool_index import load_index  # noqa: E402

HDR = 0x1C


def hdr(d):
    if len(d) < HDR:
        return None
    return struct.unpack_from("<7I", d, 0)


def classify(att, marks):
    types = [m.type for m in att if m.tag == 0xFC and m.dir == ">"]
    if 0x09 not in types:
        return "abort"
    lab = label_at(marks, att[0].ts)
    if lab.startswith("fp_good"):
        return "good"
    if lab.startswith("fp_bad"):
        return "bad"
    return "?"


def assemble(reads):
    """reads : lectures (dans l'ordre) d'un même (dir, buf, TYPE) dans une tentative, morceaux 0xfc/0xfd.
    Retourne (longueur_totale, bytes recollés, liste des lignes) ; None si pas d'en-tête valide."""
    total, chunks, lines = None, {}, []
    for r in reads:
        h = hdr(r["data"])
        if not h or h[0] != 1 or h[5] != r["msg"]["type"]:
            continue
        total = h[1]
        off, clen = h[2], h[6]
        avail = len(r["data"]) - HDR
        chunks[off] = r["data"][HDR:HDR + min(clen, avail)]
        lines.append(r["msg"]["lineno"])
    if total is None:
        return None
    buf = bytearray(total)
    have = 0
    for off, c in chunks.items():
        buf[off:off + len(c)] = c
        have += len(c)
    return total, bytes(buf), lines, have


def entropy(b):
    if not b:
        return 0.0
    c = Counter(b)
    n = len(b)
    return -sum(v / n * math.log2(v / n) for v in c.values())


def ranges(flags, want):
    out, start = [], None
    for i, f in enumerate(flags + [None]):
        if f == want and start is None:
            start = i
        elif f != want and start is not None:
            out.append((start, i))
            start = None
    return out


def fmt_ranges(rs, limit=24):
    s = ", ".join("0x%x-0x%x" % (a, b - 1) if b - a > 1 else "0x%x" % a for a, b in rs[:limit])
    if len(rs) > limit:
        s += ", ...(+%d)" % (len(rs) - limit)
    return s or "-"


def collect(capture):
    msgs, _ = parse_file(capture)
    sb = [m for m in msgs if m.ep == 0x08]
    mp = marks_path_for(capture)
    marks = load_marks(mp) if os.path.exists(mp) else []
    rows = load_index(capture, 0x08)
    res = []
    for att in attempts(sb):
        lo, hi = att[0].lineno, att[-1].lineno
        cls = classify(att, marks)
        groups = OrderedDict()
        for r in rows:
            ln = r["msg"]["lineno"]
            if lo <= ln <= hi and r["msg"]["tag"] in (0xFC, 0xFD, 0xFE):
                key = (r["dir"], r["buf"], r["msg"]["type"])
                groups.setdefault(key, []).append(r)
        payloads = {}
        for key, reads in groups.items():
            a = assemble(reads)
            if a:
                payloads[key] = a
        res.append({"lo": lo, "hi": hi, "cls": cls, "label": label_at(marks, att[0].ts), "payloads": payloads})
    return res


def analyse_key(key, items, out, max_hex):
    """items : liste de (tentative, (total, bytes, lines, have))."""
    d, buf, t = key
    out.append("## %s %s TYPE=0x%02x : %d tentatives" % (d, buf, t, len(items)))
    for att, (total, b, lines, have) in items:
        out.append("  L%-5d %-5s %-10s total=0x%x lu=0x%x lignes=%s ent=%.2f" % (
            att["lo"], att["cls"], att["label"], total, have, ",".join(map(str, lines)), entropy(b)))
    totals = set(x[1][0] for x in items)
    n = min(x[1][3] for x in items)  # octets réellement lus partout
    if n == 0:
        out.append("  (charge vide)")
        return
    if len(totals) > 1:
        out.append("  longueurs différentes : %s ; comparaison sur les 0x%x premiers octets" % (
            sorted(hex(x) for x in totals), n))
    by = {}
    for att, p in items:
        by.setdefault(att["cls"], []).append(p[1][:n])
    allb = [p[1][:n] for _, p in items]
    flags = []
    for i in range(n):
        col = set(x[i] for x in allb)
        if len(col) == 1:
            flags.append("C")
            continue
        g = set(x[i] for x in by.get("good", []))
        bd = set(x[i] for x in by.get("bad", []))
        if len(g) == 1 and len(bd) == 1 and g != bd and len(by.get("good", [])) >= 2 and len(by.get("bad", [])) >= 1:
            flags.append("D")
        else:
            flags.append("V")
    cnt = Counter(flags)
    out.append("  sur 0x%x octets : constants=%d discriminants good/bad=%d variables=%d" % (
        n, cnt["C"], cnt["D"], cnt["V"]))
    out.append("  constants : " + fmt_ranges(ranges(flags, "C")))
    out.append("  discriminants : " + fmt_ranges(ranges(flags, "D")))
    out.append("  variables : " + fmt_ranges(ranges(flags, "V")))
    # entropie par fenêtre de 64 octets, moyenne sur les tentatives
    ents = []
    for w in range(0, n, 64):
        e = sum(entropy(x[w:w + 64]) for x in allb) / len(allb)
        ents.append("%x:%.1f" % (w, e))
    if len(ents) > 16:
        vals = [float(e.split(":")[1]) for e in ents]
        out.append("  entropie/64o (moyenne) : %d fenêtres, min=%.1f max=%.1f médiane=%.1f ; fenêtres < 5.0 : %s" % (
            len(vals), min(vals), max(vals), sorted(vals)[len(vals) // 2], " ".join(e for e, v in zip(ents, vals) if v < 5.0) or "-"))
    else:
        out.append("  entropie/64o (moyenne) : " + " ".join(ents))
    # hexdump des zones discriminantes et du début de charge
    for a, b in ranges(flags, "D")[:max_hex]:
        out.append("  D 0x%x-0x%x :" % (a, b - 1))
        for att, p in items:
            out.append("     L%-5d %-5s %s" % (att["lo"], att["cls"], p[1][a:b].hex(" ")))


def render(capture, max_hex, dump_dir):
    res = collect(capture)
    out = ["# ool_attempts : %s" % capture,
           "# classes : " + ", ".join("L%d=%s(%s)" % (a["lo"], a["cls"], a["label"]) for a in res), ""]
    keys = []
    for a in res:
        for k in a["payloads"]:
            if k not in keys:
                keys.append(k)
    for k in keys:
        items = [(a, a["payloads"][k]) for a in res if k in a["payloads"]]
        analyse_key(k, items, out, max_hex)
        out.append("")
        if dump_dir:
            for a, p in items:
                fn = "L%05d_%s_%s%s_%02x.bin" % (a["lo"], a["cls"], "in" if k[0] == ">" else "out", k[1], k[2])
                with open(os.path.join(dump_dir, fn), "wb") as f:
                    f.write(p[1])
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("capture")
    ap.add_argument("--max-hex", type=int, default=12)
    ap.add_argument("--dump-dir", help="écrit les charges recollées (sous analysis/out/ uniquement)")
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    dd = None
    if a.dump_dir:
        dd = safe_output_path(a.dump_dir)
        os.makedirs(dd, exist_ok=True)
    text = render(a.capture, a.max_hex, dd)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
