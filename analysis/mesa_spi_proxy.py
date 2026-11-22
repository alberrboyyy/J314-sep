#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
mesa_spi_proxy.py — primitive réutilisable : une TRANSACTION SPI avec le capteur
Touch ID (« mesa ») depuis une session m1n1 proxyclient DÉJÀ OUVERTE.

But : porter en une classe appelable le transport SPI2 du capteur, tel que
`tools/mesa_hello.sh` le programme via le proxy (MMIO en mode FIFO scruté). Cette
brique servira de RELAIS : l'AP émet vers le capteur des octets venus du SEP et
renvoie au SEP la réponse du capteur, en lockstep (dialogue chiffré SEP↔capteur).

CE MODULE N'OUVRE AUCUN MATÉRIEL. Il s'utilise ainsi, à l'intérieur d'un script
`pending/` qui a déjà bootstrappé le proxy (cf. mesa_hello.sh l.49-59) :

    from m1n1.proxy import UartInterface, M1N1Proxy
    from m1n1.proxyutils import ProxyUtils, bootstrap_port
    iface = UartInterface(); p = M1N1Proxy(iface); bootstrap_port(iface, p)
    u = ProxyUtils(p)
    from analysis.mesa_spi_proxy import MesaSPI
    mesa = MesaSPI(iface, p, u)      # résout les adresses dans l'ADT, vérifie l'état iBoot
    try:
        mesa.power_on()              # alim gpio0 196 + config spi2 (ne touche PAS au pmgr)
        ident = mesa.read_id()       # auto-test : doit rendre l'identité connue
        # ... relais : rx = mesa.xfer(tx_du_SEP) ...
    finally:
        mesa.restore()               # éteint le capteur, remet les registres d'iBoot

Marquage des sources, conformément à CLAUDE.md (phase 2) :
  - « VU » = lu tel quel dans tools/mesa_hello.sh (réf. de ligne) ou dans les docs
    du repo (docs/sensor_hw.md). Rien ici ne vient d'un kext : `source: kext` ne
    s'applique pas (transport pur, protocole des trames en clair seulement).
  - « hypothèse » = extension au-delà de ce que mesa_hello a réellement exercé
    (voir la docstring de `xfer` et la note RELAIS en bas). Non vérifié matériel.

