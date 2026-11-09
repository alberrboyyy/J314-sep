#!/usr/bin/env python3
"""Les CRC 'Fetched' d'un boot retrouvent-ils des CRC 'Saving' d'un boot précédent ? (hv_uart.log, lecture seule)"""
import re, glob, os
root = os.path.join(os.path.dirname(__file__), '..', 'traces')
R = re.compile(r'(Fetched|Saving) (SEP-xART Locker|SEP-xART|USER-xART) with CRC: 0x([0-9a-f]+)')
tr = []
for p in sorted(glob.glob(root + '/*/hv_uart.log')):
    n = os.path.basename(os.path.dirname(p))
    ev = [(m.group(1), m.group(2), m.group(3)) for l in open(p, errors='replace') for m in [R.search(l)] if m and 'AppleSEPXART' in l]
    if ev: tr.append((n, ev))
out = []
for i, (n, ev) in enumerate(tr):
    fetched = []
    for e in ev:
        if e[0] == 'Fetched' and e[2] not in ('c70f','e0aa','cf1d','9ae7') and e not in fetched: fetched.append(e)
        if len(fetched) >= 3 and len([x for x in ev[:ev.index(e)+1] if x[0]=='Fetched']) > 18: break
    first = [e for e in ev if e[0] == 'Fetched'][:16]
    if len(first) < 2:
        out.append(f'{n}: pas de Fetched (boot non couvert par ce log)'); continue
    sep, user = first[0][2], first[1][2]
    last = [e for e in ev if e[0]=='Fetched' and e[1]=='SEP-xART Locker' and e[2] not in ('c70f','e0aa','cf1d','9ae7')]
    lastv = last[0][2] if last else None
    saves = [(e[1], e[2]) for e in ev if e[0] == 'Saving']
    out.append(f'{n}: fetch SEP={sep} USER={user} SEPL(var)={lastv} ; Saving dans ce log : {len(saves)}')
    # recherche dans les logs précédents
    for lbl, v in (('SEP', sep), ('USER', user), ('SEPL', lastv)):
        if v is None: continue
        hits = [(tr[j][0][:15], s[0]) for j in range(i) for s in [(e[1], e[2]) for e in tr[j][1] if e[0]=='Saving' and e[2]==v] if s]
        out.append(f'    {lbl}={v} retrouvé comme Saving dans : {hits[-2:] if hits else "aucun log précédent"}')
open(os.path.join(os.path.dirname(__file__), 'out', 'xart_chain.txt'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out))
