import glob, os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TRACES
from sepreplay.crc import crc16_arc, self_test
from sepreplay.sensor import parse_status, parse_frame, status_from_uart_line, build_read_request

STATUS = bytes.fromhex("80 20 00 10 00 00 00 00 60 00 00 00 52 33 00 00")


class SensorTests(unittest.TestCase):
    def test_crc_vector(self):
        self.assertTrue(self_test())

    def test_status_constant(self):
        s = parse_status(STATUS)
        self.assertEqual((s.frame.op, s.frame.index, s.frame.total_len), (0x20, 0, 0x10))
        self.assertTrue(s.frame.length_ok)
        self.assertEqual(len(s.frame.payload), 9)
        self.assertEqual((s.state_byte, s.avail_u32), (0, 0x3352))
        self.assertFalse(s.trailer_is_crc16_arc)          # messages.md : 0x35de attendu, pas CRC-16/ARC
        self.assertEqual(crc16_arc(STATUS[:-2]), 0x35DE)

    def test_bad(self):
        with self.assertRaises(ValueError):
            parse_frame(b"\x00\x20\x00")
        with self.assertRaises(ValueError):
            parse_status(bytes([0x80, 0x13, 0, 0x0B, 0, 0, 0]))

    def test_read_request(self):
        r = build_read_request(0x7200)
        self.assertEqual(len(r), 11)
        f = parse_frame(r)
        self.assertEqual((f.op, f.total_len), (0x13, 0x0B))
        self.assertEqual(int.from_bytes(r[7:], "little"), 0x7200)

    def test_all_uart_logs(self):
        logs = sorted(glob.glob(os.path.join(TRACES, "*", "hv_uart.log")))
        found = same = 0
        for p in logs:
            with open(p, errors="replace") as f:
                for line in f:
                    raw = status_from_uart_line(line)
                    if raw is not None:
                        found += 1
                        same += raw == STATUS
        self.assertGreaterEqual(found, 16)               # 16/16 dans la doc ; 20 comptées
        self.assertEqual(found, same)
        print("\n[step3] statut capteur identique dans %d/%d traces portant la ligne SensorStatus" % (same, found))


if __name__ == "__main__":
    unittest.main()
