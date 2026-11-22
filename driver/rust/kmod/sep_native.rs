// SPDX-License-Identifier: GPL-2.0
//! sep_native : pilote plateforme Rust hors arbre du SEP (j314c / t6001), option (b) de
//! `docs/driver_rust_design.md` §2 : il se lie au nœud distinct `j314c,sep-native` créé à chaud par
//! `driver/linux/sep_native_ovl.ko`, jamais au nœud `apple,sep` (qui reste `disabled`, donc `apple_sep`
//! intégré au noyau ne se lie pas).
//!
//! Au probe : prend la mailbox `mbox`, la région réservée `sepfw`, les manifestes du nœud `apple,sep`
//! d'origine, construit la shmem (DMA cohérent, DART du SEP via `iommus`), journalise tout ce qu'il a
//! trouvé, et **s'arrête là** tant que le paramètre `allow_boot` vaut 0 (défaut).
//!
//! Avec `allow_boot=1` : séquence de boot de m1n1 `proxyclient/m1n1/hw/sep.py` `SEP.boot()` (la séquence
//! éprouvée, et non celle de `drivers/soc/apple/sep.rs`) : GET_STATUS→0x66, BOOT_TZ0→0x69 puis 0xD2,
//! GET_STATUS→0x66, BOOT_IMG4 + SET_SHMEM→0x6A, démapping du firmware. Puis il **écoute seulement** :
//! annonces de découverte 0xFD (table nom→EP) et messages spontanés connus. Tout message inattendu → état
//! `Halted` définitif.
//!
//! Avec `allow_xart=1` (exige `allow_boot=1`) : ouverture de l'EP 0x13 `xarm` par le CNTL (SECMODE 0x14, puis
//! tampons A/B de 0x8000 : 0x04/0x02/0x05/0x03, chacun attendant son ack), comme `pending/sep_native_persist.sh`,
//! puis `/dev/sep_native` : le démon `sepd` lit les requêtes 0x13 (avec la copie du tampon B) et soumet des
//! réponses typées ; le noyau ne garde AUCUN store ni politique, il vérifie chaque réponse contre la requête en
//! attente (`xart_gate::check_reply` : même TAG, TYPE/PARAM/DATA permis, longueurs) avant de l'envoyer.
//! Les SAVE (0x01/0x06) ne sont acquittés que si `allow_xart_save_ack=1` ; sinon un SAVE reçu → `Halted`.
//! Rien n'est jamais envoyé vers 0x08 (sbio) ni 0x12 (sks).
//!
//! Une fois le premier mot envoyé au SEP, le module garde une référence sur lui-même (rmmod → EBUSY) et
//! un unbind fuit volontairement mailbox, shmem et mapping firmware (le SEP peut encore faire du DMA ;
//! seul un power-cycle le remet à zéro).
//!
//! Le cœur sans allocation de `sep-proto` (`word`, `discovery`) est inclus par `#[path]` à la racine du
//! crate, comme dans `sep_proto_selftest.rs`, pour que ses chemins `crate::...` se résolvent.

// --- cœur de sep-proto, sans allocation -------------------------------------------------------------------
#[path = "../sep-proto/src/common.rs"]
#[allow(dead_code, unreachable_pub)]
mod common;
// `crate::{Error, Result}` utilisés par les modules de sep-proto (et seulement par eux).
use common::{Error, Result};

#[path = "../sep-proto/src/discovery.rs"]
#[allow(dead_code, unreachable_pub)]
mod discovery;
#[path = "../sep-proto/src/word.rs"]
#[allow(dead_code, unreachable_pub)]
mod word;
#[path = "../sep-proto/src/crc.rs"]
#[allow(dead_code, unreachable_pub)]
mod crc;
#[path = "../sep-proto/src/xart.rs"]
#[allow(dead_code, unreachable_pub)]
mod xart;
#[path = "../sep-proto/src/xart_gate.rs"]
#[allow(dead_code, unreachable_pub)]
mod xart_gate;

kernel::module_platform_driver! {
    type: drv::SepNative,
    name: "sep_native",
    authors: ["Albert Braimi"],
    description: "j314c SEP boot driver (fail-closed, every write gated by a module parameter)",
    license: "GPL",
    params: {
        allow_boot: u32 {
            default: 0,
            description: "1 = boot SEPOS (GET_STATUS/TZ0/IMG4/SET_SHMEM). 0 (default) = probe only, send nothing",
        },
        allow_xart: u32 {
            default: 0,
            description: "1 = open EP 0x13 (CNTL SECMODE + OOL A/B) and serve it through /dev/sep_native (needs allow_boot=1)",
        },
        allow_xart_save_ack: u32 {
            default: 0,
            description: "1 = allow the daemon to ACK xART SAVEs (advances the sealed counter). 0 = a SAVE halts the driver",
        },
        allow_sbio: u32 {
            default: 0,
            description: "NOT IMPLEMENTED: any value other than 0 makes probe fail",
        },
        allow_sks: u32 {
            default: 0,
            description: "NOT IMPLEMENTED: any value other than 0 makes probe fail",
        },
    },
}

mod drv {
    use crate::discovery::{self, EpInfo};
    use crate::word::Word;
    use crate::xart::{is_save, EP_XART, OP_FWBOOT};
    use crate::xart_gate::{check_reply, request_b_len, AWrite, RecHdr, MAX_SAVES, OOL_SIZE, REC_HDR, REC_MAX};
    use kernel::{
        bindings, c_str, device, dma,
        fs::{File, Kiocb},
        iov::{IovIterDest, IovIterSource},
        miscdevice::{MiscDevice, MiscDeviceOptions, MiscDeviceRegistration},
        new_condvar, new_mutex, of, platform,
        prelude::*,
        soc::apple::mailbox::{MailCallback, Mailbox, Message},
        sync::{
            aref::ARef,
            atomic::{Acquire, Atomic, Full, Relaxed, Release},
            Arc, CondVar, CondVarTimeoutResult, Mutex,
        },
        time::msecs_to_jiffies,
        types::ForeignOwnable,
        workqueue::{self, impl_has_work, new_work, Work, WorkItem},
    };

    // --- constantes du protocole ---------------------------------------------------------------------------
    // Source : m1n1 `proxyclient/m1n1/hw/sep.py` (public) ; tableau « Boot ROM » de `docs/messages.md`.
    const EP_BOOT: u8 = 0xFF;
    const EP_SHMEM: u8 = 0xFE;
    /// TAG des mots de boot : 0, comme m1n1 (`SEPMessage` sans TAG). macOS met 1 (C1 L5-L12) ; on suit m1n1.
    const BOOT_TAG: u8 = 0;
    const ROM_GET_STATUS: u8 = 0x02;
    const ROM_BOOT_TZ0: u8 = 0x05;
    const ROM_BOOT_IMG4: u8 = 0x06;
    /// TYPE de SET_SHMEM sur l'EP 0xFE : 0x18 comme m1n1 (macOS envoie 0x1c, design Q11 : on ne change rien).
    const ROM_SET_SHMEM: u8 = 0x18;
    const ROM_STATUS_OK: u8 = 0x66;
    const ROM_TZ0_DONE: u8 = 0x69;
    const ROM_UNK_DONE: u8 = 0xD2;
    const ROM_IMG4_DONE: u8 = 0x6A;
    /// DATA attendue de 0x66 avant TZ0 puis après 0xD2 : 1 puis 2. m1n1 ne la vérifie pas ; le kext l'exige
    /// (`kext_sepmanager.md` §2, `source: kext`) et C11 la montre sous macOS. Vérification stricte ici :
    /// toute autre valeur → Halted (fail-closed ; avant TZ0 rien d'autre n'a été envoyé que GET_STATUS).
    const STATUS_BEFORE_TZ0: u32 = 1;
    const STATUS_AFTER_TZ0: u32 = 2;
    const IOVA_SHIFT: u32 = 12;

    /// Délai maximal par réponse de la ROM. m1n1 attend sans limite ; 5 s = délai du harnais pour les acks
    /// CNTL (`pending/sep_native_persist.sh`). Valeur `hypothèse` (aucune mesure de latence de la ROM).
    const BOOT_REPLY_TIMEOUT_MS: u32 = 5000;
    /// Après 0x6A, temps d'écoute avant d'afficher la table de découverte (C1 : annonces ~0,6 s après).
    const DISCOVERY_SETTLE_MS: u32 = 3000;

