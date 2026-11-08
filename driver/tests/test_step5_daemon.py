import glob, hashlib, os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TRACES, trace_dir, C11, C12
from sepreplay.mailbox import read_trace
from sepreplay.gt import reassemble
from sepreplay.daemon import INIT_SEQUENCE, BlobStore, InitPlan, export_request, blob_uid, T_EXPORT, T_IMPORT

C8, C9, C10B = "20261108-004657", "20261108-010915", "20261108-012015"


def sbio_traces():
    out = []
    for d in sorted(glob.glob(os.path.join(TRACES, "*", "sep.log"))):
        tr = read_trace(d)
        if any(m.ep == 8 and m.tag == 0xFC and m.dir == ">" for m in tr.msgs):
            out.append(tr)
    return out


def ap_cmds(tr):
    return [m.type for m in tr.msgs if m.ep == 8 and m.tag == 0xFC and m.dir == ">"]


def imports(tr):
    return [t for t in reassemble(tr, 8, {T_IMPORT}) if t.total > 0 and t.dir == ">" and t.buf == "A"]


def exports(tr):
    """(requête, réponse) de chaque 0x6c : réponse = dir '<' tampon B ; requête = transfert 0x18 juste avant."""
    ts = reassemble(tr, 8, {T_EXPORT})
    out = []
    for i, t in enumerate(ts):
        if t.total > 0x18 and t.dir == "<" and t.buf == "B":
            req = next(r for r in reversed(ts[:i]) if r.total == 0x18)
            out.append((req, t))
    return out


class InitSequenceTests(unittest.TestCase):
    def test_57_commands_on_all_captures(self):
        trs = sbio_traces()
        n = sum(ap_cmds(t)[:57] == list(INIT_SEQUENCE) for t in trs)
        self.assertEqual(n, len(trs))
        self.assertEqual(len(trs), 18)
        print("\n[step5] séquence d'init de 57 commandes reproduite exactement : %d/%d captures avec sbio" % (n, len(trs)))

    def test_plan_without_store_has_only_types(self):
        cmds = InitPlan(BlobStore()).commands()
        self.assertEqual([c[0] for c in cmds], list(INIT_SEQUENCE))
        self.assertEqual(sum(c[0] == T_IMPORT for c in cmds), 2)
        self.assertTrue(all(c[1] is None for c in cmds))


class BlobLoopTests(unittest.TestCase):
    def store_from(self, tr, which):
        s = BlobStore()
        items = [t.blob for t in imports(tr)] if which == "imports" else [r.blob for _, r in exports(tr)]
        for b in items:
            s.on_export(b)
        return s

    def check_boot(self, tr, store):
        """Le plan du démon doit donner, aux slots 0x6d, les mêmes octets que ceux envoyés par macOS dans cette trace."""
        plan = [c for c in InitPlan(store).commands() if c[0] == T_IMPORT]
        sent = [t.blob for t in imports(tr)]
        self.assertEqual(len(sent), 2)
        return sum(p[1] == s for p, s in zip(plan, sent)), plan, sent

    def test_c11_to_c12_exact(self):
        c11 = read_trace(trace_dir(C11))
        ex = exports(c11)
        self.assertEqual(len(ex), 14)                                # 7 paires (501 puis -1) dans C11
        store = self.store_from(c11, "exports")
        ok, _, _ = self.check_boot(read_trace(trace_dir(C12)), store)
        self.assertEqual(ok, 2)
        print("\n[step5] C11 -> C12 : %d/2 blobs 0x6d identiques (sha complet) au dernier 0x6c de C11" % ok)

    def test_exports_requests_and_headers_c11(self):
        ex = exports(read_trace(trace_dir(C11)))
        self.assertEqual(len(ex), 14)
        for req, resp in ex:
            self.assertEqual(req.blob, export_request(blob_uid(resp.blob)))
            self.assertEqual(resp.complete, True)
            self.assertEqual(len(resp.blob), resp.total)
        self.assertEqual({blob_uid(r.blob) for _, r in ex}, {501, 0xFFFFFFFF})

    def test_c9_persistence_to_c11(self):
        """C9 -> C11 : C10b n'a aucun succès entre les deux ; le store rechargé depuis les imports C9 redonne ceux de C11."""
        c9, c11 = read_trace(trace_dir(C9)), read_trace(trace_dir(C11))
        store = self.store_from(c9, "imports")
        ok, _, _ = self.check_boot(c11, store)
        self.assertEqual(ok, 2)
        self.assertEqual(len(imports(read_trace(trace_dir(C10B)))), 2)

    def test_c8_to_c9_partial(self):
        """C8 -> C9 : les gros exports de C8 ne sont lus qu'en 3 morceaux de 996 o (tracer sans full_types 0x6c, offsets 0,
        16356, 32712). Égalité exacte pour le petit blob (uid -1) ; pour le gros : longueur annoncée identique et les
        3 x 996 o lus égaux octet pour octet aux mêmes offsets de l'import de C9."""
        c8, c9 = read_trace(trace_dir(C8)), read_trace(trace_dir(C9))
        store = BlobStore()
        exp = exports(c8)
        for _, r in exp:
            if r.complete:
                store.on_export(r.blob)
        sent = imports(c9)
        small = [c[1] for c in InitPlan(store).commands() if c[0] == T_IMPORT][0]
        self.assertEqual(small, sent[0].blob)
        last = [r for _, r in exp if blob_uid(r.blob) == 501][-1]
        self.assertFalse(last.complete)
        self.assertEqual(last.total, sent[1].total)                  # 0x9317
        self.assertEqual(sorted(last.chunks), [0, 16356, 32712])
        for off, piece in last.chunks.items():
            self.assertEqual(sent[1].chunks[off][:len(piece)], piece)
        print("\n[step5] C8 -> C9 : petit blob exact ; gros : longueur 0x%x identique, 3 x 996 o lus identiques (partiel, tracer)" % last.total)

    def test_wrong_blob_rejected(self):
        with self.assertRaises(ValueError):
            BlobStore().on_export(b"XXXX" + bytes(40))


if __name__ == "__main__":
    unittest.main()
