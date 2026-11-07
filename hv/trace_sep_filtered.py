# SPDX-License-Identifier: GPL-2.0-or-later
"""
trace_sep_filtered.py -- traceur du mailbox SEP, observation pure, filtré par endpoint.

Script destiné à `run_guest.py -m <ce fichier>` (lancé par tools/boot_and_trace.sh).
run_guest.py l'exécute via hv.run_script() -> runpy.run_path(init_globals=hv.shell_locals),
donc les globales `hv`, `p`, `u`, `iface`, `TraceMode`, `trace_range`, ... sont déjà définies.

Ce que fait ce script
---------------------
- Trace UNIQUEMENT 4 registres 64 bits du mailbox ASC du noeud ADT /arm-io/sep (reg[0]) :
    INBOX0/INBOX1   (+0x8800/+0x8808) en écriture  -> messages AP -> SEP  (dir '>')
    OUTBOX0/OUTBOX1 (+0x8830/+0x8838) en lecture   -> messages SEP -> AP  (dir '<')
  Offsets repris de m1n1 (proxyclient/m1n1/hw/asc.py ASCRegs, src/asc.c). Aucun autre registre,
  aucun autre périphérique, aucun autre traceur n'est activé.
- Observation pure : aucune écriture, aucun blocage, aucune injection. Le script n'appelle
  jamais u.write / p.write* / iface.writemem et n'utilise pas TraceMode.HOOK. En mode ASYNC
  (défaut) l'accès du guest est exécuté par m1n1 (EL2, en C) et seul un événement est remonté ;
  en mode SYNC c'est le code générique de l'hyperviseur (hv.handle_vm_hook_mapped) qui rejoue
  à l'identique l'accès du guest, comme pour tout traceur m1n1.
- Une ligne par message, dans un fichier, format :
    <timestamp> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=...]
  champs du mot 0 (doc Asahi) : bits 0-7 EP, 8-15 TAG, 16-23 TYPE, 24-31 PARAM, 32-63 DATA.
  <timestamp> = heure de réception côté PC (time.time(), secondes, 6 décimales), PAS l'horloge
  du Mac. En ASYNC les événements sont bufferisés : le timestamp est l'heure de traitement.
  ool=... : présent seulement si le mot 1 du mailbox (INBOX1/OUTBOX1) a des bits non nuls hors
  des champs d'état FIFO connus (OUTCNT/INCNT/OUTPTR/INPTR, bits 40-56). Valeur brute
  `ool=m1:0x<16 hex>`. Ce n'est PAS un décodage de buffer out-of-line en mémoire partagée
  (non implémenté : aucun format vérifié).
- Lignes commençant par '#' : en-tête et méta (ignorées comme commentaires par
  analysis/parse_trace.py). Les annonces de noms d'endpoint (EP=0xFD TYPE=0, d'après
  m1n1 hw/sep.py `_handle_ep_discovery`) sont recopiées en commentaire `# epname ...`,
  quel que soit le filtre. Interprétation reprise de m1n1, non vérifiée sur macOS 13.5.

Variables d'environnement
-------------------------
  SEP_EPS          liste d'endpoints à garder, ex. "0x08,0x12,0x13" (virgules/espaces,
                   décimal ou 0x..). Vide ou absent = tous.
  SEP_TRACE_OUT    fichier de sortie. Défaut : <repo>/traces/sep_<AAAAMMJJ-HHMMSS>.log
                   (le chemin est affiché au démarrage et écrit en tête du fichier).
  SEP_TRACE_MODE   ASYNC (défaut) ou SYNC.
  SEP_FLUSH_S      intervalle max entre deux flush, secondes (défaut 0.5).
  SEP_SHMEM_DUMP   1 = lecture unique de l'en-tête de la mémoire partagée SEP (voir plus bas).
                   Défaut 0 (désactivé : comportement strictement identique à avant).
  SEP_SHMEM_DUMP_FULL  octets max par région listée dans la table (défaut 0 = pas de dump des
                   régions). Total plafonné à SHMEM_FULL_TOTAL_MAX (32 MiB).
  SEP_SHMEM_WHEN   trigger (défaut) ou next : moment de la lecture, voir plus bas.
  SEP_SHMEM_SYNC_MAX  nombre max de messages AP->SEP tracés en SYNC en attendant le déclencheur
                   (défaut 64) ; au-delà : abandon, `# shmem_error`, retour au mode normal.
  SEP_OOL_EPS      endpoints dont on lit les deux buffers OOL à chaque message, ex. "0x08".
                   Défaut vide = désactivé (comportement strictement identique à avant).
                   ACTIF => INBOX et OUTBOX tracés en SYNC pendant toute la session.
  SEP_OOL_BYTES    octets lus au début de chaque buffer (défaut 0x4000, borné par la taille apprise).
  SEP_OOL_MAX_MB   plafond global des fichiers .bin écrits (défaut 64) ; au-delà : `# ool_cap`,
                   plus aucun .bin, les lignes `# ool` continuent.

Lecture de la mémoire partagée (SEP_SHMEM_DUMP=1) -- lecture seule, une fois par boot
-------------------------------------------------------------------------------------
Déclencheur : premier message `> EP=0xfe` de TYPE 0x1c (vu dans C1/C3, L13, DATA=0x580) ou 0x18
(SET_SHMEM dans m1n1 hw/sep.py). Hypothèse (non vérifiée) reprise de m1n1 : IOVA = DATA << 12 dans
le DART /arm-io/dart-sep ; à l'IOVA, table d'entrées de 16 octets `<4sII` (nom, taille, offset)
+ 4 octets inconnus, terminée par le nom b"llun" ; données à partir de +0x4000.
Sorties : `<SEP_TRACE_OUT>.shmem_hdr.bin` (0x4000 octets bruts), lignes `# shmem ...` dans le log ;
avec SEP_SHMEM_DUMP_FULL>0 : `<SEP_TRACE_OUT>.shmem_<idx>_<nom>.bin` par région (plafonnées).
Toute erreur -> une ligne `# shmem_error ...`, le tracing continue.

Pourquoi le hook INBOX passe en SYNC jusqu'à la lecture : en ASYNC, le handler Python tourne dans
la boucle de réception de l'hôte (proxy.py reply()) pendant que le guest tourne ; m1n1 n'est PAS
dans uartproxy_run, donc aucune commande proxy (readmem, read32) n'est possible : elle provoquerait
hv_tick -> HV_USER_INTERRUPT -> REQ_BOOT imbriqué -> shell HV (hv.shellwrap affiche d'ailleurs
« Running in asynchronous context. Target operations are not available. »). Le seul contexte où
l'hôte peut lire la mémoire est une exception guest (hv.ctx non nul). Donc, si SEP_SHMEM_DUMP=1,
INBOX0/1 (écritures AP->SEP seulement) sont tracés en SYNC au démarrage ; OUTBOX reste dans le mode
demandé. Dès la lecture faite (ou abandonnée), INBOX est re-déclaré dans le mode normal (ASYNC par
défaut), appliqué par hv.pt_update() à la sortie de l'exception. En SYNC le handler d'écriture
tourne AVANT que m1n1 ne rejoue l'écriture vers le matériel (hv.handle_vm_hook_mapped).
  SEP_SHMEM_WHEN=trigger : lecture dans le hook du message EP=0xfe lui-même, donc avant que le SEP
    ne le reçoive : le SEP n'a encore rien à traiter, il n'attend rien de l'AP ; l'AP a forcément
    rempli et mappé la zone avant d'envoyer l'IOVA. Choix par défaut (moindre risque de course).
  SEP_SHMEM_WHEN=next : lecture au message AP->SEP suivant (le SEP a pu modifier la zone entre-temps).
Il n'existe pas de vrai mécanisme différé hors du chemin du guest : pendant la lecture tous les CPU
du guest sont arrêtés (hv_rendezvous) ; le time stealing de m1n1 masque la durée au guest, pas au SEP.
Traduction DART refaite ici en lecture seule (pas DART.ioread de m1n1, qui lit des pages de table
entières et ne vérifie pas les adresses) : registres TCR/TTBR lus par p.read32, PTE L1/L2 lus 8 octets
par 8 octets, chaque adresse physique vérifiée dans [hv.ram_base, hv.ram_base+hv.ram_size) avant
lecture. Aucune écriture : ni SEP, ni DART (pas d'invalidation TLB, pas d'ERROR clear), ni mémoire guest.
Seuls compatibles gérés : dart,t8020 et dart,t6000 (format PTE de m1n1 hw/dart8020.py).

Lecture des buffers OOL par endpoint (SEP_OOL_EPS) -- lecture seule, à chaque message
-------------------------------------------------------------------------------------
Apprentissage (aucune valeur codée en dur) : messages `> EP=0x00` (CNTL) de TYPE 2/3/4/5, l'endpoint
concerné étant PARAM. Hypothèse analyste (C4, non vérifiée) : TYPE 4 = taille et TYPE 2 = IOVA>>12 du
buffer A ; TYPE 5 = taille et TYPE 3 = IOVA>>12 du buffer B. Ligne `# ool learn` à chaque valeur apprise.
Pour chaque message (> et <) d'un EP de SEP_OOL_EPS dont un buffer est connu (IOVA et taille), lecture
de min(SEP_OOL_BYTES, taille) octets de chaque buffer connu par SepDartReader (même traduction lecture
seule que SEP_SHMEM_DUMP ; stream trouvé par find_sid au premier accès, puis mémorisé par buffer).
Moment de la lecture : '>' dans le hook INBOX1 AVANT que m1n1 ne rejoue l'écriture (le SEP n'a pas
encore reçu le message) ; '<' dans le hook OUTBOX1 APRÈS la lecture matérielle (le message est dépilé,
le SEP a pu continuer à écrire). Sortie, une ligne par buffer, juste après la ligne du message (même ts) :
  # ool <ts> seq=<n> EP=0x.. dir=> buf=A sha=<8 hex sha256> nz=<octets non nuls> changed=<plages>
      len=0x.. elapsed_ms=..
  seq = numéro du message (compteur `seen`, tous EP confondus, 1 = premier). changed = plages
  `off+len` (hex) différentes du dump précédent du même buffer, `init` au premier, `none` sinon ;
  au plus 16 plages puis `,...(+N)`. Le contenu brut n'est écrit que s'il change (ou au premier dump) :
  `<SEP_TRACE_OUT>.ool/<seq 6 chiffres>_<ep 2 hex>_<buf>.bin`. Toute erreur -> `# ool_error ...`.
  La lecture a lieu même si SEP_EPS exclut l'EP (la ligne `# ool` existe alors sans ligne message).
Coût : en SYNC chaque accès INBOX/OUTBOX = une exception guest remontée au PC (aller-retour USB),
plus, pour les EP de SEP_OOL_EPS, ~4 commandes proxy de traduction + 1 readmem par page de 16 KiB et
par buffer. Ordre de grandeur (extrapolé de C4 : 2.4 ms pour 0x4000 octets + traduction) : ~5 ms par
message pour 2 buffers, soit ~0.1-0.2 s ajoutés sur une rafale SBIO de 25 messages. Non mesuré :
voir `elapsed_ms`. Réduire SEP_OOL_BYTES diminue le coût du readmem, pas celui de la traduction.
Risques : le SEP lit/écrit ces buffers de son côté ; pendant la lecture les CPU du guest sont arrêtés
mais pas le SEP, donc un dump peut être incohérent (partiellement mis à jour). Le ralentissement peut
déclencher des timeouts côté macOS ou SEP (non observé, non testé).

Console : un seul print au démarrage (+ un en cas d'erreur d'écriture). Aucun print par message.

NON TESTÉ SUR LE MATÉRIEL (écrit sans accès au Mac, vérifié uniquement par py_compile) :
- que macOS 13.5 écrive INBOX0 puis INBOX1 et lise OUTBOX0 puis OUTBOX1 dans cet ordre
  (c'est ce que fait m1n1 ; le traceur ASC générique de m1n1 suppose la même chose) ;
- que les sous-pages (granularité 4 octets, cf. src/hv/hv_vm.c) se mappent sans souci sur
  ce bloc ; que le mode ASYNC ne perde pas d'événements sous forte charge ;
- que /arm-io/sep reg[0] soit bien la base ASC sur j314c (m1n1 hw/sep.py le suppose) ;
- que le mot 1 du mailbox SEP soit toujours 0 hors champs FIFO (m1n1 envoie INBOX1=0).
- TOUT le chemin SEP_SHMEM_DUMP : mélange SYNC (INBOX) / ASYNC (OUTBOX), bascule de mode en cours
  d'exécution, compatible et stream DART de dart-sep sous macOS 13.5, sémantique DATA<<12, format de
  la table côté macOS, durée de la lecture et réaction du SEP à cette pause.
- TOUT le chemin SEP_OOL_EPS (non lancé sur le Mac) : sémantique CNTL TYPE 2/3/4/5, SYNC permanent des
  deux boîtes, cohérence des dumps, durée réelle, tolérance de macOS/SEP au ralentissement.
"""

