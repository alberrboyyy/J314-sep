#!/usr/bin/env python3
"""Parse une trace SEP (format défini dans .claude/agents/tracer.md) et produit des stats.

Format attendu, une ligne par message :
    <timestamp> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=...]
  - timestamp : entier ou flottant
  - dir       : '>' (AP -> SEP) ou '<' (SEP -> AP)
  - EP/TAG/TYPE/PARAM : 8 bits ; DATA : 32 bits (doc Asahi : bits 32-63)
  - ool       : optionnel, valeur opaque gardée en chaîne (tout le reste de la ligne)

Les lignes vides et les lignes commençant par '#' sont comptées comme commentaires
(compte affiché). Toute autre ligne hors format est comptée comme invalide et les 5
premières sont affichées avec leur numéro de ligne.

Stdlib uniquement. Lecture seule sur traces/ ; écritures uniquement sous analysis/out/.

Usage :
    python3 analysis/parse_trace.py <trace.log | dossier> [--ep 0x08,0x12] [--json] [-o analysis/out/x.txt]
                                    [--between <étiq1> <étiq2>]

--between : limite les stats aux messages dont le timestamp est dans [t(étiq1), t(étiq2)], bornes
incluses, d'après <dossier de capture>/marks.txt (écrit par tools/mark.sh : "<epoch> <étiquette>",
même horloge PC que le tracer). t(étiq1) = 1re occurrence de étiq1 ; t(étiq2) = 1re occurrence de
étiq2 à t >= t(étiq1). Les numéros de ligne restent ceux de la trace complète.
"""

import argparse
import json
import os
import re
import sys
from collections import namedtuple

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO_ROOT, "analysis", "out")
TRACES_DIR = os.path.join(REPO_ROOT, "traces")

Message = namedtuple("Message", "lineno ts dir ep tag type param data ool")
BadLine = namedtuple("BadLine", "lineno text reason")

LINE_RE = re.compile(
    r"^\s*(?P<ts>[0-9]+(?:\.[0-9]*)?)\s+(?P<dir>[<>])"
    r"\s+EP=0x(?P<ep>[0-9a-fA-F]+)"
    r"\s+TAG=0x(?P<tag>[0-9a-fA-F]+)"
    r"\s+TYPE=0x(?P<type>[0-9a-fA-F]+)"
    r"\s+PARAM=0x(?P<param>[0-9a-fA-F]+)"
    r"\s+DATA=0x(?P<data>[0-9a-fA-F]+)"
    r"(?:\s+ool=(?P<ool>.*?))?\s*$"
)

FIELD_MAX = {"ep": 0xFF, "tag": 0xFF, "type": 0xFF, "param": 0xFF, "data": 0xFFFFFFFF}

DIR_LABEL = {">": "AP->SEP", "<": "SEP->AP"}


def resolve_trace_path(path):
    """Un dossier de capture -> <dossier>/sep.log (sortie de hv/trace_sep_filtered.py),
    à défaut <dossier>/trace.log ; sinon le fichier tel quel."""
    if os.path.isdir(path):
        sep = os.path.join(path, "sep.log")
        return sep if os.path.exists(sep) else os.path.join(path, "trace.log")
    return path


def parse_line(line):
    """Retourne (dict de champs, None) ou (None, raison)."""
    m = LINE_RE.match(line)
    if not m:
        return None, "format non reconnu"
    fields = {}
    for name, maxval in FIELD_MAX.items():
        val = int(m.group(name), 16)
        if val > maxval:
            return None, "%s=0x%x hors plage (max 0x%x)" % (name.upper(), val, maxval)
        fields[name] = val
    ts_txt = m.group("ts")
    fields["ts"] = float(ts_txt) if "." in ts_txt else int(ts_txt)
    fields["dir"] = m.group("dir")
    fields["ool"] = m.group("ool")
    return fields, None


def parse_file(path):
    """Parse une trace. Retourne (messages, bad_lines).

    messages  : liste de Message (lineno commence à 1)
    bad_lines : liste de BadLine (lignes non vides, non commentaires, hors format)
    Les commentaires/lignes vides ne sont dans aucune des deux listes ; voir
    parse_file_full() pour leur compte.
    """
    messages, bad, _ = parse_file_full(path)
    return messages, bad


