#!/usr/bin/env python3
"""Regroupe les messages d'un endpoint (défaut EP 0x08, SBIO) en transactions et rafales.

Lecture seule sur traces/ ; sorties uniquement sous analysis/out/ (via -o).

Modèle de regroupement (OBSERVÉ dans traces/20261107-033436_c1-boot, pas une spécification) :
  - « commande » : '>' TAG=0xfc TYPE=X ouvre une transaction X ; '<' TAG=0xfc TYPE=X la ferme.
  - « fragment » : messages TAG=0xfe / TAG=0xfd de même TYPE=X. S'ils arrivent pendant une
    transaction X ouverte -> rattachés à celle-ci (variante « pendant ») ; sinon rattachés à la
    dernière transaction X fermée (variante « après »).
  - « autre » : tout le reste (TAG hors 0xfc/0xfe/0xfd), listé à part avec son numéro de ligne.
Une rafale = suite de messages séparés de moins de --gap secondes (horloge PC du tracer ; en mode
ASYNC c'est l'heure de traitement, pas l'heure exacte du message).

Usage :
    python3 analysis/sbio_transactions.py traces/<capture>/ [--ep 0x08] [--gap 2.0] [-o analysis/out/x.txt]
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, resolve_trace_path, write_output  # noqa: E402

CMD_TAG, FRAG_TAGS = 0xFC, (0xFE, 0xFD)


def hhmmss(ts):
    return time.strftime("%H:%M:%S", time.localtime(ts)) + ("%.3f" % (ts % 1))[1:]


def group(messages):
    """Retourne une liste d'événements ordonnés : ('tx', dict) ou ('other', Message)."""
    events, open_tx, last_closed = [], {}, {}
    for m in messages:
        if m.tag == CMD_TAG and m.dir == ">":
            tx = {"type": m.type, "start": m, "end": None, "frags": [], "inner": [], "frag_when": None}
            open_tx[m.type] = tx
            events.append(("tx", tx))
        elif m.tag == CMD_TAG and m.dir == "<":
            tx = open_tx.pop(m.type, None)
            if tx is None:
                events.append(("other", m))      # réponse sans commande vue
            else:
                tx["end"] = m
                last_closed[m.type] = tx
        elif m.tag in FRAG_TAGS:
            tx = open_tx.get(m.type)
            when = "pendant"
            if tx is None:
                tx, when = last_closed.get(m.type), "après"
            if tx is None:
                events.append(("other", m))
            else:
                tx["frags"].append(m)
                tx["frag_when"] = tx["frag_when"] or when
        else:
            # message hors 0xfc/0xfe/0xfd : noté « inner » des transactions ouvertes à cet instant
            for tx in open_tx.values():
                tx["inner"].append(m)
            events.append(("other", m))
    return events


def fmt_msg(m):
    return "L%d %s %s TAG=0x%02x TYPE=0x%02x PARAM=0x%02x DATA=0x%08x" % (
        m.lineno, hhmmss(m.ts), m.dir, m.tag, m.type, m.param, m.data)


def fmt_tx(tx):
    s, e = tx["start"], tx["end"]
    dur = "%.1f ms" % ((e.ts - s.ts) * 1000) if e else "NON FERMÉE"
    out = "L%d-%s %s TYPE=0x%02x  (%s)" % (s.lineno, ("L%d" % e.lineno) if e else "?", hhmmss(s.ts), tx["type"], dur)
    nz = [m for m in (s, e) if m and (m.data or m.param)]
    if nz:
        out += "  [DATA/PARAM non nuls : %s]" % ", ".join("L%d" % m.lineno for m in nz)
    if tx["frags"]:
        first = tx["frags"][0]
        out += "  frag(%s, 1er %s par %s) : %s" % (
            tx["frag_when"], "0x%02x" % first.tag, "AP" if first.dir == ">" else "SEP",
            " ".join("%s%02x:%x" % (f.dir, f.tag, f.data >> 16) for f in tx["frags"]))
    if tx["inner"]:
        out += "  pendant : " + ", ".join("L%d" % m.lineno for m in tx["inner"])
    return out


def bursts(messages, gap):
    cur = []
    for m in messages:
        if cur and m.ts - cur[-1].ts > gap:
            yield cur
            cur = []
        cur.append(m)
    if cur:
        yield cur


def render(path, ep, gap):
    msgs, _bad = parse_file(path)
    msgs = [m for m in msgs if m.ep == ep]
    lines = ["# %s  EP=0x%02x  messages=%d  gap rafale=%.1fs" % (path, ep, len(msgs), gap), ""]
    for b in bursts(msgs, gap):
        lines.append("## Rafale L%d-L%d  %s -> %s  (%d messages)" % (
            b[0].lineno, b[-1].lineno, hhmmss(b[0].ts), hhmmss(b[-1].ts), len(b)))
        for kind, x in group(b):
            lines.append(("  TX    " + fmt_tx(x)) if kind == "tx" else ("  AUTRE " + fmt_msg(x)))
        lines.append("")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("trace")
    ap.add_argument("--ep", default="0x08")
    ap.add_argument("--gap", type=float, default=2.0)
    ap.add_argument("-o", "--output")
    a = ap.parse_args(argv)
    text = render(resolve_trace_path(a.trace), int(a.ep, 0), a.gap)
    if a.output:
        write_output(a.output, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
