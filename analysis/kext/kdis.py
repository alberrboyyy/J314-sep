#!/usr/bin/env python3
"""Outils de désassemblage pour un kext du fileset (phase 2, extraction de protocole uniquement).

Dépend de capstone (venv du scratchpad). Produit des index (références de chaînes, appels,
immédiats) ; n'écrit aucun code désassemblé dans le repo (les listings vont dans analysis/out/, ignoré).

  kdis.py KERNEL BUNDLE strrefs            # fonction -> chaînes référencées (adrp+add)
  kdis.py KERNEL BUNDLE callers ADDR       # sites d'appel `bl ADDR` + w1/w2 immédiats avant l'appel
  kdis.py KERNEL BUNDLE func ADDR          # listing d'une fonction (vers stdout, à ne pas commiter)
"""
import os
import re
import sys

import capstone

sys.path.insert(0, os.path.dirname(__file__))
from macho_fileset import Image, fileset_entries, segments  # noqa: E402


class Kext:
    def __init__(self, path, bundle):
        self.img = Image(path)
        fo = dict((n, f) for n, v, f in fileset_entries(self.img.buf))[bundle]
        self.segs = segments(self.img.buf, fo)
        text = [s for seg in self.segs for s in seg[5] if s[0] == "__text"][0]
        self.text_va, self.text_size, toff = text[1], text[2], text[3]
        self.cstr = [s for seg in self.segs for s in seg[5] if s[0] in ("__cstring", "__os_log")]
        md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
        md.detail = False
        self.ins = []
        code = self.img.buf[toff:toff + self.text_size]
        # désassemblage linéaire, en sautant les mots non décodables
        off = 0
        while off < len(code):
            got = False
            for i in md.disasm_lite(code[off:], self.text_va + off):
                self.ins.append(i)
                off = i[0] - self.text_va + i[1]
                got = True
            if off < len(code):
                self.ins.append((self.text_va + off, 4, ".word", ""))
                off += 4
        self.idx = {a: n for n, (a, *_r) in enumerate(self.ins)}
        self._funcs()

    def _funcs(self):
        """Début de fonction = instruction pacibsp / stp x29,x30 précédée d'un ret/b, ou cible de bl."""
        starts = set()
        for a, s, m, o in self.ins:
            if m == "bl":
                t = int(o.lstrip("#"), 16)
                if self.text_va <= t < self.text_va + self.text_size:
                    starts.add(t)
            if m == "pacibsp":
                starts.add(a)
        self.fstarts = sorted(starts)

    def func_of(self, va):
        import bisect
        i = bisect.bisect_right(self.fstarts, va) - 1
        return self.fstarts[i] if i >= 0 else None

    def func_range(self, start):
        import bisect
        i = bisect.bisect_right(self.fstarts, start)
        end = self.fstarts[i] if i < len(self.fstarts) else self.text_va + self.text_size
        return start, end

    def is_str(self, va):
        return any(s[1] <= va < s[1] + s[2] for s in self.cstr)

    def adr_targets(self):
        """(addr_ins, cible) pour adrp+add / adr."""
        regs = {}
        out = []
        for a, s, m, o in self.ins:
            if m == "adrp":
                r, imm = o.split(", ")
                regs[r] = int(imm.lstrip("#"), 16)
            elif m == "add" and "#" in o:
                p = o.split(", ")
                if len(p) == 3 and p[1] in regs and p[2].startswith("#"):
                    t = regs[p[1]] + int(p[2].lstrip("#"), 0)
                    out.append((a, t))
                    regs.pop(p[1], None)
            elif m == "adr":
                r, imm = o.split(", ")
                out.append((a, int(imm.lstrip("#"), 16)))
        return out

    def strrefs(self):
        res = {}
        for a, t in self.adr_targets():
            if self.is_str(t):
                f = self.func_of(a)
                res.setdefault(f, []).append((a, self.img.cstr(t, 120)))
        return res

    def callers(self, target):
        out = []
        for n, (a, s, m, o) in enumerate(self.ins):
            if m in ("bl", "b") and o == f"#{target:#x}":
                regs = {}
                for k in range(n - 1, max(n - 25, 0), -1):
                    aa, ss, mm, oo = self.ins[k]
                    if mm in ("ret", "bl", "b") and k != n:
                        break
                    if mm in ("mov", "movz", "orr"):
                        p = oo.split(", ")
                        if p[0] in ("w1", "w2", "w3", "x1", "x2", "x3") and p[0][1:] not in regs:
                            regs[p[0][1:]] = oo
                out.append((a, self.func_of(a), regs))
        return out

    def listing(self, start):
        s, e = self.func_range(start)
        tg = dict(self.adr_targets())
        for a, sz, m, o in self.ins[self.idx[s]:self.idx.get(e, len(self.ins))]:
            note = ""
            if a in tg:
                t = tg[a]
                note = f"  ; {t:#x}"
                if self.is_str(t):
                    note += " " + repr(self.img.cstr(t, 80))
            yield f"{a:#x}: {m} {o}{note}"


def fname(k, f, refs):
    """Nom de fonction : 1re chaîne qui ressemble à un identifiant (__func__ des asserts/logs)."""
    for a, s in refs.get(f, []):
        if s and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", s) and len(s) > 3:
            return s
    return "?"


def main():
    k = Kext(sys.argv[1], sys.argv[2])
    cmd = sys.argv[3]
    refs = k.strrefs()
    if cmd == "strrefs":
        for f in sorted(refs):
            print(f"{f:#x} {fname(k, f, refs)}: " + " | ".join(repr(s)[:60] for a, s in refs[f]))
    elif cmd == "callers":
        t = int(sys.argv[4], 16)
        for a, f, regs in k.callers(t):
            print(f"{a:#x} in {f:#x} {fname(k, f, refs):35} {regs}")
    elif cmd == "vcallers":
        # appels virtuels arm64e : `mov x17, #SLOT` ou `add x8, x16, #SLOT`, puis blraa ;
        # on relève les registres d'arguments posés entre l'autda précédent et le blraa.
        slot = int(sys.argv[4], 16)
        pats = (f"x17, #{slot:#x}", f"x16, #{slot:#x}")
        seen = set()
        for n, (a, sz, m, o) in enumerate(k.ins):
            if not (m in ("mov", "add") and o.endswith(pats)):
                continue
            j = next((q for q in range(n, min(n + 30, len(k.ins))) if k.ins[q][2].startswith("blr")), None)
            if j is None or j in seen:
                continue
            seen.add(j)
            st = n
            while st > n - 30 and k.ins[st][2] != "autda":
                st -= 1
            regs = {}
            for q in range(j - 1, st - 12, -1):
                aa, ss, mm, oo = k.ins[q]
                if mm.startswith("bl") or mm in ("ret", "b", "retab"):
                    break
                p = oo.split(", ")
                r = p[0] if p else ""
                if r[:1] in "wx" and r[1:] in ("1", "2", "3", "4", "5", "6") and r[1:] not in regs:
                    regs[r[1:]] = f"{mm} {oo}"
            f = k.func_of(a)
            cmdv = regs.get("1", "")
            print(f"{k.ins[j][0]:#x}\t{f:#x}\t{fname(k, f, refs)}\t{cmdv}\t{regs}")
    elif cmd == "func":
        for line in k.listing(int(sys.argv[4], 16)):
            print(line)


if __name__ == "__main__":
    main()