import atexit
import hashlib
import os
import re
import struct
import sys
import time

from m1n1.hv import TraceMode
from m1n1.hw.asc import ASCRegs
from m1n1.trace import ADTDevTracer

SEP_NODE = "/arm-io/sep"

# Offsets relatifs à reg[0] (ASCRegs) ; 2 registres 64 bits contigus chacun.
INBOX_OFF = 0x8800    # INBOX0, INBOX1
OUTBOX_OFF = 0x8830   # OUTBOX0, OUTBOX1
PAIR_SIZE = 0x10

# Champs d'état FIFO du mot 1 côté OUTBOX (R_OUTBOX1 dans m1n1 hw/asc.py : bits 40..56).
MSG1_FIFO_MASK = ((1 << 57) - 1) & ~((1 << 40) - 1)

# --- mémoire partagée (SEP_SHMEM_DUMP) -------------------------------------------------------
DART_SEP_NODE = "/arm-io/dart-sep"
SHMEM_TRIGGER_EP = 0xFE
SHMEM_TRIGGER_TYPES = (0x1C, 0x18)   # 0x1c vu dans C1/C3 ; 0x18 = SET_SHMEM de m1n1 hw/sep.py
SHMEM_HDR_SIZE = 0x4000
SHMEM_FULL_TOTAL_MAX = 32 << 20
DART_PAGE = 0x4000
# Offsets DART8020Regs (m1n1 hw/dart8020.py) : TCR[sid] = 0x100 + 4*sid ; TTBR[sid][l0] = 0x200 + 16*sid + 4*l0
DART_TCR = 0x100
DART_TTBR = 0x200
TCR_TRANSLATE_ENABLE = 1 << 7
TCR_BYPASS_DART = 1 << 8
TTBR_VALID = 1 << 31
TTBR_ADDR_MASK = (1 << 31) - 1
# Champ OFFSET des PTE (m1n1 PTE_T8020 / PTE_T6000), adresse = OFFSET << 14.
PTE_OFFSET = {"dart,t8020": (14, 39), "dart,t6000": (10, 39)}

