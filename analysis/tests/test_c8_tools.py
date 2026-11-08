#!/usr/bin/env python3
"""Tests de sbio_latency.pairs, ool_attempts.assemble/ranges et ool_index.content_end sur des données
SYNTHÉTIQUES construites en mémoire (aucune capture réelle).

    python3 -m unittest discover -s analysis/tests -v
"""

import os
import struct
import sys
import unittest
from collections import namedtuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import lock_cycles  # noqa: E402
import ool_attempts  # noqa: E402
import ool_index  # noqa: E402
import sbio_latency  # noqa: E402

M = namedtuple("M", "lineno ts dir ep tag type param data ool")


def chunk(t, total, off, payload):
    return struct.pack("<7I", 1, total, off, 0, 0, t, len(payload)) + payload


class TestC8Tools(unittest.TestCase):
    def test_pairs(self):
        msgs = [M(1, 1.000, ">", 8, 0xFC, 0x23, 0, 0, None),
                M(2, 1.002, "<", 8, 0xFC, 0x23, 0, 0, None),
                M(3, 1.010, ">", 8, 0xFC, 0x65, 0, 0, None),
                M(4, 1.011, "<", 8, 0xFE, 0x65, 0, 0, None),
                M(5, 1.012, ">", 8, 0xFD, 0x65, 0, 0x10000, None),
                M(6, 1.020, "<", 8, 0xFC, 0x65, 0, 0, None),
                M(7, 1.030, ">", 0x12, 0xFC, 0x23, 0, 0, None)]
        p = sbio_latency.pairs(msgs, 8)
        self.assertEqual([(t, l1, l2, fr) for t, _, l1, l2, fr in p], [(0x23, 1, 2, 0), (0x65, 3, 6, 2)])
        self.assertAlmostEqual(p[0][1], 2.0, places=3)

    def test_assemble(self):
        body = bytes(range(256)) * 2
        r1 = {"data": chunk(0x65, 512, 0, body[:300]), "msg": {"type": 0x65, "lineno": 10}}
        r2 = {"data": chunk(0x65, 512, 300, body[300:]), "msg": {"type": 0x65, "lineno": 12}}
        rx = {"data": chunk(0x07, 4, 0, b"abcd"), "msg": {"type": 0x65, "lineno": 13}}  # TYPE incohérent : ignoré
        total, b, lines, have = ool_attempts.assemble([r1, r2, rx])
        self.assertEqual((total, b, lines, have), (512, body, [10, 12], 512))
        self.assertIsNone(ool_attempts.assemble([rx]))

    def test_ranges_and_end(self):
        self.assertEqual(ool_attempts.ranges(list("CCDVVC"), "V"), [(3, 5)])
        self.assertEqual(ool_attempts.fmt_ranges([(0, 1), (3, 5)]), "0x0, 0x3-0x4")
        self.assertEqual(ool_index.content_end(b"\1\0\2\0\0"), 3)
        self.assertEqual(ool_index.content_end(b"\0\0"), 0)


class TestOolIndexKey(unittest.TestCase):
    """Capture SYNTHÉTIQUE (tempdir) : une ligne changed=none doit renvoyer au dernier .bin de même
    (buffer, longueur), comme le tracer, pas au dernier .bin du buffer."""

    def test_none_uses_same_length(self):
        import hashlib
        import shutil
        import tempfile
        d = tempfile.mkdtemp()
        try:
            os.mkdir(os.path.join(d, "sep.log.ool"))
            small = b"\1" + b"\0" * 0x3FF          # lecture 0x400
            big = b"\0" * 0x4000                     # lecture complète, tout à zéro
            for name, blob in (("000001_08_B.bin", big), ("000002_08_B.bin", small)):
                with open(os.path.join(d, "sep.log.ool", name), "wb") as f:
                    f.write(blob)
            sha = lambda b: hashlib.sha256(b).hexdigest()[:8]  # noqa: E731
            log = [
                "1.0 < EP=0x08 TAG=0xfc TYPE=0x65 PARAM=0x00 DATA=0x00000000",
                "# ool 1.0 seq=1 EP=0x08 dir=< buf=B sha=%s nz=0 changed=init len=0x4000 elapsed_ms=0.1 file=000001_08_B.bin" % sha(big),
                "2.0 < EP=0x08 TAG=0xfc TYPE=0x06 PARAM=0x00 DATA=0x00000000",
                "# ool 2.0 seq=2 EP=0x08 dir=< buf=B sha=%s nz=1 changed=init len=0x400 elapsed_ms=0.1 file=000002_08_B.bin" % sha(small),
                "3.0 < EP=0x08 TAG=0xfe TYPE=0x65 PARAM=0x00 DATA=0x00000000",
                "# ool 3.0 seq=3 EP=0x08 dir=< buf=B sha=%s nz=0 changed=none len=0x4000 elapsed_ms=0.1" % sha(big),
            ]
            with open(os.path.join(d, "sep.log"), "w") as f:
                f.write("\n".join(log) + "\n")
            rows = ool_index.load_index(d, 0x08)
            self.assertEqual(rows[2]["src"], "000001_08_B.bin")
            self.assertEqual(rows[2]["end"], 0)
            self.assertTrue(all(r["sha_ok"] for r in rows))
        finally:
            shutil.rmtree(d)


class TestLockCyclesClock(unittest.TestCase):
    """Lignes ACMTRM INVENTÉES reprenant les deux formes de `now=` (C3 : epoch(0), C8 : secondes(base))."""

    def test_state_epoch(self):
        self.assertEqual(lock_cycles.state_epoch(1794020395, 0), 1794020395)   # forme C3
        self.assertEqual(lock_cycles.state_epoch(739, 1794023194), 1794023933)  # forme C8
        self.assertIsNone(lock_cycles.state_epoch(504, 0))                     # ni l'un ni l'autre

    def test_load_states_and_offset(self):
        import tempfile
        lines = [b"x ACMTRM: _publish: _onDeviceLockStateChanged LOCKED(1) reason=1 seen=0 now=1794020395(0)\r",
                 b"bruit",
                 b"ACMTRM: _publish: _startPolicy UNLOCKED(0) reason=0 now=504(0)",
                 b"ACMTRM: _publish: _onDeviceLockStateChanged UNLOCKED(0) reason=0 now=739(1794023194)"]
        with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
            f.write(b"\n".join(lines))
        try:
            st = lock_cycles.load_states(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(st, [(1794020395, "LOCKED", 1), (1794023933, "UNLOCKED", 4)])
        fn, desc = lock_cycles.mac_to_pc_fn("/inexistant", "71546")
        self.assertEqual(fn(1794023933), 1794095479.0)
        self.assertIn("+71546.0", desc)


if __name__ == "__main__":
    unittest.main()
