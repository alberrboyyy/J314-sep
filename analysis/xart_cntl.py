#!/usr/bin/env python3
"""Pour chaque sep.log : ordre d'activation CNTL (type 4/2/5/3) des endpoints, TAG CNTL, requête 0x14, annonce 0xFD ; valeurs xarm (0x13). Lecture seule."""
import re, glob, os
R = re.compile(r'^(\S+) ([<>]) EP=0x(\w+) TAG=0x(\w+) TYPE=0x(\w+) PARAM=0x(\w+) DATA=0x(\w+)')
root = os.path.join(os.path.dirname(__file__), '..', 'traces')
out = []
for p in sorted(glob.glob(root + '/*/sep.log')):
    n = os.path.basename(os.path.dirname(p))
    cnt = {}; order = []; tags = set(); q14 = False; ann = []; t0 = None; first13 = None; firstreply = None
    for i, l in enumerate(open(p), 1):
        m = R.match(l)
        if not m: continue
        ts, d, ep, tag, ty, pa, da = m.groups(); ep=int(ep,16); tag=int(tag,16); ty=int(ty,16); pa=int(pa,16); da=int(da,16)
        if t0 is None: t0 = float(ts)
        if ep == 0 and d == '>' and ty == 0x14: q14 = True
        if ep == 0 and d == '>' and ty in (2,3,4,5):
            tags.add(tag)
            if pa not in cnt: cnt[pa] = {}; order.append(pa)
            cnt[pa][ty] = da
        if ep == 0xfd and ty == 0: ann.append(pa)
        if ep == 0x13 and d == '>' and firstreply is None: firstreply = float(ts) - t0
        if ep == 0x08 and d == '>': break
    x = cnt.get(0x13, {})
    out.append(f'{n}: CNTL tags={sorted(tags)} 0x14={q14} ordre_activation={[hex(e) for e in order]} annonces_FD={[hex(e) for e in ann]}')
    out.append(f'    xarm: T4={x.get(4,0):#x} T2={x.get(2,0):#x} T5={x.get(5,0):#x} T3={x.get(3,0):#x} ; 1re réponse AP sur 0x13 à +{firstreply:.2f}s')
open(os.path.join(os.path.dirname(__file__), 'out', 'xart_cntl.txt'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out))