    // Disposition de la shmem : m1n1 `SEPShMem` (même résultat octet pour octet que `sep.rs::build_shmem`,
    // au magic près). Table de 16 octets par entrée (nom, taille, offset), puis `llun`.
    const SHMEM_SIZE: usize = 0x30000;
    const SHMEM_ALIGN: usize = 0x4000;
    const SHMEM_PANIC_OFFSET: usize = 0x4000;
    const SHMEM_PANIC_SIZE: usize = 0x8000;
    /// Magic de l'entrée « tampon panique » de la shmem.
    ///
    /// **À CONFIRMER.** m1n1 `hw/sep.py` écrit `CINP` (commentaire « PNIC », c.-à-d. `CINP` lu à l'envers) ;
    /// `drivers/soc/apple/sep.rs:118` écrit `CNIP`. On suit m1n1 (séquence éprouvée sous m1n1 sur cette
    /// machine) ; on ne sait pas si SEPOS vérifie ce champ (`docs/driver_rust_design.md` §1.4-2).
    const SHMEM_MAGIC_PANIC: [u8; 4] = *b"CINP";
    const SHMEM_MAGIC_LPOL: [u8; 4] = *b"OPLA";
    const SHMEM_MAGIC_IBOT: [u8; 4] = *b"IPIS";
    const SHMEM_MAGIC_END: [u8; 4] = *b"llun";

    // Messages spontanés connus après le boot (toutes les captures : `docs/messages.md` « xART au boot »,
    // SEP-BOOT 2026-11-09, `kext_sepmanager.md` §3). On les journalise sans répondre.
    const CNTL_SPONTANEOUS: [u8; 3] = [0x0d, 0x29, 0x10];
    /// 1er message de `xarm` (C1 L30, 19/19) : TAG 0x02 TYPE 0x0e. Non servi si allow_xart=0.
    const XARM_FIRST_TAG: u8 = 0x02;
    const XARM_FIRST_TYPE: u8 = 0x0e;

    // CNTL EP 0x00 (`pending/sep_native_persist.sh` `cntl_send` / `pump_ep0`, éprouvé sous m1n1 ; design §3.3).
    const CNTL_ACK: u8 = 0x01;
    const CNTL_SET_A_IOVA: u8 = 0x02;
    const CNTL_SET_B_IOVA: u8 = 0x03;
    const CNTL_SET_A_SIZE: u8 = 0x04;
    const CNTL_SET_B_SIZE: u8 = 0x05;
    const CNTL_PING: u8 = 0x11;
    const CNTL_PONG: u8 = 0x12;
    const CNTL_SECMODE: u8 = 0x14;
    /// Seuls TYPE que le pilote envoie sur l'EP 0x00 après le boot.
    const CNTL_TX_TYPES: [u8; 6] = [CNTL_SECMODE, CNTL_SET_A_SIZE, CNTL_SET_A_IOVA, CNTL_SET_B_SIZE, CNTL_SET_B_IOVA, CNTL_PONG];
    /// Délai par ack CNTL (5 s, comme le harnais).
    const CNTL_ACK_TIMEOUT_MS: u32 = 5000;
    /// EP auxquels ce pilote ne doit jamais rien envoyer (défense en profondeur ; aucun chemin n'y mène).
    const EP_SBIO: u8 = 0x08;
    const EP_SKS: u8 = 0x12;
    /// Requêtes 0x13 en attente de réponse (snew-reel : 6 au plus en même temps).
    const PEND_LEN: usize = 16;

    const RING_LEN: usize = 64; // puissance de 2 (indices u32 qui bouclent)
    const ROM_QUEUE_LEN: usize = 4;
    const EPTABLE_LEN: usize = 32;
    const HALTED_LOG_LIMIT: u32 = 16;
    const IGNORED_LOG_LIMIT: u32 = 256;

    /// Un seul device lié à la fois (deux clients de `sep_mbox` s'écraseraient sans erreur, design §2).
    static BOUND: Atomic<u32> = Atomic::new(0);
    /// Passe à 1 juste avant le premier mot envoyé au SEP ; ne revient jamais à 0 (module non déchargeable).
    static TOUCHED: Atomic<u32> = Atomic::new(0);

    fn param_allow_boot() -> u32 {
        *crate::module_parameters::allow_boot.value()
    }
    fn param_allow_xart() -> bool {
        *crate::module_parameters::allow_xart.value() != 0
    }
    fn param_allow_save_ack() -> bool {
        *crate::module_parameters::allow_xart_save_ack.value() != 0
    }

    /// Paramètres d'écriture prévus par le design mais non implémentés dans cette version.
    fn unimplemented_params() -> [(&'static str, u32); 2] {
        [
            ("allow_sbio", *crate::module_parameters::allow_sbio.value()),
            ("allow_sks", *crate::module_parameters::allow_sks.value()),
        ]
    }

    /// Raison lisible d'une erreur de `sep-proto`.
    fn why(e: &crate::Error) -> &'static str {
        match e {
            crate::Error::Unexpected(s) => s,
            crate::Error::OutOfRange(s, _) => s,
            crate::Error::Short => "enregistrement trop court",
            crate::Error::BadMagic => "magic",
        }
    }

    // --- anneau RX ------------------------------------------------------------------------------------------
    /// Anneau à un producteur et un consommateur, sans verrou ni allocation.
    ///
    /// Le design (§3.1) prévoit un `SpinLock<[Message; N]>`. Mais le callback mailbox tourne en IRQ dure et
    /// cet arbre n'a pas de spinlock Rust qui coupe les IRQ (`SpinLock` = `spin_lock` simple) : un work qui
    /// tiendrait le verrou quand l'IRQ arrive sur le même CPU bloquerait le CPU. D'où cet anneau atomique :
    /// - producteur unique : `recv_message`, appelé sous `mbox->rx_lock` (`mailbox.c` `apple_mbox_recv_irq`,
    ///   `apple_mbox_poll`), donc jamais deux fois en même temps ;
    /// - consommateur unique : le work `SepData`, un seul `work_struct` (non réentrant dans la workqueue).
    struct Ring {
        head: Atomic<u32>,
        tail: Atomic<u32>,
        overflow: Atomic<u32>,
        slots: [Atomic<u64>; RING_LEN],
    }

    impl Ring {
        const fn new() -> Self {
            Ring {
                head: Atomic::new(0),
                tail: Atomic::new(0),
                overflow: Atomic::new(0),
                slots: [const { Atomic::new(0) }; RING_LEN],
            }
        }

        /// Producteur (IRQ). Renvoie false si l'anneau est plein (le mot est perdu → Halted au drain).
        fn push(&self, w: u64) -> bool {
            let h = self.head.load(Relaxed);
            let t = self.tail.load(Acquire);
            if h.wrapping_sub(t) as usize >= RING_LEN {
                self.overflow.store(1, Release);
                return false;
            }
            self.slots[h as usize % RING_LEN].store(w, Relaxed);
            self.head.store(h.wrapping_add(1), Release);
            true
        }

        /// Consommateur (work).
        fn pop(&self) -> Option<u64> {
            let t = self.tail.load(Relaxed);
            let h = self.head.load(Acquire);
            if t == h {
                return None;
            }
            let w = self.slots[t as usize % RING_LEN].load(Relaxed);
            self.tail.store(t.wrapping_add(1), Release);
            Some(w)
        }
    }

    // --- état -----------------------------------------------------------------------------------------------
    #[derive(Clone, Copy, PartialEq, Eq, Debug)]
    enum State {
        /// Probe fait, rien envoyé.
        Idle,
        /// Séquence de boot en cours : seuls des mots EP 0xFF sont admis.
        Booting,
        /// 0x6A reçu : écoute seule (découverte + spontanés connus).
        Running,
        /// Définitif jusqu'au power-cycle : plus aucun envoi.
        Halted,
    }

    /// Requête 0x13 reçue, pas encore acquittée.
    #[derive(Clone, Copy)]
    struct Pending {
        seq: u32,
        w: Word,
        /// Déjà lue par le démon (remise à false à chaque ouverture de /dev/sep_native).
        delivered: bool,
    }

