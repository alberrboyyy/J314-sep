import glob, os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TRACES, trace_dir, C11, C12
from sepreplay.mailbox import read_trace
from sepreplay.gt import (check_counters, reassemble, check_slices, load_ool, IMAGE_LEN, T_IMAGE, SLICE_LEN, OOL_MAX_CHUNK)
from sepreplay.crc import crc16_arc

C6, C8 = "20261107-043828", "20261108-004657"


def images(tr):
    """Transferts 0x65 AP->SEP (dir '>' tampon A) : on écarte les relectures de la même charge sous '<' (anciens tracers sans split_dir)."""
    return [t for t in reassemble(tr, 8, {T_IMAGE}) if t.total and t.dir == ">" and t.buf == "A"]


class CounterTests(unittest.TestCase):
    def test_counter_rule_all_traces(self):
        tot = bad = n_tr = 0
        for d in sorted(glob.glob(os.path.join(TRACES, "*", "sep.log"))):
            tr = read_trace(d)
            n, b = check_counters(tr.msgs, 0x08)
            tot += n
            bad += len(b)
            n_tr += n > 0
            self.assertEqual(b, [], d)
        self.assertGreater(tot, 4006)
        print("\n[step4] compteur GT : %d messages fc/fd/fe sur %d traces, %d exceptions" % (tot, n_tr, bad))

    def test_counter_rule_detects_error(self):
        from sepreplay.mailbox import Msg
        ms = [Msg(1, "0", ">", 8, 0xFC, 0x6D, 0, 0), Msg(2, "0", "<", 8, 0xFE, 0x6D, 0, 0),
              Msg(3, "0", ">", 8, 0xFD, 0x6D, 0, 0x20000)]
        n, bad = check_counters(ms, 8)
        self.assertEqual((n, len(bad)), (3, 1))


class ReassemblyTests(unittest.TestCase):
    def test_ool_sha_integrity(self):
        n = 0
        for pre in (C6, C8, C11, C12):
            for r in load_ool(read_trace(trace_dir(pre)), 8):
                self.assertIsNot(r.sha_ok, False)
                n += r.sha_ok is True
        self.assertGreater(n, 0)

    def test_c11_65_24_of_24(self):
        im = images(read_trace(trace_dir(C11)))
        self.assertEqual(len(im), 24)
        self.assertTrue(all(t.complete and t.total == IMAGE_LEN and len(t.blob) == IMAGE_LEN for t in im))
        self.assertTrue(all(len(t.chunks) == 2 or len(t.chunks) == 3 for t in im))      # 0x7200 / 0x3fe4 -> 3 morceaux
        ok = sum(o for t in im for _, o in check_slices(t.blob))
        self.assertEqual(ok, 288)
        print("\n[step4] C11 : 24/24 transferts 0x65 de 0x7200 o ; %d/288 CRC OK" % ok)

    def test_65_all_sessions_39_images_468_slices(self):
        n_img = n_ok = 0
        for pre in (C6, C8, C11):
            im = images(read_trace(trace_dir(pre)))
            n_img += sum(t.complete and t.total == IMAGE_LEN for t in im)
            n_ok += sum(o for t in im for _, o in check_slices(t.blob))
        self.assertEqual((n_img, n_ok), (39, 468))
        print("\n[step4] C6+C8+C11 : %d/39 images, %d/468 tranches CRC OK" % (n_img, n_ok))

    def test_slice_detects_corruption(self):
        t = images(read_trace(trace_dir(C11)))[0]
        b = bytearray(t.blob)
        b[SLICE_LEN * 5 + 100] ^= 1
        res = check_slices(bytes(b))
        self.assertEqual([k for k, o in res if not o], [5])

    def test_fixed_sizes_c11_c12(self):
        """Tailles 0x5b = 0xfc99 (sha d5a6117d identique), 0x5f = 0x568e puis 0x70ce : lues dans les OOL (hypothèses de verification_status)."""
        seen = {}
        for pre in (C11, C12):
            ts = [t for t in reassemble(read_trace(trace_dir(pre)), 8, {0x5B, 0x5F}) if t.total > 2]
            self.assertTrue(all(t.complete for t in ts))
            seen[pre] = [(t.type, t.total) for t in ts]
            self.assertEqual(seen[pre], [(0x5F, 0x568E), (0x5B, 0xFC99), (0x5F, 0x70CE)])


if __name__ == "__main__":
    unittest.main()
