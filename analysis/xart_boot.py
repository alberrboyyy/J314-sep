#!/usr/bin/env python3
"""Echange xART (EP 0x13) et messages EP 0x00 avant le premier message EP 0x08 (sbio), pour tous les sep.log.
Lecture seule sur traces/. Sortie : analysis/out/xart_boot.txt"""
import re, sys, glob, os, collections
R = re.compile(r'^(\S+) ([<>]) EP=0x(\w+) TAG=0x(\w+) TYPE=0x(\w+) PARAM=0x(\w+) DATA=0x(\w+)(.*)$')
root = os.path.join(os.path.dirname(__file__), '..', 'traces')
out = []
seqs = {}
for p in sorted(glob.glob(root + '/*/sep.log')):
    name = os.path.basename(os.path.dirname(p))
    msgs = []
    for i, l in enumerate(open(p), 1):
        m = R.match(l.rstrip('\n'))
        if not m: continue
        ts, d, ep, tag, ty, pa, da, rest = m.groups()
        msgs.append((i, float(ts), d, int(ep, 16), int(tag, 16), int(ty, 16), int(pa, 16), int(da, 16), rest.strip()))
    first08 = next((k for k, m in enumerate(msgs) if m[3] == 8 and m[2] == '>'), len(msgs))
    ann = next((m[0] for m in msgs if m[3] == 0xfd and m[5] == 0 and m[6] == 8), None)
    win = [m for m in msgs[:first08] if m[3] in (0x13, 0x00) and not (m[3] == 0 and m[4] == 7)]
    t0 = win[0][1] if win else 0
    seqs[name] = [(m[2], m[3], m[4], m[5], m[6], m[7]) for m in win]
    out.append(f'## {name}  (fenêtre : {len(win)} messages avant la 1re activation sbio (> EP=0x08), ligne {msgs[first08][0] if first08 < len(msgs) else "-"})')
    for m in win:
        if ann and m[0] > ann and not any('ANN' in o for o in out[-1:]) and not getattr(sys.modules[__name__], '_m', None) == name:
            out.append(f'--- annonce 0xFD de sbio à L{ann} ---'); setattr(sys.modules[__name__], '_m', name)
        oo = ' ' + m[8] if m[8] else ''
        out.append(f'L{m[0]:<5} +{m[1]-t0:8.3f}s {m[2]} EP={m[3]:#04x} TAG={m[4]:#04x} TYPE={m[5]:#04x} PARAM={m[6]:#04x} DATA={m[7]:#010x}{oo}')
    out.append('')
# comparaison : séquence EP 0x13 seulement, (dir,tag,type,param,data)
ref = None
out.append('## Comparaison EP 0x13 (dir,tag,type,param,data) à la 1re trace')
keys = list(seqs)
def x13(n): return [s for s in seqs[n] if s[1] == 0x13]
for n in keys:
    s = x13(n)
    ident = s == x13(keys[0])
    sans = [(a,b,c,d,e) for (a,_,b,c,d,e) in s]
    out.append(f'{n}: {len(s)} msgs, identique à C1 : {ident}')
    if not ident:
        a = x13(keys[0])
        for k in range(max(len(a), len(s))):
            x = a[k] if k < len(a) else None; y = s[k] if k < len(s) else None
            if x != y: out.append(f'   rang {k}: C1={x} ici={y}')
out.append('')
out.append('## Comparaison EP 0x00 hors CNTL TAG 7')
for n in keys:
    s = [s for s in seqs[n] if s[1] == 0]
    out.append(f'{n}: ' + ' '.join(f'{x[0]}t{x[2]:#x}/ty{x[3]:#x}/d{x[5]:#x}' for x in s)[:600])
open(os.path.join(os.path.dirname(__file__), 'out', 'xart_boot.txt'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out[:60]))
