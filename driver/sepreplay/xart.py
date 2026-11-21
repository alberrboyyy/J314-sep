"""Étape 6 : codec du flux xART (EP 0x13) + parseur du coffre gigalocker (.gl).

PÉRIMÈTRE = OBSERVÉ (VU) uniquement (docs/gigalocker.md : coffre parsé sur disque, format de la
réponse FETCH corrélé sur c24 ; cf. analysis/parse_gigalocker.py). Ce module DÉCODE / ENCODE et LIT
le coffre. Il ne DÉCIDE rien et n'émet rien.

CE QUI N'EST PAS ICI (= hypothèse NON testée, voir docs/handler_0x13.md) : la POLITIQUE du handler
natif — répondre « absent » pour laisser la puce sceller un état frais, acquitter le SAVE, et la
coexistence du MASTER partagé macOS/Linux. Ces décisions touchent le SEP (écriture) : hors de ce
module, hors-hardware. Python pur, lecture seule.
"""
import struct
import zlib
from dataclasses import dataclass

EP_XART = 0x13

# Opérations xART, par le champ TYPE du message SEP->AP (VU, docs/gigalocker.md §Protocole, messages.md).
OP_FWBOOT       = 0x0e  # état fw-boot (le SEP demande, l'AP acquitte)
OP_OSUUID       = 0x13  # le SEP réclame l'UUID de l'« OS courant »
OP_FETCH_MASTER = 0x00  # FETCH d'un maître (sélecteur dans DATA[1] : 0=USER, 1=SEP)
OP_FETCH_GL     = 0x05  # FETCH d'un gigalocker (UUID à lire dans le tampon B)
OP_ABSENT       = 0x07  # locker introuvable (erreur / réponse « absent »)
OP_EP_ANNOUNCE  = 0x1d  # le SEP annonce un endpoint applicatif (nom dans DATA)
OP_SAVE_XART    = 0x01  # SAVE d'un maître xART (re-scellement) -- ÉCRITURE si acquitté
OP_SAVE_LOCKER  = 0x06  # SAVE d'un gigalocker            -- ÉCRITURE si acquitté

_OP_NAME = {OP_FWBOOT: "fwboot", OP_OSUUID: "osuuid", OP_FETCH_MASTER: "fetch_master",
            OP_FETCH_GL: "fetch_gl", OP_ABSENT: "absent", OP_EP_ANNOUNCE: "ep_announce",
            OP_SAVE_XART: "save_xart", OP_SAVE_LOCKER: "save_locker"}

SEL_USER, SEL_SEP = 0, 1  # sélecteur de maître (DATA[1]) : 0 -> USER-xART, 1 -> SEP-xART


def op_name(type_):
    return _OP_NAME.get(type_, "op_%#x" % type_)


def selector(data):
    """Drapeau/sélecteur porté par DATA[1] (maître : 0=USER, 1=SEP ; gigalocker : 0/1).
    VU (docs/gigalocker.md) : à RÉ-ÉMETTRE tel quel dans la réponse."""
    return (data >> 8) & 0xFF


def is_save(type_):
    """Un SAVE acquitté = écriture SEP (compteur scellé). Le codec ne fait que le reconnaître."""
    return type_ in (OP_SAVE_XART, OP_SAVE_LOCKER)


# --- Codec de la longueur de réponse FETCH (VU, corrélé c24, docs/gigalocker.md) ---
# Longueur totale écrite dans le tampon A = PARAM | (DATA[octet0] << 8).
def decode_fetch_len(param, data):
    return param | ((data & 0xFF) << 8)


def encode_fetch_len(length, flag=0):
    """Taille réelle du blob rendu -> (param, data). Le driver RECALCULE (ne rejoue pas la capture :
    le blob diffère). `flag` = sélecteur/drapeau à ré-émettre, placé dans DATA[1]."""
    if not 0 <= length <= 0xFFFF:
        raise ValueError("longueur hors plage : %#x" % length)
    param = length & 0xFF
    data = ((length >> 8) & 0xFF) | ((flag & 0xFF) << 8)
    return param, data


# --- Parseur du coffre gigalocker (.gl) (VU, docs/gigalocker.md ; même logique que analysis/parse_gigalocker.py) ---
SLOT = 0x9000
T_USER_MASTER, T_SEP_MASTER = 0x01, 0x02
T_GIGALOCKER = (0x03, 0x04)


