#!/usr/bin/env python3
"""Découpe le trafic SBIO (EP 0x08) d'une capture selon les cycles LOCKED/UNLOCKED annoncés par
macOS dans hv_uart.log, et isole les « tentatives » (séquences ouvertes par `> 0xfc TYPE=0x23`).

Lecture seule sur traces/ ; sorties uniquement sous analysis/out/ (via -o).

Pourquoi : dans C3 (traces/20261107-035930_c3-touchid) les marques de marks.txt ne coïncident pas
avec les actions (verrouillages/déverrouillages en plus). Les lignes noyau
`ACMTRM: _publish: ... LOCKED(1)|UNLOCKED(0) ... now=<epoch Mac>` donnent l'état réel de l'écran.
L'epoch Mac est comparé tel quel à l'horloge PC du tracer : décalage supposé < ~2 s (vérifié dans
C3 par ancrages CRC xART, ex. uart L3397 <-> sep L2158, voir analysis/out/c3_report.md).

Tentative (définition OBSERVÉE, pas une spécification) : de `> 0xfc 0x23` jusqu'au message
précédant le `> 0xfc 0x23` suivant, ou jusqu'à `< 0xfc 0x21` inclus. Résumé : suite des TYPE des
commandes `>` 0xfc, plus les notifications `<` hors 0xfc/0xfe/0xfd notées `[TAG/TYPE/PARAM]`.

Usage :
    python3 analysis/lock_cycles.py traces/<capture>/ [-o analysis/out/x.txt]
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, resolve_trace_path, write_output, load_marks  # noqa: E402

STATE_RE = re.compile(r"_publish: _(\w+) (LOCKED|UNLOCKED)\(\d\).*?now=(\d+)")


def hhmmss(ts):
    ms = int(round(ts * 1000))
    return time.strftime("%H:%M:%S", time.localtime(ms // 1000)) + ".%03d" % (ms % 1000)


def load_states(uart_path):
    out = []
    # Numérotation identique à `grep -n` : découpage sur \n seulement (le log contient des \r).
    with open(uart_path, "rb") as f:
        for n, raw in enumerate(f.read().split(b"\n"), 1):
            m = STATE_RE.search(raw.decode("utf-8", "replace"))
            if m:
                out.append((int(m.group(3)), m.group(2), n))
    return out


def tok(m):
    if m.tag == 0xFC:
        return "%02x" % m.type
    return "[%02x/%02x/p%x]" % (m.tag, m.type, m.param)


def attempts(sbio):
    """Liste de listes de messages, une par tentative."""
    res, cur = [], None
    for m in sbio:
        if m.tag == 0xFC and m.dir == ">" and m.type == 0x23:
            cur = [m]
            res.append(cur)
            continue
        if cur is None:
            continue
        cur.append(m)
        if m.tag == 0xFC and m.dir == "<" and m.type == 0x21:
            cur = None
    return res


def summarize(att):
    toks = []
    for m in att:
        if m.tag == 0xFC and m.dir == ">":
            toks.append(tok(m))
        elif m.tag not in (0xFC, 0xFE, 0xFD) and m.dir == "<":
            toks.append(tok(m))
    return " ".join(toks)


def label_at(marks, ts):
    lab = "-"
    for mk in marks:
        if mk.ts <= ts and not mk.label.startswith("note"):
            lab = mk.label
    return lab


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("capture")
    ap.add_argument("-o", "--output")
    a = ap.parse_args(argv)
    sep = resolve_trace_path(a.capture)
    msgs, _bad = parse_file(sep)
    sbio = [m for m in msgs if m.ep == 0x08]
    states = load_states(os.path.join(a.capture, "hv_uart.log"))
    try:
        marks = load_marks(os.path.join(a.capture, "marks.txt"))
    except (OSError, ValueError):
        marks = []

    lines = ["# lock_cycles : %s" % sep, "", "## États écran (hv_uart.log, epoch Mac)"]
    for ts, st, n in states:
        lines.append("uart L%-5d %-8s now=%d (%s)  marque PC en cours : %s" % (n, st, ts, hhmmss(ts), label_at(marks, ts)))

    lines += ["", "## Tentatives (> 0xfc 0x23 ...)",
              "début(L) | heure PC | durée ms | marque en cours | état écran (dernier now <= t) | séquence"]
    for att in attempts(sbio):
        t0, t1 = att[0].ts, att[-1].ts
        st = [s for s in states if s[0] <= t0]
        st_txt = ("%s@%d" % (st[-1][1], st[-1][0])) if st else "?"
        nxt = [s for s in states if s[0] > t0]
        nxt_txt = ("→ %s@%d" % (nxt[0][1], nxt[0][0])) if nxt else ""
        lines.append("L%d-L%d | %s | %d | %s | %s %s | %s" % (
            att[0].lineno, att[-1].lineno, hhmmss(t0), (t1 - t0) * 1000, label_at(marks, t0),
            st_txt, nxt_txt, summarize(att)))

    lines += ["", "## Notifications SBIO hors 0xfc/0xfe/0xfd"]
    for m in sbio:
        if m.tag not in (0xFC, 0xFE, 0xFD):
            st = [s for s in states if s[0] <= m.ts]
            lines.append("L%d %s %s TAG=0x%02x TYPE=0x%02x PARAM=0x%02x DATA=0x%08x | %s | %s" % (
                m.lineno, hhmmss(m.ts), m.dir, m.tag, m.type, m.param, m.data, label_at(marks, m.ts),
                ("%s@%d" % (st[-1][1], st[-1][0])) if st else "?"))
    text = "\n".join(lines) + "\n"
    if a.output:
        print("écrit :", write_output(a.output, text))
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
