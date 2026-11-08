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


if __name__ == "__main__":
    unittest.main()
