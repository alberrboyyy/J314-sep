"""Étape 6 : codec xART (EP 0x13) + parseur du coffre .gl, validés sur données réelles.

VU uniquement : séquence 0x13 de la capture snew-reel, coffre .gl lu sur disque (docs/gigalocker.md).
Ne teste PAS la politique du handler natif (absent->scellage frais) : c'est une hypothèse (handler_0x13.md).
"""
import glob
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TRACES, trace_dir
from sepreplay.mailbox import read_trace
from sepreplay import xart

SNEW = "20261111-113919"   # snew-reel


def coffre_bytes():
    hits = glob.glob(os.path.join(TRACES, "*_xart_read", "*.gl.bin"))
    if not hits:
        raise unittest.SkipTest("coffre .gl absent")
    with open(sorted(hits)[0], "rb") as f:
        return f.read()


class FetchLenCodecTests(unittest.TestCase):
    def test_documented_examples(self):
        # docs/gigalocker.md : SEP-xART 0x64/0x03 -> 0x364 ; USER-xART 0x14/0x08 -> 0x814 ; gl 0x0c/0x0c -> 0xc0c.
        self.assertEqual(xart.decode_fetch_len(0x64, 0x03), 0x364)
        self.assertEqual(xart.decode_fetch_len(0x14, 0x08), 0x814)
        self.assertEqual(xart.decode_fetch_len(0x0c, 0x0c), 0xc0c)

    def test_roundtrip_with_flag(self):
        # Réponse maître SEP : longueur 0x364, sélecteur sel=1 -> PARAM=0x64 DATA=0x0103 (selftest sep_xart_replay).
        param, data = xart.encode_fetch_len(0x364, flag=xart.SEL_SEP)
        self.assertEqual((param, data), (0x64, 0x0103))
        self.assertEqual(xart.decode_fetch_len(param, data), 0x364)
        self.assertEqual(xart.selector(data), xart.SEL_SEP)

    def test_recalculated_not_replayed(self):
        # Le driver recalcule depuis la taille réelle : une charge arbitraire donne la bonne longueur.
        for ln in (0x28, 0x2014, 0x540, 0x352):
            param, data = xart.encode_fetch_len(ln)
            self.assertEqual(xart.decode_fetch_len(param, data), ln)


class CoffreParseTests(unittest.TestCase):
    def setUp(self):
        self.lockers = xart.parse_coffre(coffre_bytes())

    def test_counts(self):
        masters = [L for L in self.lockers if L.is_master]
        gls = [L for L in self.lockers if not L.is_master]
        self.assertEqual(len(self.lockers), 12)
        self.assertEqual(len(masters), 2)     # SEP-xART (0x02) + USER-xART (0x01)
        self.assertEqual(len(gls), 10)
        self.assertEqual({m.type for m in masters}, {0x01, 0x02})
        print("\n[step6] coffre : %d lockers (%d maîtres + %d gigalockers)" %
              (len(self.lockers), len(masters), len(gls)))

    def test_masters_sizes_and_lookup(self):
        # docs/gigalocker.md : slot 6 = SEP-xART 0x352 ; slot 9 = USER-xART 0x540.
        sep = xart.find_master(self.lockers, xart.SEL_SEP)
        usr = xart.find_master(self.lockers, xart.SEL_USER)
        self.assertEqual((sep.type, sep.length), (0x02, 0x352))
        self.assertEqual((usr.type, usr.length), (0x01, 0x540))
        self.assertEqual(len(sep.payload), 0x352)   # charge de la bonne taille

    def test_gigalocker_lookup_by_uuid(self):
        # slot 11 « Credential Manager » : UUID 8624497a8c2ff2582625a036fab3b8e3 (docs/gigalocker.md).
        uuid = bytes.fromhex("8624497a8c2ff2582625a036fab3b8e3")
        L = xart.find_gigalocker(self.lockers, uuid)
        self.assertIsNotNone(L)
        self.assertEqual(L.type in xart.T_GIGALOCKER, True)
        self.assertIsNone(xart.find_gigalocker(self.lockers, b"\x00" * 16))   # UUID absent -> None


class CrcAndSerializeTests(unittest.TestCase):
    def setUp(self):
        self.raw = coffre_bytes()
        self.lockers = xart.parse_coffre(self.raw)

    def test_crc_matches_all_lockers(self):
        # CRC stocké (+0x16) = zlib.crc32(charge) pour les 12 lockers (algo VÉRIFIÉ, docs/gigalocker.md).
        for L in self.lockers:
            self.assertEqual(L.crc, xart.slot_crc(L.payload), "CRC slot %d" % L.slot)
            self.assertTrue(L.crc_ok)
        print("\n[step6] CRC-32/ISO-HDLC(charge) == CRC stocké pour %d/%d lockers" %
              (len(self.lockers), len(self.lockers)))

    def test_serialize_roundtrip_byte_exact(self):
        # Réécrire un locker parsé reproduit son slot d'origine à l'octet près.
        for L in self.lockers:
            base = L.slot * xart.SLOT
            self.assertEqual(xart.serialize_locker(L), self.raw[base:base + xart.SLOT],
                             "slot %d non identique" % L.slot)

    def test_build_header_new_locker(self):
        # En-tête d'un NOUVEAU locker : type/longueur/CRC corrects ; round-trip parse cohérent.
        payload = b"\xde\xad\xbe\xef" * 20
        h = xart.build_header(xart.T_SEP_MASTER, b"", payload)
        self.assertEqual(h[0x01], xart.T_SEP_MASTER)
        import struct
        self.assertEqual(struct.unpack_from("<I", h, 0x12)[0], len(payload))
        self.assertEqual(struct.unpack_from("<I", h, 0x16)[0], xart.slot_crc(payload))


class SnewSequenceTests(unittest.TestCase):
    def test_xart_opening_sequence(self):
        tr = read_trace(trace_dir(SNEW))
        reqs = [m for m in tr.msgs if m.ep == xart.EP_XART and not m.to_sep]   # SEP->AP ('<')
        self.assertGreater(len(reqs), 5)
        ops = [m.type for m in reqs]
        # Ouverture VU (docs/gigalocker.md §Protocole) : fw-boot puis OS-UUID.
        self.assertEqual(xart.op_name(ops[0]), "fwboot")
        self.assertEqual(xart.op_name(ops[1]), "osuuid")
        names = [xart.op_name(o) for o in ops]
        self.assertIn("fetch_master", names)       # FETCH des maîtres
        # un FETCH maître porte un sélecteur 0/1 dans DATA[1]
        masters = [m for m in reqs if m.type == xart.OP_FETCH_MASTER]
        self.assertTrue(all(xart.selector(m.data) in (xart.SEL_USER, xart.SEL_SEP) for m in masters))
        print("\n[step6] snew-reel : %d requêtes 0x13 ; ouverture %s" % (len(reqs), names[:4]))


if __name__ == "__main__":
    unittest.main()
