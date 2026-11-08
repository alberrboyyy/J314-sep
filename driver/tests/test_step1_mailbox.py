import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import trace_dir, C8, C11, C12
from sepreplay.mailbox import decode_word, encode_word, read_trace

# Comptes connus (tail `# end seen=N logged=N` du tracer, comptés indépendamment par grep)
KNOWN = {C8: 3981, C11: 6348, C12: 641}


class WordTests(unittest.TestCase):
    def test_layout(self):
        ep, tag, typ, par, data = decode_word(0x11223344_55667788)
        self.assertEqual((ep, tag, typ, par, data), (0x88, 0x77, 0x66, 0x55, 0x11223344))
        self.assertEqual(encode_word(ep, tag, typ, par, data), 0x11223344_55667788)

    def test_range(self):
        with self.assertRaises(ValueError):
            encode_word(0x100, 0, 0, 0, 0)
        with self.assertRaises(ValueError):
            decode_word(1 << 64)


class ReplayTests(unittest.TestCase):
    def test_counts_and_roundtrip(self):
        for pre, n in KNOWN.items():
            tr = read_trace(trace_dir(pre))
            self.assertEqual(len(tr.msgs), n, pre)
            self.assertEqual((tr.end_seen, tr.end_logged), (n, n))
            self.assertEqual(tr.bad_lines, [])
            for m in tr.msgs:
                self.assertEqual(decode_word(m.word), (m.ep, m.tag, m.type, m.param, m.data))

    def test_ool_reads_c11(self):
        tr = read_trace(trace_dir(C11))
        self.assertEqual(len(tr.ool), 994)           # 994 lectures OOL EP 0x08 (journal C11)
        self.assertTrue(all(o.msg is not None for o in tr.ool))

    def test_ool_reads_c8_c12(self):
        self.assertEqual(len(read_trace(trace_dir(C8)).ool), 480)
        self.assertEqual(len(read_trace(trace_dir(C12)).ool), 151)


if __name__ == "__main__":
    unittest.main()