# --- buffers OOL (SEP_OOL_EPS) ----------------------------------------------------------------
CNTL_EP = 0x00
# TYPE CNTL -> (buffer, champ). Hypothèse analyste C4, non vérifiée.
OOL_CNTL_TYPES = {0x02: ("A", "iova"), 0x04: ("A", "size"), 0x03: ("B", "iova"), 0x05: ("B", "size")}
OOL_MAX_RANGES = 16


def diff_ranges(old, new, chunk=64):
    """Plages (off, len) où old et new diffèrent ; une longueur différente compte comme modifiée.
    Comparaison par blocs de `chunk` octets, détail octet par octet seulement dans les blocs différents."""
    n = min(len(old), len(new))
    ranges = []
    start = None
    if old[:n] != new[:n]:
        for c in range(0, n, chunk):
            e = min(n, c + chunk)
            if old[c:e] == new[c:e]:
                if start is not None:
                    ranges.append((start, c - start))
                    start = None
                continue
            for i in range(c, e):
                if old[i] != new[i]:
                    if start is None:
                        start = i
                elif start is not None:
                    ranges.append((start, i - start))
                    start = None
    if start is not None:
        ranges.append((start, n - start))
    if len(new) != len(old):
        hi = max(len(old), len(new))
        if ranges and ranges[-1][0] + ranges[-1][1] == n:
            s0 = ranges.pop()[0]
            ranges.append((s0, hi - s0))
        else:
            ranges.append((n, hi - n))
    return ranges


