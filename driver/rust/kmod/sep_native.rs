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
//!
//! Avec `allow_sbio=1` (exige `allow_xart=1`) : une fois `sbio` annoncé en 0x08 (après le scellement xART) et le
//! xART calme (aucune requête en attente, aucun trafic 0x13 depuis 2 s), ouverture de 0x08 par le CNTL (A8/B8 de
//! 0x4000 : 0x04/0x02/0x05/0x03, PARAM 0x08, sans 2e SECMODE), puis UNE poignée `> EP 0x08 TAG 0xfc TYPE 0x73`
//! (gt_packet capturé sous macOS, embarqué à la compilation), écoute 6 s, dump de B8 et verdict VIVANT/MUET
//! (`docs/j3_sbio_open.md`). Rien d'autre n'est jamais envoyé à 0x08 ; rien n'est jamais envoyé à 0x12 (sks).
//!
//! Avec `allow_sks=1` (J7a, exige `allow_sbio=1 sbio_open=1 allow_sbio_relay=0`, `docs/sks_native_plan.md` §4) : après
//! l'ouverture précoce de 0x08, ouverture CNTL SEULE de skdl (0x17, A=B=0x4000), sks (0x12, A=B=0x8000) et scrd (0x0a,
//! A=B=0x4000), dans cet ordre (c12), chacun seulement une fois annoncé en 0xFD au bon numéro avec les tailles attendues
//! ET son annonce 0x1d acquittée ; puis écoute passive 10 s (mots journalisés, dumps de B, jamais de réponse), puis le
//! 0x73. **Aucun mot n'est jamais envoyé AUX EP 0x17/0x12/0x0a** (porte d'envoi) : ni ping skdl, ni RPC sks.
//!
//! Avec `allow_sbio_bio=1` (exige `allow_sbio_params=3`) : E-ENROLL-START (J6a, `docs/j6_enroll_match_protocol.md`
//! §6) — après la dernière étape de la 2e passe (2e 0x63), UN seul `0x03` commandStartEnroll, charge FIXE de 68 octets
//! à zéro (`sbio_gate::ENROLL_INDATA_MIN`, contenu réel inconnu), puis ÉCOUTE seule : la réponse au 0x03 (quelle
//! qu'elle soit) et tout mot sbio ultérieur sont remis tels quels (mot + instantané de B8) à /dev/sep_sbio, sans
//! jamais répondre, sans Halted ; plus aucune commande n'est admise. Silence de 6 s après le 0x03 → écoute aussi.
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
// `crate::le_u32` utilisé par `gt` et `sbio_gate`.
use common::le_u32;

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
#[path = "../sep-proto/src/gt.rs"]
#[allow(dead_code, unreachable_pub)]
mod gt;
#[path = "../sep-proto/src/sbio_gate.rs"]
#[allow(dead_code, unreachable_pub)]
mod sbio_gate;
#[path = "../sep-proto/src/ks_gate.rs"]
#[allow(dead_code, unreachable_pub)]
mod ks_gate;

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
            description: "1 = once xART is sealed and quiet, open EP 0x08 (sbio) and send ONE 0x73 hello (needs allow_xart=1)",
        },
        allow_sbio_relay: u32 {
            default: 0,
            description: "1 = after a live 0x73, /dev/sep_sbio relays 0x17,0x15,0x16,0x42,0x18,0x5f in that order, once each (needs allow_sbio=1)",
        },
        allow_sbio_params: u32 {
            default: 0,
            description: "relay after 0x5f (needs allow_sbio_relay=1): 0 (default) = nothing; 1 = 0x5d 0x5c 0x6a 0x31 0x32 0x01 0x1f 0x31 0x32; 2 = those, then 0x5b (captured calibration, AP->SEP in 4 fragments) and 0x63; 3 = those, then the 2nd macOS pass 0x19 0x17 0x15 0x16 0x42 0x18 0x5f 0x5d 0x5c 0x6a 0x6f 0x31 0x32 0x01 0x1f 0x63 0x63, each at its own place only",
        },
        sbio_open: u32 {
            default: 1,
            description: "sbio CNTL open: 1 (default) = early, right after the 0x1d 'sbio' announce is acked, as macOS; 0 = late, after 2 s of xART quiet",
        },
        allow_sks: u32 {
            default: 0,
            description: "J7a (needs allow_sbio=1, sbio_open=1, allow_sbio_relay=0): 0 (default) = nothing; 1 = after the early sbio open, CNTL-open skdl 0x17 (0x4000), sks 0x12 (0x8000) and scrd 0x0a (0x4000), each only once announced and acked, in that order, then listen passively 10 s, then the 0x73. NEVER any word to 0x17/0x12/0x0a (no skdl ping, no sks RPC)",
        },
        allow_sbio_bio: u32 {
            default: 0,
            description: "E-ENROLL-START (needs allow_sbio_params=3): 0 (default) = nothing; 1 = after the 2nd 0x63 of the 2nd pass, ONE 0x03 commandStartEnroll with a FIXED 68-byte all-zero enroll_indata_v2_t (content unknown: hypothesis), then listen only: every later sbio word is handed raw to /dev/sep_sbio, never answered, no other command ever (no 0x06/0x23/0x09/0x65, never EP 0x12)",
        },
    },
}

mod drv {
    use crate::discovery::{self, EpInfo};
    use crate::gt::{self, CounterChecker, OOL_HDR};
    use crate::ks_gate::{self, OpenGate, KS_EPS, KS_SCRD, KS_SKDL, KS_SKS};
    use crate::sbio_gate::{self, EvtHdr, Step, EVT_HDR, EVT_MAX, KIND_BIO_REPLY, KIND_NOTIFY, KIND_REPLY, KIND_SPONT, MAX_REPLY};
    use crate::word::{Dir, Msg, Word};
    use crate::xart::{is_save, EP_XART, OP_EP_ANNOUNCE, OP_FWBOOT};
    use crate::xart_gate::{check_reply, request_b_len, AWrite, RecHdr, MAX_SAVES, OOL_SIZE, REC_HDR, REC_MAX};
    use kernel::time::{Instant, Monotonic};
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
            Arc, CondVar, CondVarTimeoutResult, Mutex, MutexGuard,
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
    /// Délai par ack CNTL (5 s, comme le harnais).
    const CNTL_ACK_TIMEOUT_MS: u32 = 5000;
    /// EP sbio : rien ne lui est envoyé, sauf avec allow_sbio=1 l'ouverture CNTL (PARAM 0x08) et UN 0x73.
    const EP_SBIO: u8 = 0x08;
    /// EP auxquels ce pilote n'envoie jamais rien (défense en profondeur ; aucun chemin n'y mène). Avec allow_sks=1,
    /// seul le CNTL (EP 0x00) PARAM 0x17/0x12/0x0a est admis, et seulement les 4 mots d'ouverture (`ks_gate::OpenGate`).
    const EP_SKS: u8 = ks_gate::EP_SKS;
    const EP_SKDL: u8 = ks_gate::EP_SKDL;
    const EP_SCRD: u8 = ks_gate::EP_SCRD;

    // --- J7a (allow_sks=1), `docs/sks_native_plan.md` §4 -----------------------------------------------------
    /// Attente, pour chaque EP keystore, de son annonce 0xFD (+ tailles) et de l'ack de son annonce 0x1d. c12 : sks
    /// annoncé 0,36 s après skdl ; seal frais natif : après le dernier SAVE (~2 s). Au-delà : EP non ouvert, ni lui ni
    /// les suivants ; le 0x73 part quand même (pas de Halted).
    const KS_WAIT_MS: i64 = 30_000;
    /// Écoute passive après la dernière ouverture, avant le 0x73.
    const KS_LISTEN_MS: i64 = 10_000;
    /// Dumps de B par EP keystore après un nouveau mot (en plus du dump de fin).
    const KS_DUMP_LIMIT: u32 = 4;
    /// Lignes de journal des mots keystore reçus (compte gardé au-delà).
    const KS_LOG_LIMIT: u32 = 128;

