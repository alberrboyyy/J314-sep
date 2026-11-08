"""CRC-16/ARC (polynôme réfléchi 0xA001, init 0, pas de XOR final), écrit ici à partir de la définition standard.

Statut : contrôle des tranches 0x65 = `vérifié (macOS)` (K4, 468/468 tranches). Aucun code Apple.
"""


def _table():
    t = []
    for i in range(256):
        c = i
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
        t.append(c)
    return t


_T = _table()


def crc16_arc(data, crc=0):
    for b in data:
        crc = (crc >> 8) ^ _T[(crc ^ b) & 0xFF]
    return crc


def self_test():
    """Valeur de contrôle standard du catalogue CRC : CRC-16/ARC("123456789") = 0xBB3D."""
    return crc16_arc(b"123456789") == 0xBB3D