    struct Core {
        state: State,
        halt_reason: &'static str,
        /// Réponses de la ROM (EP 0xFF) pas encore lues par le fil de boot, dans l'ordre d'arrivée.
        rom: [u64; ROM_QUEUE_LEN],
        rom_len: usize,
        /// BOOT_IMG4 et SET_SHMEM envoyés : le 0x6A qui suit fait passer en Running dès sa réception (dans le work), pour
        /// que les annonces 0xFD qui le suivent ne tombent pas dans l'état Booting.
        shmem_sent: bool,
        eps: [Option<EpInfo>; EPTABLE_LEN],
        n_eps: usize,
        ignored_after_halt: u32,
        /// Messages bénins ignorés après l'ouverture de 0x13 (autres EP annoncés, 0xFD).
        ignored: u32,
        // --- xART (allow_xart=1) ---
        /// EP de `xarm` une fois l'ouverture commencée (toujours 0x13).
        xarm: Option<u8>,
        /// Tampons A/B annoncés au SEP et acquittés.
        xart_open: bool,
        /// TAG du message CNTL dont on attend l'ack.
        cntl_wait: Option<u8>,
        cntl_tag: u8,
        pend: [Option<Pending>; PEND_LEN],
        n_pend: usize,
        next_seq: u32,
        /// Copie du tampon B prise à l'arrivée de la requête `b_owner` (une seule à la fois).
        bsnap: KVec<u8>,
        b_owner: Option<u32>,
        nsave: u32,
    }

    impl Core {
        fn new(bsnap: KVec<u8>) -> Self {
            Core {
                state: State::Idle,
                halt_reason: "",
                rom: [0; ROM_QUEUE_LEN],
                rom_len: 0,
                shmem_sent: false,
                eps: [const { None }; EPTABLE_LEN],
                n_eps: 0,
                ignored_after_halt: 0,
                ignored: 0,
                xarm: None,
                xart_open: false,
                cntl_wait: None,
                cntl_tag: 0,
                pend: [None; PEND_LEN],
                n_pend: 0,
                next_seq: 1,
                bsnap,
                b_owner: None,
                nsave: 0,
            }
        }

        fn pend_index(&self, seq: u32) -> Option<usize> {
            self.pend[..self.n_pend].iter().position(|p| p.is_some_and(|p| p.seq == seq))
        }

        fn pend_remove(&mut self, i: usize) {
            self.pend.copy_within(i + 1..self.n_pend, i);
            self.n_pend -= 1;
            self.pend[self.n_pend] = None;
        }

        fn rom_pop(&mut self) -> Option<Word> {
            if self.rom_len == 0 {
                return None;
            }
            let w = self.rom[0];
            self.rom.copy_within(1.., 0);
            self.rom_len -= 1;
            Some(Word::decode(w))
        }

        fn ep_index(&self, ep: u8) -> Option<usize> {
            self.eps[..self.n_eps].iter().position(|e| e.as_ref().is_some_and(|i| i.ep == ep))
        }

        /// EP annoncé sous ce nom (4 octets, espaces finaux compris), par la table de découverte.
        fn ep_by_name(&self, name: &[u8; 4]) -> Option<u8> {
            self.eps[..self.n_eps].iter().flatten().find(|i| &i.name == name).map(|i| i.ep)
        }
    }

    /// Région `sepfw` (firmware préchargé par iBoot, réservée par m1n1).
    #[derive(Clone, Copy)]
    struct FwRegion {
        phys: u64,
        size: usize,
    }

    /// Un tampon OOL (DMA cohérent sur le DART du SEP).
    type Ool = dma::Coherent<[u8]>;

    #[pin_data]
    pub(crate) struct SepData {
        dev: ARef<device::Device>,
        shmem: dma::Coherent<[u8]>,
        /// Tampons OOL de l'EP 0x13 (A = AP→SEP, B = SEP→AP), alloués seulement si allow_xart=1.
        ool: Option<(Ool, Ool)>,
        fw: FwRegion,
        ring: Ring,
        /// Un seul ouvreur de /dev/sep_native.
        opened: Atomic<u32>,
        #[pin]
        core: Mutex<Core>,
        /// Seule mailbox d'envoi. Verrou pris APRÈS `core` (jamais l'inverse). La mailbox tient une référence sur
        /// ce `SepData` (cookie) : le cycle est cassé au unbind si rien n'a été envoyé, gardé exprès sinon.
        #[pin]
        tx: Mutex<Option<Mailbox<SepData>>>,
        #[pin]
        cv: CondVar,
        #[pin]
        work: Work<SepData>,
    }

    impl_has_work! {
        impl HasWork<Self, 0> for SepData { self.work }
    }

    impl WorkItem for SepData {
        type Pointer = Arc<SepData>;

        fn run(this: Arc<SepData>) {
            this.drain();
        }
    }

    impl MailCallback for SepData {
        type Data = Arc<SepData>;

        /// Contexte d'IRQ dure : copie du mot dans l'anneau, mise en file du work unique. Ni log, ni
        /// allocation, ni verrou.
        fn recv_message(data: <Self::Data as ForeignOwnable>::Borrowed<'_>, msg: Message) {
            // msg1 n'est pas utilisé par le SEP (m1n1 le lit et le jette, sep.rs l'ignore).
            let _ = data.ring.push(msg.msg0);
            let this: Arc<SepData> = data.into();
            // Déjà en file → Err(this) rendu et relâché ; le work en cours videra aussi ce mot.
            let _ = workqueue::system().enqueue(this);
        }
    }

    impl SepData {
        fn halt(&self, core: &mut Core, why: &'static str, raw: Option<u64>) {
            if core.state == State::Halted {
                return;
            }
            core.state = State::Halted;
            core.halt_reason = why;
            // Réveille un éventuel `read` bloqué (il renvoie alors EIO).
            self.cv.notify_all();
            match raw {
                Some(w) => dev_err!(self.dev, "HALTED : {} (mot {:#018x}) ; plus aucun envoi jusqu'au power-cycle\n", why, w),
                None => dev_err!(self.dev, "HALTED : {} ; plus aucun envoi jusqu'au power-cycle\n", why),
            }
        }

        /// Work : vide l'anneau dans l'ordre d'arrivée.
        fn drain(&self) {
            loop {
                if self.ring.overflow.load(Acquire) != 0 {
                    let mut core = self.core.lock();
                    self.halt(&mut core, "anneau RX plein, message perdu", None);
                }
                let Some(raw) = self.ring.pop() else { break };
                let mut core = self.core.lock();
                self.handle(&mut core, raw);
            }
            self.cv.notify_all();
        }

        fn handle(&self, core: &mut Core, raw: u64) {
            let w = Word::decode(raw);
            match core.state {
                State::Halted => {
                    core.ignored_after_halt = core.ignored_after_halt.saturating_add(1);
                    if core.ignored_after_halt <= HALTED_LOG_LIMIT {
                        dev_info!(self.dev, "Halted : mot reçu et ignoré {:#018x}\n", raw);
                    }
                }
                State::Idle => self.halt(core, "message reçu alors que rien n'a été envoyé", Some(raw)),
                State::Booting => {
                    if w.ep != EP_BOOT {
                        self.halt(core, "message hors EP 0xFF pendant le boot", Some(raw));
                    } else if core.rom_len >= ROM_QUEUE_LEN {
                        self.halt(core, "trop de réponses ROM non lues", Some(raw));
                    } else {
                        let n = core.rom_len;
                        core.rom[n] = raw;
                        core.rom_len += 1;
                        if core.shmem_sent && w.ty == ROM_IMG4_DONE {
                            core.state = State::Running;
                        }
                    }
                }
                State::Running => self.handle_running(core, w, raw),
            }
        }

