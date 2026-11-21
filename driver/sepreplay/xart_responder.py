"""Étape 7 : modèle de la réponse AP à l'EP 0x13 (xART), OBSERVÉ sur macOS.

PÉRIMÈTRE = OBSERVÉ (VU), validé par REPRODUCTION : pour chaque requête du SEP dans une capture
(`snew-reel`), ce module recalcule la réponse que macOS a envoyée, et le test (test_step7) vérifie
qu'elle est identique à celle de la trace, ligne à ligne. C'est donc le côté AP du protocole 0x13 tel
qu'il s'est RÉELLEMENT comporté — pas une invention.

CE QUI N'EST **PAS** ICI (= hypothèse NON testée, voir docs/handler_0x13.md, docs/route_native.md) :
la POLITIQUE du handler NATIF Linux, qui DIVERGE de macOS sur deux points et deux seulement :
  1. branche ABSENT : rendre « locker-absent » quand le store Linux n'a pas le locker (macOS, lui, a
     toujours son coffre et sert tout) → c'est ce qui laisserait la puce sceller un état frais ;
  2. persist-on-SAVE : STOCKER le blob du SAVE dans le store Linux (macOS ne fait qu'acquitter).
Ces deux divergences TOUCHENT le SEP (écriture) et ne sont validables QUE sur matériel (porte Albert).
Elles sont isolées plus bas dans `native_fetch_decision()` / `native_on_save()`, explicitement marquées
HYPOTHÈSE, et le test ne les confronte à aucune vérité terrain (il n'en existe pas). Python pur, lecture
seule : ce module CALCULE une réponse, il n'émet RIEN vers le SEP.

Sources : captures `snew-reel` (EP 0x13), docs/gigalocker.md (codec FETCH), docs/handler_0x13.md.
"""
from dataclasses import dataclass

from . import xart

# Types de RÉPONSE de l'AP (VU snew-reel) — distincts des types de REQUÊTE du SEP (xart.OP_*).
RESP_DONE     = 0x00   # réponse générique « fait / données en A » (ack, UUID, FETCH servi, absent…)
RESP_ANNOUNCE = 0x16   # ack d'une annonce d'endpoint (TYPE 0x1d)

# Masque appliqué par macOS au DATA de la requête pour former le DATA de l'ack (VU : SAVE, annonces).
_ACK_MASK = 0xFFFFFF00


@dataclass(frozen=True)
class Response:
    """Réponse AP->SEP calculée pour une requête. `writes_uuid`/`serves_blob` = tampon A touché (VU
    par les lignes `# ool`), non modélisé octet-près ici. `kind` = étiquette lisible."""
    tag: int
    type: int
    param: int
    data: int
    kind: str
    writes_uuid: bool = False   # osuuid : 16 o d'UUID écrits en A
    serves_blob: bool = False   # FETCH : blob scellé écrit en A (longueur = param/data)


def observed_response(req, served_len=None):
    """Réponse de macOS (VU) à une requête 0x13 `req` (un mailbox.Msg, SEP->AP).

    `served_len` : longueur du blob servi, pour un FETCH (0x00/0x05). macOS la tire du coffre ; le test
    la relit dans la capture (le blob est opaque, on ne le fabrique pas). Hors FETCH, ignorée.
    """
    t = req.type
    if t == xart.OP_FWBOOT:                 # 0x0e — état fw-boot
        return Response(req.tag, RESP_DONE, 0x00, 0x00000100, "ack_fwboot")
    if t == xart.OP_OSUUID:                 # 0x13 — UUID de l'OS courant (16 o écrits en A)
        return Response(req.tag, RESP_DONE, 0x00, 0x00000000, "uuid", writes_uuid=True)
    if t in (xart.OP_FETCH_MASTER, xart.OP_FETCH_GL):   # 0x00 / 0x05 — FETCH : longueur + sélecteur ré-émis
        if served_len is None:
            raise ValueError("FETCH : served_len requis")
        param, data = xart.encode_fetch_len(served_len, flag=xart.selector(req.data))
        kind = "fetch_master" if t == xart.OP_FETCH_MASTER else "fetch_gl"
        return Response(req.tag, RESP_DONE, param, data, kind, serves_blob=True)
    if t == xart.OP_ABSENT:                 # 0x07 — le SEP signale un locker absent : simple ack
        return Response(req.tag, RESP_DONE, 0x00, 0x00000000, "ack_absent")
    if xart.is_save(t):                     # 0x01 / 0x06 — SAVE : macOS ACQUITTE (DATA masqué)
        return Response(req.tag, RESP_DONE, 0x00, req.data & _ACK_MASK, "ack_save")
    if t == xart.OP_EP_ANNOUNCE:            # 0x1d — annonce d'endpoint : ack TYPE 0x16 (DATA masqué)
        return Response(req.tag, RESP_ANNOUNCE, 0x00, req.data & _ACK_MASK, "ack_announce")
    raise ValueError("requête 0x13 non modélisée : TYPE=%#x" % t)


# --------------------------------------------------------------------------------------------------
# DIVERGENCES DU HANDLER NATIF LINUX  —  ⚠️ HYPOTHÈSE NON TESTÉE (docs/handler_0x13.md §2/§3).
# Aucune vérité terrain : aucune capture ne montre ces branches (macOS ne les emprunte jamais).
# Ces fonctions décrivent la LOGIQUE proposée ; les activer en vrai = écriture SEP = porte Albert.
# --------------------------------------------------------------------------------------------------
def native_fetch_decision(store, req):
    """HYPOTHÈSE. Côté Linux, un FETCH : si le store a le locker -> le servir ; sinon -> ABSENT.
    (macOS sert toujours ; la branche ABSENT est la nouveauté qui laisserait la puce sceller du frais.)
    Renvoie ("serve", locker) ou ("absent", None). Ne décide RIEN de matériel : pur calcul sur le store.
    """
    if req.type == xart.OP_FETCH_MASTER:
        loc = xart.find_master(store, xart.selector(req.data))
    elif req.type == xart.OP_FETCH_GL:
        loc = None   # le vrai UUID est dans le tampon B (hors message) ; résolution au moment du boot
    else:
        raise ValueError("pas un FETCH : TYPE=%#x" % req.type)
    return ("serve", loc) if loc is not None else ("absent", None)


def native_on_save(req):
    """HYPOTHÈSE. Côté Linux, un SAVE devrait être ACQUITTÉ **puis le blob (tampon B) PERSISTÉ** dans le
    store xART de Linux (macOS ne fait qu'acquitter). ⚠️ L'acquittement fait AVANCER le compteur scellé
    du SEP = ÉCRITURE = porte Albert (docs/handler_0x13.md, stockholm-se-brick-definitif). Ici on ne
    renvoie que la DÉCISION attendue, aucune émission.
    """
    return ("ack_and_persist", req.data & _ACK_MASK)
