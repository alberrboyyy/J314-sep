#!/usr/bin/env python3
"""Lit adt.txt (sortie de tools/dump_adt.sh) et liste : spi1-4, le noeud compatible biosensor,mesa,
ses proprietes (function-mesa_*, mesa-*, interrupts, gpios) et le noeud cible de chaque phandle.
Usage : analysis/adt_find_mesa.py <adt.txt>      (lecture seule, aucun acces au Mac)"""
import re, sys


def parse(path):
    root = {"name": "/", "props": {}, "kids": [], "parent": None, "path": "/"}
    cur = root
    for line in open(path, errors="replace"):
        t = line.strip()
        if not t:
            continue
        if t == "}":
            cur = cur["parent"] or root
        elif t.endswith(" {") and " = " not in t:
            n = {"name": t[:-2], "props": {}, "kids": [], "parent": cur}
            n["path"] = cur["path"].rstrip("/") + "/" + n["name"]
            cur["kids"].append(n)
            cur = n
        elif " = " in t:
            k, v = t.split(" = ", 1)
            cur["props"][k] = v
    return root


def walk(n):
    yield n
    for k in n["kids"]:
        yield from walk(k)


def show(n, pat=None):
    print(f"== {n['path']}")
    for k, v in n["props"].items():
        if pat is None or re.search(pat, k):
            print(f"   {k} = {v}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = parse(sys.argv[1])
    nodes = list(walk(root))
    by_ph = {}
    for n in nodes:
        for key in ("AAPL,phandle", "phandle"):
            if key in n["props"]:
                by_ph[n["props"][key].strip()] = n
    print(f"# {len(nodes)} noeuds")

    print("\n# Controleurs spi1..spi4")
    for n in nodes:
        if re.fullmatch(r"spi[1-4]", n["name"]):
            show(n, r"^(compatible|reg|interrupts|interrupt-parent|device_type|clock|spi|AAPL,phandle|pmgr)")
            print("   enfants :", ", ".join(k["name"] for k in n["kids"]) or "(aucun)")

    print("\n# Noeuds biosensor,mesa")
    found = [n for n in nodes if "biosensor,mesa" in n["props"].get("compatible", "")]
    if not found:
        print("AUCUN noeud biosensor,mesa trouve")
    for n in found:
        par = n["parent"]
        print(f"parent : {par['path'] if par else '?'}  compatible={par['props'].get('compatible') if par else '?'}")
        show(n)
        print("\n# function-* : phandle -> noeud cible")
        for k, v in n["props"].items():
            if k.startswith("function-"):
                m = re.match(r"(\d+):", v.strip())
                tgt = by_ph.get(m.group(1)) if m else None
                print(f"   {k}: {v}  ->  {tgt['path'] if tgt else 'phandle non resolu'}")
        print("\n# gpios / interrupts")
        for k, v in n["props"].items():
            if "gpio" in k or k in ("interrupts", "interrupt-parent"):
                print(f"   {k} = {v}")
        if par:
            print("\n# parent")
            show(par, r"^(compatible|reg|interrupts|clock|spi|AAPL,phandle)")

    print("\n# Noeuds GPIO (phandle)")
    for n in nodes:
        if re.match(r"(gpio|aop-gpio|nub-gpio|smc-gpio)", n["name"]) and "AAPL,phandle" in n["props"]:
            print(f"   {n['path']} phandle={n['props']['AAPL,phandle']} compatible={n['props'].get('compatible')}")


main()
