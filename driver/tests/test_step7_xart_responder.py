"""Étape 7 : le modèle de réponse AP (xart_responder) reproduit la capture snew-reel ligne à ligne.

VU uniquement. Pour chaque requête 0x13 du SEP, on recalcule la réponse de macOS et on la compare à
celle réellement envoyée dans la trace. Ne teste PAS la politique native (absent/persist) : pas de
vérité terrain (handler_0x13.md). La divergence native n'est vérifiée que pour sa cohérence interne.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TRACES, trace_dir
from sepreplay.mailbox import read_trace
from sepreplay import xart
from sepreplay import xart_responder as resp

SNEW = "20261111-113919"   # snew-reel


def pairs(tr):
    """Apparie chaque requête SEP->AP ('<') à sa réponse AP->SEP ('>') de même TAG, en FIFO.
    Gère les paires propres (TAG != 0) ET le lot d'annonces (TAG 0 : N annonces puis N acks)."""
    pending = {}   # tag -> file de requêtes en attente
    out = []
    for m in tr.msgs:
        if m.ep != xart.EP_XART:
            continue
        if not m.to_sep:                      # '<' SEP->AP : une requête
            pending.setdefault(m.tag, []).append(m)
        else:                                 # '>' AP->SEP : une réponse
            q = pending.get(m.tag)
            if q:
                out.append((q.pop(0), m))
    return out


class ResponderReplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pairs = pairs(read_trace(trace_dir(SNEW)))

    def test_pairs_found(self):
        self.assertGreater(len(self.pairs), 20)   # ~30 échanges 0x13 dans snew-reel
        # toutes les requêtes du SEP vues sont modélisées (aucune ValueError)
        kinds = {resp.observed_response(req, served_len=(0 if req.type in
                 (xart.OP_FETCH_MASTER, xart.OP_FETCH_GL) else None)).kind for req, _ in self.pairs}
        print("\n[step7] %d paires 0x13 ; comportements : %s" % (len(self.pairs), sorted(kinds)))

    def test_acks_match_capture_exactly(self):
        """fwboot / osuuid / absent / SAVE / annonce : réponse entièrement déterminée -> égalité stricte."""
        checked = 0
        for req, got in self.pairs:
            if req.type in (xart.OP_FETCH_MASTER, xart.OP_FETCH_GL):
                continue   # FETCH : longueur dépend du blob, testé à part
            r = resp.observed_response(req)
            self.assertEqual(r.type, got.type, "TYPE pour TAG=%#x" % req.tag)
            self.assertEqual(r.param, got.param, "PARAM pour TAG=%#x" % req.tag)
            self.assertEqual(r.data, got.data, "DATA pour TAG=%#x (req TYPE=%#x)" % (req.tag, req.type))
            checked += 1
        self.assertGreater(checked, 8)   # fwboot + osuuid + 0x07 + 5 annonces + 3 SAVE…

    def test_save_ack_masks_data(self):
        """Les SAVE (0x01/0x06) sont bien ACQUITTÉS par macOS, DATA masqué (octet bas à 0)."""
        saves = [(req, got) for req, got in self.pairs if xart.is_save(req.type)]
        self.assertTrue(saves, "aucun SAVE dans la capture ?")
        for req, got in saves:
            self.assertEqual(got.type, resp.RESP_DONE)
            self.assertEqual(got.data, req.data & 0xFFFFFF00)   # macOS acquitte (VU TAG 0x13/0x14/0x15)

    def test_announce_acks_type16(self):
        """Les annonces (0x1d) sont acquittées en TYPE 0x16, DATA masqué."""
        anns = [(req, got) for req, got in self.pairs if req.type == xart.OP_EP_ANNOUNCE]
        self.assertGreaterEqual(len(anns), 3)
        for req, got in anns:
            self.assertEqual(got.type, resp.RESP_ANNOUNCE)
            self.assertEqual(got.data, req.data & 0xFFFFFF00)

    def test_fetch_selector_and_codec_roundtrip(self):
        """FETCH : on ne connaît pas la longueur du blob (opaque), mais la réponse capturée doit :
        (a) être du TYPE 0x00 ; (b) ré-émettre le sélecteur de la requête ; (c) être exactement
        reproduite par notre codec à partir de la longueur qu'elle encode -> prouve codec + sélecteur."""
        fetches = [(req, got) for req, got in self.pairs
                   if req.type in (xart.OP_FETCH_MASTER, xart.OP_FETCH_GL)]
        self.assertGreater(len(fetches), 5)
        for req, got in fetches:
            self.assertEqual(got.type, resp.RESP_DONE)
            self.assertEqual(xart.selector(got.data), xart.selector(req.data))   # sélecteur ré-émis
            ln = xart.decode_fetch_len(got.param, got.data)                      # longueur encodée
            r = resp.observed_response(req, served_len=ln)
            self.assertEqual((r.param, r.data), (got.param, got.data))           # reproduction exacte


class NativeDivergenceTests(unittest.TestCase):
    """HYPOTHÈSE (pas de vérité terrain) : on vérifie seulement la cohérence interne de la logique native."""
    def test_fetch_absent_when_store_empty(self):
        class R:  # fausse requête FETCH maître, sélecteur SEP
            type, data = xart.OP_FETCH_MASTER, 0x00000100
        self.assertEqual(resp.native_fetch_decision([], R)[0], "absent")   # store vide -> absent

    def test_fetch_serves_when_present(self):
        import glob
        hits = glob.glob(os.path.join(TRACES, "*_xart_read", "*.gl.bin"))
        if not hits:
            self.skipTest("coffre .gl absent")
        with open(sorted(hits)[0], "rb") as f:
            store = xart.parse_coffre(f.read())

        class R:
            type, data = xart.OP_FETCH_MASTER, 0x00000100   # sélecteur SEP
        decision, loc = resp.native_fetch_decision(store, R)
        self.assertEqual(decision, "serve")
        self.assertTrue(loc.is_master)

    def test_save_decision_is_ack_and_persist(self):
        class R:
            type, data = xart.OP_SAVE_XART, 0x89290103
        self.assertEqual(resp.native_on_save(R), ("ack_and_persist", 0x89290100))


if __name__ == "__main__":
    unittest.main()
