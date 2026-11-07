#!/usr/bin/env python3
"""Tests unitaires de analysis/ sur des traces SYNTHÉTIQUES inventées (fake_a/, fake_b/).

Ces fichiers ne sont pas des captures. Lancer depuis la racine du repo :
    python3 -m unittest discover -s analysis/tests -v
"""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import diff_traces  # noqa: E402
import parse_trace  # noqa: E402

FAKE_A = os.path.join(HERE, "fake_a")
FAKE_B = os.path.join(HERE, "fake_b", "trace.log")


class TestParse(unittest.TestCase):
    def test_counts(self):
        msgs, bad, comments = parse_trace.parse_file_full(FAKE_A)  # dossier -> trace.log
        self.assertEqual(len(msgs), 6)
        self.assertEqual(comments, 3)  # 2 commentaires + 1 ligne vide
        self.assertEqual([b.lineno for b in bad], [8, 10, 11])
        self.assertIn("hors plage", bad[1].reason)

    def test_fields(self):
        msgs, _ = parse_trace.parse_file(FAKE_A)
        m = msgs[1]
        self.assertEqual((m.lineno, m.ts, m.dir, m.ep, m.tag, m.type, m.param, m.data, m.ool),
                         (4, 101.5, "<", 0x08, 0x01, 0x81, 0x00, 1, None))
        self.assertIsInstance(msgs[0].ts, int)
        self.assertEqual(msgs[5].ool, "buf@0x1000 len=0x40")
        self.assertEqual(msgs[5].lineno, 9)

    def test_stats(self):
        msgs, _ = parse_trace.parse_file(FAKE_A)
        st = parse_trace.compute_stats(msgs)
        self.assertEqual(st["by_ep"][(0x08,)]["count"], 3)
        e = st["by_param"][(0x08, ">", 0x01, 0x00)]
        self.assertEqual((e["count"], e["first_line"], e["last_line"], e["first_ts"], e["last_ts"],
                          e["distinct_data"]), (2, 3, 9, 100, 104, 2))
        self.assertEqual(st["by_type"][(0x18, "<", 0x0f)]["distinct_data"], 1)

    def test_ep_filter(self):
        msgs, _ = parse_trace.parse_file(FAKE_A)
        f = parse_trace.filter_eps(msgs, parse_trace.parse_ep_list("0x18, 0x0a"))
        self.assertEqual({m.ep for m in f}, {0x18, 0x0a})

    def test_cli_json_and_bad_lines_reported(self):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = parse_trace.main([FAKE_A, "--json"])
        self.assertEqual(rc, 0)
        doc = json.loads(out.getvalue())
        self.assertEqual(doc["n_bad_lines"], 3)
        self.assertEqual(doc["bad_lines_sample"][0]["lineno"], 8)
        self.assertIn("3 ligne(s) invalide(s)", err.getvalue())

    def test_text_shows_bad_lines(self):
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            parse_trace.main([FAKE_A])
        self.assertIn("L8 [format non reconnu]", out.getvalue())

    def test_refuse_write_outside_out(self):
        root = parse_trace.REPO_ROOT
        for bad in (os.path.join(root, "traces", "x.txt"),
                    os.path.join(root, "docs", "x.txt"),
                    os.path.join(root, "analysis", "out", "..", "x.txt")):
            with self.assertRaises(ValueError):
                parse_trace.safe_output_path(bad)
        ok = os.path.join(root, "analysis", "out", "sub", "x.txt")
        self.assertEqual(parse_trace.safe_output_path(ok), ok)
        with redirect_stderr(io.StringIO()):
            rc = parse_trace.main([FAKE_A, "-o", os.path.join(root, "traces", "x.txt")])
        self.assertEqual(rc, 2)
        self.assertFalse(os.path.exists(os.path.join(root, "traces", "x.txt")))


FAKE_MARKS = os.path.join(HERE, "fake_marks")


class TestBetween(unittest.TestCase):
    def test_window_inclusive(self):
        msgs, _ = parse_trace.parse_file(FAKE_MARKS)
        s, e = parse_trace.find_window(parse_trace.load_marks(parse_trace.marks_path_for(FAKE_MARKS)),
                                       "doigt", "retrait")
        self.assertEqual((s.ts, e.ts, s.lineno, e.lineno), (1001.5, 1004.0, 3, 4))
        w = parse_trace.filter_window(msgs, s.ts, e.ts)
        self.assertEqual([m.lineno for m in w], [4, 5, 6])  # 1002, 1003, 1004 (borne incluse)

    def test_end_must_follow_start(self):
        marks = parse_trace.load_marks(parse_trace.marks_path_for(FAKE_MARKS))
        s, e = parse_trace.find_window(marks, "retrait", "doigt")  # 2e "doigt", après "retrait"
        self.assertEqual(e.ts, 1004.5)
        with self.assertRaises(ValueError):
            parse_trace.find_window(marks, "doigt", "debut")
        with self.assertRaises(ValueError):
            parse_trace.find_window(marks, "inconnu", "doigt")

    def test_cli_between(self):
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            rc = parse_trace.main([os.path.join(FAKE_MARKS, "sep.log"), "--between", "doigt", "retrait",
                                   "--ep", "0x08", "--json"])
        self.assertEqual(rc, 0)
        doc = json.loads(out.getvalue())
        self.assertEqual(doc["n_messages"], 2)
        self.assertEqual(doc["window"]["start"]["label"], "doigt")
        self.assertAlmostEqual(doc["window"]["duration_s"], 2.5)

    def test_cli_between_errors(self):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(parse_trace.main([FAKE_A, "--between", "a", "b"]), 2)  # pas de marks.txt
            self.assertEqual(parse_trace.main([FAKE_MARKS, "--between", "x", "doigt"]), 2)


class TestDiff(unittest.TestCase):
    def setUp(self):
        self.a, _ = parse_trace.parse_file(FAKE_A)
        self.b, _ = parse_trace.parse_file(FAKE_B)

    def test_sets(self):
        d = diff_traces.diff_sets(self.a, self.b)
        self.assertEqual([k for k, _, _ in d["only_a"]], [(0x0a, "<", 0x02, 0x01)])
        self.assertEqual([k for k, _, _ in d["only_b"]], [(0x08, ">", 0x02, 0x03)])
        self.assertEqual([(k, ca, cb) for k, ca, cb, _, _ in d["changed"]],
                         [((0x18, "<", 0x0f, 0x00), 1, 2), ((0x18, ">", 0x0f, 0x00), 1, 2)])

    def test_seq_ignores_tag_and_data(self):
        r = diff_traces.diff_sequences(self.a, self.b)
        blocks = r[0x08]["blocks"]
        self.assertEqual(len(blocks), 1)
        op, ba, bb = blocks[0]
        self.assertEqual(op, "insert")
        self.assertEqual([m.lineno for m in bb], [5])
        self.assertEqual(r[0x0a]["blocks"][0][0], "delete")
        self.assertEqual([m.lineno for m in r[0x18]["blocks"][0][2]], [9, 10])

    def test_identical_sequences(self):
        r = diff_traces.diff_sequences(self.a, self.a)
        self.assertTrue(all(not v["blocks"] for v in r.values()))

    def test_cli_header(self):
        out = io.StringIO()
        with redirect_stdout(out), redirect_stderr(io.StringIO()):
            rc = diff_traces.main([FAKE_A, FAKE_B, "--seq"])
        self.assertEqual(rc, 0)
        self.assertIn("observation, pas une interprétation", out.getvalue())
        self.assertIn("+ B L5", out.getvalue())


if __name__ == "__main__":
    unittest.main()