    // --- sbio (allow_sbio=1), `docs/j3_sbio_open.md` (vérifié c9) et `pending/sep_native_sbio.sh` -----------
    /// Taille de A8 et de B8 (comme macOS et le harnais m1n1).
    const SBIO_OOL_SIZE: usize = 0x4000;
    /// gt_packet 0x73 capturé sous macOS (`traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin`,
    /// copie octet pour octet, sha256 0982f722…92f3). Le noyau ne lit aucun fichier : embarqué à la compilation.
    const SBIO_HELLO: &[u8] = include_bytes!("sbio_hello_0x73.bin");
    const GT_TAG_CMD: u8 = 0xFC;
    const SBIO_OP_HELLO: u8 = 0x73;
    /// TAG d'une réponse sbio comptée comme signe de vie (en plus de TAG 0xfc TYPE 0x73).
    const SBIO_TAG_ALIVE: u8 = 0x04;
    // Contrôle à la compilation : gt_packet version 1 (+0x00), opcode 0x73 (+0x14), tient dans A8.
    const _: () = assert!(
        SBIO_HELLO.len() > 0x14 && SBIO_HELLO.len() <= SBIO_OOL_SIZE && SBIO_HELLO[0] == 1 && SBIO_HELLO[0x14] == SBIO_OP_HELLO
    );
    /// xART considéré calme : aucune requête 0x13 en attente et aucun mot 0x13 (reçu ou envoyé) depuis ce délai.
    const SBIO_QUIET_MS: i64 = 2000;
    /// Délai maximal (depuis la fin de l'ouverture de 0x13) pour voir `sbio` annoncé puis le xART calme ; au-delà,
    /// rien n'est envoyé à 0x08 (pas de Halted : le service xART continue).
    const SBIO_WAIT_MAX_MS: i64 = 120_000;
    /// Écoute de l'EP 0x08 après le 0x73.
    const SBIO_LISTEN_MS: i64 = 6000;
    /// Pas d'attente des boucles sbio (réveils du work en plus).
    const SBIO_POLL_MS: u32 = 250;
    const SBIO_DUMP_LEN: usize = 0x80;
    const SBIO_DUMP_LIMIT: u32 = 4;
    const SBIO_LOG_LIMIT: u32 = 128;
    /// Annonce 0x1d de sbio sur 0x13 : DATA = 'sbi' (24 bits bas), PARAM = 'o' (c12 : `TYPE 0x1d PARAM 0x6f DATA
    /// 0x00736269`). Ouverture précoce (sbio_open=1) dès que son ack (TYPE 0x16) est envoyé, comme macOS (~35 ms).
    const SBIO_ANNOUNCE_DATA: u32 = 0x0073_6269;
    const SBIO_ANNOUNCE_PARAM: u8 = 0x6f;
    /// Relais (allow_sbio_relay=1) : délai maximal par réponse GT du SEP (6 s, l'écoute des scripts sbio3..11).
    const RELAY_REPLY_TIMEOUT_MS: u32 = 6000;
    /// Notifications sbio (TAG 0x01-0x04) gardées pour /dev/sep_sbio ; au-delà, perdues et comptées (pas de Halted).
    const NOTE_LEN: usize = 16;
    /// Écoute après le 0x03 (allow_sbio_bio=1) : mots sbio non-notification gardés pour /dev/sep_sbio (avec
    /// l'instantané de B8, au plus SBIO_OOL_SIZE octets chacun) ; au-delà, perdus et comptés (jamais de Halted).
    const SPONT_LEN: usize = 8;
    /// Lignes de journal noyau des mots spontanés (le démon reçoit tout, dans la limite de SPONT_LEN en attente).
    const SPONT_LOG_LIMIT: u32 = 64;
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
    fn param_allow_sbio() -> bool {
        *crate::module_parameters::allow_sbio.value() != 0
    }
    fn param_allow_relay() -> bool {
        *crate::module_parameters::allow_sbio_relay.value() != 0
    }
    /// Niveau du relais après le patch (`sbio_gate::limit`) : 0, 1, 2 ou 3 (autre valeur refusée au probe).
    fn param_sbio_params() -> u32 {
        *crate::module_parameters::allow_sbio_params.value()
    }
    fn relay_limit() -> usize {
        sbio_gate::limit(param_sbio_params()).unwrap_or(sbio_gate::LIMIT_PATCH)
    }
    fn param_sbio_open() -> u32 {
        *crate::module_parameters::sbio_open.value()
    }
    /// Niveau bio (E-ENROLL-START) : 0 ou 1 (autre valeur refusée au probe ; exige allow_sbio_params=3).
    fn param_sbio_bio() -> u32 {
        *crate::module_parameters::allow_sbio_bio.value()
    }