        fn handle_running(&self, core: &mut Core, w: Word, raw: u64) {
            match (w.ep, w.ty) {
                (discovery::EP_DISCOVERY, 0x00) => {
                    if core.ep_index(w.param).is_some() {
                        if core.xart_open {
                            self.ignore(core, "0xFD : EP déjà annoncé", raw);
                        } else {
                            self.halt(core, "EP annoncé deux fois", Some(raw));
                        }
                    } else if core.n_eps >= EPTABLE_LEN {
                        if core.xart_open {
                            self.ignore(core, "0xFD : table de découverte pleine, annonce non retenue", raw);
                        } else {
                            self.halt(core, "table de découverte pleine", Some(raw));
                        }
                    } else {
                        let info = EpInfo { ep: w.param, name: discovery::decode_name(w.data), sizes_raw: None };
                        dev_info!(self.dev, "découverte : EP {:#04x} = '{}'\n", info.ep, info.name_str());
                        if &info.name == b"sbio" {
                            dev_info!(self.dev, "sbio annoncé (EP {:#04x}) ; rien ne lui sera envoyé\n", info.ep);
                        }
                        let n = core.n_eps;
                        core.eps[n] = Some(info);
                        core.n_eps += 1;
                    }
                }
                (discovery::EP_DISCOVERY, 0x01) => match core.ep_index(w.param) {
                    Some(i) => {
                        if let Some(e) = core.eps[i].as_mut() {
                            e.sizes_raw = Some(w.data);
                        }
                        dev_info!(self.dev, "découverte : EP {:#04x} tailles {:#010x}\n", w.param, w.data);
                    }
                    None if core.xart_open => self.ignore(core, "0xFD TYPE 1 avant TYPE 0", raw),
                    None => self.halt(core, "FD TYPE 1 avant TYPE 0", Some(raw)),
                },
                (discovery::EP_DISCOVERY, _) if core.xart_open => self.ignore(core, "0xFD TYPE inconnu", raw),
                (discovery::EP_CNTL, ty) if w.tag == 0 && CNTL_SPONTANEOUS.contains(&ty) => {
                    dev_info!(self.dev, "CNTL spontané connu TYPE {:#04x} (rien envoyé)\n", ty);
                }
                (discovery::EP_CNTL, CNTL_ACK) if core.cntl_wait == Some(w.tag) => {
                    core.cntl_wait = None;
                    dev_info!(self.dev, "CNTL ack TAG {:#04x} DATA {:#x}\n", w.tag, w.data);
                }
                (discovery::EP_CNTL, CNTL_PING) if param_allow_xart() => {
                    // `< 0x11 → > 0x12`, même TAG (pump_ep0 du harnais).
                    dev_info!(self.dev, "CNTL 0x11 TAG {:#04x} → 0x12\n", w.tag);
                    let _ = self.send_running(core, Word::new(discovery::EP_CNTL, w.tag, CNTL_PONG, 0, 0), "CNTL 0x12");
                }
                (ep, _) if core.ep_by_name(b"xarm") == Some(ep) => self.on_xarm(core, w, raw),
                // Une fois 0x13 ouvert : message sur un AUTRE EP annoncé (sbio, sks, xars, pnon, hibe, stac, hdcp…)
                // → journalisé et ignoré, sans réponse ni Halted, comme le harnais m1n1 (un Halted au milieu des
                // SAVE laisserait le xART à moitié scellé). Restent Halted : EP 0x00 inconnu, EP jamais annoncé.
                (ep, _) if core.xart_open && ep != discovery::EP_CNTL && core.ep_index(ep).is_some() => {
                    self.ignore(core, "message sur un autre EP annoncé, sans réponse", raw)
                }
                _ => self.halt(core, "message inconnu après le boot", Some(raw)),
            }
        }

        /// Journalise un message bénin ignoré (sans réponse). Journal limité à `IGNORED_LOG_LIMIT` lignes ; le
        /// total figure dans la table finale.
        fn ignore(&self, core: &mut Core, what: &'static str, raw: u64) {
            core.ignored = core.ignored.saturating_add(1);
            if core.ignored <= IGNORED_LOG_LIMIT {
                dev_info!(self.dev, "ignoré ({}) : {:#018x}\n", what, raw);
            } else if core.ignored == IGNORED_LOG_LIMIT + 1 {
                dev_info!(self.dev, "ignorés : journal coupé au-delà de {} messages (compte gardé)\n", IGNORED_LOG_LIMIT);
            }
        }

        /// Requête du SEP sur `xarm`. Sans allow_xart : seule la 1re (0x0e) est admise, journalisée sans réponse.
        /// Avec : contrôle du TYPE, copie de B si la requête en porte, mise en file pour le démon.
        fn on_xarm(&self, core: &mut Core, w: Word, raw: u64) {
            if !param_allow_xart() {
                if w.tag == XARM_FIRST_TAG && w.ty == XARM_FIRST_TYPE {
                    dev_info!(self.dev, "xarm (EP {:#04x}) : 1re requête TYPE 0x0e reçue, NON servie (allow_xart=0)\n", w.ep);
                } else {
                    self.halt(core, "requête xarm alors que allow_xart=0", Some(raw));
                }
                return;
            }
            if w.ep != EP_XART {
                return self.halt(core, "xarm annoncé ailleurs qu'en 0x13", Some(raw));
            }
            if is_save(w.ty) && !param_allow_save_ack() {
                return self.halt(core, "SAVE xART reçu et allow_xart_save_ack=0 : pas d'ACK, arrêt (fail-closed)", Some(raw));
            }
            let blen = match request_b_len(&w) {
                Ok(n) => n,
                Err(e) => return self.halt(core, why(&e), Some(raw)),
            };
            if !core.xart_open && w.ty != OP_FWBOOT {
                return self.halt(core, "requête xarm autre que 0x0e avant l'ouverture des tampons", Some(raw));
            }
            if core.n_pend >= PEND_LEN {
                return self.halt(core, "trop de requêtes xarm en attente", Some(raw));
            }
            let seq = core.next_seq;
            if blen > 0 {
                if core.b_owner.is_some() {
                    return self.halt(core, "deux requêtes à tampon B en attente (B écrasé)", Some(raw));
                }
                let Some((_, b)) = self.ool.as_ref() else {
                    return self.halt(core, "tampon B absent", Some(raw));
                };
                core.bsnap.clear();
                if blen > b.len() || core.bsnap.resize(blen, 0, GFP_KERNEL).is_err() {
                    return self.halt(core, "copie de B impossible", Some(raw));
                }
                dma_rmb();
                // SAFETY: `b` est une allocation cohérente de `b.len()` octets, vivante (tenue par `self`) ;
                // `bsnap` a `blen <= b.len()` octets. Le SEP a écrit B avant d'envoyer la requête et ne le
                // réécrit qu'après notre réponse (protocole, une seule requête à B en attente, contrôlé ci-dessus).
                unsafe { core::ptr::copy_nonoverlapping(b.as_ptr().cast::<u8>(), core.bsnap.as_mut_ptr(), blen) };
                core.b_owner = Some(seq);
            }
            core.next_seq = seq.wrapping_add(1);
            let n = core.n_pend;
            core.pend[n] = Some(Pending { seq, w, delivered: false });
            core.n_pend += 1;
            dev_info!(
                self.dev,
                "xarm < seq {} TAG {:#04x} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} (B {} o)\n",
                seq, w.tag, w.ty, w.param, w.data, blen
            );
        }

        /// Envoi après le boot : CNTL (TYPE de la liste fermée) ou xarm une fois ouvert ; rien d'autre.
        /// Appelé avec `core` verrouillé (ordre des verrous : core puis tx). Refus ou erreur → Halted.
        fn send_running(&self, core: &mut Core, w: Word, what: &'static str) -> Result {
            let allowed = core.state == State::Running
                && param_allow_xart()
                && w.ep != EP_SBIO
                && w.ep != EP_SKS
                && match w.ep {
                    discovery::EP_CNTL => CNTL_TX_TYPES.contains(&w.ty),
                    ep => core.xarm == Some(ep) && core.xart_open,
                };
            if !allowed {
                self.halt(core, "envoi refusé par la porte (bug)", Some(w.encode()));
                return Err(EIO);
            }
            let raw = w.encode();
            let r = match self.tx.lock().as_ref() {
                Some(m) => m.send(Message { msg0: raw, msg1: 0 }, false),
                None => Err(EIO),
            };
            match r {
                Ok(()) => {
                    dev_info!(self.dev, "> {} : {:#018x}\n", what, raw);
                    Ok(())
                }
                Err(e) => {
                    self.halt(core, "erreur d'envoi mailbox", Some(raw));
                    Err(e)
                }
            }
        }

