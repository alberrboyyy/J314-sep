"""Étape 3 : trame capteur `[0x80][opcode][index][u32 LE longueur totale][charge]` et statut `80 20 00 10000000 ...`.

Statuts (docs/verification_status.md) : trame et statut = **hypothèse** (source kext + uart, 16/16 traces annoncées ;
20/20 comptées ici). Le contenu du statut complet est INCONNU : ce module expose les octets bruts. Les accesseurs
`state_byte` / `avail_u32` suivent la lecture du kext (octet +7 = état, u32 +0xc = octets disponibles) et sont étiquetés
hypothèse : sur le statut d'init observé ils valent 0 et 0x3352, ce qui n'est PAS interprété ici.
Pas de nœud DT réel : rien ici ne touche un bus.
"""
import re
import struct
from dataclasses import dataclass

from .crc import crc16_arc

MAGIC = 0x80
OP_STATUS = 0x20       # observé dans l'uart ; nom de commande = hypothèse
OP_READ_DATA = 0x13    # `80 13 00 0b000000 <size u32>` (hypothèse, kext)
HEADER_LEN = 7

_UART_RE = re.compile(r"SensorStatus:\s+(\d+)B \|((?: [0-9a-f]{2})+)")


@dataclass(frozen=True)
class Frame:
    op: int
    index: int
    total_len: int
    payload: bytes
    raw: bytes

    @property
    def length_ok(self):
        return self.total_len == len(self.raw)


def parse_frame(raw: bytes) -> Frame:
    if len(raw) < HEADER_LEN:
        raise ValueError("trame trop courte")
    if raw[0] != MAGIC:
        raise ValueError("marqueur 0x80 absent")
    total = struct.unpack_from("<I", raw, 3)[0]
    return Frame(raw[1], raw[2], total, bytes(raw[HEADER_LEN:]), bytes(raw))


def build_read_request(size: int) -> bytes:
    """Trame de demande de lecture de données : 11 octets (hypothèse, kext ; jamais observée sur un bus)."""
    return bytes([MAGIC, OP_READ_DATA, 0]) + struct.pack("<II", 0x0B, size)


@dataclass(frozen=True)
class Status:
    frame: Frame

    @property
    def state_byte(self):      # hypothèse (kext) : 7 = données disponibles
        return self.frame.raw[7] if len(self.frame.raw) > 7 else None

    @property
    def avail_u32(self):       # hypothèse (kext)
        return struct.unpack_from("<I", self.frame.raw, 12)[0] if len(self.frame.raw) >= 16 else None

    @property
    def trailer_u16(self):
        return struct.unpack_from("<H", self.frame.raw, len(self.frame.raw) - 2)[0]

    @property
    def trailer_is_crc16_arc(self):
        """Faux sur le statut d'init observé (documenté : format du statut complet inconnu)."""
        return crc16_arc(self.frame.raw[:-2]) == self.trailer_u16


def parse_status(raw: bytes) -> Status:
    f = parse_frame(raw)
    if f.op != OP_STATUS:
        raise ValueError("opcode %#x != statut" % f.op)
    return Status(f)


def status_from_uart_line(line: str):
    """Extrait les octets d'une ligne uart `... SensorStatus:    16B | 80 20 ...`, None si absente."""
    m = _UART_RE.search(line)
    if not m:
        return None
    raw = bytes(int(x, 16) for x in m.group(2).split())
    if len(raw) != int(m.group(1)):
        raise ValueError("longueur annoncée %s != %d octets" % (m.group(1), len(raw)))
    return raw