AUCUNE de ces fonctions n'écrit vers le SEP. Les écritures matérielles se limitent
à la broche d'alimentation du capteur (gpio0 196) et aux registres de /arm-io/spi2,
exactement comme mesa_hello.sh. L'envoi effectif de trames reste le fait d'un script
`pending/` relu et lancé par Albert.
"""

# ============================================================================
#  Carte des registres de /arm-io/spi2  (contrôleur AppleSPIMCController)
#  Offsets dans reg[0]. Source : tools/mesa_hello.sh l.82-83 (VU).
# ============================================================================
CTRL     = 0x000   # mesa_hello:82  — 0xc=reset FIFO (l.93), 0x1=RUN (l.111), 0=stop (l.121)
CFG      = 0x004   # mesa_hello:82  — 0x40002 en mode scruté (l.138 ; 0x40042 en DMA sous macOS)
STATUS   = 0x008   # mesa_hello:82  — (défini pour complétude ; non utilisé en mode scruté)
PIN      = 0x00c   # mesa_hello:82  — mis à 0 (l.135)
TXDATA   = 0x010   # mesa_hello:82  — un octet émis par write32 (l.104)
RXDATA   = 0x020   # mesa_hello:82  — un octet reçu par read32 (l.109)
CLKDIV   = 0x030   # mesa_hello:82  — 3 (l.136) ; concorde avec docs/sensor_hw.md (CLKDIV 3)
RXCNT    = 0x034   # mesa_hello:82  — nombre d'octets à recevoir (l.97)
WDELAY   = 0x038   # mesa_hello:82  — mis à 0 (l.137)
TXCNT    = 0x04c   # mesa_hello:82  — nombre d'octets à émettre (l.96)
FIFOSTAT = 0x10c   # mesa_hello:83  — niveau TX = bits 8-15 (l.101), niveau RX = bits 24-31 (l.107)
IE_XFER  = 0x130   # mesa_hello:83  — interruptions transfert masquées : 0 (l.133)
IF_XFER  = 0x134   # mesa_hello:83  — drapeaux transfert ; 0xffffffff pour effacer (l.94), bit1(0x2)=fini (l.116)
IE_FIFO  = 0x138   # mesa_hello:83  — interruptions FIFO masquées : 0 (l.134)
IF_FIFO  = 0x13c   # mesa_hello:83  — drapeaux FIFO ; 0xffffffff pour effacer (l.95)

# --- valeurs de contrôle (VU : mesa_hello.sh) ---
CTRL_FIFO_RESET = 0x0c       # l.93
CTRL_RUN        = 0x01       # l.111
CTRL_STOP       = 0x00       # l.121
CFG_POLLED      = 0x40002    # l.138 (mode FIFO scruté ; PAS 0x40042 qui est le DMA de macOS)
CLKDIV_MESA     = 3          # l.136
IF_CLEAR        = 0xffffffff # l.94-95
XFER_DONE_BIT   = 0x2        # l.116 (IF_XFER & 2)
FIFO_DEPTH      = 16         # l.102 (16 - niveau) : profondeur des FIFO
XFER_TIMEOUT_S  = 2.0        # l.118

# ============================================================================
#  GPIO (alimentation + broche « donnée prête »)  — /arm-io/gpio0
#  Source : mesa_hello.sh l.70, 87, 141-143, 170 (VU) ; docs/sensor_hw.md.
# ============================================================================
PWR_PIN   = 196    # function-mesa_pwr ; registre = gpio0 + 4*196 (mesa_hello:70)
READY_PIN = 195    # « donnée prête », active haute, LECTURE SEULE (docs/sensor_hw.md ; transport.h)
# Séquence d'alimentation, valeurs écrites dans le registre de la broche 196 (VU) :
PWR_SEQ_A = 0x76802   # l.141 (1er écrit)
PWR_SEQ_B = 0x76a02   # l.141 (2e écrit) / aussi « éteint » en fin (l.168)
PWR_ON    = 0x76a03   # l.143 (sortie à 1 = capteur alimenté)
PWR_ORIG  = 0x7680e   # l.87 : état d'origine attendu de la broche (assert), remis en fin (l.170)

# --- délais de la séquence d'alimentation (secondes) --- (VU : mesa_hello.sh l.142, 144)
PWR_SETTLE_S = 0.04   # l.142 (après 0x76a02)
PWR_ON_S     = 0.06   # l.144 (après 0x76a03)
GAP_S        = 0.01   # l.145+ (pause entre deux trames)

# ============================================================================
#  Trames en clair du « bonjour » (en-tête : 80 <cmd> <long 16b BE> 00 00 00)
#  Source : mesa_hello.sh l.126,129,145-147,156 (VU) ; docs/sensor_hw.md §Dialogue.
# ============================================================================
FRAME_WAKE    = bytes.fromhex("80780007000000")        # réveil 0x78 (l.145)
FRAME_STATUS  = bytes.fromhex("80100007000000")        # état 0x10 (l.126)
FRAME_GET_ID  = bytes.fromhex("80700007000000")        # identité 0x70 (l.147)
FRAME_READ_1B = bytes.fromhex("8013000b0000001b000000")  # « donne 0x1b octets » 0x13 (l.156)
STATUS_RXLEN  = 0x17   # on lit 0x17 octets pour un état (l.126)
STATUS_HEAD   = bytes.fromhex("80200010")              # début du corps d'état (l.149)
ID_LEN        = 0x1b
# Identité lue sous macOS (C18/C19) et depuis m1n1 (MESA-HELLO) — mesa_hello.sh l.129 (VU).
ID_EXPECTED   = bytes.fromhex("80d4001b00000000700219c05c0fd2aa349a81c76e030200d87576")


class MesaError(Exception):
    pass


class MesaSPI:
    """
    Transaction SPI avec le capteur mesa depuis une session proxyclient ouverte.

    Construit avec (iface, p, u) :
      - iface : UartInterface (gardé pour homogénéité d'appel ; non utilisé ici)
      - p     : M1N1Proxy (toutes les écritures/lectures MMIO passent par p.read32/write32)
      - u     : ProxyUtils (sert à charger l'ADT une fois, pour résoudre les adresses)

    __init__ résout les adresses dans l'ADT EXACTEMENT comme mesa_hello.sh (l.66-87)
    et refait les mêmes vérifications de sûreté (spi2 alimenté par iBoot, broches SPI
    dans l'état d'iBoot, broche 196 dans l'état attendu). Aucune écriture au __init__.
    """

    def __init__(self, iface, p, u, check_state=True):
        self.iface = iface
        self.p = p
        self.u = u
        self._saved = None       # registres spi2 sauvegardés (remis par restore())
        self._pwr_orig = None    # valeur d'origine de la broche d'alimentation
        self._resolve_addrs(u, check_state=check_state)

    # ---- résolution des adresses (ADT) ------------------------------------
    def _resolve_addrs(self, u, check_state=True):
        # Import tardif : le module reste importable HORS LIGNE (le SELFTEST n'a
        # pas m1n1). mesa_hello.sh fait ces mêmes accès l.59, 66-76.
        from m1n1 import adt
        tree = adt.load_adt(u.get_adt())

        spi = tree["/arm-io/spi2"]
        # Garde-fou de mesa_hello.sh l.67 : c'est bien le nœud du capteur mesa.
        compat = [c.compatible[0] for c in spi if hasattr(c, "compatible")]
        if compat != ["biosensor,mesa"]:
            raise MesaError(f"/arm-io/spi2 sans capteur mesa (compatible={compat})")
        self.SPI, self._spi_size = spi.get_reg(0)          # mesa_hello:68

        gpio, _ = tree["/arm-io/gpio0"].get_reg(0)         # mesa_hello:69
        self.GPIO = gpio
        self.PWR = gpio + 4 * PWR_PIN                       # mesa_hello:70
        self.READY = gpio + 4 * READY_PIN                   # broche 195 (lecture seule)

        # Registre d'état d'alimentation (PS) de SPI2 — calcul de mesa_hello.sh l.71-74.
        pmgr = tree["/arm-io/pmgr"]
        dev = {d.name: d for d in pmgr.devices}["SPI2"]
        ps = getattr(pmgr, "ps-regs")[dev.psreg]
        self.PS_ADDR = pmgr.get_reg(ps.reg)[0] + ps.offset + dev.psidx * 8

        if check_state:
            self._check_state()

    def _check_state(self):
        """Mêmes vérifications de sûreté que mesa_hello.sh (l.77, 80, 87). Lecture seule."""
        p = self.p
        ps_val = p.read32(self.PS_ADDR)
        if (ps_val & 0xff) != 0xff:                         # mesa_hello:77
            raise MesaError(f"spi2 non alimenté par iBoot (PS={ps_val:#x}) : on n'écrit pas dans le pmgr")
        pins = [p.read32(self.GPIO + 4 * n) for n in (48, 49, 50)]   # mesa_hello:78
        if pins != [0x8742a0, 0x874220, 0x874220]:          # mesa_hello:80
            raise MesaError("broches SPI pas dans l'état laissé par iBoot : arrêt")
        self._pwr_orig = p.read32(self.PWR)                 # mesa_hello:85
        if self._pwr_orig != PWR_ORIG:                      # mesa_hello:87
            raise MesaError(f"broche {PWR_PIN} dans un état inattendu ({self._pwr_orig:#x}) : arrêt")

    # ---- transaction SPI ---------------------------------------------------
    def xfer(self, tx, rx_len=None):
        """
        Une transaction SPI2 en mode FIFO scruté. Émet `tx` (bytes), reçoit `rx_len`
        octets et les rend. Séquence identique à mesa_hello.sh `xfer` (l.89-123).

        rx_len : par défaut len(tx). Le SPI étant full-duplex, lire autant d'octets
                 qu'on en émet capture toujours la réponse simultanée.
          - rx_len == len(tx)  : VU (mesa_hello lit l'état/les réponses ainsi, l.126,157)
          - rx_len == 0        : VU (mesa_hello émet les trames de commande sans lire, l.145-147)
          - 0 < rx_len < len(tx) ou autre : hypothèse (jamais exercé par mesa_hello).
            mesa_hello impose rx_len ∈ {0, n} (assert l.91) ; on garde ce garde-fou.

        NOTE RELAIS (hypothèse, non vérifié matériel) : relayer des trames chiffrées
        SEP↔capteur de longueur quelconque en mode scruté est une EXTENSION. Sous
        macOS ces gros blocs (jusqu'à 0x7200 o) passent en DMA (SIO), pas par ce FIFO.
        La boucle fill/drain ci-dessous gère une longueur quelconque, mais chaque octet
        = un aller-retour MMIO par le proxy : pour de gros blocs, XFER_TIMEOUT_S (2 s)
        peut être trop court sur lien distant. À régler/valider sur matériel.
        """
        import time
        p, SPI = self.p, self.SPI
        n = len(tx)
        if rx_len is None:
            rx_len = n
        if rx_len not in (0, n):                             # garde-fou de mesa_hello:91
            raise MesaError(f"rx_len doit être 0 ou {n} (mode scruté de mesa_hello), reçu {rx_len}")

        p.write32(SPI + CTRL, CTRL_FIFO_RESET)               # l.93 : reset FIFO
        p.write32(SPI + IF_XFER, IF_CLEAR)                   # l.94
        p.write32(SPI + IF_FIFO, IF_CLEAR)                   # l.95
        p.write32(SPI + TXCNT, n)                            # l.96
        p.write32(SPI + RXCNT, rx_len)                       # l.97

        sent = 0
        rx = bytearray()

        def fill():
            nonlocal sent
            lvl = (p.read32(SPI + FIFOSTAT) >> 8) & 0xff     # l.101 : niveau TX
            k = min(n - sent, FIFO_DEPTH - lvl)
            for b in tx[sent:sent + max(k, 0)]:              # l.103-104
                p.write32(SPI + TXDATA, b)
            sent += max(k, 0)

        def drain():
            lvl = (p.read32(SPI + FIFOSTAT) >> 24) & 0xff    # l.107 : niveau RX
            for _ in range(min(lvl, rx_len - len(rx))):      # l.108-109
                rx.append(p.read32(SPI + RXDATA) & 0xff)

        fill()                                               # l.110
        p.write32(SPI + CTRL, CTRL_RUN)                      # l.111 : RUN
        t0 = time.monotonic()
        while True:                                          # l.113-120
            fill()
            drain()
            flags = p.read32(SPI + IF_XFER)
            if sent == n and len(rx) == rx_len and (flags & XFER_DONE_BIT):
                break
            if time.monotonic() - t0 > XFER_TIMEOUT_S:
                raise MesaError(
                    f"échange bloqué : émis {sent}/{n}, reçu {len(rx)}/{rx_len}, "
                    f"IF_XFER={flags:#x} FIFOSTAT={p.read32(SPI + FIFOSTAT):#x}")
        p.write32(SPI + CTRL, CTRL_STOP)                     # l.121
        return bytes(rx)

    # ---- alimentation & configuration -------------------------------------
    def power_on(self):
        """
        Configure spi2 en mode scruté puis alimente le capteur (gpio0 196).
        Séquence identique à mesa_hello.sh l.132-144. NE TOUCHE PAS au pmgr
        (spi2 est déjà alimenté par iBoot, vérifié au __init__).
        Sauvegarde d'abord les registres pour restore().
        """
        import time
        p, SPI = self.p, self.SPI
        # Sauvegarde (mesa_hello:84) — remise par restore().
        self._saved = {r: p.read32(SPI + r)
                       for r in (CTRL, CFG, PIN, CLKDIV, WDELAY, IE_XFER, IE_FIFO)}
        if self._pwr_orig is None:
            self._pwr_orig = p.read32(self.PWR)

        # Réglages du contrôleur (mesa_hello:132-138).
        p.write32(SPI + CTRL, CTRL_STOP)        # l.132
        p.write32(SPI + IE_XFER, 0)             # l.133
        p.write32(SPI + IE_FIFO, 0)             # l.134
        p.write32(SPI + PIN, 0)                 # l.135
        p.write32(SPI + CLKDIV, CLKDIV_MESA)    # l.136
        p.write32(SPI + WDELAY, 0)              # l.137
        p.write32(SPI + CFG, CFG_POLLED)        # l.138

        # Alimentation du capteur (mesa_hello:141-144).
        p.write32(self.PWR, PWR_SEQ_A)          # l.141
        p.write32(self.PWR, PWR_SEQ_B)          # l.141
        time.sleep(PWR_SETTLE_S)                # l.142
        p.write32(self.PWR, PWR_ON)             # l.143
        time.sleep(PWR_ON_S)                    # l.144

    def ready(self):
        """Lit la broche « donnée prête » (gpio0 195). Active haute. LECTURE SEULE.
        Rend True si une réponse est en attente. Source : docs/sensor_hw.md (VU, Linux)."""
        # bit 0 = donnée de la broche (format du pilote public, cf. gpio_peek.sh l.83).
        return bool(self.p.read32(self.READY) & 1)

    def power_off(self):
        """Éteint le capteur (mesa_hello:168-169)."""
        import time
        self.p.write32(self.SPI + CTRL, CTRL_STOP)
        self.p.write32(self.PWR, PWR_SEQ_B)     # l.168 : capteur éteint
        time.sleep(0.02)                        # l.169

    def restore(self):
        """
        Remise en état d'iBoot : éteint le capteur, remet la broche 196 à sa valeur
        d'origine et les registres spi2 sauvegardés. Identique à mesa_hello.sh l.166-173.
        Sûr à appeler même si power_on() n'a pas été lancé.
        """
        import time
        p, SPI = self.p, self.SPI
        p.write32(SPI + CTRL, CTRL_STOP)
        if self._pwr_orig is not None:
            p.write32(self.PWR, PWR_SEQ_B)      # l.168
            time.sleep(0.02)                    # l.169
            p.write32(self.PWR, self._pwr_orig) # l.170
        if self._saved:
            for r in (CFG, PIN, CLKDIV, WDELAY, IE_XFER, IE_FIFO, CTRL):   # l.171
                p.write32(SPI + r, self._saved[r])

    # ---- helpers « bonjour » (auto-test de cohérence) ---------------------
    def status(self):
        """
        Lit l'état du capteur (trame 0x10). Rend le corps (octets après l'en-tête de
        7 octets), soit 16 octets. Identique à mesa_hello.sh `status()` (l.125-127).
        """
        r = self.xfer(FRAME_STATUS + bytes(16), STATUS_RXLEN)
        return r[7:]

    def hello(self):
        """
        Reproduit le « bonjour » de mesa_hello.sh (réveil → état → identité → état →
        lecture de l'identité). N'écrit rien de plus que les 4 trames en clair.
        Suppose power_on() déjà fait. Rend (identité|None, dernier état).
        Séquence : mesa_hello.sh l.145-158.
        """
        import time
        self.xfer(FRAME_WAKE, 0);    time.sleep(GAP_S)   # l.145 réveil
        self.status();               time.sleep(GAP_S)   # l.146 état
        self.xfer(FRAME_GET_ID, 0);  time.sleep(GAP_S)   # l.147 identité
        st = self.status()                               # l.148 état
        ok = st[:4] == STATUS_HEAD                        # l.149
        pending = (st[12] | (st[13] << 8)) if ok else None  # l.150
        ident = None
        if pending == ID_LEN:                             # l.153
            time.sleep(GAP_S)
            self.xfer(FRAME_READ_1B, 0); time.sleep(GAP_S)   # l.156 demande
            ident = self.xfer(bytes(ID_LEN), ID_LEN)         # l.157 lecture
            time.sleep(GAP_S)
            self.status()                                    # l.158
        return ident, st

    def read_id(self):
        """
        Allume (si besoin), fait le « bonjour » et vérifie l'identité contre la valeur
        connue (ID_EXPECTED). Rend l'identité (bytes). Lève MesaError si elle diffère.
        Auto-test de cohérence du transport.
        """
        ident, _ = self.hello()
        if ident is None:
            raise MesaError("pas d'identité lue (le capteur n'annonce pas 0x1b octets)")
        if ident != ID_EXPECTED:
            raise MesaError(f"identité inattendue : {ident.hex()} (attendu {ID_EXPECTED.hex()})")
        return ident


# ============================================================================
#  SELFTEST STRUCTUREL — AUCUN MATÉRIEL
#  Vérifie : carte des registres cohérente, séquence xfer correcte (sur un faux
#  proxy qui émule le FIFO en bouclage), séquence d'alimentation, trames du bonjour.
#  N'ouvre aucun port, n'importe pas m1n1.
# ============================================================================
class _FakeProxy:
    """Émule juste assez du contrôleur spi2 (FIFO bouclé) pour exercer xfer()/power_on()
    hors ligne. NE représente PAS le vrai capteur : sert à valider la SÉQUENCE de
    registres, pas le protocole. En bouclage, RX = TX (écho)."""

    def __init__(self, spi_base=0, pwr_addr=None):
        self.spi = spi_base
        self.pwr_addr = pwr_addr
        self.mem = {}            # adresse -> valeur (pour les regs non FIFO)
        self.writes = []         # journal (offset, valeur) pour les écritures spi2
        self._reset()

    def _reset(self):
        self.tx_cnt = 0
        self.rx_cnt = 0
        self.tx_fifo = []        # octets en attente d'être « décalés »
        self.shifted = 0         # total d'octets sortis
        self.rx_fifo = []        # octets reçus (écho), en attente de lecture
        self.rx_made = 0
        self.running = False

    # --- helpers d'offset ---
    def _off(self, addr):
        return addr - self.spi

    def write32(self, addr, val):
        if self.pwr_addr is not None and addr == self.pwr_addr:
            self.mem[addr] = val
            return
        off = self._off(addr)
        self.writes.append((off, val))
        if off == CTRL:
            if val == CTRL_FIFO_RESET:
                self._reset()
            elif val == CTRL_RUN:
                self.running = True
            elif val == CTRL_STOP:
                self.running = False
        elif off == TXCNT:
            self.tx_cnt = val
        elif off == RXCNT:
            self.rx_cnt = val
        elif off == TXDATA:
            self.tx_fifo.append(val & 0xff)
        else:
            self.mem[addr] = val

    def _process(self):
        # Décale tout le TX FIFO ; génère l'écho RX dans la limite de rx_cnt.
        if self.running and self.tx_fifo:
            for b in self.tx_fifo:
                self.shifted += 1
                if self.rx_made < self.rx_cnt:
                    self.rx_fifo.append(b)
                    self.rx_made += 1
            self.tx_fifo = []

    def read32(self, addr):
        off = self._off(addr)
        if off == FIFOSTAT:
            self._process()
            tx_lvl = len(self.tx_fifo)
            rx_lvl = len(self.rx_fifo)
            return (tx_lvl << 8) | (rx_lvl << 24)
        if off == RXDATA:
            return self.rx_fifo.pop(0) if self.rx_fifo else 0
        if off == IF_XFER:
            self._process()
            return XFER_DONE_BIT if (self.running and self.shifted >= self.tx_cnt) else 0
        return self.mem.get(addr, 0)


def _selftest():
    import sys
    fails = []

    def check(cond, msg):
        print(("  OK  " if cond else "FAIL  ") + msg)
        if not cond:
            fails.append(msg)

    print("== Carte des registres spi2 (mesa_hello.sh l.82-83) ==")
    regmap = {"CTRL": CTRL, "CFG": CFG, "STATUS": STATUS, "PIN": PIN, "TXDATA": TXDATA,
              "RXDATA": RXDATA, "CLKDIV": CLKDIV, "RXCNT": RXCNT, "WDELAY": WDELAY,
              "TXCNT": TXCNT, "FIFOSTAT": FIFOSTAT, "IE_XFER": IE_XFER, "IF_XFER": IF_XFER,
              "IE_FIFO": IE_FIFO, "IF_FIFO": IF_FIFO}
    for name, off in regmap.items():
        print(f"     {name:9s} +{off:#05x}")
    # offsets de mesa_hello.sh l.82-83, vérifiés un par un
    expected = {"CTRL": 0x0, "CFG": 0x4, "STATUS": 0x8, "PIN": 0xc, "TXDATA": 0x10,
                "RXDATA": 0x20, "CLKDIV": 0x30, "RXCNT": 0x34, "WDELAY": 0x38, "TXCNT": 0x4c,
                "FIFOSTAT": 0x10c, "IE_XFER": 0x130, "IF_XFER": 0x134, "IE_FIFO": 0x138, "IF_FIFO": 0x13c}
    check(regmap == expected, "offsets identiques à mesa_hello.sh l.82-83")
    check(len(set(regmap.values())) == len(regmap), "offsets tous distincts")

    print("== Constantes de contrôle / alimentation (mesa_hello.sh) ==")
    check(CFG_POLLED == 0x40002, "CFG mode scruté = 0x40002 (l.138)")
    check(CLKDIV_MESA == 3, "CLKDIV = 3 (l.136)")
    check((CTRL_FIFO_RESET, CTRL_RUN, CTRL_STOP) == (0xc, 1, 0), "CTRL reset/run/stop (l.93,111,121)")
    check((PWR_SEQ_A, PWR_SEQ_B, PWR_ON, PWR_ORIG) == (0x76802, 0x76a02, 0x76a03, 0x7680e),
          "séquence broche 196 (l.141-143,87,170)")
    check((PWR_PIN, READY_PIN) == (196, 195), "broches alim=196 / prêt=195 (mesa_hello:70 ; sensor_hw)")

    print("== Trames en clair (mesa_hello.sh / sensor_hw) ==")
    check(FRAME_WAKE.hex() == "80780007000000", "réveil 0x78 (l.145)")
    check(FRAME_STATUS.hex() == "80100007000000", "état 0x10 (l.126)")
    check(FRAME_GET_ID.hex() == "80700007000000", "identité 0x70 (l.147)")
    check(FRAME_READ_1B.hex() == "8013000b0000001b000000", "lecture 0x13 0x1b octets (l.156)")
    check(len(ID_EXPECTED) == ID_LEN and ID_EXPECTED[:2] == b"\x80\xd4", "identité attendue (l.129)")

    print("== Séquence xfer() sur faux proxy (émulation FIFO, hors ligne) ==")
    # On construit MesaSPI sans toucher à l'ADT (pas de m1n1 hors ligne).
    m = MesaSPI.__new__(MesaSPI)
    m.SPI = 0x0
    m.GPIO = 0x0
    m.PWR = 0xdeadbeef
    m.READY = 0xcafe
    m._saved = None
    m._pwr_orig = PWR_ORIG
    fp = _FakeProxy(spi_base=0, pwr_addr=0xdeadbeef)
    m.p = fp

    # 1) émission simple (rx_len=0) : les octets sont bien poussés, CTRL run puis stop.
    fp.writes.clear()
    out = m.xfer(FRAME_WAKE, 0)
    offs = [o for o, _ in fp.writes]
    check(out == b"", "xfer(rx_len=0) ne rend rien")
    check(offs[0] == CTRL and fp.writes[0][1] == CTRL_FIFO_RESET, "1er write = reset FIFO")
    check((IF_XFER in offs) and (IF_FIFO in offs), "drapeaux IF effacés")
    tx_idx = offs.index(TXCNT)
    check(fp.writes[tx_idx][1] == len(FRAME_WAKE), "TXCNT = longueur émise")
    check((CTRL, CTRL_RUN) in fp.writes, "CTRL RUN écrit")
    check(fp.writes[-1] == (CTRL, CTRL_STOP), "dernier write = CTRL stop")
    n_txdata = sum(1 for o, _ in fp.writes if o == TXDATA)
    check(n_txdata == len(FRAME_WAKE), "un write TXDATA par octet émis")

    # 2) full-duplex (rx_len=len) : en bouclage, RX == TX.
    payload = bytes(range(20))   # > FIFO_DEPTH pour exercer la boucle fill/drain
    got = m.xfer(payload, len(payload))
    check(got == payload, "xfer full-duplex rend l'écho (longueur > 16, boucle fill/drain OK)")

    # 3) status() : lit 0x17 octets, découpe au 7e.
    body = m.status()
    check(len(body) == STATUS_RXLEN - 7, "status() rend le corps après l'en-tête de 7 octets")

    # 4) garde-fou rx_len invalide.
    try:
        m.xfer(b"\x01\x02\x03", 2)
        check(False, "rx_len invalide doit lever MesaError")
    except MesaError:
        check(True, "rx_len ∉ {0,n} lève MesaError (garde-fou l.91)")

    print("== Séquence power_on() / restore() sur faux proxy ==")
    fp2 = _FakeProxy(spi_base=0, pwr_addr=0xdeadbeef)
    m.p = fp2
    m._saved = None
    m.power_on()
    w = fp2.writes
    check((CFG, CFG_POLLED) in w, "power_on écrit CFG=0x40002")
    check((CLKDIV, CLKDIV_MESA) in w, "power_on écrit CLKDIV=3")
    check((PIN, 0) in w, "power_on écrit PIN=0")
    check(fp2.mem.get(0xdeadbeef) == PWR_ON, "broche 196 finit à 0x76a03 (allumé)")
    check(m._saved is not None, "registres sauvegardés avant modification")
    m.restore()
    check(fp2.mem.get(0xdeadbeef) == PWR_ORIG, "restore remet la broche 196 à son état d'origine")

    print()
    if fails:
        print(f"SELFTEST : {len(fails)} ÉCHEC(S)")
        for f in fails:
            print("   - " + f)
        sys.exit(1)
    print("SELFTEST : tout passe (structure cohérente, aucun matériel touché).")


if __name__ == "__main__":
    _selftest()