        /// Ouverture de l'EP 0x13 : SECMODE puis A taille/adresse, B taille/adresse (PARAM = EP), chacun attendant
        /// son ack CNTL (même TAG). Séquence de `pending/sep_native_persist.sh`.
        fn open_xart(&self) -> Result {
            let Some((a, b)) = self.ool.as_ref() else { return Err(EINVAL) };
            let (Some(ia), Some(ib)) = (iova_page(a.dma_handle()), iova_page(b.dma_handle())) else {
                dev_err!(self.dev, "IOVA A/B inutilisables : 0x13 non ouvert (rien envoyé)\n");
                return Err(EINVAL);
            };
            let size = OOL_SIZE as u32;
            let mut core = self.core.lock();
            if core.state != State::Running {
                return Err(EIO);
            }
            if core.ep_by_name(b"xarm") != Some(EP_XART) {
                dev_err!(self.dev, "xarm non annoncé en 0x13 : 0x13 non ouvert (rien envoyé)\n");
                return Err(ENODEV);
            }
            core.xarm = Some(EP_XART);
            dev_info!(self.dev, "ouverture 0x13 : A IOVA {:#x}, B IOVA {:#x}, {:#x} o chacun\n", a.dma_handle(), b.dma_handle(), size);
            dma_wmb();
            let steps: [(u8, u8, u32, &'static str); 5] = [
                (CNTL_SECMODE, 0, 0, "CNTL SECMODE"),
                (CNTL_SET_A_SIZE, EP_XART, size, "CNTL A taille"),
                (CNTL_SET_A_IOVA, EP_XART, ia, "CNTL A adresse"),
                (CNTL_SET_B_SIZE, EP_XART, size, "CNTL B taille"),
                (CNTL_SET_B_IOVA, EP_XART, ib, "CNTL B adresse"),
            ];
            for (ty, param, d, what) in steps {
                core.cntl_tag = core.cntl_tag % 8 + 1;
                let tag = core.cntl_tag;
                core.cntl_wait = Some(tag);
                self.send_running(&mut core, Word::new(discovery::EP_CNTL, tag, ty, param, d), what)?;
                let mut left = msecs_to_jiffies(CNTL_ACK_TIMEOUT_MS);
                while core.cntl_wait.is_some() {
                    if core.state == State::Halted {
                        return Err(EIO);
                    }
                    match self.cv.wait_interruptible_timeout(&mut core, left) {
                        CondVarTimeoutResult::Woken { jiffies } => left = jiffies,
                        CondVarTimeoutResult::Timeout => {
                            self.halt(&mut core, "pas d'ack CNTL à l'ouverture de 0x13", None);
                            return Err(ETIMEDOUT);
                        }
                        CondVarTimeoutResult::Signal { .. } => {
                            self.halt(&mut core, "signal reçu pendant l'ouverture de 0x13", None);
                            return Err(EINTR);
                        }
                    }
                }
            }
            core.xart_open = true;
            dev_info!(self.dev, "0x13 ouvert ; requêtes en attente : {}\n", core.n_pend);
            Ok(())
        }

        /// Réponse du démon (`write`) : contrôle contre la requête en attente, écriture de A, envoi. Toute
        /// incohérence → Halted (rien n'est envoyé).
        fn submit_reply(&self, rec: &[u8]) -> Result {
            let mut core = self.core.lock();
            if core.state != State::Running || !core.xart_open {
                return Err(EIO);
            }
            let (h, a) = match RecHdr::decode(rec) {
                Ok(x) => x,
                Err(e) => {
                    self.halt(&mut core, why(&e), None);
                    return Err(EINVAL);
                }
            };
            let Some(i) = core.pend_index(h.seq).filter(|&i| core.pend[i].is_some_and(|p| p.delivered)) else {
                self.halt(&mut core, "réponse à une requête inconnue ou non lue", Some(h.w.encode()));
                return Err(EINVAL);
            };
            let Some(req) = core.pend[i].map(|p| p.w) else { return Err(EINVAL) };
            let aw = match check_reply(&req, &h.w, a, param_allow_save_ack()) {
                Ok(aw) => aw,
                Err(e) => {
                    dev_err!(self.dev, "réponse refusée seq {} : requête {:#018x}\n", h.seq, req.encode());
                    self.halt(&mut core, why(&e), Some(h.w.encode()));
                    return Err(EINVAL);
                }
            };
            if aw == AWrite::Replace {
                let Some((abuf, _)) = self.ool.as_ref() else { return Err(EIO) };
                // SAFETY: `abuf` est une allocation cohérente de `abuf.len()` (= OOL_SIZE) octets, vivante ;
                // `a.len() <= OOL_SIZE` (check_reply). Le SEP ne lit A qu'après le mot de réponse envoyé
                // ci-dessous ; les écritures sont sérialisées par `core`.
                unsafe {
                    let dst = abuf.as_mut_ptr().cast::<u8>();
                    core::ptr::write_bytes(dst, 0, abuf.len());
                    core::ptr::copy_nonoverlapping(a.as_ptr(), dst, a.len());
                }
            }
            dma_wmb();
            self.send_running(&mut core, h.w, "réponse xarm")?;
            dev_info!(self.dev, "xarm > seq {} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} (A {} o)\n", h.seq, h.w.ty, h.w.param, h.w.data, a.len());
            core.pend_remove(i);
            if core.b_owner == Some(h.seq) {
                core.b_owner = None;
            }
            if is_save(req.ty) {
                core.nsave += 1;
                dev_warn!(self.dev, "SAVE acquitté #{}/{} (compteur scellé avancé)\n", core.nsave, MAX_SAVES);
                if core.nsave >= MAX_SAVES {
                    self.halt(&mut core, "budget de SAVE atteint (MAX_SAVES) sans stabilisation", None);
                }
            }
            Ok(())
        }

        fn state(&self) -> State {
            self.core.lock().state
        }

        fn log_table(&self) {
            let core = self.core.lock();
            dev_info!(self.dev, "table de découverte : {} EP (état {:?}, {} message(s) ignoré(s))\n", core.n_eps, core.state, core.ignored);
            for e in core.eps[..core.n_eps].iter().flatten() {
                match e.pages() {
                    Some(p) => dev_info!(self.dev, "  EP {:#04x} '{}' pages {:?}\n", e.ep, e.name_str(), p),
                    None => dev_info!(self.dev, "  EP {:#04x} '{}'\n", e.ep, e.name_str()),
                }
            }
            if core.state == State::Halted {
                dev_info!(self.dev, "raison du Halted : {}\n", core.halt_reason);
            }
        }

        /// Attend la prochaine réponse de la ROM et la contrôle. Tout écart → Halted.
        fn expect_rom(&self, want_ty: u8, want_data: Option<u32>, step: &'static str) -> Result<Word> {
            let mut core = self.core.lock();
            let mut left = msecs_to_jiffies(BOOT_REPLY_TIMEOUT_MS);
            loop {
                if core.state == State::Halted {
                    return Err(EIO);
                }
                if let Some(w) = core.rom_pop() {
                    if w.ty != want_ty || want_data.is_some_and(|d| d != w.data) {
                        dev_err!(
                            self.dev,
                            "{} : attendu TYPE {:#04x} DATA {:?}, reçu TAG {:#04x} TYPE {:#04x} DATA {:#x}\n",
                            step, want_ty, want_data, w.tag, w.ty, w.data
                        );
                        self.halt(&mut core, "réponse ROM inattendue", Some(w.encode()));
                        return Err(EIO);
                    }
                    dev_info!(self.dev, "{} : TAG {:#04x} TYPE {:#04x} DATA {:#x} (OK)\n", step, w.tag, w.ty, w.data);
                    return Ok(w);
                }
                match self.cv.wait_interruptible_timeout(&mut core, left) {
                    CondVarTimeoutResult::Woken { jiffies } => left = jiffies,
                    CondVarTimeoutResult::Timeout => {
                        dev_err!(self.dev, "{} : pas de réponse en {} ms\n", step, BOOT_REPLY_TIMEOUT_MS);
                        self.halt(&mut core, "timeout d'une réponse ROM", None);
                        return Err(ETIMEDOUT);
                    }
                    CondVarTimeoutResult::Signal { .. } => {
                        self.halt(&mut core, "signal reçu pendant le boot", None);
                        return Err(EINTR);
                    }
                }
            }
        }

        /// Attend `ms` millisecondes en laissant le work remplir la table (réveils ignorés).
        fn settle(&self, ms: u32) {
            let mut core = self.core.lock();
            let mut left = msecs_to_jiffies(ms);
            while let CondVarTimeoutResult::Woken { jiffies } = self.cv.wait_interruptible_timeout(&mut core, left) {
                left = jiffies;
            }
        }
    }