def fmt_ranges(ranges, limit=OOL_MAX_RANGES):
    if not ranges:
        return "none"
    txt = ",".join(f"0x{o:x}+0x{l:x}" for o, l in ranges[:limit])
    if len(ranges) > limit:
        txt += f",...(+{len(ranges) - limit})"
    return txt


class ShmemError(Exception):
    pass


class SepDartReader:
    """Traduction IOVA -> PA dans dart-sep, lecture seule, adresses vérifiées dans la RAM."""

    def __init__(self, hv, path=DART_SEP_NODE):
        node = hv.adt[path]
        self.compat = node.compatible[0]
        if self.compat not in PTE_OFFSET:
            raise ShmemError(f"compatible DART non géré : {self.compat}")
        self.base = node.get_reg(0)[0]
        self.p = hv.p
        self.iface = hv.iface
        self.ram_lo = hv.ram_base
        self.ram_hi = hv.ram_base + hv.ram_size
        lo, hi = PTE_OFFSET[self.compat]
        self.pte_lo, self.pte_mask = lo, (1 << (hi - lo + 1)) - 1

    def _check(self, pa, size, what):
        if not (self.ram_lo <= pa and pa + size <= self.ram_hi):
            raise ShmemError(f"{what} PA 0x{pa:x}+0x{size:x} hors RAM "
                             f"[0x{self.ram_lo:x},0x{self.ram_hi:x})")

    def _pte(self, table_pa, idx, what):
        pa = table_pa + 8 * idx
        self._check(pa, 8, what)
        return struct.unpack("<Q", self.iface.readmem(pa, 8))[0]

    def tcr(self, sid):
        return self.p.read32(self.base + DART_TCR + 4 * sid)

    def translate_page(self, sid, iova):
        tcr = self.tcr(sid)
        if tcr & TCR_BYPASS_DART or not tcr & TCR_TRANSLATE_ENABLE:
            raise ShmemError(f"sid {sid}: TCR=0x{tcr:08x} (bypass ou traduction inactive) : refusé")
        l0 = iova >> 36
        if l0 >= 4:
            raise ShmemError(f"IOVA 0x{iova:x} hors L0")
        ttbr = self.p.read32(self.base + DART_TTBR + 16 * sid + 4 * l0)
        if not ttbr & TTBR_VALID:
            return None
        l1 = self._pte((ttbr & TTBR_ADDR_MASK) << 12, (iova >> 25) & 0x7FF, "L1")
        if not l1 & 1:
            return None
        l2 = self._pte(((l1 >> self.pte_lo) & self.pte_mask) << 14, (iova >> 14) & 0x7FF, "L2")
        if not l2 & 1:
            return None
        return ((l2 >> self.pte_lo) & self.pte_mask) << 14

    def find_sid(self, iova):
        """Premier stream (0 d'abord) où la page de iova est mappée. Lecture des TCR seulement."""
        tried = []
        for sid in range(16):
            try:
                tcr = self.tcr(sid)
                if tcr & TCR_BYPASS_DART or not tcr & TCR_TRANSLATE_ENABLE:
                    continue
                pa = self.translate_page(sid, iova & ~(DART_PAGE - 1))
            except ShmemError as e:
                tried.append(f"{sid}:{e}")
                continue
            if pa is not None:
                return sid, tried
            tried.append(f"{sid}:unmapped")
        raise ShmemError("IOVA 0x%x non mappée dans aucun stream (%s)" % (iova, "; ".join(tried) or "aucun stream actif"))

    def read(self, sid, iova, size):
        out = []
        cur, end = iova, iova + size
        while cur < end:
            page = cur & ~(DART_PAGE - 1)
            n = min(end, page + DART_PAGE) - cur
            pa = self.translate_page(sid, page)
            if pa is None:
                raise ShmemError(f"page IOVA 0x{page:x} non mappée (sid {sid})")
            pa += cur - page
            self._check(pa, n, "data")
            out.append(self.iface.readmem(pa, n))
            cur += n
        return b"".join(out)


