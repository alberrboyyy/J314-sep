"""Étape 4 : fragmentation GT (TAG 0xfc/0xfd/0xfe) sur EP sbio, réassemblage OOL et CRC des tranches 0x65.

Statuts (docs/verification_status.md) :
  - mot GT (TAG in {fc,fd,fe}, TYPE = commande, PARAM = 0, DATA = compteur << 16) : **vérifié (côté macOS)**.
  - en-tête OOL 0x1c o (u32 LE : 1, total, offset, 0, 0, TYPE, longueur du morceau) : **vérifié (lecture)**.
  - 0x65 = 12 tranches de 0x980, CRC-16/ARC en fin de tranche : **vérifié (proposé)**, K4.
  - A = AP->SEP, B = SEP->AP : hypothèse (la direction est celle écrite par le tracer, `dir=` de la ligne `# ool`).
Règle de compteur testée ici (observation sur les traces, formulée à partir de messages.md « Fragments ») :
  `fc` : DATA = 0 ; `fe` : compteur = nombre de `fd` déjà vus dans le transfert ; `fd` : compteur = ce nombre + 1 ;
  le transfert recommence à chaque `> fc` ou à un `< fc` non sollicité.
"""
import hashlib
import os
import struct
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

from .crc import crc16_arc
from .mailbox import Trace, Msg, AP_TO_SEP

GT_TAGS = (0xFC, 0xFD, 0xFE)
OOL_HDR = 0x1C
OOL_PAGE = 0x4000
OOL_MAX_CHUNK = OOL_PAGE - OOL_HDR           # 0x3fe4 o de charge par morceau
SLICE_LEN = 0x980
SLICES_PER_IMAGE = 12
IMAGE_LEN = SLICE_LEN * SLICES_PER_IMAGE     # 0x7200
T_IMAGE = 0x65


def check_counters(msgs, ep):
    """Rejoue la règle de compteur sur les messages GT de l'EP. Retourne (nb vérifiés, [(lineno, raison)])."""
    n, bad = 0, []
    pending = set()
    nfd = 0
    for m in msgs:
        if m.ep != ep or m.tag not in GT_TAGS:
            continue
        n += 1
        if m.param != 0 or (m.data & 0xFFFF):
            bad.append((m.lineno, "param/octets bas de DATA"))
            continue
        k = m.data >> 16
        if m.tag == 0xFC:
            if m.dir == AP_TO_SEP:
                pending.add(m.type)
                nfd = 0
            elif m.type in pending:
                pending.discard(m.type)
            else:
                nfd = 0
            if k:
                bad.append((m.lineno, "fc avec compteur %d" % k))
        elif m.tag == 0xFE:
            if k != nfd:
                bad.append((m.lineno, "fe %d != %d" % (k, nfd)))
        else:
            nfd += 1
            if k != nfd:
                bad.append((m.lineno, "fd %d != %d" % (k, nfd)))
    return n, bad


@dataclass
class OolRecord:
    lineno: int            # ligne `# ool`
    dir: str
    buf: str
    msg: Optional[Msg]
    data: bytes
    sha_ok: Optional[bool]


def load_ool(trace: Trace, ep: int) -> List[OolRecord]:
    """Rattache chaque `# ool` de l'EP à son contenu. `changed=none` -> dernier .bin de même (buf, len) :
    le tracer ne compare qu'à la lecture précédente de même tampon et même longueur."""
    out, last = [], {}
    for o in trace.ool:
        if o.ep != ep:
            continue
        key = (o.buf, o.length)
        if o.file:
            last[key] = o.file
        src = last.get(key)
        data, ok = b"", None
        if src:
            with open(os.path.join(trace.ooldir, src), "rb") as f:
                data = f.read()
            ok = hashlib.sha256(data).hexdigest()[:8] == o.sha
        out.append(OolRecord(o.lineno, o.dir, o.buf, o.msg, data, ok))
    return out


@dataclass
class Transfer:
    dir: str
    buf: str
    type: int
    line: int
    total: int
    chunks: Dict[int, bytes] = field(default_factory=dict)
    truncated: bool = False
    conflict: bool = False

    @property
    def blob(self):
        return b"".join(self.chunks[k] for k in sorted(self.chunks))

    @property
    def contiguous(self):
        pos = 0
        for off in sorted(self.chunks):
            if off != pos:
                return False
            pos += len(self.chunks[off])
        return True

    @property
    def complete(self):
        return self.contiguous and len(self.blob) == self.total and not self.truncated


def reassemble(trace: Trace, ep: int, types=None) -> List[Transfer]:
    """Réassemble les transferts GT dont la 1re charge (offset 0) est apparue ; une entrée par transfert."""
    out, cur = [], {}
    for r in load_ool(trace, ep):
        m, d = r.msg, r.data
        if m is None or m.ep != ep or m.tag not in GT_TAGS or len(d) < OOL_HDR or d[0] != 1:
            continue
        valid, total, off, z1, z2, typ, ln = struct.unpack_from("<7I", d, 0)
        if typ != m.type or (types is not None and typ not in types):
            continue
        key = (r.dir, r.buf, typ)
        if off == 0:
            cur[key] = Transfer(r.dir, r.buf, typ, m.lineno, total)
            out.append(cur[key])
        t = cur.get(key)
        if t is None or total != t.total:
            continue
        piece = d[OOL_HDR:OOL_HDR + ln]
        if len(piece) < ln:
            t.truncated = True
        if off in t.chunks and t.chunks[off] != piece:
            t.conflict = True
        t.chunks[off] = piece
    return out


def check_slices(blob, slice_len=SLICE_LEN, n=SLICES_PER_IMAGE):
    """Contrôle des tranches capteur d'une image : en-tête `80 52 NN`, u32 LE à +3 = slice_len, CRC-16/ARC LE final.
    Retourne [(index, ok)]."""
    res = []
    for k in range(n):
        s = blob[k * slice_len:(k + 1) * slice_len]
        ok = (len(s) == slice_len and s[0] == 0x80 and s[1] == 0x52
              and struct.unpack_from("<I", s, 3)[0] == slice_len
              and crc16_arc(s[:-2]) == struct.unpack_from("<H", s, slice_len - 2)[0])
        res.append((k, ok))
    return res