    /// Barrière d'écriture DMA (`dma_wmb()`, arm64 `dmb oshst`) avant le mot mailbox qui annonce un tampon,
    /// comme `apple_rtkit_send_message` (`rtkit.c:628`) : `apple_mbox_send` écrit par `writeq_relaxed`, sans
    /// barrière. Pas de `dma_wmb` dans le Rust de cet arbre (seulement `smp_*`), d'où l'assembleur.
    fn dma_wmb() {
        // SAFETY: `dmb oshst` est une barrière mémoire : aucun accès mémoire, aucun registre modifié, aucun
        // effet sur la pile ; elle ne fait qu'ordonner les écritures précédentes avant les suivantes.
        unsafe { core::arch::asm!("dmb oshst", options(nostack, preserves_flags)) };
    }

    /// Barrière de lecture DMA (`dma_rmb()`, arm64 `dmb oshld`) entre la réception d'une requête et la lecture de B.
    fn dma_rmb() {
        // SAFETY: `dmb oshld` est une barrière mémoire : aucun accès mémoire, aucun registre modifié, aucun
        // effet sur la pile ; elle ne fait qu'ordonner les lectures précédentes avant les suivantes.
        unsafe { core::arch::asm!("dmb oshld", options(nostack, preserves_flags)) };
    }

    /// Envoie un mot de boot (EP 0xFF / 0xFE) au SEP ; refuse hors de l'état Booting. Après le boot, le seul
    /// chemin d'envoi est `SepData::send_running`.
    fn send(data: &SepData, ep: u8, ty: u8, payload: u32, what: &str) -> Result {
        if data.state() != State::Booting || (ep != EP_BOOT && ep != EP_SHMEM) {
            dev_err!(data.dev, "envoi {} refusé : état {:?}\n", what, data.state());
            return Err(EIO);
        }
        let w = Word::new(ep, BOOT_TAG, ty, 0, payload).encode();
        dev_info!(data.dev, "> {} : {:#018x}\n", what, w);
        let r = match data.tx.lock().as_ref() {
            Some(m) => m.send(Message { msg0: w, msg1: 0 }, false),
            None => Err(EIO),
        };
        if let Err(e) = r {
            dev_err!(data.dev, "envoi {} : erreur mailbox {:?}\n", what, e);
            data.halt(&mut data.core.lock(), "erreur d'envoi mailbox", Some(w));
            return Err(e);
        }
        Ok(())
    }

    /// Marque le SEP comme touché AVANT le premier envoi : module non déchargeable, unbind = fuite.
    fn mark_touched() {
        if TOUCHED.xchg(1, Full) == 0 {
            // SAFETY: `THIS_MODULE` est le pointeur `struct module` de ce module, valide tant que le module est
            // chargé (on y est). `__module_get` ne fait qu'incrémenter son compteur de références ; la
            // référence n'est jamais rendue, exprès (rmmod → EBUSY jusqu'au reboot).
            unsafe { bindings::__module_get(crate::THIS_MODULE.as_ptr()) };
        }
    }

    /// Mapping DMA du firmware `sepfw` sur le device (donc sur le DART du SEP).
    ///
    /// Sens BIDIRECTIONAL (lecture + écriture pour le SEP), comme le `dart_map` de m1n1 (PTE sans bit de
    /// protection, `m1n1/src/dart.c`), et non DMA_TO_DEVICE comme `sep.rs` : `io-pgtable-dart.c` poserait
    /// alors NO_WRITE, configuration jamais essayée sur cette machine.
    fn map_fw(data: &SepData) -> Result<u64> {
        // SAFETY: `dev` est un device lié (on est dans probe) ; `phys`/`size` décrivent la région réservée
        // `sepfw` (RAM réservée par m1n1, jamais libérée par Linux) ; le résultat est contrôlé juste après
        // par `dma_mapping_error`.
        let iova = unsafe {
            bindings::dma_map_resource(
                data.dev.as_raw(),
                data.fw.phys,
                data.fw.size,
                bindings::dma_data_direction_DMA_BIDIRECTIONAL,
                0,
            )
        };
        // SAFETY: même device, `iova` vient de `dma_map_resource` ci-dessus.
        if unsafe { bindings::dma_mapping_error(data.dev.as_raw(), iova) } != 0 {
            dev_err!(data.dev, "mapping DMA du firmware impossible\n");
            return Err(ENOMEM);
        }
        Ok(iova)
    }

    fn unmap_fw(data: &SepData, iova: u64) {
        // SAFETY: `iova`/`size` sont exactement ceux du `dma_map_resource` réussi de `map_fw` sur ce device ;
        // appelé une seule fois, après 0x6A (le SEP a fini de lire le firmware, m1n1 `sep.py` démappe ici).
        // (`sep.rs::remove` passe l'adresse physique à `dma_unmap_resource` : on passe bien l'IOVA.)
        unsafe {
            bindings::dma_unmap_resource(
                data.dev.as_raw(),
                iova,
                data.fw.size,
                bindings::dma_data_direction_DMA_BIDIRECTIONAL,
                0,
            )
        };
    }

    /// IOVA >> 12, à condition qu'elle soit alignée sur 4 Ko et tienne dans le champ DATA (32 bits).
    fn iova_page(iova: u64) -> Option<u32> {
        if iova & ((1 << IOVA_SHIFT) - 1) != 0 {
            return None;
        }
        u32::try_from(iova >> IOVA_SHIFT).ok()
    }

    /// Séquence de m1n1 `hw/sep.py` `SEP.boot()`. Toute erreur laisse l'état en Halted ; l'appelant ne
    /// libère jamais rien après le premier envoi.
    fn boot(data: &SepData) -> Result {
        let shmem_page = iova_page(data.shmem.dma_handle()).ok_or_else(|| {
            dev_err!(data.dev, "IOVA shmem {:#x} inutilisable (alignement / 32 bits)\n", data.shmem.dma_handle());
            EINVAL
        })?;
        {
            let mut core = data.core.lock();
            if core.state != State::Idle {
                dev_err!(data.dev, "boot refusé : état {:?} (raison : {})\n", core.state, core.halt_reason);
                return Err(EIO);
            }
            core.state = State::Booting;
        }
        mark_touched();

        send(data, EP_BOOT, ROM_GET_STATUS, 0, "GET_STATUS")?;
        data.expect_rom(ROM_STATUS_OK, Some(STATUS_BEFORE_TZ0), "GET_STATUS #1")?;

        send(data, EP_BOOT, ROM_BOOT_TZ0, 0, "BOOT_TZ0")?;
        data.expect_rom(ROM_TZ0_DONE, None, "BOOT_TZ0 ack 0x69")?;
        data.expect_rom(ROM_UNK_DONE, None, "BOOT_TZ0 ack 0xD2")?;

        send(data, EP_BOOT, ROM_GET_STATUS, 0, "GET_STATUS")?;
        data.expect_rom(ROM_STATUS_OK, Some(STATUS_AFTER_TZ0), "GET_STATUS #2")?;

        // m1n1 mappe le firmware avant le 1er GET_STATUS ; ici juste avant IMG4 (différence côté AP
        // seulement : le SEP ne voit l'IOVA qu'avec BOOT_IMG4).
        let fw_iova = match map_fw(data) {
            Ok(i) => i,
            Err(e) => {
                data.halt(&mut data.core.lock(), "mapping firmware impossible après TZ0", None);
                return Err(e);
            }
        };
        dev_info!(data.dev, "firmware mappé : phys {:#x} taille {:#x} → IOVA {:#x}\n", data.fw.phys, data.fw.size, fw_iova);
        let Some(fw_page) = iova_page(fw_iova) else {
            // Rien n'a été annoncé au SEP : on peut démapper.
            unmap_fw(data, fw_iova);
            data.halt(&mut data.core.lock(), "IOVA firmware inutilisable (alignement / 32 bits)", None);
            return Err(EINVAL);
        };

        dma_wmb();
        send(data, EP_BOOT, ROM_BOOT_IMG4, fw_page, "BOOT_IMG4")?;
        send(data, EP_SHMEM, ROM_SET_SHMEM, shmem_page, "SET_SHMEM")?;
        {
            let mut core = data.core.lock();
            core.shmem_sent = true;
            // 0x6A déjà arrivé entre les deux envois (encore dans la file ROM) : Running dès maintenant.
            if core.state == State::Booting && core.rom[..core.rom_len].iter().any(|&r| Word::decode(r).ty == ROM_IMG4_DONE) {
                core.state = State::Running;
            }
        }
        // En cas d'échec à partir d'ici, le firmware RESTE mappé (le SEP peut le lire) : fuite voulue.
        data.expect_rom(ROM_IMG4_DONE, None, "BOOT_IMG4 ack 0x6A")?;

        unmap_fw(data, fw_iova);
        dev_info!(data.dev, "firmware démappé après 0x6A (comme m1n1)\n");
        // L'état est passé à Running dans le work, à la réception de 0x6A (cf. `Core::shmem_sent`).
        if data.state() == State::Running {
            dev_info!(data.dev, "SEPOS lancé\n");
            Ok(())
        } else {
            Err(EIO)
        }
    }

