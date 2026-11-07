#!/usr/bin/env python3
"""Tests de analysis/ool_view.py sur des dumps SYNTHÉTIQUES (fake_ool/, voir SYNTHETIQUE.txt).

    python3 -m unittest discover -s analysis/tests -v
"""

import io
import os
import sys
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import ool_view  # noqa: E402

FAKE = os.path.join(HERE, "fake_ool")


class TestOolView(unittest.TestCase):
    def test_diff_ranges(self):
        self.assertEqual(ool_view.diff_ranges(b"\0" * 8, b"\0\1\1\0\0\0\0\2"), [(1, 2), (7, 1)])
        self.assertEqual(ool_view.diff_ranges(b"ab", b"ab"), [])
        self.assertEqual(ool_view.diff_ranges(b"abc", b"abXYZ"), [(2, 3)])
        self.assertEqual(ool_view.diff_ranges(b"abc", b"abcde"), [(3, 2)])

    def test_find_and_list(self):
        d = ool_view.find_dir(FAKE)          # capture -> unique *.ool
        self.assertTrue(d.endswith("sep.log.ool"))
        groups, ignored = ool_view.list_dumps(d)
        self.assertEqual(ignored, ["notes.txt"])
        self.assertEqual([s for s, _ in groups[(0x08, "A")]], [11, 12, 20])
        self.assertEqual([s for s, _ in groups[(0x08, "B")]], [11, 16])

    def test_cli_output(self):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = ool_view.main([FAKE, "--buf", "A"])
        txt = out.getvalue()
        self.assertEqual(rc, 0)
        self.assertNotIn("buf=B", txt)
        self.assertIn("diff seq=11 -> seq=12 plages=2 : 0x10+0x4,0x3f+0x1", txt)
        self.assertIn("diff seq=12 -> seq=20 plages=1 : 0x10+0x1", txt)
        self.assertIn("000010 + 01 02 03 04", txt)
        self.assertIn("nz=5", txt)

    def test_length_change(self):
        out = io.StringIO()
        with redirect_stdout(out):
            ool_view.main([os.path.join(FAKE, "sep.log.ool"), "--ep", "0x08", "--buf", "B"])
        self.assertIn("plages=1 : 0x20+0x4", out.getvalue())


if __name__ == "__main__":
    unittest.main()