def _decode_shmem_table(buf):
    """Décodage best-effort de la table <4sII + 4 octets> ; renvoie (entrées, fin, raison)."""
    entries = []
    for i in range(len(buf) // 16):
        raw = buf[i * 16:(i + 1) * 16]
        name, size, off = struct.unpack_from("<4sII", raw)
        extra = struct.unpack_from("<I", raw, 12)[0]
        if name == b"llun":
            return entries, i, "llun"
        if not all(0x20 <= c < 0x7F for c in name):
            return entries, i, "nom_non_ascii:" + raw.hex()
        entries.append((i, name.decode("ascii"), size, off, extra))
    return entries, len(buf) // 16, "fin_buffer_sans_llun"


def _parse_eps(txt):
    txt = (txt or "").replace(",", " ").split()
    if not txt:
        return None
    eps = set()
    for t in txt:
        v = int(t, 0)
        if not 0 <= v <= 0xFF:
            raise ValueError(f"SEP_EPS: endpoint hors plage 0..0xff : {t}")
        eps.add(v)
    return frozenset(eps)


def _default_out():
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        repo = os.path.dirname(here)
    except NameError:
        repo = os.getcwd()
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return os.path.join(repo, "traces", f"sep_{stamp}.log")


class SEPMailboxObserver(ADTDevTracer):
    """Observateur du mailbox SEP. Sous-classe ADTDevTracer (m1n1/trace/__init__.py) sans
    rien modifier dans m1n1 : seuls les handlers w_INBOX1 / r_OUTBOX1 sont définis,
    appelés par Tracer.evt_rw() après mise à jour du cache de registres."""

    DEFAULT_MODE = TraceMode.ASYNC
    REGMAPS = []   # on ne trace pas tout reg[0] : voir start()
    NAMES = []

    def __init__(self, hv, devpath, out, eps=None, mode=None, flush_s=0.5):
        super().__init__(hv, devpath, verbose=0)
        self.out = out
        self.eps = eps
        self.mode = mode or self.DEFAULT_MODE
        self.flush_s = flush_s
        self._last_flush = time.monotonic()
        self._write_failed = False
        self.n_seen = 0
        self.n_logged = 0
        self.epnames = {}
        # SEP_SHMEM_DUMP (voir docstring)
        self.shmem = None          # None = désactivé ; sinon dict de config/état
        # SEP_OOL_EPS (voir docstring)
        self.ool = None            # None = désactivé ; sinon dict de config/état

    def enable_shmem_dump(self, out_path, full_max=0, when="trigger", sync_max=64):
        self.shmem = dict(out_path=out_path, full_max=full_max, when=when, sync_max=sync_max,
                          done=False, pending=None, n_tx=0)

    def enable_ool(self, eps, out_dir, nbytes=0x4000, max_bytes=64 << 20):
        # Lecture à chaque message => les deux boîtes en SYNC pendant toute la session.
        self.mode = TraceMode.SYNC
        self.ool = dict(eps=eps, out_dir=out_dir, nbytes=nbytes, max_bytes=max_bytes, written=0,
                        capped=False, bufs={}, prev={}, dart=None, warned=set())

    def start(self):
        base, size = self.dev.get_reg(0)
        if size < OUTBOX_OFF + PAIR_SIZE:
            raise Exception(f"{SEP_NODE} reg[0] trop petit ({size:#x}) pour le mailbox ASC")
        regmap = ASCRegs(self._cache, base)
        regmap.cached = ASCRegs(self._cache.cached, base)
        self.regmaps[base] = regmap
        self.asc = regmap
        self.base = base
        # Écritures du guest sur INBOX0/1 seulement ; lectures sur OUTBOX0/1 seulement.
        # SEP_SHMEM_DUMP : INBOX en SYNC jusqu'à la lecture (seul contexte où lire la mémoire).
        in_mode = TraceMode.SYNC if self.shmem is not None else self.mode
        self.trace(base + INBOX_OFF, PAIR_SIZE, in_mode, read=False, write=True, regmap=regmap)
        self.trace(base + OUTBOX_OFF, PAIR_SIZE, self.mode, read=True, write=False, regmap=regmap)
        return base

    def _inbox_back_to_normal(self):
        # Re-déclaration (même zone, même ident -> remplace l'entrée) ; appliquée par hv.pt_update()
        # à la fin de l'exception en cours.
        if self.mode != TraceMode.SYNC:
            self.trace(self.base + INBOX_OFF, PAIR_SIZE, self.mode, read=False, write=True,
                       regmap=self.asc)

    # --- handlers appelés par Tracer.evt_rw ---------------------------------------------

    def w_INBOX1(self, inbox1):
        inbox0 = self.asc.cached.INBOX0.reg
        self._emit(">", inbox0.value, inbox1.value, tx=True)

    def r_OUTBOX1(self, outbox1):
        outbox0 = self.asc.cached.OUTBOX0.reg
        self._emit("<", outbox0.value, outbox1.value, tx=False)

    # --- sortie --------------------------------------------------------------------------

    def _emit(self, d, m0, m1, tx):
        ts = time.time()
        self.n_seen += 1
        ep = m0 & 0xFF
        tag = (m0 >> 8) & 0xFF
        typ = (m0 >> 16) & 0xFF
        param = (m0 >> 24) & 0xFF
        data = (m0 >> 32) & 0xFFFFFFFF

        lines = []
        if not tx and ep == 0xFD and typ == 0:
            # Annonce de nom d'endpoint (interprétation m1n1 hw/sep.py, non vérifiée 13.5).
            name = "".join(chr((data >> (i * 8)) & 0xFF) for i in range(3, -1, -1))
            if self.epnames.get(param) != name:
                self.epnames[param] = name
                safe = name.encode("ascii", "backslashreplace").decode("ascii")
                lines.append(f"# epname {ts:.6f} EP=0x{param:02x} NAME={safe!r}\n")

        if self.eps is None or ep in self.eps:
            extra = m1 if tx else (m1 & ~MSG1_FIFO_MASK)
            line = (f"{ts:.6f} {d} EP=0x{ep:02x} TAG=0x{tag:02x} TYPE=0x{typ:02x} "
                    f"PARAM=0x{param:02x} DATA=0x{data:08x}")
            if extra:
                line += f" ool=m1:0x{m1:016x}"
            lines.append(line + "\n")
            self.n_logged += 1

        if lines:
            self._write("".join(lines))

        if self.ool is not None:
            try:
                if tx and ep == CNTL_EP and typ in OOL_CNTL_TYPES:
                    self._ool_learn(param, typ, data, ts)
                if ep in self.ool["eps"]:
                    self._ool_dump(ep, d, ts)
            except Exception as e:   # jamais d'exception vers shellwrap
                self._write(f"# ool_error {ts:.6f} seq={self.n_seen} interne {type(e).__name__}: {e}\n")

        if tx and self.shmem is not None and not self.shmem["done"]:
            try:
                self._shmem_step(ep, typ, data)
            except Exception as e:   # ne jamais faire planter le tracer (shellwrap -> shell HV)
                self._shmem_finish(f"# shmem_error {time.time():.6f} interne {type(e).__name__}: {e}\n")

    # --- SEP_OOL_EPS ---------------------------------------------------------------------

    def _ool_learn(self, target_ep, typ, data, ts):
        st = self.ool
        if target_ep not in st["eps"]:
            return
        buf, field = OOL_CNTL_TYPES[typ]
        b = st["bufs"].setdefault((target_ep, buf), {"iova": None, "size": None, "sid": None})
        val = data << 12 if field == "iova" else data
        if b[field] != val:
            b[field] = val
            b["sid"] = None        # nouvelle IOVA ou taille : stream à retrouver
            st["prev"].pop((target_ep, buf), None)
            self._write(f"# ool learn {ts:.6f} seq={self.n_seen} EP=0x{target_ep:02x} buf={buf} "
                        f"{field}=0x{val:x} (CNTL TYPE=0x{typ:02x} DATA=0x{data:08x})\n")

    def _ool_dump(self, ep, d, ts):
        st = self.ool
        seq = self.n_seen
        known = [(name, st["bufs"].get((ep, name))) for name in ("A", "B")]
        known = [(n, b) for n, b in known if b and b["iova"] is not None and b["size"]]
        if not known:
            if ep not in st["warned"]:
                st["warned"].add(ep)
                self._write(f"# ool_error {ts:.6f} seq={seq} EP=0x{ep:02x} buffers inconnus "
                            f"(pas encore de CNTL TYPE 2/3/4/5 PARAM=0x{ep:02x}) ; messages suivants de cet EP "
                            f"ignorés sans autre ligne jusqu'à apprentissage\n")
            return
        if self.hv.ctx is None:
            self._write(f"# ool_error {ts:.6f} seq={seq} EP=0x{ep:02x} contexte asynchrone, "
                        f"lecture impossible\n")
            return
        for name, b in known:
            t0 = time.monotonic()
            try:
                if st["dart"] is None:
                    st["dart"] = SepDartReader(self.hv)
                dart = st["dart"]
                if b["sid"] is None:
                    b["sid"], _ = dart.find_sid(b["iova"])
                n = min(st["nbytes"], b["size"])
                blob = dart.read(b["sid"], b["iova"], n)
            except Exception as e:
                self._write(f"# ool_error {ts:.6f} seq={seq} EP=0x{ep:02x} dir={d} buf={name} "
                            f"iova=0x{b['iova']:x} {type(e).__name__}: {e}\n")
                continue
            elapsed = (time.monotonic() - t0) * 1000
            key = (ep, name)
            prev = st["prev"].get(key)
            if prev is None:
                changed = "init"
            else:
                changed = fmt_ranges(diff_ranges(prev, blob))
            st["prev"][key] = blob
            sha = hashlib.sha256(blob).hexdigest()[:8]
            nz = len(blob) - blob.count(0)
            line = (f"# ool {ts:.6f} seq={seq} EP=0x{ep:02x} dir={d} buf={name} sha={sha} nz={nz} "
                    f"changed={changed} len=0x{len(blob):x} elapsed_ms={elapsed:.2f}")
            if changed != "none":
                line += self._ool_save(seq, ep, name, blob)
            self._write(line + "\n")

    def _ool_save(self, seq, ep, name, blob):
        st = self.ool
        if st["capped"]:
            return " file=-"
        if st["written"] + len(blob) > st["max_bytes"]:
            st["capped"] = True
            self._write(f"# ool_cap {time.time():.6f} seq={seq} plafond SEP_OOL_MAX_MB atteint "
                        f"({st['written']} octets écrits) : plus aucun .bin\n")
            return " file=-"
        try:
            os.makedirs(st["out_dir"], exist_ok=True)
            fn = f"{seq:06d}_{ep:02x}_{name}.bin"
            with open(os.path.join(st["out_dir"], fn), "wb") as f:
                f.write(blob)
            st["written"] += len(blob)
            return f" file={fn}"
        except Exception as e:
            self._write(f"# ool_error {time.time():.6f} seq={seq} écriture .bin {type(e).__name__}: {e}\n")
            return " file=-"

    # --- SEP_SHMEM_DUMP ------------------------------------------------------------------

    def _shmem_finish(self, line=None):
        st = self.shmem
        st["done"] = True
        if line:
            self._write(line)
        try:
            self.out.flush()
        except Exception:
            pass
        try:
            self._inbox_back_to_normal()
        except Exception as e:
            self._write(f"# shmem_error {time.time():.6f} retour_mode {type(e).__name__}: {e}\n")

    def _shmem_step(self, ep, typ, data):
        st = self.shmem
        st["n_tx"] += 1
        if st["pending"] is None and ep == SHMEM_TRIGGER_EP and typ in SHMEM_TRIGGER_TYPES:
            st["pending"] = (data << 12, ep, typ, data)
            self._write(f"# shmem trigger {time.time():.6f} EP=0x{ep:02x} TYPE=0x{typ:02x} "
                        f"DATA=0x{data:08x} iova=0x{data << 12:x} when={st['when']}\n")
            if st["when"] == "next":
                return
        elif st["pending"] is None:
            if st["n_tx"] >= st["sync_max"]:
                self._shmem_finish(f"# shmem_error {time.time():.6f} pas de déclencheur EP=0xfe "
                                   f"TYPE 0x1c/0x18 en {st['n_tx']} messages AP->SEP ; abandon\n")
            return
        if self.hv.ctx is None:
            # Contexte asynchrone : aucune lecture possible. Ne devrait pas arriver (INBOX en SYNC).
            self._shmem_finish(f"# shmem_error {time.time():.6f} contexte asynchrone, lecture impossible\n")
            return
        try:
            self._shmem_dump(*st["pending"])
            self._shmem_finish()
        except Exception as e:
            self._shmem_finish(f"# shmem_error {time.time():.6f} {type(e).__name__}: {e}\n")

    def _shmem_dump(self, iova, ep, typ, data):
        st = self.shmem
        t0 = time.monotonic()
        dart = SepDartReader(self.hv)
        sid, tried = dart.find_sid(iova)
        self._write(f"# shmem dart {time.time():.6f} node={DART_SEP_NODE} base=0x{dart.base:x} "
                    f"compat={dart.compat} sid={sid} skipped={len(tried)}\n")
        hdr = dart.read(sid, iova, SHMEM_HDR_SIZE)
        hdr_path = st["out_path"] + ".shmem_hdr.bin"
        with open(hdr_path, "wb") as f:
            f.write(hdr)
        self._write(f"# shmem hdr {time.time():.6f} iova=0x{iova:x} size=0x{len(hdr):x} "
                    f"file={os.path.basename(hdr_path)}\n")
        entries, end_idx, reason = _decode_shmem_table(hdr)
        self._write(f"# shmem table {time.time():.6f} entries={len(entries)} end_idx={end_idx} "
                    f"end={reason}\n")
        for i, name, size, off, extra in entries:
            self._write(f"# shmem entry {i} NAME={name!r} SIZE=0x{size:x} OFF=0x{off:x} "
                        f"X=0x{extra:08x}\n")
        if st["full_max"] > 0 and entries:
            total = 0
            for i, name, size, off, extra in entries:
                n = min(size, st["full_max"], SHMEM_FULL_TOTAL_MAX - total)
                if n <= 0:
                    self._write(f"# shmem_error {time.time():.6f} region {i} ignorée : plafond total\n")
                    continue
                try:
                    blob = dart.read(sid, iova + off, n)
                except Exception as e:
                    self._write(f"# shmem_error {time.time():.6f} region {i} {name!r} "
                                f"{type(e).__name__}: {e}\n")
                    continue
                total += len(blob)
                safe = re.sub(r"[^A-Za-z0-9]", "_", name)
                rpath = f"{st['out_path']}.shmem_{i:02d}_{safe}.bin"
                with open(rpath, "wb") as f:
                    f.write(blob)
                self._write(f"# shmem region {i} NAME={name!r} iova=0x{iova + off:x} "
                            f"dumped=0x{len(blob):x}/0x{size:x} file={os.path.basename(rpath)}\n")
        self._write(f"# shmem done {time.time():.6f} elapsed_ms={(time.monotonic() - t0) * 1000:.1f}\n")

    def _write(self, s):
        try:
            self.out.write(s)
            now = time.monotonic()
            if now - self._last_flush >= self.flush_s:
                self.out.flush()
                self._last_flush = now
        except Exception as e:
            if not self._write_failed:
                self._write_failed = True
                print(f"[trace_sep_filtered] ERREUR écriture {getattr(self.out, 'name', '?')}: {e}",
                      file=sys.stderr)

    def close(self):
        try:
            self.out.write(f"# end {time.time():.6f} seen={self.n_seen} logged={self.n_logged}\n")
            self.out.flush()
            self.out.close()
        except Exception:
            pass


def _setup():
    eps = _parse_eps(os.environ.get("SEP_EPS", ""))
    mode_txt = os.environ.get("SEP_TRACE_MODE", "ASYNC").strip().upper()
    if mode_txt not in ("ASYNC", "SYNC"):
        raise ValueError(f"SEP_TRACE_MODE doit valoir ASYNC ou SYNC, pas {mode_txt!r}")
    mode = TraceMode[mode_txt]
    flush_s = float(os.environ.get("SEP_FLUSH_S", "0.5"))
    out_path = os.environ.get("SEP_TRACE_OUT") or _default_out()

    try:
        hv.adt[SEP_NODE]
    except KeyError:
        raise Exception(f"noeud ADT {SEP_NODE} absent : rien à tracer")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    out = open(out_path, "a", buffering=1 << 16)

    tracer = SEPMailboxObserver(hv, SEP_NODE, out, eps=eps, mode=mode, flush_s=flush_s)
    shmem_on = os.environ.get("SEP_SHMEM_DUMP", "0").strip() not in ("", "0")
    shmem_txt = "off"
    if shmem_on:
        full_max = int(os.environ.get("SEP_SHMEM_DUMP_FULL", "0") or "0", 0)
        when = os.environ.get("SEP_SHMEM_WHEN", "trigger").strip().lower()
        if when not in ("trigger", "next"):
            raise ValueError(f"SEP_SHMEM_WHEN doit valoir trigger ou next, pas {when!r}")
        sync_max = int(os.environ.get("SEP_SHMEM_SYNC_MAX", "64"), 0)
        tracer.enable_shmem_dump(os.path.abspath(out_path), full_max=max(0, full_max),
                                 when=when, sync_max=max(1, sync_max))
        shmem_txt = f"on(full_max=0x{max(0, full_max):x},when={when},sync_max={sync_max})"
    ool_eps = _parse_eps(os.environ.get("SEP_OOL_EPS", ""))
    ool_txt = "off"
    if ool_eps:
        nbytes = int(os.environ.get("SEP_OOL_BYTES", "0x4000") or "0x4000", 0)
        if nbytes <= 0:
            raise ValueError("SEP_OOL_BYTES doit être > 0")
        max_mb = int(os.environ.get("SEP_OOL_MAX_MB", "64") or "64", 0)
        tracer.enable_ool(ool_eps, os.path.abspath(out_path) + ".ool", nbytes=nbytes,
                          max_bytes=max(0, max_mb) << 20)
        if mode_txt != "SYNC":
            mode_txt = "SYNC(forcé par SEP_OOL_EPS)"
        ool_txt = (f"on(eps={','.join(f'0x{e:02x}' for e in sorted(ool_eps))},bytes=0x{nbytes:x},"
                   f"max_mb={max_mb})")
    base = tracer.start()

    eps_txt = "all" if eps is None else ",".join(f"0x{e:02x}" for e in sorted(eps))
    out.write(f"# trace_sep_filtered start {time.time():.6f} node={SEP_NODE} base=0x{base:x} "
              f"mode={mode_txt} eps={eps_txt} shmem={shmem_txt} ool={ool_txt} ts=host_time_time\n")
    out.write("# format: <ts> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=...]"
              " ; '>' AP->SEP (INBOX), '<' SEP->AP (OUTBOX)\n")
    out.flush()
    atexit.register(tracer.close)

    print(f"[trace_sep_filtered] mailbox {SEP_NODE}@0x{base:x} mode={mode_txt} eps={eps_txt} shmem={shmem_txt} "
          f"ool={ool_txt} -> {os.path.abspath(out_path)}")
    return tracer


sep_tracer = _setup()