    /// J7a : 0 ou 1 (autre valeur refusée au probe ; exige allow_sbio=1, sbio_open=1, allow_sbio_relay=0).
    fn param_allow_sks() -> u32 {
        *crate::module_parameters::allow_sks.value()
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

    /// Avancement de sbio (allow_sbio=1). Seul `Opening` admet les CNTL PARAM 0x08, seul `Open` admet le 0x73,
    /// seul `Relay` admet les commandes du relais (une transaction à la fois, `sbio_gate::RELAY_SEQUENCE`).
    #[derive(Clone, Copy, PartialEq, Eq, Debug)]
    enum SbioPhase {
        Off,
        Opening,
        Open,
        /// 0x73 envoyé (une seule fois) ; sans allow_sbio_relay, plus rien n'est admis vers 0x08.
        HelloSent,
        /// allow_sbio_relay=1 et sbio VIVANT : /dev/sep_sbio sert le relais.
        Relay,
    }

    /// Commande du relais en vol (une seule à la fois).
    struct Txn {
        step: &'static Step,
        /// `> fc` envoyé.
        sent: bool,
        /// Fragments AP→SEP de la commande (1 sauf 0x5b) et nombre déjà envoyés (`> fc` puis `> fd`).
        frags_in: usize,
        sent_in: usize,
        /// `< fe` reçu pendant l'envoi fragmenté : le fil d'écriture doit mettre le fragment suivant dans A8 et
        /// envoyer `> fd DATA sent_in << 16`.
        want_next: bool,
        /// Fragment reçu, réponse incomplète : le fil d'écriture doit envoyer `> fe`.
        want_more: bool,
        done: bool,
        total: Option<usize>,
        got: usize,
        nfrag: usize,
        /// Nombre de `< fd` reçus dans ce transfert (compteur du prochain `> fe`).
        nfd: u16,
        last: Word,
        /// Le 0x03 d'E-ENROLL-START : sa réponse est prise brute (1er mot non-notification, instantané de B8), jamais
        /// contrôlée ni complétée (pas de `> fe`), puis écoute.
        bio: bool,
    }

    /// État du relais sbio (allow_sbio_relay=1).
    struct Relay {
        /// Indice de la prochaine étape admise dans `RELAY_SEQUENCE`.
        next: usize,
        txn: Option<Txn>,
        counter: CounterChecker,
        /// Réponse réassemblée (préallouée à MAX_REPLY au probe) ; `reply` = mot final, en attente de lecture.
        buf: KVec<u8>,
        reply: Option<Word>,
        notes: [Word; NOTE_LEN],
        n_notes: usize,
        notes_dropped: u32,
        /// KIND de l'événement `reply` (KIND_REPLY, ou KIND_BIO_REPLY pour le 0x03 : `buf` = instantané brut de B8).
        reply_kind: u8,
        /// Écoute après le 0x03 (allow_sbio_bio=1) : plus aucune commande, chaque mot sbio → `spont` (ou `notes`).
        listen: bool,
        /// File circulaire des mots spontanés : emplacement `i` = `spont_buf[i * SBIO_OOL_SIZE ..][.. len]`
        /// (préalloué au probe seulement si allow_sbio_bio=1, sinon vide).
        spont: [(Word, usize); SPONT_LEN],
        spont_head: usize,
        n_spont: usize,
        spont_dropped: u32,
        spont_seen: u32,
        spont_buf: KVec<u8>,
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
        /// Dernier mot 0x13 reçu ou envoyé (fenêtre de calme avant sbio).
        xart_last: Option<Instant<Monotonic>>,
        // --- sbio (allow_sbio=1) ---
        sbio: SbioPhase,
        /// Mots EP 0x08 reçus (tout état), et reçus après le 0x73.
        sbio_rx: u32,
        sbio_rx_after: u32,
        /// Reçu après le 0x73 : TAG 0xfc TYPE 0x73, ou TAG 0x04.
        sbio_alive_msg: bool,
        /// L'ack (TYPE 0x16) de l'annonce 0x1d 'sbio' a été envoyé au SEP (déclencheur de l'ouverture précoce).
        sbio_ack_sent: bool,
        relay: Relay,
        // --- J7a (allow_sks=1), indices de `KS_EPS` (skdl, sks, scrd) ---
        /// L'ack (TYPE 0x16) de l'annonce 0x1d de cet EP a été envoyé.
        ks_acked: [bool; 3],
        /// Ouverture en cours (EP) et porte de ses 4 mots CNTL ; `None` / fermée hors ouverture.
        ks_opening: Option<u8>,
        ks_gate: OpenGate,
        /// 4 acks CNTL reçus.
        ks_open: [bool; 3],
        /// Mots reçus sur l'EP (tout état).
        ks_rx: [u32; 3],
        ks_logged: u32,
    }

    impl Core {
        fn new(bsnap: KVec<u8>, relay_buf: KVec<u8>, spont_buf: KVec<u8>) -> Self {
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
                xart_last: None,
                sbio: SbioPhase::Off,
                sbio_rx: 0,
                sbio_rx_after: 0,
                sbio_alive_msg: false,
                sbio_ack_sent: false,
                ks_acked: [false; 3],
                ks_opening: None,
                ks_gate: OpenGate::closed(),
                ks_open: [false; 3],
                ks_rx: [0; 3],
                ks_logged: 0,
                relay: Relay {
                    next: 0,
                    txn: None,
                    counter: CounterChecker::new(),
                    buf: relay_buf,
                    reply: None,
                    notes: [Word::new(0, 0, 0, 0, 0); NOTE_LEN],
                    n_notes: 0,
                    notes_dropped: 0,
                    reply_kind: KIND_REPLY,
                    listen: false,
                    spont: [(Word::new(0, 0, 0, 0, 0), 0); SPONT_LEN],
                    spont_head: 0,
                    n_spont: 0,
                    spont_dropped: 0,
                    spont_seen: 0,
                    spont_buf,
                },
            }
        }

        /// xART calme : aucune requête 0x13 en attente, aucun ack CNTL attendu, aucun mot 0x13 depuis 2 s.
        fn xart_quiet(&self) -> bool {
            self.n_pend == 0 && self.cntl_wait.is_none() && self.xart_last.is_none_or(|t| t.elapsed().as_millis() >= SBIO_QUIET_MS)
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
        /// Tampons A8/B8 de l'EP 0x08 (0x4000 chacun, distincts de ceux de 0x13), alloués seulement si allow_sbio=1.
        sbio_ool: Option<(Ool, Ool)>,
        /// Tampons A/B de skdl, sks, scrd (indices de `KS_EPS`, tailles `KsEp::size`), alloués seulement si
        /// allow_sks=1. A n'est jamais écrit (rien n'est envoyé à ces EP) ; B est seulement lu (dumps).
        ks_ool: Option<[(Ool, Ool); 3]>,
        fw: FwRegion,
        ring: Ring,
        /// Un seul ouvreur de /dev/sep_native.
        opened: Atomic<u32>,
        /// Un seul ouvreur de /dev/sep_sbio.
        sbio_opened: Atomic<u32>,
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
                            if param_allow_sbio() {
                                dev_info!(self.dev, "sbio annoncé (EP {:#04x}) ; ouverture quand le xART sera calme\n", info.ep);
                            } else {
                                dev_info!(self.dev, "sbio annoncé (EP {:#04x}) ; rien ne lui sera envoyé\n", info.ep);
                            }
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
                (ep, _) if core.ep_by_name(b"xarm") == Some(ep) => {
                    core.xart_last = Some(Instant::now());
                    self.on_xarm(core, w, raw)
                }
                // allow_sbio=1 : tout mot de sbio (annoncé en 0x08) est journalisé à part, sans réponse ni Halted
                // (notifications spontanées TAG 0x01 lockState, 0x02-0x04, et réponse éventuelle au 0x73).
                (EP_SBIO, _) if param_allow_sbio() && core.xart_open && core.ep_by_name(b"sbio") == Some(EP_SBIO) => {
                    self.on_sbio(core, w, raw)
                }
                // allow_sks=1 : mot de skdl/sks/scrd (annoncé au numéro attendu) → journal + compte, jamais de réponse
                // ni de Halted (J7a = écoute passive).
                (ep, _) if param_allow_sks() != 0
                    && core.xart_open
                    && ks_gate::ks_index(ep).is_some_and(|i| core.ep_by_name(&KS_EPS[i].name) == Some(ep)) =>
                {
                    self.on_keystore(core, w, raw)
                }
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

        /// Mot reçu sur skdl/sks/scrd (allow_sks=1) : journalisé (étiquette `ks_gate::classify`), compté. Jamais de
        /// réponse, jamais de Halted ; le fil du probe dumpe B après un nouveau mot (borné).
        fn on_keystore(&self, core: &mut Core, w: Word, raw: u64) {
            let Some(i) = ks_gate::ks_index(w.ep) else { return };
            core.ks_rx[i] = core.ks_rx[i].saturating_add(1);
            core.ks_logged = core.ks_logged.saturating_add(1);
            if core.ks_logged <= KS_LOG_LIMIT {
                let (op, txn, len, flag) = ks_gate::sks_fields(&w);
                dev_info!(
                    self.dev,
                    "keystore < EP {:#04x} '{}' TAG {:#04x} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} ({} ; {} ; champs sks op {:#04x} txn {:#04x} len {:#x} flag {:#x}) : {:#018x}\n",
                    w.ep, KS_EPS[i].name_str(), w.tag, w.ty, w.param, w.data,
                    ks_gate::kind_label(ks_gate::classify(&w)),
                    if core.ks_open[i] { "EP ouvert" } else { "EP PAS ENCORE ouvert" },
                    op, txn, len, flag, raw
                );
            } else if core.ks_logged == KS_LOG_LIMIT + 1 {
                dev_info!(self.dev, "keystore : journal coupé au-delà de {} mots (compte gardé)\n", KS_LOG_LIMIT);
            }
            self.cv.notify_all();
        }

        /// Mot reçu sur sbio (allow_sbio=1) : journalisé, compté. Avant le relais : jamais de réponse, jamais de
        /// Halted. En phase `Relay` : remis à `on_relay` (notification → événement ; réponse GT → transaction).
        fn on_sbio(&self, core: &mut Core, w: Word, raw: u64) {
            core.sbio_rx = core.sbio_rx.saturating_add(1);
            let after = matches!(core.sbio, SbioPhase::HelloSent | SbioPhase::Relay);
            if after {
                core.sbio_rx_after = core.sbio_rx_after.saturating_add(1);
                if (w.tag == GT_TAG_CMD && w.ty == SBIO_OP_HELLO) || w.tag == SBIO_TAG_ALIVE {
                    core.sbio_alive_msg = true;
                }
            }
            if core.sbio_rx <= SBIO_LOG_LIMIT {
                let what = match w.tag {
                    0x01 => "notification lockState",
                    0x02..=0x04 => "notification TAG 0x02-0x04",
                    0xFC..=0xFE => "GT",
                    _ => "autre",
                };
                dev_info!(
                    self.dev,
                    "sbio < TAG {:#04x} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} ({}, {} le 0x73) : {:#018x}\n",
                    w.tag, w.ty, w.param, w.data, what, if after { "après" } else { "avant" }, raw
                );
            } else if core.sbio_rx == SBIO_LOG_LIMIT + 1 {
                dev_info!(self.dev, "sbio : journal coupé au-delà de {} mots (compte gardé)\n", SBIO_LOG_LIMIT);
            }
            if core.sbio == SbioPhase::Relay {
                self.on_relay(core, w, raw);
            }
        }

        /// Relais (work, `core` verrouillé). Notification TAG 0x01-0x04 → file d'événements (pleine : perdue et
        /// comptée, pas de Halted). Réponse GT de la commande en vol → contrôle (compteur GT, en-tête de B8 par
        /// `sbio_gate::check_fragment`), copie du fragment, puis `done` ou `want_more`. Tout autre mot → Halted.
        fn on_relay(&self, core: &mut Core, w: Word, raw: u64) {
            if sbio_gate::is_notification(w.tag) {
                let r = &mut core.relay;
                if r.n_notes < NOTE_LEN {
                    r.notes[r.n_notes] = w;
                    r.n_notes += 1;
                } else {
                    r.notes_dropped = r.notes_dropped.saturating_add(1);
                    dev_warn!(self.dev, "sbio : notification perdue (file pleine, {} perdue(s)) : {:#018x}\n", r.notes_dropped, raw);
                }
                return;
            }
            if core.relay.listen {
                return self.on_listen(core, w, raw);
            }
            if core.relay.txn.as_ref().is_some_and(|t| t.bio && t.sent && !t.done) {
                return self.on_bio_answer(core, w, raw);
            }
            // Envoi fragmenté en cours (0x5b) : seul `< fe` est admis tant que tous les fragments ne sont pas partis
            // (un `< fc` précoce = refus du SEP → Halted) ; ensuite la réponse normale (`< fc`).
            let sending = core.relay.txn.as_ref().is_some_and(|t| t.sent_in < t.frags_in);
            let expected = core.relay.txn.as_ref().is_some_and(|t| {
                t.sent && !t.want_more && !t.want_next && !t.done && w.ty == t.step.op
                    && if sending {
                        w.tag == gt::TAG_FE
                    } else {
                        (t.nfrag == 0 && w.tag == GT_TAG_CMD) || (t.nfrag > 0 && w.tag == gt::TAG_FD)
                    }
            });
            if !expected {
                return self.halt(core, "sbio : mot inattendu pendant le relais (hors transaction, TAG/TYPE)", Some(raw));
            }
            if let Err(f) = core.relay.counter.check(&Msg::new(0, Dir::ToAp, w)) {
                dev_err!(self.dev, "sbio : compteur GT faux : {:?}\n", f);
                return self.halt(core, "sbio : règle du compteur GT violée", Some(raw));
            }
            if sending {
                // `< fe DATA (sent_in - 1) << 16` (compteur contrôlé ci-dessus) : B8 n'est pas lu (c12 : tout à zéro ;
                // qui l'efface n'est pas établi), seulement journalisé.
                if let Some((_, b8)) = self.sbio_ool.as_ref() {
                    self.dump_b8(b8, "B8 au < fe (envoi fragmenté)");
                }
                let Some(t) = core.relay.txn.as_mut() else { return };
                t.want_next = true;
                t.last = w;
                dev_info!(self.dev, "sbio relais < {} TAG 0xfe DATA {:#010x} : fragment {}/{} reçu, suivant demandé\n",
                          t.step.name, w.data, t.sent_in, t.frags_in);
                return;
            }
            let Some((_, b8)) = self.sbio_ool.as_ref() else {
                return self.halt(core, "sbio : B8 absent", Some(raw));
            };
            let mut hdr = [0u8; OOL_HDR];
            dma_rmb();
            // SAFETY: `b8` est une allocation cohérente de SBIO_OOL_SIZE >= OOL_HDR octets, vivante (tenue par `self`).
            // Le SEP a écrit B8 avant d'envoyer ce mot et ne le réécrit qu'après notre `> fe` (protocole GT).
            unsafe {
                let src = b8.as_ptr().cast::<u8>();
                for (i, x) in hdr.iter_mut().enumerate() {
                    *x = core::ptr::read_volatile(src.add(i));
                }
            }
            let Some(t) = core.relay.txn.as_ref() else { return };
            let f = match sbio_gate::check_fragment(t.step, &hdr, t.got, t.total, t.nfrag) {
                Ok(f) => f,
                Err(e) => {
                    dev_err!(self.dev, "sbio : en-tête B8 refusé : {:02x?}\n", hdr);
                    return self.halt(core, why(&e), Some(raw));
                }
            };
            let end = f.offset + f.len;
            if OOL_HDR + f.len > b8.len() {
                return self.halt(core, "sbio : fragment au-delà de B8", Some(raw));
            }
            // `end <= total <= MAX_REPLY = capacité préallouée` : pas d'allocation ici.
            let grown = end <= core.relay.buf.capacity() && core.relay.buf.resize(end, 0, GFP_KERNEL).is_ok();
            if !grown {
                return self.halt(core, "sbio : tampon de réponse trop petit", Some(raw));
            }
            let buf = &mut core.relay.buf;
            // SAFETY: `b8` vivant, `OOL_HDR + f.len <= b8.len()` (contrôlé ci-dessus) ; `buf` a `end` octets et
            // `offset + len == end`. Lecture octet par octet en volatile (mémoire DMA).
            unsafe {
                let src = b8.as_ptr().cast::<u8>().add(OOL_HDR);
                for i in 0..f.len {
                    buf[f.offset + i] = core::ptr::read_volatile(src.add(i));
                }
            }
            let Some(t) = core.relay.txn.as_mut() else { return };
            t.total = Some(f.total);
            t.got = end;
            t.nfrag += 1;
            t.last = w;
            if w.tag == gt::TAG_FD {
                t.nfd = t.nfd.wrapping_add(1);
            }
            if end == f.total {
                t.done = true;
            } else {
                t.want_more = true;
            }
            dev_info!(
                self.dev,
                "sbio relais < {} TAG {:#04x} fragment {} : total {:#x} offset {:#x} long {:#x} ({})\n",
                t.step.name, w.tag, t.nfrag, f.total, f.offset, f.len, if t.done { "complet" } else { "suite demandée" }
            );
        }

        /// Copie volatile des `dst.len()` premiers octets de B8 (`dst.len() <= B8`, contrôlé par l'appelant).
        fn read_b8(&self, b8: &Ool, dst: &mut [u8]) {
            dma_rmb();
            let n = dst.len().min(b8.len());
            // SAFETY: `b8` est une allocation cohérente de SBIO_OOL_SIZE octets, vivante (tenue par `self`) ; on lit
            // `n <= b8.len()` octets. Le SEP peut la réécrire : instantané octet par octet en volatile, jamais
            // interprété par le noyau (remis tel quel au démon).
            unsafe {
                let src = b8.as_ptr().cast::<u8>();
                for (i, x) in dst[..n].iter_mut().enumerate() {
                    *x = core::ptr::read_volatile(src.add(i));
                }
            }
        }

        /// Longueur de l'instantané de B8 (en-tête gt lu d'abord, `sbio_gate::snapshot_len`).
        fn b8_snap_len(&self, b8: &Ool) -> usize {
            let mut hdr = [0u8; OOL_HDR];
            self.read_b8(b8, &mut hdr);
            sbio_gate::snapshot_len(&hdr).min(b8.len())
        }

        /// Réponse au 0x03 (E-ENROLL-START) : le 1er mot sbio non-notification après `> fc 0x03`, quel qu'il soit
        /// (TAG/TYPE/DATA), est LA réponse. Instantané brut de B8 dans `relay.buf`, compteur GT contrôlé pour le journal
        /// seulement, puis passage en écoute. Jamais de `> fe`, jamais de Halted ici.
        fn on_bio_answer(&self, core: &mut Core, w: Word, raw: u64) {
            if let Err(f) = core.relay.counter.check(&Msg::new(0, Dir::ToAp, w)) {
                dev_warn!(self.dev, "sbio 0x03 : la réponse viole la règle du compteur GT ({:?}) : journalisé, pas de Halted\n", f);
            }
            let Some((_, b8)) = self.sbio_ool.as_ref() else {
                return self.halt(core, "sbio : B8 absent", Some(raw));
            };
            let n = self.b8_snap_len(b8);
            core.relay.buf.clear();
            if n > core.relay.buf.capacity() || core.relay.buf.resize(n, 0, GFP_KERNEL).is_err() {
                return self.halt(core, "sbio : tampon de réponse trop petit (0x03)", Some(raw));
            }
            self.read_b8(b8, &mut core.relay.buf);
            let ack = sbio_gate::is_plain_ack(w.tag, w.ty, w.param, w.data, &core.relay.buf);
            self.dump_b8(b8, "B8 à la réponse au 0x03");
            dev_warn!(
                self.dev,
                "sbio E-ENROLL-START < TAG {:#04x} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} : {} (B8 : {} o remis au démon) ; ÉCOUTE seule désormais\n",
                w.tag, w.ty, w.param, w.data, if ack { "ACK vide (forme attendue)" } else { "réponse NON conforme à un ack vide" }, n
            );
            core.relay.listen = true;
            if let Some(t) = core.relay.txn.as_mut() {
                t.done = true;
                t.got = n;
                t.last = w;
            }
        }

        /// Écoute (après le 0x03) : tout mot sbio non-notification est mis en file avec l'instantané de B8, jamais
        /// répondu, jamais de Halted (file pleine : perdu et compté).
        fn on_listen(&self, core: &mut Core, w: Word, raw: u64) {
            let r = &mut core.relay;
            r.spont_seen = r.spont_seen.saturating_add(1);
            let k = r.spont_seen;
            let Some((_, b8)) = self.sbio_ool.as_ref() else {
                dev_warn!(self.dev, "sbio écoute : B8 absent, mot {:#018x} non copié\n", raw);
                return;
            };
            if r.n_spont >= SPONT_LEN || r.spont_buf.len() < SPONT_LEN * SBIO_OOL_SIZE {
                r.spont_dropped = r.spont_dropped.saturating_add(1);
                dev_warn!(self.dev, "sbio écoute : mot spontané n°{} perdu (file pleine, {} perdu(s)) : {:#018x}\n", k, r.spont_dropped, raw);
                return;
            }
            let slot = (r.spont_head + r.n_spont) % SPONT_LEN;
            let n = self.b8_snap_len(b8);
            let base = slot * SBIO_OOL_SIZE;
            self.read_b8(b8, &mut core.relay.spont_buf[base..base + n]);
            let r = &mut core.relay;
            r.spont[slot] = (w, n);
            r.n_spont += 1;
            if k <= SPONT_LOG_LIMIT {
                dev_warn!(
                    self.dev,
                    "sbio écoute : mot spontané n°{} < TAG {:#04x} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} ({:#018x}) : NON répondu ; B8 {} o remis au démon\n",
                    k, w.tag, w.ty, w.param, w.data, raw, n
                );
                self.dump_b8(b8, "B8 au mot spontané");
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
                && w.ep != EP_SKS
                && w.ep != EP_SKDL
                && w.ep != EP_SCRD
                && match w.ep {
                    // CNTL PARAM 0x08 (tampons de sbio) : seulement pendant l'ouverture de sbio, TYPE 0x02-0x05.
                    discovery::EP_CNTL if w.param == EP_SBIO => {
                        param_allow_sbio()
                            && core.sbio == SbioPhase::Opening
                            && matches!(w.ty, CNTL_SET_A_IOVA | CNTL_SET_B_IOVA | CNTL_SET_A_SIZE | CNTL_SET_B_SIZE)
                    }
                    // CNTL PARAM 0x17/0x12/0x0a (J7a) : seulement l'EP en cours d'ouverture, et exactement le mot suivant
                    // des 4 de `ks_gate::open_steps` (TYPE, PARAM, DATA = taille ou IOVA de NOS tampons), une fois chacun.
                    discovery::EP_CNTL if ks_gate::ks_index(w.param).is_some() => {
                        param_allow_sks() == 1
                            && core.ks_opening == Some(w.param)
                            && core.ks_gate.admit(w.ty, w.param, w.data)
                    }
                    // Autres CNTL : SECMODE (PARAM 0, DATA 0) et tampons PARAM 0x13 seulement avant la fin de
                    // l'ouverture de 0x13 ; 0x12 (pong) PARAM 0 DATA 0.
                    discovery::EP_CNTL => match w.ty {
                        CNTL_SECMODE => w.param == 0 && w.data == 0 && !core.xart_open,
                        CNTL_SET_A_IOVA | CNTL_SET_B_IOVA | CNTL_SET_A_SIZE | CNTL_SET_B_SIZE => {
                            w.param == EP_XART && !core.xart_open
                        }
                        CNTL_PONG => w.param == 0 && w.data == 0,
                        _ => false,
                    },
                    // sbio : phase Open → exactement `TAG 0xfc TYPE 0x73 PARAM 0 DATA 0`, une seule fois (→ HelloSent) ;
                    // phase Relay → `> fc` de la commande en vol (DATA 0, une fois), `> fe` demandé (DATA nfd << 16), ou
                    // pour la seule étape `frag_in` (0x5b) `> fd` du fragment suivant après un `< fe` (DATA k << 16).
                    EP_SBIO if param_allow_sbio() => match core.sbio {
                        SbioPhase::Open => {
                            let ok = (w.tag, w.ty, w.param, w.data) == (GT_TAG_CMD, SBIO_OP_HELLO, 0, 0);
                            if ok {
                                core.sbio = SbioPhase::HelloSent;
                            }
                            ok
                        }
                        SbioPhase::Relay => {
                            param_allow_relay()
                                && core.relay.txn.as_ref().is_some_and(|t| {
                                    w.ty == t.step.op
                                        && w.param == 0
                                        && ((w.tag == GT_TAG_CMD && w.data == 0 && !t.sent)
                                            || (w.tag == gt::TAG_FE && t.want_more && w.data == u32::from(t.nfd) << 16)
                                            || (w.tag == gt::TAG_FD
                                                && t.step.frag_in
                                                && t.want_next
                                                && t.sent_in < t.frags_in
                                                && w.data == (t.sent_in as u32) << 16))
                                })
                        }
                        _ => false,
                    },
                    EP_SBIO => false,
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
            self.cntl_steps(&mut core, &steps, "pas d'ack CNTL à l'ouverture de 0x13", "signal reçu pendant l'ouverture de 0x13")?;
            core.xart_open = true;
            core.xart_last = Some(Instant::now());
            dev_info!(self.dev, "0x13 ouvert ; requêtes en attente : {}\n", core.n_pend);
            Ok(())
        }

        /// Envoie des CNTL `(TYPE, PARAM, DATA, libellé)` un par un, TAG 1..8 en boucle, chacun attendant son ack
        /// `< TYPE 0x01` de même TAG (5 s). Timeout ou signal → Halted.
        fn cntl_steps(
            &self,
            core: &mut MutexGuard<'_, Core>,
            steps: &[(u8, u8, u32, &'static str)],
            on_timeout: &'static str,
            on_signal: &'static str,
        ) -> Result {
            for &(ty, param, d, what) in steps {
                core.cntl_tag = core.cntl_tag % 8 + 1;
                let tag = core.cntl_tag;
                core.cntl_wait = Some(tag);
                self.send_running(core, Word::new(discovery::EP_CNTL, tag, ty, param, d), what)?;
                let mut left = msecs_to_jiffies(CNTL_ACK_TIMEOUT_MS);
                while core.cntl_wait.is_some() {
                    if core.state == State::Halted {
                        return Err(EIO);
                    }
                    match self.cv.wait_interruptible_timeout(core, left) {
                        CondVarTimeoutResult::Woken { jiffies } => left = jiffies,
                        CondVarTimeoutResult::Timeout => {
                            self.halt(core, on_timeout, None);
                            return Err(ETIMEDOUT);
                        }
                        CondVarTimeoutResult::Signal { .. } => {
                            self.halt(core, on_signal, None);
                            return Err(EINTR);
                        }
                    }
                }
            }
            Ok(())
        }

        /// Attend `sbio` annoncé en 0x08 et, selon `quiet`, le xART calme (true) ou l'ack de l'annonce 0x1d 'sbio'
        /// (false, ouverture précoce). Délai compté depuis `start` (SBIO_WAIT_MAX_MS). Échec : rien n'est envoyé à
        /// 0x08 par cette attente, pas de Halted (le service xART continue). Le verrou est rendu pendant l'attente
        /// (condvar) : le work et sepd continuent de servir 0x13.
        fn sbio_wait(&self, core: &mut MutexGuard<'_, Core>, start: Instant<Monotonic>, quiet: bool) -> Result {
            loop {
                if core.state != State::Running {
                    return Err(EIO);
                }
                match core.ep_by_name(b"sbio") {
                    Some(EP_SBIO) if (quiet && core.xart_quiet()) || (!quiet && core.sbio_ack_sent) => return Ok(()),
                    Some(EP_SBIO) | None => {}
                    Some(ep) => {
                        dev_err!(self.dev, "sbio annoncé en {:#04x} et non en 0x08 : rien envoyé à sbio\n", ep);
                        return Err(ENODEV);
                    }
                }
                if start.elapsed().as_millis() >= SBIO_WAIT_MAX_MS {
                    dev_err!(
                        self.dev,
                        "sbio : {} pas vu après {} ms : rien de plus envoyé à sbio\n",
                        if quiet { "xART calme" } else { "ack de l'annonce 0x1d 'sbio'" }, SBIO_WAIT_MAX_MS
                    );
                    return Err(ETIMEDOUT);
                }
                if let CondVarTimeoutResult::Signal { .. } = self.cv.wait_interruptible_timeout(core, msecs_to_jiffies(SBIO_POLL_MS)) {
                    dev_err!(self.dev, "signal pendant l'attente de sbio : rien de plus envoyé à sbio\n");
                    return Err(EINTR);
                }
            }
        }

        /// J3 (`docs/j3_sbio_open.md`) : ouvre 0x08 (A8/B8 par le CNTL, sans 2e SECMODE), puis envoie UNE poignée
        /// 0x73, écoute 6 s, dumpe B8, donne le verdict VIVANT/MUET (renvoyé : true = VIVANT).
        /// Ouverture : `sbio_open=1` (précoce, défaut) dès l'ack de l'annonce 0x1d 'sbio', comme macOS, pendant que le
        /// xART continue (les requêtes 0x13 sont toujours mises en file pour sepd pendant l'attente des acks CNTL,
        /// appariés par TAG) ; `sbio_open=0` (tardive) quand le xART est calme. Le 0x73 part dans les deux cas une
        /// fois le xART calme. Avant le 1er CNTL de sbio, un échec n'envoie rien et ne met pas en Halted. Un ack CNTL
        /// absent → Halted (cntl_steps). Après l'ouverture, un échec d'attente du calme n'envoie pas le 0x73.
        fn run_sbio(&self) -> Result<bool> {
            let Some((a8, b8)) = self.sbio_ool.as_ref() else { return Err(EINVAL) };
            let (Some(ia), Some(ib)) = (iova_page(a8.dma_handle()), iova_page(b8.dma_handle())) else {
                dev_err!(self.dev, "IOVA A8/B8 inutilisables : sbio non ouvert (rien envoyé)\n");
                return Err(EINVAL);
            };
            let early = param_sbio_open() == 1;
            let start = Instant::<Monotonic>::now();
            let mut core = self.core.lock();
            // 1. Déclencheur de l'ouverture.
            self.sbio_wait(&mut core, start, !early)?;
            dev_info!(
                self.dev,
                "sbio : ouverture {} ({} requête(s) 0x13 en attente) ; 0x08 : A8 IOVA {:#x}, B8 IOVA {:#x}, {:#x} o chacun\n",
                if early { "PRÉCOCE (ack 0x1d 'sbio' envoyé)" } else { "TARDIVE (xART calme depuis 2 s)" },
                core.n_pend, a8.dma_handle(), b8.dma_handle(), SBIO_OOL_SIZE
            );
            // 2. Ouverture : 4 CNTL PARAM 0x08, pas de SECMODE (global, déjà envoyé pour 0x13).
            let size = SBIO_OOL_SIZE as u32;
            let steps: [(u8, u8, u32, &'static str); 4] = [
                (CNTL_SET_A_SIZE, EP_SBIO, size, "CNTL A8 taille"),
                (CNTL_SET_A_IOVA, EP_SBIO, ia, "CNTL A8 adresse"),
                (CNTL_SET_B_SIZE, EP_SBIO, size, "CNTL B8 taille"),
                (CNTL_SET_B_IOVA, EP_SBIO, ib, "CNTL B8 adresse"),
            ];
            core.sbio = SbioPhase::Opening;
            dma_wmb();
            let r = self.cntl_steps(&mut core, &steps, "pas d'ack CNTL à l'ouverture de 0x08", "signal reçu pendant l'ouverture de 0x08");
            if r.is_err() {
                core.sbio = SbioPhase::Off;
                return r.map(|()| false);
            }
            core.sbio = SbioPhase::Open;
            dev_info!(self.dev, "0x08 ouvert ; mots sbio reçus jusqu'ici : {}\n", core.sbio_rx);
            // J7a : skdl, sks, scrd ouverts (CNTL seul) puis écoute passive, AVANT le 0x73. Erreur → pas de 0x73.
            let quiet_start = if param_allow_sks() == 1 {
                self.run_keystore(&mut core)?;
                Instant::<Monotonic>::now()
            } else {
                start
            };
            if early {
                self.sbio_wait(&mut core, quiet_start, true)?;
                dev_info!(self.dev, "sbio : xART calme ({} ms sans trafic 0x13, aucune requête en attente) ; envoi du 0x73\n", SBIO_QUIET_MS);
            }
            // 3. Poignée 0x73 : A8 = gt_packet capturé, relu avant l'envoi.
            // SAFETY: `a8` est une allocation cohérente de `a8.len()` (= SBIO_OOL_SIZE) octets, vivante (tenue par
            // `self`) ; `SBIO_HELLO.len() <= SBIO_OOL_SIZE` (assertion de compilation). Le SEP ne lit A8 qu'après
            // le mot 0x73 envoyé ci-dessous ; seul ce fil écrit A8, sous `core`.
            let (v0, op) = unsafe {
                let dst = a8.as_mut_ptr().cast::<u8>();
                core::ptr::write_bytes(dst, 0, a8.len());
                core::ptr::copy_nonoverlapping(SBIO_HELLO.as_ptr(), dst, SBIO_HELLO.len());
                (core::ptr::read_volatile(dst), core::ptr::read_volatile(dst.add(0x14)))
            };
            if v0 != 1 || op != SBIO_OP_HELLO {
                self.halt(&mut core, "A8 relu : pas un gt_packet 0x73 (+0x00 != 1 ou +0x14 != 0x73)", None);
                return Err(EIO);
            }
            self.dump_b8(b8, "B8 avant le 0x73");
            dma_wmb();
            self.send_running(&mut core, Word::new(EP_SBIO, GT_TAG_CMD, SBIO_OP_HELLO, 0, 0), "sbio 0x73 (poignée)")?;
            // 4. Écoute 6 s ; dump de B8 après chaque nouveau mot sbio (borné), puis à la fin.
            let t0 = Instant::<Monotonic>::now();
            let mut seen = core.sbio_rx_after;
            let mut dumps = 0;
            while t0.elapsed().as_millis() < SBIO_LISTEN_MS && core.state != State::Halted {
                if let CondVarTimeoutResult::Signal { .. } = self.cv.wait_interruptible_timeout(&mut core, msecs_to_jiffies(SBIO_POLL_MS)) {
                    dev_warn!(self.dev, "signal pendant l'écoute de sbio : écoute écourtée\n");
                    break;
                }
                if core.sbio_rx_after != seen && dumps < SBIO_DUMP_LIMIT {
                    seen = core.sbio_rx_after;
                    dumps += 1;
                    self.dump_b8(b8, "B8 après un mot sbio");
                }
            }
            let (b0, b14) = self.dump_b8(b8, "B8 en fin d'écoute");
            let alive = (b0 == 1 && b14 == SBIO_OP_HELLO) || core.sbio_alive_msg;
            dev_info!(
                self.dev,
                "VERDICT sbio : {} (B8 +0x00={:#04x} +0x14={:#04x} ; {} mot(s) 0x08 après le 0x73 ; TAG 0xfc TYPE 0x73 ou TAG 0x04 : {})\n",
                if alive { "VIVANT" } else { "MUET" },
                b0, b14, core.sbio_rx_after, if core.sbio_alive_msg { "oui" } else { "non" }
            );
            if param_allow_sks() == 1 {
                dev_info!(
                    self.dev,
                    "keystore (bilan) : ouverts skdl {} sks {} scrd {} ; mots reçus skdl {} sks {} scrd {}\n",
                    core.ks_open[KS_SKDL], core.ks_open[KS_SKS], core.ks_open[KS_SCRD],
                    core.ks_rx[KS_SKDL], core.ks_rx[KS_SKS], core.ks_rx[KS_SCRD]
                );
            }
            if alive && param_allow_relay() && core.state == State::Running {
                let bio_tail = if param_sbio_bio() != 0 { ", puis UN 0x03 (E-ENROLL-START) et écoute seule" } else { "" };
                core.sbio = SbioPhase::Relay;
                core.relay.counter = CounterChecker::new();
                dev_info!(
                    self.dev,
                    "sbio : relais ouvert (allow_sbio_relay=1, allow_sbio_params={}, allow_sbio_bio={}) : {} étape(s) dans l'ordre, de 0x17 à {:#04x}{}\n",
                    param_sbio_params(), param_sbio_bio(), relay_limit(), sbio_gate::RELAY_SEQUENCE[relay_limit() - 1].op,
                    bio_tail
                );
            }
            Ok(alive && core.sbio == SbioPhase::Relay)
        }

        /// J7a : attend que l'EP `i` de `KS_EPS` soit annoncé en 0xFD AU NUMÉRO attendu, avec ses tailles (TYPE 1), et que
        /// son annonce 0x1d soit acquittée. `Ok(true)` = prêt ; `Ok(false)` = pas vu en KS_WAIT_MS (rien envoyé, pas de
        /// Halted). Annoncé ailleurs ou tailles inattendues → `Err` (fail-closed : plus rien de keystore, pas de 0x73).
        fn ks_wait(&self, core: &mut MutexGuard<'_, Core>, i: usize) -> Result<bool> {
            let e = &KS_EPS[i];
            let t0 = Instant::<Monotonic>::now();
            loop {
                if core.state != State::Running {
                    return Err(EIO);
                }
                match core.ep_by_name(&e.name) {
                    Some(ep) if ep != e.ep => {
                        dev_err!(self.dev, "keystore : '{}' annoncé en {:#04x} et non en {:#04x} : arrêt (rien envoyé)\n", e.name_str(), ep, e.ep);
                        return Err(ENODEV);
                    }
                    Some(_) => {
                        let sizes = core.ep_index(e.ep).and_then(|k| core.eps[k].as_ref()).and_then(|x| x.sizes_raw);
                        if let Some(raw) = sizes {
                            if ks_gate::check_pages(e, raw).is_err() {
                                dev_err!(self.dev, "keystore : '{}' tailles 0xFD {:#010x} ≠ attendues {:?} : arrêt (rien envoyé)\n", e.name_str(), raw, e.pages);
                                return Err(EINVAL);
                            }
                            if core.ks_acked[i] {
                                return Ok(true);
                            }
                        }
                    }
                    None => {}
                }
                if t0.elapsed().as_millis() >= KS_WAIT_MS {
                    let fd = core.ep_by_name(&e.name).is_some();
                    dev_info!(
                        self.dev,
                        "VERDICT {} : NON PRÊT en {} ms (annonce 0xFD : {} ; ack 0x1d : {}) ; {} non ouvert(s), rien envoyé\n",
                        e.name_str(), KS_WAIT_MS, if fd { "oui" } else { "NON" }, if core.ks_acked[i] { "oui" } else { "non" },
                        if i + 1 < KS_EPS.len() { "lui et les suivants" } else { "lui" }
                    );
                    return Ok(false);
                }
                if let CondVarTimeoutResult::Signal { .. } = self.cv.wait_interruptible_timeout(core, msecs_to_jiffies(SBIO_POLL_MS)) {
                    dev_err!(self.dev, "signal pendant l'attente de '{}' : arrêt (rien envoyé)\n", e.name_str());
                    return Err(EINTR);
                }
            }
        }

        /// J7a (`docs/sks_native_plan.md` §4, expérience 1) : ouvre skdl, puis sks, puis scrd (ordre de c12) par le
        /// CNTL SEULEMENT (4 mots chacun, porte `OpenGate`), chacun une fois prêt (`ks_wait`) ; le premier EP pas prêt
        /// arrête les ouvertures (les suivants ne sont pas ouverts). Puis écoute passive KS_LISTEN_MS (dumps de B après
        /// un nouveau mot, bornés, puis en fin). Aucun mot n'est envoyé AUX EP keystore. Ack CNTL absent → Halted.
        fn run_keystore(&self, core: &mut MutexGuard<'_, Core>) -> Result {
            let Some(bufs) = self.ks_ool.as_ref() else { return Err(EINVAL) };
            for i in [KS_SKDL, KS_SKS, KS_SCRD] {
                let e = &KS_EPS[i];
                if !self.ks_wait(core, i)? {
                    break;
                }
                let (a, b) = &bufs[i];
                let (Some(ia), Some(ib)) = (iova_page(a.dma_handle()), iova_page(b.dma_handle())) else {
                    dev_err!(self.dev, "keystore : IOVA de '{}' inutilisables : arrêt (rien envoyé)\n", e.name_str());
                    return Err(EINVAL);
                };
                if a.len() != e.size as usize || b.len() != e.size as usize {
                    return Err(EINVAL);
                }
                dev_info!(
                    self.dev,
                    "keystore : ouverture de '{}' (EP {:#04x}) : A IOVA {:#x}, B IOVA {:#x}, {:#x} o chacun ; {} requête(s) 0x13 en attente\n",
                    e.name_str(), e.ep, a.dma_handle(), b.dma_handle(), e.size, core.n_pend
                );
                let w = ks_gate::open_steps(e, ia, ib);
                let label: [&'static str; 4] = match i {
                    KS_SKDL => ["CNTL A17 taille", "CNTL A17 adresse", "CNTL B17 taille", "CNTL B17 adresse"],
                    KS_SKS => ["CNTL A12 taille", "CNTL A12 adresse", "CNTL B12 taille", "CNTL B12 adresse"],
                    _ => ["CNTL A0a taille", "CNTL A0a adresse", "CNTL B0a taille", "CNTL B0a adresse"],
                };
                let steps: [(u8, u8, u32, &'static str); 4] = [
                    (w[0].0, w[0].1, w[0].2, label[0]),
                    (w[1].0, w[1].1, w[1].2, label[1]),
                    (w[2].0, w[2].1, w[2].2, label[2]),
                    (w[3].0, w[3].1, w[3].2, label[3]),
                ];
                core.ks_gate = OpenGate::new(e, ia, ib);
                core.ks_opening = Some(e.ep);
                dma_wmb();
                let r = self.cntl_steps(core, &steps, "pas d'ack CNTL à l'ouverture d'un EP keystore", "signal reçu pendant l'ouverture d'un EP keystore");
                core.ks_opening = None;
                let done = core.ks_gate.done();
                core.ks_gate = OpenGate::closed();
                r?;
                if !done {
                    self.halt(core, "ouverture keystore incomplète (bug)", None);
                    return Err(EIO);
                }
                core.ks_open[i] = true;
                dev_info!(self.dev, "keystore : '{}' ouvert (4 acks) ; mots reçus sur cet EP jusqu'ici : {}\n", e.name_str(), core.ks_rx[i]);
            }
            dev_info!(
                self.dev,
                "keystore : écoute passive {} ms (rien envoyé à 0x17/0x12/0x0a) ; ouverts skdl {} sks {} scrd {}\n",
                KS_LISTEN_MS, core.ks_open[KS_SKDL], core.ks_open[KS_SKS], core.ks_open[KS_SCRD]
            );
            let t0 = Instant::<Monotonic>::now();
            let mut seen = core.ks_rx;
            let mut dumps = [0u32; 3];
            while t0.elapsed().as_millis() < KS_LISTEN_MS && core.state == State::Running {
                if let CondVarTimeoutResult::Signal { .. } = self.cv.wait_interruptible_timeout(core, msecs_to_jiffies(SBIO_POLL_MS)) {
                    dev_warn!(self.dev, "signal pendant l'écoute keystore : écoute écourtée, pas de 0x73\n");
                    return Err(EINTR);
                }
                for i in 0..KS_EPS.len() {
                    if core.ks_rx[i] != seen[i] && dumps[i] < KS_DUMP_LIMIT {
                        seen[i] = core.ks_rx[i];
                        dumps[i] += 1;
                        self.dump_ool(&bufs[i].1, "B keystore après un mot", KS_EPS[i].name_str());
                    }
                }
            }
            if core.state != State::Running {
                return Err(EIO);
            }
            for (i, e) in KS_EPS.iter().enumerate() {
                if core.ks_open[i] {
                    self.dump_ool(&bufs[i].1, "B keystore en fin d'écoute", e.name_str());
                }
            }
            dev_info!(
                self.dev,
                "VERDICT keystore : skdl {} sks {} scrd {} ; mots reçus pendant/avant l'écoute : skdl {} sks {} scrd {} ; puis 0x73\n",
                if core.ks_open[KS_SKDL] { "OUVERT" } else { "non ouvert" },
                if core.ks_open[KS_SKS] { "OUVERT" } else { "non ouvert" },
                if core.ks_open[KS_SCRD] { "OUVERT" } else { "non ouvert" },
                core.ks_rx[KS_SKDL], core.ks_rx[KS_SKS], core.ks_rx[KS_SCRD]
            );
            Ok(())
        }

        /// Une commande du relais (`write` de /dev/sep_sbio, contexte processus) : contrôle (ordre, longueur exacte,
        /// charge fixe, niveau `allow_sbio_params`), gt_packet dans A8, `> fc`, puis pour 0x5b seulement les fragments
        /// suivants (`> fd`, chacun après le `< fe` du SEP), puis attente des fragments de la réponse (`> fe` demandés
        /// par le work), 6 s par mot attendu. Toute incohérence, délai ou signal → Halted.
        fn relay_cmd(&self, op: u8, payload: &[u8]) -> Result {
            let mut core = self.core.lock();
            if core.state != State::Running || core.sbio != SbioPhase::Relay {
                return Err(EIO);
            }
            if core.relay.txn.is_some() || core.relay.reply.is_some() {
                // Réponse précédente pas encore lue : le relais est strictement en lockstep.
                return Err(EBUSY);
            }
            if core.relay.listen {
                // Écoute (après le 0x03) : plus aucune commande, sans Halted (rien n'est envoyé).
                dev_err!(self.dev, "sbio écoute : commande {:#04x} refusée (plus aucun envoi après le 0x03)\n", op);
                return Err(EPERM);
            }
            let step = match sbio_gate::check_next(core.relay.next, relay_limit(), param_sbio_bio(), op, payload) {
                Ok(s) => s,
                Err(e) => {
                    dev_err!(self.dev, "sbio relais : commande {:#04x} ({} o) refusée à l'étape {}\n", op, payload.len(), core.relay.next);
                    self.halt(&mut core, why(&e), None);
                    return Err(EINVAL);
                }
            };
            let frags_in = sbio_gate::cmd_frags(step, payload.len());
            if self.write_a8(&mut core, step, payload, 0).is_err() {
                return Err(EIO);
            }
            let w = Word::new(EP_SBIO, GT_TAG_CMD, op, 0, 0);
            if core.relay.counter.check(&Msg::new(0, Dir::ToSep, w)).is_err() {
                self.halt(&mut core, "sbio : compteur GT faux à l'envoi", None);
                return Err(EIO);
            }
            let bio = core::ptr::eq(step, &sbio_gate::ENROLL_START);
            core.relay.buf.clear();
            core.relay.txn = Some(Txn {
                step, sent: false, frags_in, sent_in: 0, want_next: false, want_more: false, done: false, total: None,
                got: 0, nfrag: 0, nfd: 0, last: w, bio,
            });
            if bio {
                dev_warn!(self.dev, "sbio E-ENROLL-START : envoi du 0x03 commandStartEnroll (68 o à zéro, allow_sbio_bio=1), une seule fois\n");
            }
            dev_info!(self.dev, "sbio relais > {} ({:#04x}) : charge {} o en {} fragment(s), tête {:02x?}\n",
                      step.name, op, payload.len(), frags_in, &payload[..payload.len().min(8)]);
            dma_wmb();
            self.send_running(&mut core, w, "sbio relais (fc)")?;
            if let Some(t) = core.relay.txn.as_mut() {
                t.sent = true;
                t.sent_in = 1;
            }
            let mut left = msecs_to_jiffies(RELAY_REPLY_TIMEOUT_MS);
            loop {
                if core.state == State::Halted {
                    return Err(EIO);
                }
                let Some(t) = core.relay.txn.as_ref() else { return Err(EIO) };
                if t.done {
                    break;
                }
                let is_bio = t.bio;
                if t.want_next {
                    // Fragment `k` (1..frags_in) : A8 réécrit (le SEP a fini de lire le précédent : il a répondu fe).
                    let k = t.sent_in;
                    if k >= t.frags_in || self.write_a8(&mut core, step, payload, k).is_err() {
                        self.halt(&mut core, "sbio : fragment AP→SEP hors bornes", None);
                        return Err(EIO);
                    }
                    let fd = Word::new(EP_SBIO, gt::TAG_FD, op, 0, (k as u32) << 16);
                    if core.relay.counter.check(&Msg::new(0, Dir::ToSep, fd)).is_err() {
                        self.halt(&mut core, "sbio : compteur GT faux au > fd", None);
                        return Err(EIO);
                    }
                    dma_wmb();
                    self.send_running(&mut core, fd, "sbio relais (fd, fragment AP→SEP)")?;
                    if let Some(t) = core.relay.txn.as_mut() {
                        t.want_next = false;
                        t.sent_in = k + 1;
                    }
                    left = msecs_to_jiffies(RELAY_REPLY_TIMEOUT_MS);
                    continue;
                }
                if t.want_more {
                    let more = Word::new(EP_SBIO, gt::TAG_FE, op, 0, u32::from(t.nfd) << 16);
                    if core.relay.counter.check(&Msg::new(0, Dir::ToSep, more)).is_err() {
                        self.halt(&mut core, "sbio : compteur GT faux au > fe", None);
                        return Err(EIO);
                    }
                    // A8 inchangé (c12 seq 315 : A identique).
                    self.send_running(&mut core, more, "sbio relais (fe, fragment suivant)")?;
                    if let Some(t) = core.relay.txn.as_mut() {
                        t.want_more = false;
                    }
                    left = msecs_to_jiffies(RELAY_REPLY_TIMEOUT_MS);
                    continue;
                }
                match self.cv.wait_interruptible_timeout(&mut core, left) {
                    CondVarTimeoutResult::Woken { jiffies } => left = jiffies,
                    CondVarTimeoutResult::Timeout if is_bio => {
                        // Silence du SEP au 0x03 : pas de Halted (rien de plus ne sera envoyé) ; écoute, une réponse
                        // tardive arrivera comme mot spontané.
                        core.relay.txn = None;
                        core.relay.next += 1;
                        core.relay.listen = true;
                        dev_warn!(self.dev, "sbio E-ENROLL-START : AUCUNE réponse au 0x03 en 6 s (silence) ; ÉCOUTE seule désormais\n");
                        return Err(ETIMEDOUT);
                    }
                    CondVarTimeoutResult::Timeout => {
                        self.halt(&mut core, "sbio : pas de réponse GT en 6 s", None);
                        return Err(ETIMEDOUT);
                    }
                    CondVarTimeoutResult::Signal { .. } => {
                        self.halt(&mut core, "sbio : signal pendant une transaction du relais", None);
                        return Err(EINTR);
                    }
                }
            }
            let Some(t) = core.relay.txn.take() else { return Err(EIO) };
            core.relay.next += 1;
            core.relay.reply = Some(t.last);
            core.relay.reply_kind = if t.bio { KIND_BIO_REPLY } else { KIND_REPLY };
            dev_info!(
                self.dev,
                "sbio relais : {} ({:#04x}) terminé, réponse {} o en {} fragment(s), tête {:02x?}\n",
                step.name, op, t.got, t.nfrag, &core.relay.buf[..t.got.min(8)]
            );
            Ok(())
        }

        /// A8 = gt_packet du fragment `k` de la commande (k = 0 : commande entière si elle tient en un morceau), reste
        /// à zéro ; relit `+0x00`, `+0x08` (offset) et `+0x14`. Erreur → Halted.
        fn write_a8(&self, core: &mut Core, step: &Step, payload: &[u8], k: usize) -> Result {
            let Some((a8, _)) = self.sbio_ool.as_ref() else {
                self.halt(core, "sbio : A8 absent", None);
                return Err(EIO);
            };
            let mut hdr = [0u8; OOL_HDR];
            let range = if step.frag_in {
                match sbio_gate::fragment_header(step.op, payload.len(), k) {
                    Ok((h, r)) => {
                        hdr = h;
                        r
                    }
                    Err(e) => {
                        self.halt(core, why(&e), None);
                        return Err(EINVAL);
                    }
                }
            } else {
                let mut pkt = [0u8; OOL_HDR + sbio_gate::MAX_CMD];
                if k != 0 || sbio_gate::build_packet(step.op, payload, &mut pkt).is_err() {
                    self.halt(core, "sbio : gt_packet impossible", None);
                    return Err(EINVAL);
                }
                hdr.copy_from_slice(&pkt[..OOL_HDR]);
                0..payload.len()
            };
            let chunk = &payload[range.clone()];
            if OOL_HDR + chunk.len() > a8.len() {
                self.halt(core, "sbio : fragment plus grand que A8", None);
                return Err(EINVAL);
            }
            // SAFETY: `a8` est une allocation cohérente de SBIO_OOL_SIZE octets, vivante (tenue par `self`) ;
            // `OOL_HDR + chunk.len() <= a8.len()` (contrôlé ci-dessus). Le SEP ne lit A8 qu'après le mot envoyé
            // ensuite (`> fc`, ou `> fd` qui suit son `< fe` : il a fini de lire le fragment précédent) ; seul le fil
            // d'écriture écrit A8, sous `core`.
            let (v0, off, o14) = unsafe {
                let dst = a8.as_mut_ptr().cast::<u8>();
                core::ptr::write_bytes(dst, 0, a8.len());
                core::ptr::copy_nonoverlapping(hdr.as_ptr(), dst, OOL_HDR);
                core::ptr::copy_nonoverlapping(chunk.as_ptr(), dst.add(OOL_HDR), chunk.len());
                let rd = |o: usize| core::ptr::read_volatile(dst.add(o));
                (rd(0), u32::from_le_bytes([rd(8), rd(9), rd(10), rd(11)]), rd(0x14))
            };
            if v0 != 1 || o14 != step.op || off as usize != range.start {
                self.halt(core, "A8 relu : pas le gt_packet de la commande", None);
                return Err(EIO);
            }
            Ok(())
        }

        /// Journalise les `SBIO_DUMP_LEN` premiers octets de B8 (mots u32 petit-boutistes), l'en-tête gt_packet et le
        /// nombre d'octets non nuls ; renvoie (B8[0x00], B8[0x14]).
        fn dump_b8(&self, b8: &Ool, label: &'static str) -> (u8, u8) {
            self.dump_ool(b8, label, "B8")
        }

        /// Dump d'un tampon OOL (≥ SBIO_DUMP_LEN octets) : octets non nuls, champs gt_packet, 0x80 premiers octets.
        fn dump_ool(&self, b8: &Ool, label: &str, prefix: &str) -> (u8, u8) {
            let mut buf = [0u8; SBIO_DUMP_LEN];
            dma_rmb();
            if b8.len() < SBIO_DUMP_LEN {
                return (0, 0);
            }
            // SAFETY: `b8` est une allocation cohérente d'au moins SBIO_DUMP_LEN octets (contrôlé ci-dessus), vivante (tenue par
            // `self`). Le SEP peut l'écrire en même temps : lecture octet par octet en volatile (instantané sans
            // garantie de cohérence, journal seulement).
            let nz = unsafe {
                let src = b8.as_ptr().cast::<u8>();
                for (i, x) in buf.iter_mut().enumerate() {
                    *x = core::ptr::read_volatile(src.add(i));
                }
                (0..b8.len()).filter(|&i| core::ptr::read_volatile(src.add(i)) != 0).count()
            };
            let u = |o: usize| u32::from_le_bytes([buf[o], buf[o + 1], buf[o + 2], buf[o + 3]]);
            dev_info!(
                self.dev,
                "{} : {} octet(s) non nul(s) sur {:#x} ; en-tête version {:#x} total {:#x} offset {:#x} opcode {:#x} fragment {:#x}\n",
                label, nz, b8.len(), u(0), u(4), u(8), u(0x14), u(0x18)
            );
            for o in (0..SBIO_DUMP_LEN).step_by(16) {
                dev_info!(self.dev, "  {}+{:#05x} : {:08x} {:08x} {:08x} {:08x}\n", prefix, o, u(o), u(o + 4), u(o + 8), u(o + 12));
            }
            (buf[0], buf[0x14])
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
            core.xart_last = Some(Instant::now());
            dev_info!(self.dev, "xarm > seq {} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} (A {} o)\n", h.seq, h.w.ty, h.w.param, h.w.data, a.len());
            core.pend_remove(i);
            if core.b_owner == Some(h.seq) {
                core.b_owner = None;
            }
            if req.ty == OP_EP_ANNOUNCE {
                let name = ks_gate::announce_name(&req);
                if let Some(i) = KS_EPS.iter().position(|e| e.name == name) {
                    core.ks_acked[i] = true;
                    if param_allow_sks() != 0 {
                        dev_info!(self.dev, "annonce 0x1d '{}' acquittée\n", KS_EPS[i].name_str());
                        self.cv.notify_all();
                    }
                }
            }
            if req.ty == OP_EP_ANNOUNCE && req.param == SBIO_ANNOUNCE_PARAM && req.data & 0x00FF_FFFF == SBIO_ANNOUNCE_DATA {
                core.sbio_ack_sent = true;
                dev_info!(self.dev, "annonce 0x1d 'sbio' acquittée (déclencheur de l'ouverture précoce)\n");
                // Réveille run_sbio tout de suite (ouverture précoce ~ms après l'ack, comme macOS ~35 ms).
                self.cv.notify_all();
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

    // --- /dev/sep_sbio (allow_sbio_relay=1) ----------------------------------------------------------------
    // write : UNE commande `sbio_gate` (MAGIC, opcode, longueur, charge) ; bloque jusqu'à la réponse complète
    //         (réassemblée) ; contrôlée par `check_cmd` (liste, ordre, longueur exacte, charge fixe, niveau
    //         `allow_sbio_params` ; 0x5b : blob capturé seulement, CRC-32). Refus/délai → Halted.
    // read  : bloque jusqu'à un événement : notification TAG 0x01-0x04 (d'abord) ou la réponse de la dernière
    //         commande. Tampon >= EVT_MAX exigé. EIO une fois Halted. Un seul ouvreur (EBUSY).
    // N'existe qu'après « VERDICT sbio : VIVANT » avec allow_sbio_relay=1. Jamais de mot brut.

    /// Type de l'interface de relais (aucune donnée propre : tout est dans `SepData`).
    struct SbioFile;

    #[pin_data]
    struct SbioDev {
        #[pin]
        reg: MiscDeviceRegistration<SbioFile>,
        data: Arc<SepData>,
    }

    #[vtable]
    impl MiscDevice for SbioFile {
        type Ptr = Arc<SepData>;

        fn open(_file: &File, misc: &MiscDeviceRegistration<SbioFile>) -> Result<Arc<SepData>> {
            // SAFETY: le seul `MiscDeviceRegistration<SbioFile>` enregistré est le champ `reg` d'un `SbioDev`
            // épinglé dans un `KBox` oublié (`core::mem::forget`) : jamais libéré, `container_of` reste valide.
            let x: &SbioDev = unsafe { &*kernel::container_of!(core::ptr::from_ref(misc).cast_mut(), SbioDev, reg) };
            let d = &x.data;
            if d.sbio_opened.cmpxchg(0, 1, Full).is_err() {
                return Err(EBUSY);
            }
            dev_info!(d.dev, "/dev/sep_sbio ouvert (étape suivante {})\n", d.core.lock().relay.next);
            Ok(d.clone())
        }

        fn release(device: Arc<SepData>, _file: &File) {
            device.sbio_opened.store(0, Release);
        }

        fn read_iter(kiocb: Kiocb<'_, Arc<SepData>>, iov: &mut IovIterDest<'_>) -> Result<usize> {
            let me = kiocb.file();
            if iov.len() < EVT_MAX {
                return Err(EINVAL);
            }
            let mut core = me.core.lock();
            loop {
                if core.state == State::Halted {
                    return Err(EIO);
                }
                if core.relay.n_notes > 0 {
                    let w = core.relay.notes[0];
                    let n = core.relay.n_notes;
                    core.relay.notes.copy_within(1..n, 0);
                    core.relay.n_notes -= 1;
                    let h = EvtHdr { kind: KIND_NOTIFY, tag: w.tag, ty: w.ty, param: w.param, data: w.data, len: 0 }.encode();
                    if iov.copy_to_iter(&h) != EVT_HDR {
                        return Err(EFAULT);
                    }
                    return Ok(EVT_HDR);
                }
                if let Some(w) = core.relay.reply {
                    let b: &[u8] = &core.relay.buf;
                    let kind = core.relay.reply_kind;
                    let h = EvtHdr { kind, tag: w.tag, ty: w.ty, param: w.param, data: w.data, len: b.len() as u32 }.encode();
                    if iov.copy_to_iter(&h) != EVT_HDR || iov.copy_to_iter(b) != b.len() {
                        return Err(EFAULT);
                    }
                    let total = EVT_HDR + b.len();
                    core.relay.reply = None;
                    return Ok(total);
                }
                if core.relay.n_spont > 0 {
                    let r = &mut core.relay;
                    let slot = r.spont_head;
                    let (w, n) = r.spont[slot];
                    let base = slot * SBIO_OOL_SIZE;
                    let h = EvtHdr { kind: KIND_SPONT, tag: w.tag, ty: w.ty, param: w.param, data: w.data, len: n as u32 }.encode();
                    if iov.copy_to_iter(&h) != EVT_HDR || iov.copy_to_iter(&r.spont_buf[base..base + n]) != n {
                        return Err(EFAULT);
                    }
                    r.spont_head = (slot + 1) % SPONT_LEN;
                    r.n_spont -= 1;
                    return Ok(EVT_HDR + n);
                }
                if me.cv.wait_interruptible(&mut core) {
                    return Err(ERESTARTSYS);
                }
            }
        }

        fn write_iter(kiocb: Kiocb<'_, Arc<SepData>>, iov: &mut IovIterSource<'_>) -> Result<usize> {
            let me = kiocb.file();
            let n = iov.len();
            if !(sbio_gate::CMD_HDR..=sbio_gate::CMD_MAX).contains(&n) {
                return Err(EINVAL);
            }
            let mut buf = KVec::with_capacity(n, GFP_KERNEL)?;
            if iov.copy_from_iter_vec(&mut buf, GFP_KERNEL)? != n {
                return Err(EFAULT);
            }
            let (op, payload) = match sbio_gate::decode_cmd(&buf) {
                Ok(x) => x,
                Err(e) => {
                    let mut core = me.core.lock();
                    me.halt(&mut core, why(&e), None);
                    return Err(EINVAL);
                }
            };
            me.relay_cmd(op, payload)?;
            Ok(n)
        }
    }

    fn register_sbio_dev(data: &Arc<SepData>) -> Result {
        let reg = KBox::pin_init(
            try_pin_init!(SbioDev {
                reg <- MiscDeviceRegistration::register(MiscDeviceOptions { name: c_str!("sep_sbio") }),
                data: data.clone(),
            }),
            GFP_KERNEL,
        )?;
        // Jamais libéré (cf. `SbioDev`) : `open` s'appuie dessus.
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
        let sbio_ool = if param_allow_sbio() {
            let a = dma::Coherent::<u8>::zeroed_slice(dev, SBIO_OOL_SIZE, GFP_KERNEL)?;
            let b = dma::Coherent::<u8>::zeroed_slice(dev, SBIO_OOL_SIZE, GFP_KERNEL)?;
            dev_info!(dev, "OOL 0x08 alloués : A8 IOVA {:#x}, B8 IOVA {:#x}\n", a.dma_handle(), b.dma_handle());
            Some((a, b))
        } else {
            None
        };
        let ks_ool = if param_allow_sks() == 1 {
            let alloc = |i: usize| -> Result<(Ool, Ool)> {
                let n = KS_EPS[i].size as usize;
                let a = dma::Coherent::<u8>::zeroed_slice(dev, n, GFP_KERNEL)?;
                let b = dma::Coherent::<u8>::zeroed_slice(dev, n, GFP_KERNEL)?;
                dev_info!(dev, "OOL '{}' alloués : A IOVA {:#x}, B IOVA {:#x}, {:#x} o chacun\n", KS_EPS[i].name_str(), a.dma_handle(), b.dma_handle(), n);
                Ok((a, b))
            };
            Some([alloc(KS_SKDL)?, alloc(KS_SKS)?, alloc(KS_SCRD)?])
        } else {
            None
        };
        let bsnap = KVec::with_capacity(if ool.is_some() { OOL_SIZE } else { 0 }, GFP_KERNEL)?;
        let relay_buf = KVec::with_capacity(if param_allow_relay() { MAX_REPLY } else { 0 }, GFP_KERNEL)?;
        // File de l'écoute E-ENROLL-START (SPONT_LEN × B8), seulement si allow_sbio_bio=1 ; remplie de zéros ici
        // (aucune allocation dans le work).
        let spont_n = if param_sbio_bio() != 0 { SPONT_LEN * SBIO_OOL_SIZE } else { 0 };
        let mut spont_buf = KVec::with_capacity(spont_n, GFP_KERNEL)?;
        spont_buf.resize(spont_n, 0, GFP_KERNEL)?;

        let data = Arc::pin_init(
            try_pin_init!(SepData {
                dev: ARef::<device::Device>::from(dev),
                shmem,
                ool,
                sbio_ool,
                ks_ool,
                fw,
                ring: Ring::new(),
                opened: Atomic::new(0),
                sbio_opened: Atomic::new(0),
                core <- new_mutex!(Core::new(bsnap, relay_buf, spont_buf)),
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
                            Ok(()) => {
                                dev_info!(
                                    dev,
                                    "/dev/sep_native prêt (lancer sepd) ; ACK des SAVE : {}\n",
                                    if param_allow_save_ack() { "AUTORISÉ" } else { "refusé (un SAVE → Halted)" }
                                );
                                // Le probe (insmod) attend ici la fin de J3 ; sepd sert le xART en parallèle.
                                if param_allow_sbio() {
                                    match data.run_sbio() {
                                        Ok(true) => match register_sbio_dev(&data) {
                                            Ok(()) => dev_info!(dev, "/dev/sep_sbio prêt (lancer sbiod)\n"),
                                            Err(e) => dev_err!(dev, "/dev/sep_sbio non créé : {:?} (rien de plus envoyé à sbio)\n", e),
                                        },
                                        Ok(false) => {}
                                        Err(e) => dev_err!(dev, "sbio : arrêt {:?} (état {:?})\n", e, data.state()),
                                    }
                                }
                            }
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
            if param_allow_sks() > 1
                || (param_allow_sks() == 1 && (!param_allow_sbio() || param_sbio_open() != 1 || param_allow_relay()))
            {
                dev_err!(pdev, "allow_sks vaut 0 ou 1 ; allow_sks=1 exige allow_sbio=1, sbio_open=1 et allow_sbio_relay=0 : refus\n");
                return Err(EINVAL);
            }
            if (param_allow_xart() && param_allow_boot() == 0)
                || (param_allow_save_ack() && !param_allow_xart())
                || (param_allow_sbio() && !param_allow_xart())
                || (param_allow_relay() && !param_allow_sbio())
                || (param_sbio_params() != 0 && !param_allow_relay())
                || sbio_gate::limit(param_sbio_params()).is_none()
                || param_sbio_open() > 1
                || param_sbio_bio() > sbio_gate::BIO_LEVEL_MAX
                || (param_sbio_bio() != 0 && param_sbio_params() != 3)
            {
                dev_err!(
                    pdev,
                    "allow_xart exige allow_boot=1, allow_xart_save_ack et allow_sbio exigent allow_xart=1, allow_sbio_relay exige allow_sbio=1, allow_sbio_params (0 à 3) exige allow_sbio_relay=1, sbio_open vaut 0 ou 1, allow_sbio_bio (0 ou 1) exige allow_sbio_params=3 : refus\n"
                );
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
