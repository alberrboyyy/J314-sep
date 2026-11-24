#!/usr/bin/env python3
"""Séquence EP 0x12 (SKS) d'une capture, requêtes appariées aux réponses, avec longueurs fil.

Le mot mailbox 0x12 ne porte PAS le contenu (celui-ci est dans l'OOL A/B, non capturé pour 0x12) :
ce script travaille donc sur les seuls champs du mot : TAG (opération), TYPE (compteur de txn),
PARAM (statut en réponse), et DATA>>16 (longueur fil en octets).

Appariement : une réponse `< TAG=(req|0x80)` même TYPE suit sa requête `>`. Les `< TAG<0x80` sans
requête sont des NOTIFICATIONS (lock/unlock). Sortie : une ligne par message dans l'ordre du fil.

Usage :
    python3 analysis/ep12_sequence.py traces/<capture>/ [--limit N] [--cmp traces/<autre>/]
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_line, resolve_trace_path  # noqa: E402


def seq(capture):
    log = resolve_trace_path(capture)
    rows = []
    with open(log, "r", encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if line.startswith("#"):
                continue
            fields, _ = parse_line(line)
            if not fields or fields.get("ep") != 0x12:
                continue
            fields["lineno"] = n
            fields["len"] = (fields["data"] >> 16) & 0xFFFF
            rows.append(fields)
    return rows


def render(capture, limit=None):
    rows = seq(capture)
    out = ["# EP 0x12 %s : %d messages" % (capture, len(rows))]
    out.append("line   dir TAG   TYPE  PARAM  len(o)   note")
    # pair up
    pend = {}
    shown = 0
    for r in rows:
        if r["dir"] == ">":
            note = "req"
            pend[(r["tag"], r["type"])] = r
        else:
            if r["tag"] & 0x80:
                req = pend.pop((r["tag"] & 0x7F, r["type"]), None)
                note = "resp(req@%d)" % req["lineno"] if req else "resp(unpaired)"
            else:
                note = "NOTIF tag=0x%02x" % r["tag"]
        out.append("%-6d %s   0x%02x  0x%02x  0x%02x   0x%-5x  %s" % (
            r["lineno"], r["dir"], r["tag"], r["type"], r["param"], r["len"], note))
        shown += 1
        if limit and shown >= limit:
            out.append("... (%d messages restants)" % (len(rows) - shown))
            break
    return "\n".join(out) + "\n", rows


def cmp_by_tag(a_rows, b_rows, a_name, b_name):
    """Pour chaque TAG, l'ensemble des longueurs fil vues en requête et en réponse, dans les 2 traces."""
    def agg(rows):
        d = {}
        for r in rows:
            base = r["tag"] & 0x7F if (r["dir"] == "<" and r["tag"] & 0x80) else r["tag"]
            key = (base, r["dir"])
            d.setdefault(key, {}).setdefault(r["len"], 0)
            d[key][r["len"]] += 1
        return d
    da, db = agg(a_rows), agg(b_rows)
    keys = sorted(set(da) | set(db))
    out = ["# Comparaison longueurs fil par (TAG, sens) : %s vs %s" % (a_name, b_name),
           "TAG   dir  %-28s %-28s  verdict_longueur" % (a_name, b_name)]
    for k in keys:
        tag, d = k
        la = da.get(k, {})
        lb = db.get(k, {})
        sa = " ".join("0x%x×%d" % (ln, c) for ln, c in sorted(la.items())) or "-"
        sb = " ".join("0x%x×%d" % (ln, c) for ln, c in sorted(lb.items())) or "-"
        set_a, set_b = set(la), set(lb)
        if set_a and set_b:
            v = "IDENTIQUE" if set_a == set_b else "DIFFERE"
        else:
            v = "absent d'une trace"
        out.append("0x%02x  %s   %-28s %-28s  %s" % (tag, d, sa, sb, v))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("capture")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--cmp")
    a = ap.parse_args(argv)
    text, rows = render(a.capture, a.limit)
    sys.stdout.write(text)
    if a.cmp:
        brows = seq(a.cmp)
        sys.stdout.write("\n" + cmp_by_tag(rows, brows, a.capture, a.cmp))


if __name__ == "__main__":
    main()
