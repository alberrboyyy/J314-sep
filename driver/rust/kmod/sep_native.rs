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
//! annonces de découverte 0xFD (table nom→EP) et messages spontanés connus. Il ne répond à RIEN
//! (aucun EP de service, aucun ACK de SAVE xART). Tout message inattendu → état `Halted` définitif.
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
            description: "NOT IMPLEMENTED: any value other than 0 makes probe fail",
        },
        allow_xart_save_ack: u32 {
            default: 0,
            description: "NOT IMPLEMENTED: any value other than 0 makes probe fail",
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
    use kernel::{
        bindings, c_str, device, dma, new_condvar, new_mutex, of, platform,
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
    /// 1er message de `xarm` (C1 L30, 19/19) : TAG 0x02 TYPE 0x0e. Non servi (allow_xart non implémenté).
    const XARM_FIRST_TAG: u8 = 0x02;
    const XARM_FIRST_TYPE: u8 = 0x0e;

    const RING_LEN: usize = 64; // puissance de 2 (indices u32 qui bouclent)
    const ROM_QUEUE_LEN: usize = 4;
    const EPTABLE_LEN: usize = 32;
    const HALTED_LOG_LIMIT: u32 = 16;

    /// Un seul device lié à la fois (deux clients de `sep_mbox` s'écraseraient sans erreur, design §2).
    static BOUND: Atomic<u32> = Atomic::new(0);
    /// Passe à 1 juste avant le premier mot envoyé au SEP ; ne revient jamais à 0 (module non déchargeable).
    static TOUCHED: Atomic<u32> = Atomic::new(0);

    fn param_allow_boot() -> u32 {
        *crate::module_parameters::allow_boot.value()
    }

    /// Paramètres d'écriture prévus par le design mais non implémentés dans cette version.
    fn unimplemented_params() -> [(&'static str, u32); 4] {
        [
            ("allow_xart", *crate::module_parameters::allow_xart.value()),
            ("allow_xart_save_ack", *crate::module_parameters::allow_xart_save_ack.value()),
            ("allow_sbio", *crate::module_parameters::allow_sbio.value()),
            ("allow_sks", *crate::module_parameters::allow_sks.value()),
        ]
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
    }

    impl Core {
        const fn new() -> Self {
            Core {
                state: State::Idle,
                halt_reason: "",
                rom: [0; ROM_QUEUE_LEN],
                rom_len: 0,
                shmem_sent: false,
                eps: [const { None }; EPTABLE_LEN],
                n_eps: 0,
                ignored_after_halt: 0,
            }
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

    #[pin_data]
    pub(crate) struct SepData {
        dev: ARef<device::Device>,
        shmem: dma::Coherent<[u8]>,
        fw: FwRegion,
        ring: Ring,
        #[pin]
        core: Mutex<Core>,
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
                        self.halt(core, "EP annoncé deux fois", Some(raw));
                    } else if core.n_eps >= EPTABLE_LEN {
                        self.halt(core, "table de découverte pleine", Some(raw));
                    } else {
                        let info = EpInfo { ep: w.param, name: discovery::decode_name(w.data), sizes_raw: None };
                        dev_info!(self.dev, "découverte : EP {:#04x} = '{}'\n", info.ep, info.name_str());
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
                    None => self.halt(core, "FD TYPE 1 avant TYPE 0", Some(raw)),
                },
                (discovery::EP_CNTL, ty) if w.tag == 0 && CNTL_SPONTANEOUS.contains(&ty) => {
                    dev_info!(self.dev, "CNTL spontané connu TYPE {:#04x} (rien envoyé)\n", ty);
                }
                (ep, XARM_FIRST_TYPE)
                    if w.tag == XARM_FIRST_TAG && core.ep_by_name(b"xarm") == Some(ep) =>
                {
                    dev_info!(
                        self.dev,
                        "xarm (EP {:#04x}) : 1re requête TYPE 0x0e reçue, NON servie (allow_xart non implémenté)\n",
                        ep
                    );
                }
                _ => self.halt(core, "message inconnu après le boot", Some(raw)),
            }
        }

        fn state(&self) -> State {
            self.core.lock().state
        }

        fn log_table(&self) {
            let core = self.core.lock();
            dev_info!(self.dev, "table de découverte : {} EP (état {:?})\n", core.n_eps, core.state);
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

    /// Envoie un mot au SEP. Seul chemin d'envoi du module ; refuse hors de l'état Booting.
    fn send(data: &SepData, mbox: &Mailbox<SepData>, ep: u8, ty: u8, payload: u32, what: &str) -> Result {
        if data.state() != State::Booting {
            dev_err!(data.dev, "envoi {} refusé : état {:?}\n", what, data.state());
            return Err(EIO);
        }
        let w = Word::new(ep, BOOT_TAG, ty, 0, payload).encode();
        dev_info!(data.dev, "> {} : {:#018x}\n", what, w);
        if let Err(e) = mbox.send(Message { msg0: w, msg1: 0 }, false) {
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
    fn boot(data: &SepData, mbox: &Mailbox<SepData>) -> Result {
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

        send(data, mbox, EP_BOOT, ROM_GET_STATUS, 0, "GET_STATUS")?;
        data.expect_rom(ROM_STATUS_OK, Some(STATUS_BEFORE_TZ0), "GET_STATUS #1")?;

        send(data, mbox, EP_BOOT, ROM_BOOT_TZ0, 0, "BOOT_TZ0")?;
        data.expect_rom(ROM_TZ0_DONE, None, "BOOT_TZ0 ack 0x69")?;
        data.expect_rom(ROM_UNK_DONE, None, "BOOT_TZ0 ack 0xD2")?;

        send(data, mbox, EP_BOOT, ROM_GET_STATUS, 0, "GET_STATUS")?;
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
        send(data, mbox, EP_BOOT, ROM_BOOT_IMG4, fw_page, "BOOT_IMG4")?;
        send(data, mbox, EP_SHMEM, ROM_SET_SHMEM, shmem_page, "SET_SHMEM")?;
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
            dev_info!(data.dev, "SEPOS lancé ; écoute seule (aucune réponse à aucun EP)\n");
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

    // --- pilote ---------------------------------------------------------------------------------------------
    pub(crate) struct SepNative {
        data: Arc<SepData>,
        mbox: Option<Mailbox<SepData>>,
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

        let data = Arc::pin_init(
            try_pin_init!(SepData {
                dev: ARef::<device::Device>::from(dev),
                shmem,
                fw,
                ring: Ring::new(),
                core <- new_mutex!(Core::new()),
                cv <- new_condvar!(),
                work <- new_work!("SepData::work"),
            }),
            GFP_KERNEL,
        )?;
        let mbox = Mailbox::new_byname(dev, c_str!("mbox"), data.clone()).inspect_err(|e| {
            dev_err!(dev, "mailbox 'mbox' indisponible : {:?}\n", e);
        })?;
        dev_info!(dev, "mailbox 'mbox' prise (réception active, rien envoyé)\n");

        if param_allow_boot() == 0 {
            dev_info!(dev, "allow_boot=0 : AUCUN envoi au SEP. Fin du probe.\n");
        } else {
            dev_info!(dev, "allow_boot=1 : séquence de boot m1n1 (GET_STATUS/TZ0/GET_STATUS/IMG4+SET_SHMEM)\n");
            // Erreur de boot ≠ échec du probe : une fois un mot envoyé, rien ne doit être libéré.
            match boot(&data, &mbox) {
                Ok(()) => {
                    data.settle(DISCOVERY_SETTLE_MS);
                }
                Err(e) => dev_err!(dev, "boot interrompu : {:?} (état {:?})\n", e, data.state()),
            }
            data.log_table();
        }
        Ok(SepNative { data, mbox: Some(mbox) })
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
                // La mailbox garde son cookie (une référence sur `SepData`) : la shmem et l'état restent
                // vivants, le callback reste valide (le module ne peut plus être déchargé, cf. mark_touched).
                if let Some(m) = self.mbox.take() {
                    core::mem::forget(m);
                }
            } else {
                // Rien n'a été envoyé : arrêt normal. Le drop de la mailbox fait `apple_mbox_stop` (plus aucun
                // callback, donc plus aucune mise en file), puis on attend un éventuel work en cours : le
                // module peut être déchargé juste après.
                self.mbox = None;
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
