#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compare le contenu OOL de l'échange xART (EP 0x13) entre DEUX captures de boot macOS.
But : savoir si le coffre renvoyé au SEP change d'un boot à l'autre (sans activité utilisateur).
- Si les lockers sont IDENTIQUES entre deux boots -> pas de fraîcheur par boot visible -> un rejeu
  fidèle de l'état courant a des chances de passer (favorable à la voie C).
- Si tout DIFFÈRE -> il y a une fraîcheur par boot -> un rejeu statique serait refusé.

Lecture seule, hors ligne. Usage : python3 -I analysis/diff_xart_ool.py <trace1> <trace2>
Les buffers A ('>') = lockers rendus par l'AP au SEP (fetch) ; B ('<') = ce que le SEP fait sauver.
"""
import hashlib
import os
import sys


def lockers(trace, direction):
    """sha256 -> (nom_fichier, nb_octets_non_nuls) des buffers OOL 0x13 de la direction donnée."""
    d = os.path.join(trace, "sep.log.ool")
    out = {}
    for f in sorted(os.listdir(d)):
        if f"_13_{direction}" not in f:
            continue
        b = open(os.path.join(d, f), "rb").read()
        nz = sum(1 for x in b if x)
        if nz < 64:            # ignorer les quasi-vides (UUID seuls, etc.)
            continue
        out[hashlib.sha256(b).hexdigest()[:12]] = (f, nz)
    return out


def main():
    t1, t2 = sys.argv[1], sys.argv[2]
    for name, direction in (("A (fetch, AP->SEP = coffre rendu)", "A"), ("B (save, SEP->AP)", "B")):
        a = lockers(t1, direction)
        b = lockers(t2, direction)
        common = set(a) & set(b)
        print(f"\n=== buffers {name} ===")
        print(f"  {os.path.basename(t1)} : {len(a)} blobs   {os.path.basename(t2)} : {len(b)} blobs")
        print(f"  identiques (même sha) : {len(common)}")
        print(f"  seulement dans 1 : {len(set(a)-set(b))}   seulement dans 2 : {len(set(b)-set(a))}")
        if common:
            print("  exemples identiques :", [a[h][0] for h in list(common)[:3]])
    print("\nLecture : beaucoup d'identiques en A => le coffre rendu est stable d'un boot à l'autre "
          "(favorable au rejeu) ; tout différent => fraîcheur par boot (rejeu statique refusé).")


if __name__ == "__main__":
    main()