HDR = 0x22   # taille de l'en-tête d'un locker (charge à partir de +0x22)


def slot_crc(payload):
    """CRC stocké à +0x16 (u32 LE) = CRC-32/ISO-HDLC de la CHARGE seule (`zlib.crc32`).
    VÉRIFIÉ : reproduit les 12/12 CRC du coffre réel (traces/20261117-224724_xart_read ;
    cf. docs/gigalocker.md, analyse 2026-11-20)."""
    return zlib.crc32(payload) & 0xFFFFFFFF


@dataclass(frozen=True)
class Locker:
    slot: int
    type: int
    uuid: bytes      # 16 o pour un gigalocker, b"" pour un maître (champ UUID nul)
    length: int
    crc: int
    payload: bytes   # charge scellée, opaque (jamais déchiffrée ici)
    header: bytes = b""   # en-tête brut [+0x00:+0x22] d'origine (préservé pour un round-trip exact)

    @property
    def is_master(self):
        return self.type in (T_USER_MASTER, T_SEP_MASTER)

    @property
    def crc_ok(self):
        """Le CRC stocké correspond-il à la charge ? (VU : vrai pour les 12 lockers réels.)"""
        return self.crc == slot_crc(self.payload)


def parse_coffre(data):
    """Octets du fichier .gl -> list[Locker]. Lecture pure ; la charge reste opaque."""
    lockers = []
    for k in range(len(data) // SLOT + 1):
        base = k * SLOT
        if base + HDR > len(data) or not any(data[base:base + SLOT]):
            continue
        typ = data[base + 0x01]
        uuid = bytes(data[base + 0x02:base + 0x12]) if typ in T_GIGALOCKER else b""
        ln = struct.unpack_from("<I", data, base + 0x12)[0]
        crc = struct.unpack_from("<I", data, base + 0x16)[0]
        payload = bytes(data[base + HDR:base + HDR + ln])
        header = bytes(data[base:base + HDR])
        lockers.append(Locker(k, typ, uuid, ln, crc, payload, header))
    return lockers


def serialize_locker(locker):
    """Locker -> octets d'UN slot (SLOT=0x9000). Si `header` est présent (locker parsé), reproduit le
    slot d'origine À L'OCTET PRÈS (round-trip VU, testé). Charge + en-tête + bourrage de zéros."""
    header = locker.header if locker.header else build_header(locker.type, locker.uuid, locker.payload)
    body = header + locker.payload
    if len(body) > SLOT:
        raise ValueError("locker trop grand pour un slot : %#x > %#x" % (len(body), SLOT))
    return body + b"\x00" * (SLOT - len(body))


def build_header(type_, uuid, payload, extra=0):
    """En-tête [+0x00:+0x22] pour un NOUVEAU locker (persist-on-SAVE natif).
    VU : réservé(1)=0, type(1), UUID(16, nul pour un maître), longueur(u32 LE), CRC(u32 LE = slot_crc).
    ⚠️ `extra` = u16 à +0x1a dont le RÔLE est INCONNU (non reproduit par un CRC-16 courant de la charge ;
    docs/gigalocker.md). Mis à 0 par défaut : à confirmer sur matériel avant tout vrai SAVE natif."""
    h = bytearray(HDR)
    h[0x01] = type_ & 0xFF
    if type_ in T_GIGALOCKER:
        h[0x02:0x12] = (uuid or b"\x00" * 16)[:16].ljust(16, b"\x00")
    struct.pack_into("<I", h, 0x12, len(payload))
    struct.pack_into("<I", h, 0x16, slot_crc(payload))
    struct.pack_into("<H", h, 0x1a, extra & 0xFFFF)
    return bytes(h)


def find_master(lockers, sel):
    """sel=1 -> SEP-xART (type 0x02) ; sel=0 -> USER-xART (type 0x01). Renvoie un Locker ou None."""
    want = T_SEP_MASTER if sel == SEL_SEP else T_USER_MASTER
    for L in lockers:
        if L.type == want:
            return L
    return None


def find_gigalocker(lockers, uuid):
    """Cherche un gigalocker par UUID (16 o lus dans le tampon B). None si absent."""
    for L in lockers:
        if L.uuid and L.uuid == uuid:
            return L
    return None