    fn put(s: &mut [u8], off: usize, src: &[u8]) -> Result {
        let end = off.checked_add(src.len()).ok_or(EINVAL)?;
        s.get_mut(off..end).ok_or(EINVAL)?.copy_from_slice(src);
        Ok(())
    }

    fn align_up(v: usize, a: usize) -> Result<usize> {
        Ok(v.checked_add(a - 1).ok_or(EINVAL)? & !(a - 1))
    }

    fn put_entry(s: &mut [u8], i: usize, name: [u8; 4], size: usize, off: usize) -> Result {
        let base = i * 16;
        put(s, base, &name)?;
        put(s, base + 4, &u32::try_from(size)?.to_le_bytes())?;
        put(s, base + 8, &u32::try_from(off)?.to_le_bytes())
    }

    /// Shmem selon m1n1 `SEPShMem` : CINP (0x4000, 0x8000, contenu u32 1 + octet 0), OPLA (lpol), IPIS (ibot).
    fn build_shmem(dev: &device::Device<device::Bound>, lpol: &[u8], ibot: &[u8]) -> Result<dma::Coherent<[u8]>> {
        let lpol_off = SHMEM_PANIC_OFFSET + SHMEM_PANIC_SIZE;
        let lpol_size = align_up(lpol.len() + 4, SHMEM_ALIGN)?;
        let ibot_off = lpol_off + lpol_size;
        let ibot_size = align_up(ibot.len() + 4, SHMEM_ALIGN)?;
        let end = ibot_off.checked_add(ibot_size).ok_or(EINVAL)?;
        if end > SHMEM_SIZE {
            dev_err!(dev, "manifestes trop gros pour la shmem ({:#x} > {:#x})\n", end, SHMEM_SIZE);
            return Err(EINVAL);
        }
        let mut b = dma::CoherentBox::<[u8]>::zeroed_slice(dev, SHMEM_SIZE, GFP_KERNEL)?;
        let s: &mut [u8] = &mut b;
        // CINP : longueur 1, un octet 0 (déjà nul).
        put(s, SHMEM_PANIC_OFFSET, &1u32.to_le_bytes())?;
        put(s, lpol_off, &u32::try_from(lpol.len())?.to_le_bytes())?;
        put(s, lpol_off + 4, lpol)?;
        put(s, ibot_off, &u32::try_from(ibot.len())?.to_le_bytes())?;
        put(s, ibot_off + 4, ibot)?;
        put_entry(s, 0, SHMEM_MAGIC_PANIC, SHMEM_PANIC_SIZE, SHMEM_PANIC_OFFSET)?;
        put_entry(s, 1, SHMEM_MAGIC_LPOL, lpol_size, lpol_off)?;
        put_entry(s, 2, SHMEM_MAGIC_IBOT, ibot_size, ibot_off)?;
        put(s, 3 * 16, &SHMEM_MAGIC_END)?;
        Ok(b.into())
    }

    fn prop_is(node: &of::Node, name: &CStr, want: &[u8]) -> bool {
        matches!(node.get_property::<KVec<u8>>(name), Ok(v) if v[..] == *want)
    }

    // --- /dev/sep_native (allow_xart=1) -------------------------------------------------------------------
    // read  : bloque jusqu'à une requête 0x13 non lue ; renvoie un enregistrement `xart_gate::RecHdr` + copie de B.
    //         Tampon utilisateur >= REC_MAX exigé (EINVAL sinon). EIO une fois Halted.
    // write : UN enregistrement de réponse (en-tête + octets pour A) par appel ; contrôlé par `check_reply`.
    // Pas d'ioctl ; un seul ouvreur (EBUSY). Le périphérique n'existe qu'après l'ouverture réussie de 0x13.

    /// Enregistrement du miscdevice, jamais libéré (le SEP a été touché : rien n'est rendu avant le power-cycle).
    #[pin_data]
    struct XartDev {
        #[pin]
        reg: MiscDeviceRegistration<SepData>,
        data: Arc<SepData>,
    }

    #[vtable]
    impl MiscDevice for SepData {
        type Ptr = Arc<SepData>;

        fn open(_file: &File, misc: &MiscDeviceRegistration<SepData>) -> Result<Arc<SepData>> {
            // SAFETY: le seul `MiscDeviceRegistration<SepData>` enregistré est le champ `reg` d'un `XartDev`
            // épinglé dans un `KBox` oublié (`core::mem::forget`) : jamais libéré, donc `container_of` donne un
            // pointeur valide pour toujours.
            let x: &XartDev = unsafe { &*kernel::container_of!(core::ptr::from_ref(misc).cast_mut(), XartDev, reg) };
            let d = &x.data;
            if d.opened.cmpxchg(0, 1, Full).is_err() {
                return Err(EBUSY);
            }
            let mut core = d.core.lock();
            let n = core.n_pend;
            // Un démon relancé revoit les requêtes lues mais pas acquittées.
            for p in core.pend[..n].iter_mut().flatten() {
                p.delivered = false;
            }
            dev_info!(d.dev, "/dev/sep_native ouvert ({} requête(s) en attente)\n", n);
            drop(core);
            Ok(d.clone())
        }

        fn release(device: Arc<SepData>, _file: &File) {
            device.opened.store(0, Release);
        }

        fn read_iter(kiocb: Kiocb<'_, Arc<SepData>>, iov: &mut IovIterDest<'_>) -> Result<usize> {
            let me = kiocb.file();
            if iov.len() < REC_MAX {
                return Err(EINVAL);
            }
            let mut core = me.core.lock();
            loop {
                if core.state == State::Halted {
                    return Err(EIO);
                }
                let n = core.n_pend;
                if let Some(i) = core.pend[..n].iter().position(|p| p.is_some_and(|p| !p.delivered)) {
                    let Some(p) = core.pend[i] else { return Err(EIO) };
                    let b: &[u8] = if core.b_owner == Some(p.seq) { &core.bsnap } else { &[] };
                    let hdr = RecHdr { seq: p.seq, w: p.w, len: b.len() as u32 }.encode();
                    if iov.copy_to_iter(&hdr) != REC_HDR || iov.copy_to_iter(b) != b.len() {
                        return Err(EFAULT);
                    }
                    let total = REC_HDR + b.len();
                    if let Some(q) = core.pend[i].as_mut() {
                        q.delivered = true;
                    }
                    return Ok(total);
                }
                if me.cv.wait_interruptible(&mut core) {
                    return Err(ERESTARTSYS);
                }
            }
        }

        fn write_iter(kiocb: Kiocb<'_, Arc<SepData>>, iov: &mut IovIterSource<'_>) -> Result<usize> {
            let me = kiocb.file();
            let n = iov.len();
            if !(REC_HDR..=REC_MAX).contains(&n) {
                return Err(EINVAL);
            }
            let mut buf = KVec::with_capacity(n, GFP_KERNEL)?;
            if iov.copy_from_iter_vec(&mut buf, GFP_KERNEL)? != n {
                return Err(EFAULT);
            }
            me.submit_reply(&buf)?;
            Ok(n)
        }
    }

    fn register_xart_dev(data: &Arc<SepData>) -> Result {
        let reg = KBox::pin_init(
            try_pin_init!(XartDev {
                reg <- MiscDeviceRegistration::register(MiscDeviceOptions { name: c_str!("sep_native") }),
                data: data.clone(),
            }),
            GFP_KERNEL,
        )?;
        // Jamais libéré (cf. `XartDev`) : `open` s'appuie dessus.
        core::mem::forget(reg);
        Ok(())
    }

