"""Étape 5 : « démon » hors ligne : séquence d'init sbio + garde/renvoi des blobs catacomb (0x6c export -> 0x6d import).

AUCUNE ÉMISSION : ce module ne fait que PRODUIRE la liste des commandes qu'un futur pilote enverrait, pour la comparer à
ce que macOS a émis dans une trace. Il n'ouvre ni mailbox ni périphérique.

Statuts (docs/verification_status.md) :
  - séquence d'init (57 premières commandes `> fc`) : **vérifié (proposé)**, K6 (8/8 boots ; ici 18/18 captures avec sbio).
    Les attributions fonction -> sous-séquence sont `hypothèse` et ne sont PAS utilisées.
  - boucle 0x6c -> 0x6d (`LTFC`) : **vérifié (proposé)** (HO : import C12 = dernier export C11 ; C9 = C8, C11 = C9).
    Contenu chiffré/opaque : le démon ne l'interprète pas. En-tête observé (hypothèse) : `LTFC`, u32 0x0a, u32 uid (+8).
    Format de la requête 0x6c : 0x18 o = uid u32 LE puis zéros (observé 2 valeurs : 501 et 0xffffffff).
  - ordre d'import « petit blob (uid -1, 0xf4 o) puis gros (uid utilisateur) » : observé dans 5 boots, `proposé`.
Hors périmètre ici : contenu des autres charges (0x5b, 0x5f, 0x15...) : seules les TYPES sont rejouées ; 0x5b fixe =
hypothèse, origine inconnue.
"""
import struct
from typing import Dict, List, Optional, Tuple

INIT_SEQUENCE: Tuple[int, ...] = tuple(int(x, 16) for x in (
    "73 "
    "17 15 16 42 18 5f 5d 5c 6a 31 32 01 1f 31 32 5b 63 "
    "19 "
    "17 15 16 42 18 5f 5d 5c 6a 6f 31 32 01 1f 63 63 "
    "7c 6b 79 6d 39 6b 79 6b 79 6d 2b 6b 79 54 2b 33 36 6e 7a 71 28 7c").split())
assert len(INIT_SEQUENCE) == 57

T_EXPORT, T_IMPORT = 0x6C, 0x6D
MAGIC = b"LTFC"
UID_NONE = 0xFFFFFFFF


def blob_uid(blob: bytes) -> int:
    if len(blob) < 12 or blob[:4] != MAGIC:
        raise ValueError("blob sans magic LTFC")
    return struct.unpack_from("<I", blob, 8)[0]


def export_request(uid: int) -> bytes:
    return struct.pack("<I", uid) + bytes(20)


class BlobStore:
    """Dernier blob exporté par uid (le SEP ne garde pas ses gabarits : l'AP les conserve)."""

    def __init__(self):
        self.blobs: Dict[int, bytes] = {}

    def on_export(self, blob: bytes):
        self.blobs[blob_uid(blob)] = bytes(blob)

    def import_order(self) -> List[int]:
        # observé : uid -1 d'abord, puis les uids utilisateur (un seul testé : 501)
        return sorted(self.blobs, key=lambda u: (u != UID_NONE, u))


class InitPlan:
    """Liste (TYPE, charge ou None) des commandes d'init. Les charges ne sont fournies que pour 0x6d (import)."""

    def __init__(self, store: BlobStore):
        self.store = store

    def commands(self) -> List[Tuple[int, Optional[bytes]]]:
        imports = [self.store.blobs[u] for u in self.store.import_order()]
        out, k = [], 0
        for t in INIT_SEQUENCE:
            if t == T_IMPORT:
                out.append((t, imports[k] if k < len(imports) else None))
                k += 1
            else:
                out.append((t, None))
        return out