def parse_file_full(path):
    """Comme parse_file mais retourne aussi le nombre de lignes vides/commentaires."""
    path = resolve_trace_path(path)
    messages, bad = [], []
    comments = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.rstrip("\r\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                comments += 1
                continue
            fields, reason = parse_line(line)
            if fields is None:
                bad.append(BadLine(lineno, line, reason))
                continue
            messages.append(Message(lineno=lineno, **fields))
    return messages, bad, comments


MARKS_NAME = "marks.txt"
Mark = namedtuple("Mark", "lineno ts label")


def marks_path_for(path):
    """marks.txt du dossier de capture (dossier passé, ou dossier du fichier trace)."""
    d = path if os.path.isdir(path) else os.path.dirname(os.path.abspath(path))
    return os.path.join(d, MARKS_NAME)


def load_marks(path):
    """Lit marks.txt. Lignes '<ts> <étiquette>' ; '#' et vides ignorées. ValueError si hors format."""
    marks = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for lineno, raw in enumerate(f, 1):
            s = raw.strip()
            if not s or s.startswith("#"):
                continue
            parts = s.split()
            if len(parts) != 2:
                raise ValueError("%s:%d : ligne hors format : %r" % (path, lineno, s))
            try:
                ts = float(parts[0])
            except ValueError:
                raise ValueError("%s:%d : timestamp invalide : %r" % (path, lineno, parts[0]))
            marks.append(Mark(lineno, ts, parts[1]))
    return marks


def find_window(marks, start_label, end_label):
    """Retourne (Mark début, Mark fin). ValueError si une étiquette manque."""
    start = next((m for m in marks if m.label == start_label), None)
    if start is None:
        raise ValueError("étiquette absente de marks.txt : %r (connues : %s)"
                         % (start_label, ", ".join(sorted({m.label for m in marks})) or "aucune"))
    end = next((m for m in marks if m.label == end_label and m.ts >= start.ts), None)
    if end is None:
        raise ValueError("étiquette %r absente de marks.txt après %r (t=%.6f)"
                         % (end_label, start_label, start.ts))
    return start, end


def filter_window(messages, t_start, t_end):
    return [m for m in messages if t_start <= m.ts <= t_end]


def parse_ep_list(text):
    """'0x08,0x12' -> {8, 18}. Accepte aussi le décimal et les espaces."""
    if not text:
        return None
    eps = set()
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        val = int(part, 0)
        if not 0 <= val <= 0xFF:
            raise argparse.ArgumentTypeError("endpoint hors plage : %s" % part)
        eps.add(val)
    return eps


def filter_eps(messages, eps):
    if eps is None:
        return messages
    return [m for m in messages if m.ep in eps]


def _new_entry(m):
    return {"count": 0, "first_ts": m.ts, "first_line": m.lineno,
            "last_ts": m.ts, "last_line": m.lineno, "_data": set()}


def _update(entry, m):
    entry["count"] += 1
    entry["last_ts"] = m.ts
    entry["last_line"] = m.lineno
    entry["_data"].add(m.data)


def compute_stats(messages):
    """Stats par ep, (ep,dir,type), (ep,dir,type,param). Ordre = première apparition."""
    by_ep, by_type, by_param = {}, {}, {}
    for m in messages:
        for table, key in ((by_ep, (m.ep,)),
                           (by_type, (m.ep, m.dir, m.type)),
                           (by_param, (m.ep, m.dir, m.type, m.param))):
            if key not in table:
                table[key] = _new_entry(m)
            _update(table[key], m)
    for table in (by_ep, by_type, by_param):
        for e in table.values():
            e["distinct_data"] = len(e.pop("_data"))
    return {"by_ep": by_ep, "by_type": by_type, "by_param": by_param}


def key_str(key):
    parts = ["EP=0x%02x" % key[0]]
    if len(key) > 1:
        parts.append(key[1])
    if len(key) > 2:
        parts.append("TYPE=0x%02x" % key[2])
    if len(key) > 3:
        parts.append("PARAM=0x%02x" % key[3])
    return " ".join(parts)


def _sorted_items(table):
    return sorted(table.items(), key=lambda kv: kv[0])


def format_text(path, messages, bad, comments, stats, eps, window=None):
    out = []
    out.append("# Trace : %s" % resolve_trace_path(path))
    if window:
        s, e = window
        out.append("# Fenêtre : %s (%.6f, marks L%d) -> %s (%.6f, marks L%d), %.3f s"
                   % (s.label, s.ts, s.lineno, e.label, e.ts, e.lineno, e.ts - s.ts))
    out.append("# Filtre EP : %s" % (",".join("0x%02x" % e for e in sorted(eps)) if eps else "aucun"))
    out.append("# Messages : %d   lignes invalides : %d   commentaires/vides : %d"
               % (len(messages), len(bad), comments))
    out.append("# 'ligne' = numéro de ligne dans la trace (pour citation). distinct_data = nb de DATA distincts.")
    if bad:
        out.append("")
        out.append("## Lignes invalides (%d, 5 premières)" % len(bad))
        for b in bad[:5]:
            out.append("  L%d [%s] %s" % (b.lineno, b.reason, b.text[:200]))
    sections = (("Par endpoint", "by_ep"),
                ("Par (endpoint, direction, type)", "by_type"),
                ("Par (endpoint, direction, type, param)", "by_param"))
    for title, name in sections:
        out.append("")
        out.append("## %s" % title)
        out.append("  %-40s %7s %9s  %-24s %-24s" % ("clé", "count", "dist_data", "premier (ts @ ligne)", "dernier (ts @ ligne)"))
        for key, e in _sorted_items(stats[name]):
            out.append("  %-40s %7d %9d  %-24s %-24s" % (
                key_str(key), e["count"], e["distinct_data"],
                "%s @ L%d" % (e["first_ts"], e["first_line"]),
                "%s @ L%d" % (e["last_ts"], e["last_line"])))
    return "\n".join(out) + "\n"


def to_json(path, messages, bad, comments, stats, eps, window=None):
    def conv(table):
        rows = []
        for key, e in _sorted_items(table):
            row = {"ep": "0x%02x" % key[0]}
            if len(key) > 1:
                row["dir"] = key[1]
            if len(key) > 2:
                row["type"] = "0x%02x" % key[2]
            if len(key) > 3:
                row["param"] = "0x%02x" % key[3]
            row.update(e)
            rows.append(row)
        return rows
    doc = {
        "trace": resolve_trace_path(path),
        "ep_filter": sorted("0x%02x" % e for e in eps) if eps else None,
        "window": ({"start": window[0]._asdict(), "end": window[1]._asdict(),
                    "duration_s": window[1].ts - window[0].ts} if window else None),
        "n_messages": len(messages),
        "n_bad_lines": len(bad),
        "n_comment_lines": comments,
        "bad_lines_sample": [b._asdict() for b in bad[:5]],
        "by_ep": conv(stats["by_ep"]),
        "by_type": conv(stats["by_type"]),
        "by_param": conv(stats["by_param"]),
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def _is_under(path, directory):
    path = os.path.realpath(path)
    directory = os.path.realpath(directory)
    return os.path.commonpath([path, directory]) == directory


def safe_output_path(path):
    """Refuse toute sortie hors analysis/out/ (et donc sous traces/)."""
    if not os.path.isabs(path):
        path = os.path.join(os.getcwd(), path)
    if _is_under(path, TRACES_DIR):
        raise ValueError("refus : écriture sous traces/ interdite (%s)" % path)
    if not _is_under(path, OUT_DIR):
        raise ValueError("refus : les sorties vont uniquement sous %s (reçu %s)" % (OUT_DIR, path))
    return path


def write_output(path, text):
    path = safe_output_path(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description="Stats d'une trace SEP.")
    ap.add_argument("trace", help="fichier trace.log ou dossier de capture")
    ap.add_argument("--ep", type=parse_ep_list, default=None, help="filtre, ex. 0x08,0x12")
    ap.add_argument("--json", action="store_true", help="sortie JSON")
    ap.add_argument("-o", "--output", help="fichier de sortie (sous analysis/out/ uniquement)")
    ap.add_argument("--between", nargs=2, metavar=("ETIQ1", "ETIQ2"),
                    help="limite aux messages entre deux repères de marks.txt (tools/mark.sh)")
    args = ap.parse_args(argv)

    if args.output:
        try:
            safe_output_path(args.output)
        except ValueError as e:
            print(e, file=sys.stderr)
            return 2

    try:
        messages, bad, comments = parse_file_full(args.trace)
    except OSError as e:
        print("erreur de lecture : %s" % e, file=sys.stderr)
        return 1
    window = None
    if args.between:
        mpath = marks_path_for(args.trace)
        if not os.path.exists(mpath):
            print("--between : pas de %s" % mpath, file=sys.stderr)
            return 2
        try:
            window = find_window(load_marks(mpath), *args.between)
        except (OSError, ValueError) as e:
            print("--between : %s" % e, file=sys.stderr)
            return 2
        messages = filter_window(messages, window[0].ts, window[1].ts)
    messages = filter_eps(messages, args.ep)
    stats = compute_stats(messages)
    render = to_json if args.json else format_text
    text = render(args.trace, messages, bad, comments, stats, args.ep, window)

    if args.output:
        p = write_output(args.output, text)
        print("écrit : %s" % p, file=sys.stderr)
    else:
        sys.stdout.write(text)
    if bad:
        print("attention : %d ligne(s) invalide(s) dans %s" % (len(bad), resolve_trace_path(args.trace)),
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
