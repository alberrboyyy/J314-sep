#!/usr/bin/env python3
"""Compare, message par message (dir/TAG/TYPE/PARAM/DATA), les tentatives SBIO d'une capture à une
séquence de référence prise dans une autre capture (lecture seule sur traces/).

Tentative = découpage de lock_cycles.attempts() (de `> 0xfc 0x23` au `< 0xfc 0x21` inclus).
Référence = N messages EP 0x08 à partir d'une ligne donnée d'une capture de référence
(défaut : C3 L2147, 25 messages = la séquence « bon doigt » vue 8× dans C3).

Usage :
    python3 analysis/attempt_compare.py traces/<capture>/ [--ref traces/<C3>/ --ref-line 2147 --ref-n 25] [-o analysis/out/x.txt]
"""

import argparse
import difflib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, write_output, load_marks, marks_path_for  # noqa: E402
from lock_cycles import attempts, label_at  # noqa: E402

C3 = "traces/20261107-035930_c3-touchid"


def word(m):
    return "%s %02x/%02x/p%x/%x" % (m.dir, m.tag, m.type, m.param, m.data)


def ref_seq(path, line, n):
    msgs, _ = parse_file(path)
    sb = [m for m in msgs if m.ep == 0x08 and m.lineno >= line]
    return sb[:n]


def render(path, ref, ref_line, ref_n):
    msgs, _ = parse_file(path)
    sb = [m for m in msgs if m.ep == 0x08]
    mp = marks_path_for(path)
    marks = load_marks(mp) if os.path.exists(mp) else []
    rs = ref_seq(ref, ref_line, ref_n)
    rw = [word(m) for m in rs]
    out = ["# attempt_compare : %s" % path,
           "# référence : %s L%d, %d messages EP 0x08 : %s" % (ref, ref_line, len(rs), " | ".join(rw)), ""]
    for att in attempts(sb):
        w = [word(m) for m in att]
        lab = label_at(marks, att[0].ts) if marks else "-"
        same = (w == rw)
        out.append("## L%d-L%d marque=%s n=%d identique_ref=%s" % (att[0].lineno, att[-1].lineno, lab, len(w), same))
        if not same:
            sm = difflib.SequenceMatcher(a=rw, b=w, autojunk=False)
            for op, i1, i2, j1, j2 in sm.get_opcodes():
                if op == "equal":
                    continue
                out.append("  %s ref[%d:%d]=%s  ->  ici[%d:%d]=%s (L%s)" % (
                    op, i1, i2, rw[i1:i2], j1, j2, w[j1:j2],
                    ",".join(str(att[k].lineno) for k in range(j1, j2)) or "-"))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("path")
    ap.add_argument("--ref", default=C3)
    ap.add_argument("--ref-line", type=int, default=2147)
    ap.add_argument("--ref-n", type=int, default=25)
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    text = render(a.path, a.ref, a.ref_line, a.ref_n)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
