#!/usr/bin/env python3
"""Compare deux captures SEP.

Par défaut : ensembles de clés (endpoint, direction, type, param) présents seulement
dans A, seulement dans B, et dans les deux avec des comptes différents.
--seq : compare en plus, par endpoint, la séquence ordonnée (dir, type, param) avec
difflib, en ignorant TAG et DATA, et affiche les blocs qui diffèrent avec les numéros
de ligne d'origine.

Une différence est une OBSERVATION, pas une interprétation.

Stdlib uniquement. Usage :
    python3 analysis/diff_traces.py <capture A> <capture B> [--ep 0x08,0x12] [--seq] [-o analysis/out/x.txt]
"""

import argparse
import difflib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import (filter_eps, parse_ep_list, parse_file, resolve_trace_path,  # noqa: E402
                         safe_output_path, write_output)

HEADER = ("# RAPPEL : une différence entre deux traces est une observation, pas une interprétation.\n"
          "# Un écart vu une seule fois peut être une coïncidence (timing, ordre non déterministe).\n")


def key4(m):
    return (m.ep, m.dir, m.type, m.param)


def fmt_key(k):
    return "EP=0x%02x %s TYPE=0x%02x PARAM=0x%02x" % k


def count_keys(messages):
    counts, first = {}, {}
    for m in messages:
        k = key4(m)
        counts[k] = counts.get(k, 0) + 1
        first.setdefault(k, m.lineno)
    return counts, first


def diff_sets(msgs_a, msgs_b):
    ca, fa = count_keys(msgs_a)
    cb, fb = count_keys(msgs_b)
    only_a = sorted(set(ca) - set(cb))
    only_b = sorted(set(cb) - set(ca))
    changed = sorted(k for k in set(ca) & set(cb) if ca[k] != cb[k])
    return {"only_a": [(k, ca[k], fa[k]) for k in only_a],
            "only_b": [(k, cb[k], fb[k]) for k in only_b],
            "changed": [(k, ca[k], cb[k], fa[k], fb[k]) for k in changed]}


def diff_sequences(msgs_a, msgs_b):
    """Par endpoint : liste de (tag_opcode, blocA, blocB), bloc = liste de Message."""
    eps = sorted({m.ep for m in msgs_a} | {m.ep for m in msgs_b})
    result = {}
    for ep in eps:
        sa = [m for m in msgs_a if m.ep == ep]
        sb = [m for m in msgs_b if m.ep == ep]
        sm = difflib.SequenceMatcher(None, [key4(m) for m in sa], [key4(m) for m in sb],
                                     autojunk=False)
        blocks = [(op, sa[i1:i2], sb[j1:j2])
                  for op, i1, i2, j1, j2 in sm.get_opcodes() if op != "equal"]
        result[ep] = {"len_a": len(sa), "len_b": len(sb), "blocks": blocks}
    return result


def _fmt_msg(m):
    return "L%-6d ts=%-14s %s TYPE=0x%02x PARAM=0x%02x" % (m.lineno, m.ts, m.dir, m.type, m.param)


def render(path_a, path_b, msgs_a, msgs_b, bad_a, bad_b, eps, seq):
    out = [HEADER.rstrip("\n")]
    out.append("# A : %s  (%d messages, %d lignes invalides)" % (resolve_trace_path(path_a), len(msgs_a), len(bad_a)))
    out.append("# B : %s  (%d messages, %d lignes invalides)" % (resolve_trace_path(path_b), len(msgs_b), len(bad_b)))
    out.append("# Filtre EP : %s" % (",".join("0x%02x" % e for e in sorted(eps)) if eps else "aucun"))
    out.append("# Lignes Lnnn = numéros de ligne dans la trace d'origine.")

    d = diff_sets(msgs_a, msgs_b)
    out.append("")
    out.append("## Seulement dans A (%d)" % len(d["only_a"]))
    for k, c, ln in d["only_a"]:
        out.append("  %-42s count=%d  première: A L%d" % (fmt_key(k), c, ln))
    out.append("")
    out.append("## Seulement dans B (%d)" % len(d["only_b"]))
    for k, c, ln in d["only_b"]:
        out.append("  %-42s count=%d  première: B L%d" % (fmt_key(k), c, ln))
    out.append("")
    out.append("## Dans les deux, comptes différents (%d)" % len(d["changed"]))
    for k, ca, cb, la, lb in d["changed"]:
        out.append("  %-42s A=%d B=%d  premières: A L%d, B L%d" % (fmt_key(k), ca, cb, la, lb))

    if seq:
        out.append("")
        out.append("## Séquences par endpoint (TAG et DATA ignorés)")
        for ep, r in diff_sequences(msgs_a, msgs_b).items():
            if not r["blocks"]:
                out.append("  EP=0x%02x : séquences identiques (%d messages)" % (ep, r["len_a"]))
                continue
            out.append("  EP=0x%02x : %d bloc(s) différent(s) (A=%d, B=%d messages)"
                       % (ep, len(r["blocks"]), r["len_a"], r["len_b"]))
            for op, ba, bb in r["blocks"]:
                out.append("    [%s]" % op)
                for m in ba:
                    out.append("      - A %s" % _fmt_msg(m))
                for m in bb:
                    out.append("      + B %s" % _fmt_msg(m))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Diff de deux captures SEP (observation, pas interprétation).")
    ap.add_argument("a", help="capture A (trace.log ou dossier)")
    ap.add_argument("b", help="capture B (trace.log ou dossier)")
    ap.add_argument("--ep", type=parse_ep_list, default=None, help="filtre, ex. 0x08,0x12")
    ap.add_argument("--seq", action="store_true", help="diff des séquences ordonnées par endpoint")
    ap.add_argument("-o", "--output", help="fichier de sortie (sous analysis/out/ uniquement)")
    args = ap.parse_args(argv)

    if args.output:
        try:
            safe_output_path(args.output)
        except ValueError as e:
            print(e, file=sys.stderr)
            return 2
    try:
        msgs_a, bad_a = parse_file(args.a)
        msgs_b, bad_b = parse_file(args.b)
    except OSError as e:
        print("erreur de lecture : %s" % e, file=sys.stderr)
        return 1
    msgs_a = filter_eps(msgs_a, args.ep)
    msgs_b = filter_eps(msgs_b, args.ep)
    text = render(args.a, args.b, msgs_a, msgs_b, bad_a, bad_b, args.ep, args.seq)
    if args.output:
        print("écrit : %s" % write_output(args.output, text), file=sys.stderr)
    else:
        sys.stdout.write(text)
    for name, bad, p in (("A", bad_a, args.a), ("B", bad_b, args.b)):
        if bad:
            print("attention : %d ligne(s) invalide(s) dans %s (%s) ; voir parse_trace.py"
                  % (len(bad), name, resolve_trace_path(p)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
