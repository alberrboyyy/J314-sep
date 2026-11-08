import glob, os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import trace_dir, TRACES, BOOTS
from sepreplay.mailbox import read_trace
from sepreplay.discovery import DiscoveryTable, cntl_opens, decode_name

# Références publiques : docs/messages.md « Endpoints » (doc Asahi + C1). Utilisées comme ORACLE du test,
# jamais par le code du module.
EXPECTED = {0x00: "cntl", 0x08: "sbio", 0x0a: "scrd", 0x0c: "sse", 0x0e: "hdcp", 0x10: "xars", 0x12: "sks",
            0x13: "xarm", 0x14: "hibe", 0x15: "pnon", 0x17: "skdl", 0x18: "stac"}


class DiscoveryTests(unittest.TestCase):
    def test_name(self):
        self.assertEqual(decode_name(0x7362696f), "sbio")

    def test_all_boots_have_same_12_eps(self):
        for pre in BOOTS:
            tab = DiscoveryTable.from_msgs(read_trace(trace_dir(pre)).msgs)
            self.assertEqual(len(tab.by_ep), 12, pre)
            self.assertEqual({e: tab.name_of(e) for e in tab.by_ep}, EXPECTED, pre)
            self.assertEqual(tab.find("sbio"), 0x08)
            self.assertEqual(tab.find("sks"), 0x12)
            self.assertIsNone(tab.find("zzzz"))

    def test_announcement_order_not_fixed(self):
        """Observation (contredit « C6..C12 ont le même ordre » de verification_status.md) : l'ordre d'annonce
        varie (C7 : 0x17,0x0c avant 0x08 ; C9 : 0x0e avant 0x15). Les 4 premiers EP annoncés sont stables.
        => le pilote ne doit PAS dépendre de l'ordre : chercher par nom."""
        orders = [tuple(DiscoveryTable.from_msgs(read_trace(trace_dir(p)).msgs).order) for p in BOOTS]
        self.assertEqual(len({o[:4] for o in orders}), 1)
        self.assertEqual(len(set(orders)), 3)
        self.assertEqual(len({frozenset(o) for o in orders}), 1)

    def test_sizes_vs_cntl(self):
        """Prédiction (écrite avant) : T4 = octet1 x 0x4000, T5 = octet3 x 0x4000 pour tout EP ouvert par CNTL.
        Résultat = observation (le sens des octets reste `hypothèse`)."""
        checked = bad = 0
        for pre in BOOTS:
            tr = read_trace(trace_dir(pre))
            tab = DiscoveryTable.from_msgs(tr.msgs)
            for ep, seqs in cntl_opens(tr.msgs).items():
                for ss, sa, rs, ra in seqs:
                    checked += 1
                    if (ss, rs) != (tab.by_ep[ep].max_send, tab.by_ep[ep].max_recv):
                        bad += 1
        self.assertGreater(checked, 0)
        self.assertEqual(bad, 0, "%d/%d séquences hors prédiction" % (bad, checked))
        print("\n[step2] FD tailles <-> CNTL T4/T5 : %d/%d séquences conformes (8 boots)" % (checked - bad, checked))

    def test_sbio_buffers_c11(self):
        tr = read_trace(trace_dir("20261108-025802"))
        o = cntl_opens(tr.msgs)[0x08]
        self.assertEqual(o, [(0x4000, 0x64000, 0x4000, 0x6c000)])   # C11 L138-145 (iova A=0x64000, B=0x6c000)


if __name__ == "__main__":
    unittest.main()
