"""Étape 2 : endpoint de découverte 0xFD -> table nom <-> numéro d'EP, tailles OOL.

Statut (docs/verification_status.md) : noms 4 caractères et tailles FD TYPE 1 = **hypothèse** (12/12 annonces
= doc Asahi publique ; sens des 4 octets de tailles : hypothèse, source kext). Ce module ne s'en sert que pour
étiqueter ; il ne code AUCUN numéro d'EP en dur (on cherche le nom : `find("sbio")`).

Format observé (SEP -> AP seulement ; aucune requête `> EP=0xFD` n'existe dans les traces) :
  TYPE 0x00, PARAM = n° d'EP, DATA = nom ASCII sur 4 octets, premier caractère dans l'octet de poids fort.
  TYPE 0x01, PARAM = n° d'EP, DATA = 4 octets de tailles en pages de 0x4000. Lecture proposée (hypothèse) :
      octet 0 = min envoi, octet 1 = max envoi, octet 2 = min réception, octet 3 = max réception
  (octet 0 = poids faible de DATA).
"""
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional

from .mailbox import Msg, SEP_TO_AP

EP_DISCOVERY = 0xFD
EP_CNTL = 0x00
OOL_PAGE = 0x4000
CNTL_SEND_SIZE, CNTL_SEND_ADDR, CNTL_RECV_SIZE, CNTL_RECV_ADDR = 0x04, 0x02, 0x05, 0x03


def decode_name(data):
    return data.to_bytes(4, "big").decode("ascii", "replace")


@dataclass
class EpInfo:
    ep: int
    name: str
    sizes_raw: Optional[int] = None   # DATA du TYPE 1, tel quel

    @property
    def pages(self):
        """(min_envoi, max_envoi, min_recv, max_recv) en pages -- lecture « hypothèse »."""
        if self.sizes_raw is None:
            return None
        r = self.sizes_raw
        return (r & 0xFF, (r >> 8) & 0xFF, (r >> 16) & 0xFF, (r >> 24) & 0xFF)

    @property
    def max_send(self):
        p = self.pages
        return None if p is None else p[1] * OOL_PAGE

    @property
    def max_recv(self):
        p = self.pages
        return None if p is None else p[3] * OOL_PAGE


class DiscoveryTable:
    def __init__(self):
        self.by_ep: Dict[int, EpInfo] = {}
        self.order: List[int] = []     # ordre d'annonce

    def feed(self, m: Msg):
        if m.ep != EP_DISCOVERY or m.dir != SEP_TO_AP:
            return
        if m.type == 0x00:
            if m.param in self.by_ep:
                raise ValueError("EP %#x annoncé deux fois" % m.param)
            self.by_ep[m.param] = EpInfo(m.param, decode_name(m.data))
            self.order.append(m.param)
        elif m.type == 0x01:
            if m.param not in self.by_ep:
                raise ValueError("TYPE 1 avant TYPE 0 pour EP %#x" % m.param)
            self.by_ep[m.param].sizes_raw = m.data
        else:
            raise ValueError("TYPE FD inconnu : %#x" % m.type)

    @classmethod
    def from_msgs(cls, msgs: Iterable[Msg]):
        t = cls()
        for m in msgs:
            t.feed(m)
        return t

    def find(self, name: str) -> Optional[int]:
        """N° d'EP par nom (4 car., espace de fin accepté : 'sks' == 'sks ')."""
        name = name.ljust(4)
        for ep, i in self.by_ep.items():
            if i.name == name:
                return ep
        return None

    def name_of(self, ep: int) -> Optional[str]:
        i = self.by_ep.get(ep)
        return None if i is None else i.name.rstrip()


def cntl_opens(msgs: Iterable[Msg]):
    """Séquences d'ouverture CNTL `> EP=0x00` TYPE 4/2/5/3 (PARAM = EP) -> {ep: [(taille_envoi, addr_envoi, taille_recv, addr_recv)]}.
    Seules les requêtes AP->SEP sont lues ; l'adresse est DATA << 12 (DATA = adresse >> 12). Hypothèse A/B : voir README.
    """
    out: Dict[int, list] = {}
    cur: Dict[int, dict] = {}
    names = {CNTL_SEND_SIZE: "ss", CNTL_SEND_ADDR: "sa", CNTL_RECV_SIZE: "rs", CNTL_RECV_ADDR: "ra"}
    for m in msgs:
        if m.ep != EP_CNTL or m.dir != ">" or m.type not in names:
            continue
        c = cur.setdefault(m.param, {})
        c[names[m.type]] = m.data if m.type in (CNTL_SEND_SIZE, CNTL_RECV_SIZE) else m.data << 12
        if len(c) == 4:
            out.setdefault(m.param, []).append((c["ss"], c["sa"], c["rs"], c["ra"]))
            cur[m.param] = {}
    return out
