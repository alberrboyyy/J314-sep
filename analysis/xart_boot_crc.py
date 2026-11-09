#!/usr/bin/env python3
"""CRC 'Fetched'/'Saving' et 'not found' du noyau (hv_uart.log), 14 premiers évènements xART du boot, par trace. Lecture seule."""
import re, glob, os
root = os.path.join(os.path.dirname(__file__), '..', 'traces')
R = re.compile(r'(Fetched|Saving) (SEP-xART Locker|SEP-xART|USER-xART)(?: with CRC: (0x[0-9a-f]+))?|(USER_XART_LOCKER) with uuid (\S+) not found|Replied to xART app: (0x[0-9a-f]+)')
out = []
for p in sorted(glob.glob(root + '/*/hv_uart.log')):
    n = os.path.basename(os.path.dirname(p))
    ev = []
    for l in open(p, errors='replace'):
        if 'AppleSEPXART' not in l: continue
        m = R.search(l)
        if not m: continue
        if m.group(1): ev.append(f'{m.group(1)[0]}:{m.group(2).replace("SEP-xART Locker","SEPL").replace("SEP-xART","SEP").replace("USER-xART","USER")}={m.group(3)}')
        elif m.group(4): ev.append('NF:' + m.group(5))
        # on ignore les 'Replied'
        if len(ev) >= 16: break
    out.append(n + '\n  ' + ' '.join(ev))
open(os.path.join(os.path.dirname(__file__), 'out', 'xart_boot_crc.txt'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out))
