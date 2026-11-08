"""Étape 1 : mot mailbox 64 bits et lecteur de sep.log.

Mot : bits 0-7 EP, 8-15 TAG, 16-23 TYPE, 24-31 PARAM, 32-63 DATA
(docs/verification_status.md, 1re ligne : « hypothèse (cohérent) », très solide en lecture ; le seul
statut `vérifié` côté macOS est l'encodage GT, voir gt.py).

Format de ligne de sep.log (défini par le tracer) :
  <ts> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x..   ('>' AP->SEP, '<' SEP->AP)
plus des commentaires `# ool ...`, `# ool learn ...`, `# epname ...`, `# end ... seen=N logged=N`.
"""
import os
import re
from dataclasses import dataclass, field
from typing import List, Optional

AP_TO_SEP = ">"
SEP_TO_AP = "<"


def decode_word(word):
    """64 bits -> (ep, tag, type, param, data)."""
    if not 0 <= word < 1 << 64:
        raise ValueError("mot hors plage")
    return (word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, (word >> 24) & 0xFF, word >> 32)


def encode_word(ep, tag, type_, param, data):
    for name, v, mx in (("ep", ep, 0xFF), ("tag", tag, 0xFF), ("type", type_, 0xFF),
                        ("param", param, 0xFF), ("data", data, 0xFFFFFFFF)):
        if not 0 <= v <= mx:
            raise ValueError("%s hors plage : %#x" % (name, v))
    return ep | tag << 8 | type_ << 16 | param << 24 | data << 32


@dataclass(frozen=True)
class Msg:
    lineno: int
    ts: str          # gardé en texte : pas de perte de précision
    dir: str
    ep: int
    tag: int
    type: int
    param: int
    data: int

    @property
    def word(self):
        return encode_word(self.ep, self.tag, self.type, self.param, self.data)

    @property
    def to_sep(self):
        return self.dir == AP_TO_SEP


@dataclass
class OolRead:
    """Ligne `# ool ...` : lecture d'un tampon OOL, rattachée au message qui la précède."""
    lineno: int
    seq: int
    ep: int
    dir: str
    buf: str            # 'A' ou 'B'
    sha: str
    length: int
    changed: str
    file: Optional[str]
    msg: Optional[Msg]   # dernier message vu avant la ligne


_MSG_RE = re.compile(
    r"^(?P<ts>\d+(?:\.\d+)?) (?P<dir>[<>]) EP=0x(?P<ep>[0-9a-fA-F]{1,2}) TAG=0x(?P<tag>[0-9a-fA-F]{1,2}) "
    r"TYPE=0x(?P<type>[0-9a-fA-F]{1,2}) PARAM=0x(?P<param>[0-9a-fA-F]{1,2}) DATA=0x(?P<data>[0-9a-fA-F]{1,8})\s*$")
_OOL_RE = re.compile(r"^# ool (?P<ts>[\d.]+) (?P<kv>.*)$")
_END_RE = re.compile(r"^# end \S+ seen=(\d+) logged=(\d+)")


@dataclass
class Trace:
    path: str
    msgs: List[Msg] = field(default_factory=list)
    ool: List[OolRead] = field(default_factory=list)
    end_seen: Optional[int] = None
    end_logged: Optional[int] = None
    bad_lines: List[int] = field(default_factory=list)

    @property
    def ooldir(self):
        return self.path + ".ool"


def resolve(path):
    """Dossier de capture ou fichier -> chemin de sep.log."""
    if os.path.isdir(path):
        return os.path.join(path, "sep.log")
    return path


def read_trace(path):
    path = resolve(path)
    tr = Trace(path)
    last = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith("#"):
                m = _OOL_RE.match(line)
                if m:
                    kv = dict(p.split("=", 1) for p in m.group("kv").split() if "=" in p)
                    if "buf" in kv and "sha" in kv:   # exclut « # ool learn ... »
                        tr.ool.append(OolRead(n, int(kv["seq"]), int(kv["EP"], 16), kv["dir"], kv["buf"],
                                              kv["sha"], int(kv["len"], 16), kv.get("changed", ""),
                                              kv.get("file"), last))
                    continue
                m = _END_RE.match(line)
                if m:
                    tr.end_seen, tr.end_logged = int(m.group(1)), int(m.group(2))
                continue
            m = _MSG_RE.match(line)
            if not m:
                tr.bad_lines.append(n)
                continue
            last = Msg(n, m["ts"], m["dir"], int(m["ep"], 16), int(m["tag"], 16), int(m["type"], 16),
                       int(m["param"], 16), int(m["data"], 16))
            tr.msgs.append(last)
    return tr
