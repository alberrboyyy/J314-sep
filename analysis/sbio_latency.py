#!/usr/bin/env python3
"""Latence requête -> réponse des commandes SBIO TAG 0xfc, par capture (lecture seule sur traces/).

Paire = `> EP TAG=0xfc TYPE=X` puis le premier `< EP TAG=0xfc TYPE=X` qui suit (définition observée
dans C1 : aucune commande en suspens). Latence = différence d'horodatage PC du tracer (pas l'horloge
du Mac). Sous SYNC, l'horodatage `>` est pris quand le tracer voit l'écriture INBOX ; il inclut donc
le coût de lecture OOL côté `>`.

Les commandes « longues » (0x09, 0x5b, 0x37, ...) faussent la moyenne : on donne aussi la médiane et
les stats restreintes aux paires < --fast-ms (défaut 10 ms) et sans fragment 0xfe/0xfd intercalé.

Usage :
    python3 analysis/sbio_latency.py traces/<A>/ [traces/<B>/ ...] [--ep 0x08] [--fast-ms 10] [-o analysis/out/x.txt]
"""

import argparse
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, write_output  # noqa: E402


def pairs(msgs, ep):
    """Liste de (type, latence_ms, ligne_req, ligne_rep, fragments_intercalés)."""
    sb = [m for m in msgs if m.ep == ep]
    out = []
    pending = {}
    frag = {}
    for m in sb:
        if m.tag == 0xFC and m.dir == ">":
            pending[m.type] = m
            frag[m.type] = 0
        elif m.tag in (0xFE, 0xFD) and m.type in pending:
            frag[m.type] += 1
        elif m.tag == 0xFC and m.dir == "<" and m.type in pending:
            r = pending.pop(m.type)
            out.append((m.type, (m.ts - r.ts) * 1000.0, r.lineno, m.lineno, frag.pop(m.type)))
    return out


def fmt_stats(vals):
    if not vals:
        return "n=0"
    return "n=%d médiane=%.2f moyenne=%.2f min=%.2f max=%.2f" % (
        len(vals), statistics.median(vals), statistics.mean(vals), min(vals), max(vals))


def render(paths, ep, fast_ms):
    lines = []
    per = {}
    for p in paths:
        msgs, _ = parse_file(p)
        pr = pairs(msgs, ep)
        allv = [x[1] for x in pr]
        fast = [x[1] for x in pr if x[1] < fast_ms and x[4] == 0]
        lines.append("## %s (EP 0x%02x)" % (p, ep))
        lines.append("toutes paires      : " + fmt_stats(allv))
        lines.append("rapides (<%g ms, sans fragment) : " % fast_ms + fmt_stats(fast))
        lt50 = [x[1] for x in pr if x[1] < 50.0]
        lines.append("paires < 50 ms (définition reconstituée des chiffres C3 2.35 / C6 7.36 / C7 ~2.5) : " + fmt_stats(lt50))
        bytype = {}
        for t, v, _, _, fr in pr:
            if fr == 0:
                bytype.setdefault(t, []).append(v)
        per[p] = bytype
        lines.append("par TYPE (sans fragment), médiane ms :")
        for t in sorted(bytype):
            v = bytype[t]
            lines.append("  0x%02x  n=%-3d med=%.2f min=%.2f max=%.2f" % (t, len(v), statistics.median(v), min(v), max(v)))
        lines.append("")
    if len(paths) > 1:
        lines.append("## Comparaison par TYPE (médiane ms, paires sans fragment ; '-' = absent)")
        types = sorted(set(t for b in per.values() for t in b))
        lines.append("TYPE  " + "  ".join("%-22s" % os.path.basename(os.path.normpath(p))[:22] for p in paths))
        for t in types:
            cells = []
            for p in paths:
                v = per[p].get(t)
                cells.append("%-22s" % ("-" if not v else "%.2f (n=%d)" % (statistics.median(v), len(v))))
            lines.append("0x%02x  " % t + "  ".join(cells))
        lines.append("")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--ep", default="0x08")
    ap.add_argument("--fast-ms", type=float, default=10.0)
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    text = render(a.paths, int(a.ep, 0), a.fast_ms)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
