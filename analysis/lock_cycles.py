#!/usr/bin/env python3
"""Découpe le trafic SBIO (EP 0x08) d'une capture selon les cycles LOCKED/UNLOCKED annoncés par
macOS dans hv_uart.log, et isole les « tentatives » (séquences ouvertes par `> 0xfc TYPE=0x23`).

Lecture seule sur traces/ ; sorties uniquement sous analysis/out/ (via -o).

Pourquoi : dans C3 (traces/20261107-035930_c3-touchid) les marques de marks.txt ne coïncident pas
avec les actions (verrouillages/déverrouillages en plus). Les lignes noyau
`ACMTRM: _publish: ... LOCKED(1)|UNLOCKED(0) ... now=<epoch Mac>` donnent l'état réel de l'écran.
`now=N(B)` : epoch Mac = N + B (C3 : N = epoch, B = 0 ; C8 : N = secondes, B = base) ; une valeur
< 1e9 (ex. C8 `now=504(0)`) est ignorée. Conversion Mac -> PC (`--mac-offset`, défaut auto) : décalage
et dérive mesurés par uart_timeline.mac_clock_anchors sur les ancrages primaires ; ignorée si < 2 s
(cas C3/C1, sortie inchangée) ; C8 : PC − Mac ≈ +71546 s, dérive ~0.8 s/100 s. Précision ±1 s.

Tentative (définition OBSERVÉE, pas une spécification) : de `> 0xfc 0x23` jusqu'au message
précédant le `> 0xfc 0x23` suivant, ou jusqu'à `< 0xfc 0x21` inclus. Résumé : suite des TYPE des
commandes `>` 0xfc, plus les notifications `<` hors 0xfc/0xfe/0xfd notées `[TAG/TYPE/PARAM]`.

Usage :
    python3 analysis/lock_cycles.py traces/<capture>/ [--mac-offset auto|<s>] [-o analysis/out/x.txt]
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, resolve_trace_path, write_output, load_marks  # noqa: E402

STATE_RE = re.compile(r"_publish: _(\w+) (LOCKED|UNLOCKED)\(\d\).*?now=(\d+)(?:\((\d+)\))?")
EPOCH_MIN = 10 ** 9  # en dessous : pas un epoch (secondes depuis le boot sans base connue)


def state_epoch(now, base):
    """Epoch Mac d'une ligne ACMTRM `now=N(B)`.

    Formes observées : C3 `now=1794020395(0)` (N = epoch, B = 0) ; C8 `now=739(1794023194)`
    (N = secondes, B = epoch de référence, epoch = N + B ; vu aussi par lecteur-logs, voir
    analysis/out/c8_uart_align.md §1) ; C8 `now=504(0)` (ni l'un ni l'autre) -> None."""
    e = now + (base or 0)
    return e if e >= EPOCH_MIN else None


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
                e = state_epoch(int(m.group(3)), int(m.group(4)) if m.group(4) else 0)
                if e is not None:
                    out.append((e, m.group(2), n))
    return out


def mac_to_pc_fn(capture, mode):
    """Conversion horloge Mac -> horloge PC. mode : 'auto' (décalage + dérive mesurés par
    uart_timeline sur les ancrages primaires ; à défaut décalage nul), ou un nombre de secondes
    (PC - Mac). Retourne (fonction, description)."""
    if mode != "auto":
        off = float(mode)
        return (lambda mac: mac + off), "décalage fixe PC-Mac = %+.1f s" % off
    try:
        import uart_timeline as ut
        msgs, _ = parse_file(resolve_trace_path(capture))
        uart = ut.read_uart(os.path.join(capture, "hv_uart.log"))
        prim, _rej = ut.find_anchors(msgs, uart)
        _sec, ab, pts = ut.mac_clock_anchors(uart, prim)
    except Exception as e:  # outil absent ou capture sans ancrage : comportement C3
        return (lambda mac: mac), "décalage nul (estimation impossible : %s)" % e
    if not ab:
        return (lambda mac: mac), "décalage nul (moins de 2 points de mesure)"
    a, b = ab
    offs = [a + b * p[0] for p in pts]  # décalage PC-Mac aux points de mesure
    if max(abs(o) for o in offs) < 2.0:
        return (lambda mac: mac), "décalage mesuré < 2 s (%+.1f..%+.1f, %d points), ignoré" % (
            min(offs), max(offs), len(pts))
    return ((lambda mac: (mac + 0.5 + a) / (1 - b)),
            "PC = Mac + décalage %+.1f..%+.1f s (dérive %.2f s/100 s), %d points (uart_timeline, ±1 s)" % (
                min(offs), max(offs), b * 100, len(pts)))


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
    ap.add_argument("--mac-offset", default="auto",
                    help="'auto' (défaut) ou secondes PC-Mac ; 0 = comparaison directe (C3)")
    a = ap.parse_args(argv)
    sep = resolve_trace_path(a.capture)
    msgs, _bad = parse_file(sep)
    sbio = [m for m in msgs if m.ep == 0x08]
    to_pc, conv = mac_to_pc_fn(a.capture, a.mac_offset)
    states = [(int(round(to_pc(e))), st, n) for e, st, n in load_states(os.path.join(a.capture, "hv_uart.log"))]
    try:
        marks = load_marks(os.path.join(a.capture, "marks.txt"))
    except (OSError, ValueError):
        marks = []

    lines = ["# lock_cycles : %s" % sep, "# horloge : %s" % conv, "",
             "## États écran (hv_uart.log, epoch Mac ramené à l'horloge PC)"]
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