    // --- pilote ---------------------------------------------------------------------------------------------
    pub(crate) struct SepNative {
        data: Arc<SepData>,
    }

    kernel::of_device_table!(
        OF_TABLE,
        MODULE_OF_TABLE,
        <SepNative as platform::Driver>::IdInfo,
        [(of::DeviceId::new(c_str!("j314c,sep-native")), ())]
    );

    fn probe_inner(pdev: &platform::Device<device::Core<'_>>) -> Result<SepNative> {
        let dev = pdev.as_ref();
        let node = dev.of_node().ok_or(ENODEV)?;
        // Nœud `apple,sep` d'origine (porte les manifestes copiés par m1n1) ; doit rester `disabled`.
        let orig = node.parse_phandle(c_str!("j314c,sep-node"), 0).ok_or_else(|| {
            dev_err!(dev, "propriété j314c,sep-node absente (overlay sep_native_ovl ?)\n");
            ENODEV
        })?;
        if !prop_is(&orig, c_str!("compatible"), b"apple,sep\0") || !prop_is(&orig, c_str!("status"), b"disabled\0") {
            dev_err!(dev, "le nœud référencé n'est pas un apple,sep désactivé : refus (risque de 2 clients mailbox)\n");
            return Err(ENODEV);
        }
        let res = node.reserved_mem_region_to_resource_byname(c_str!("sepfw")).inspect_err(|_| {
            dev_err!(dev, "pas de région sepfw (m1n1 n'a pas vu d'alias sep) : rien à faire\n");
        })?;
        let fw = FwRegion { phys: res.start(), size: res.size().try_into()? };
        let lpol: KVec<u8> = orig.get_property(c_str!("local-policy-manifest")).inspect_err(|_| {
            dev_err!(dev, "local-policy-manifest absent\n");
        })?;
        let ibot: KVec<u8> = orig.get_property(c_str!("iboot-manifest")).inspect_err(|_| {
            dev_err!(dev, "iboot-manifest absent\n");
        })?;
        dev_info!(
            dev,
            "trouvé : sepfw phys {:#x} taille {:#x}, local-policy-manifest {:#x} o, iboot-manifest {:#x} o\n",
            fw.phys, fw.size, lpol.len(), ibot.len()
        );

        let shmem = build_shmem(dev, &lpol, &ibot)?;
        dev_info!(dev, "shmem {:#x} o allouée, IOVA {:#x} (magic panique {:?})\n", SHMEM_SIZE, shmem.dma_handle(),
                  SHMEM_MAGIC_PANIC);
        let ool = if param_allow_xart() {
            let a = dma::Coherent::<u8>::zeroed_slice(dev, OOL_SIZE, GFP_KERNEL)?;
            let b = dma::Coherent::<u8>::zeroed_slice(dev, OOL_SIZE, GFP_KERNEL)?;
            dev_info!(dev, "OOL 0x13 alloués : A IOVA {:#x}, B IOVA {:#x}\n", a.dma_handle(), b.dma_handle());
            Some((a, b))
        } else {
            None
        };
        let bsnap = KVec::with_capacity(if ool.is_some() { OOL_SIZE } else { 0 }, GFP_KERNEL)?;

        let data = Arc::pin_init(
            try_pin_init!(SepData {
                dev: ARef::<device::Device>::from(dev),
                shmem,
                ool,
                fw,
                ring: Ring::new(),
                opened: Atomic::new(0),
                core <- new_mutex!(Core::new(bsnap)),
                tx <- new_mutex!(None),
                cv <- new_condvar!(),
                work <- new_work!("SepData::work"),
            }),
            GFP_KERNEL,
        )?;
        let mbox = Mailbox::new_byname(dev, c_str!("mbox"), data.clone()).inspect_err(|e| {
            dev_err!(dev, "mailbox 'mbox' indisponible : {:?}\n", e);
        })?;
        *data.tx.lock() = Some(mbox);
        dev_info!(dev, "mailbox 'mbox' prise (réception active, rien envoyé)\n");

        if param_allow_boot() == 0 {
            dev_info!(dev, "allow_boot=0 : AUCUN envoi au SEP. Fin du probe.\n");
        } else {
            dev_info!(dev, "allow_boot=1 : séquence de boot m1n1 (GET_STATUS/TZ0/GET_STATUS/IMG4+SET_SHMEM)\n");
            // Erreur de boot ≠ échec du probe : une fois un mot envoyé, rien ne doit être libéré.
            match boot(&data) {
                Ok(()) => {
                    data.settle(DISCOVERY_SETTLE_MS);
                    if param_allow_xart() {
                        match data.open_xart().and_then(|()| register_xart_dev(&data)) {
                            Ok(()) => dev_info!(
                                dev,
                                "/dev/sep_native prêt (lancer sepd) ; ACK des SAVE : {}\n",
                                if param_allow_save_ack() { "AUTORISÉ" } else { "refusé (un SAVE → Halted)" }
                            ),
                            Err(e) => dev_err!(dev, "0x13 non servi : {:?} (état {:?})\n", e, data.state()),
                        }
                    }
                }
                Err(e) => dev_err!(dev, "boot interrompu : {:?} (état {:?})\n", e, data.state()),
            }
            data.log_table();
        }
        Ok(SepNative { data })
    }

    impl platform::Driver for SepNative {
        type IdInfo = ();
        type Data<'bound> = SepNative;
        const OF_ID_TABLE: Option<of::IdTable<Self::IdInfo>> = Some(&OF_TABLE);

        fn probe<'bound>(
            pdev: &'bound platform::Device<device::Core<'_>>,
            _info: Option<&'bound Self::IdInfo>,
        ) -> impl PinInit<Self::Data<'bound>, Error> + 'bound {
            for (name, v) in unimplemented_params() {
                if v != 0 {
                    dev_err!(pdev, "{}={} : non implémenté dans cette version, refus\n", name, v);
                    return Err(EINVAL);
                }
            }
            if (param_allow_xart() && param_allow_boot() == 0) || (param_allow_save_ack() && !param_allow_xart()) {
                dev_err!(pdev, "allow_xart exige allow_boot=1 et allow_xart_save_ack exige allow_xart=1 : refus\n");
                return Err(EINVAL);
            }
            if TOUCHED.load(Acquire) != 0 {
                dev_err!(pdev, "le SEP a déjà été touché depuis ce boot : refus (power-cycle requis)\n");
                return Err(EBUSY);
            }
            if BOUND.cmpxchg(0, 1, Full).is_err() {
                dev_err!(pdev, "une instance est déjà liée : refus\n");
                return Err(EBUSY);
            }
            let r = probe_inner(pdev);
            if r.is_err() && TOUCHED.load(Acquire) == 0 {
                BOUND.store(0, Release);
            }
            r
        }
    }

    impl Drop for SepNative {
        fn drop(&mut self) {
            if TOUCHED.load(Acquire) != 0 {
                dev_warn!(
                    self.data.dev,
                    "unbind après envoi au SEP : fuite volontaire de la mailbox, de la shmem et du mapping firmware \
                     (le SEP peut encore faire du DMA) ; power-cycle requis\n"
                );
                // La mailbox reste dans `SepData::tx` et garde son cookie (une référence sur `SepData`) : ce
                // cycle voulu garde la shmem, les OOL et l'état vivants, le callback reste valide (le module ne
                // peut plus être déchargé, cf. mark_touched). /dev/sep_native, s'il existe, reste aussi.
            } else {
                // Rien n'a été envoyé : arrêt normal. Le drop de la mailbox fait `apple_mbox_stop` (plus aucun
                // callback, donc plus aucune mise en file) et rend le cookie (fin du cycle), puis on attend un
                // éventuel work en cours : le module peut être déchargé juste après.
                drop(self.data.tx.lock().take());
                // SAFETY: `self.data` est vivant (on tient une référence), donc son champ `work`, épinglé dans
                // l'`Arc`, est un `work_struct` initialisé par `new_work!` ; `raw_get` ne fait que calculer
                // son adresse.
                let raw = unsafe { Work::raw_get(&self.data.work) };
                // SAFETY: `raw` pointe vers ce `work_struct` valide (cf. ci-dessus) ; `flush_work` peut dormir,
                // on est en contexte processus (unbind / rmmod).
                unsafe { bindings::flush_work(raw) };
                BOUND.store(0, Release);
            }
        }
    }
}
