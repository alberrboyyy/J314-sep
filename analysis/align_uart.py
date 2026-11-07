#!/usr/bin/env python3
"""Cherche des points d'ancrage entre sep.log (horloge PC) et hv_uart.log (log noyau macOS, sans
horodatage PC) d'une même capture. Lecture seule sur traces/ ; sorties sous analysis/out/ (-o).

Ancrages cherchés (chaque correspondance est une OBSERVATION de valeurs égales, pas une preuve
de causalité ; la règle de correspondance elle-même est une hypothèse) :
  A. xART  : hv_uart « Replied to xART app: 0x....XX13 » (octet bas 0x13 = EP, octet suivant = XX)
             <-> sep.log '>' EP=0x13 TAG=XX (réponse AP). Rapprochement par TAG seul.
  B. CRC   : hv_uart « ... with CRC: 0xNNNN » <-> sep.log '<' EP=0x13 avec DATA>>16 == NNNN.
  C. handle: hv_uart « handle -N » <-> sep.log '<' EP=0x12 TAG=0x00 avec DATA == (-N) mod 2^32.
  D. epoch : lignes hv_uart contenant un epoch Unix (now=..., seen=..., startTime=..., now NNN)
             -> listées avec leur numéro de ligne (horloge du Mac, pas du PC).

Usage :
    python3 analysis/align_uart.py traces/<capture>/ [-o analysis/out/x.txt]
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, write_output  # noqa: E402

XART_RE = re.compile(r"Replied to xART app: 0x([0-9a-fA-F]{16})")
CRC_RE = re.compile(r"with CRC: 0x([0-9a-fA-F]+)")
HANDLE_RE = re.compile(r"handle (-[0-9]+)")
EPOCH_RE = re.compile(r"(?:now=|seen=|startTime=|now |time\(\d\) \d+->)(1[0-9]{9})")


def hhmmss(ts):
    return time.strftime("%H:%M:%S", time.localtime(ts)) + ("%.3f" % (ts % 1))[1:]


def read_uart(path):
    # Découpage sur '\n' uniquement, pour que les numéros de ligne correspondent à grep -n.
    with open(path, "rb") as f:
        raw = f.read().decode("utf-8", errors="replace")
    return raw.split("\n")


def anchors(capture):
    msgs, _ = parse_file(os.path.join(capture, "sep.log"))
    uart = read_uart(os.path.join(capture, "hv_uart.log"))
    ep13_ap = {}
    ep13_crc = {}
    ep12_handle = {}
    for m in msgs:
        if m.ep == 0x13 and m.dir == ">":
            ep13_ap.setdefault(m.tag, []).append(m)
        if m.ep == 0x13 and m.dir == "<":
            ep13_crc.setdefault(m.data >> 16, []).append(m)
        if m.ep == 0x12 and m.dir == "<" and m.tag == 0x00:
            ep12_handle.setdefault(m.data, []).append(m)

    out = []
    for i, line in enumerate(uart, 1):
        mx = XART_RE.search(line)
        if mx:
            val = int(mx.group(1), 16)
            if val & 0xFF == 0x13:
                tag = (val >> 8) & 0xFF
                c = ep13_ap.get(tag, [])
                out.append(("A", i, "xART TAG=0x%02x" % tag, c))
        mc = CRC_RE.search(line)
        if mc:
            crc = int(mc.group(1), 16)
            out.append(("B", i, "CRC 0x%04x" % crc, ep13_crc.get(crc, [])))
        for mh in HANDLE_RE.finditer(line):
            h = int(mh.group(1)) & 0xFFFFFFFF
            out.append(("C", i, "handle %s (0x%08x)" % (mh.group(1), h), ep12_handle.get(h, [])))
        me = EPOCH_RE.search(line)
        if me:
            out.append(("D", i, "epoch Mac %s (%s)" % (me.group(1), hhmmss(int(me.group(1)))), None))
    return out, uart


def render(capture):
    out, uart = anchors(capture)
    lines = ["# Ancrages hv_uart.log <-> sep.log : %s" % capture,
             "# kind uart_line | clé | lignes sep.log (heure PC)  -- (aucune) si pas de correspondance", ""]
    for kind, i, key, cands in out:
        if cands is None:
            sep = "-"
        elif not cands:
            sep = "(aucune)"
        else:
            sep = ", ".join("L%d %s" % (m.lineno, hhmmss(m.ts)) for m in cands[:4])
            if len(cands) > 4:
                sep += ", ... (%d)" % len(cands)
        lines.append("%s uart L%-5d | %-34s | %s" % (kind, i, key, sep))
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("capture")
    ap.add_argument("-o", "--output")
    a = ap.parse_args(argv)
    text = render(a.capture.rstrip("/"))
    if a.output:
        write_output(a.output, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
