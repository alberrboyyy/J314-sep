//! J7a gate: opening of the keystore endpoints skdl (0x17), sks (0x12) and scrd (0x0a) by the CNTL, WITHOUT any
//! content. No allocation, no `std`: this file is also included as is by the kernel module (`kmod/sep_native.rs`).
//!
//! What is modelled here is ONLY what macOS was seen doing in the captures (`docs/sks_native_plan.md` §1, §3):
//! - CNTL opening of each EP, same words as for 0x08/0x13: `> EP 0x00 TYPE 0x04 PARAM ep DATA size`, `TYPE 0x02
//!   DATA iova_A >> 12`, `TYPE 0x05 DATA size`, `TYPE 0x03 DATA iova_B >> 12`, each acked by `< TYPE 0x01` (same TAG).
//!   Sizes A = B = 0x4000 (skdl, scrd) and 0x8000 (sks): c12 L140-147 / L170-177 / L212-219, c1 L130-136 / L163-170 /
//!   L216-222, and = FD TYPE 1 pages (skdl/scrd `01010101`, sks `02010201`).
//! - order: skdl, then sks, then scrd (c12, c1).
//!
//! What is NOT modelled, on purpose: any word TO 0x17, 0x12 or 0x0a. The skdl `> TAG 0xfc TYPE 0x01/0x06` of c12 is a
//! GenericTransfer frame (TAG 0xfc, like sbio, `kext_sepmanager.md` §13) whose OOL was never captured (`live_eps` never
//! contained 0x17); the sks RPC carries a DER dictionary in OOL A that was never captured either. Nothing is invented:
//! the kernel only opens the EPs and listens. `classify` only labels received words for the journal.
use crate::discovery::{CNTL_RECV_ADDR, CNTL_RECV_SIZE, CNTL_SEND_ADDR, CNTL_SEND_SIZE};
use crate::word::Word;
use crate::{Error, Result};

pub const EP_SKDL: u8 = 0x17;
pub const EP_SKS: u8 = 0x12;
pub const EP_SCRD: u8 = 0x0a;

/// One keystore endpoint to open: number, 4-byte FD name (trailing space kept), OOL size (A = B), FD TYPE 1 pages.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KsEp {
    pub ep: u8,
    pub name: [u8; 4],
    pub size: u32,
    /// Expected FD TYPE 1 DATA, little-endian bytes (min send, max send, min recv, max recv, in 0x4000 pages).
    pub pages: [u8; 4],
}

impl KsEp {
    /// Name without trailing spaces.
    pub fn name_str(&self) -> &str {
        core::str::from_utf8(&self.name).unwrap_or("????").trim_end()
    }
}

/// Opening order of macOS (c12, c1): skdl, sks, scrd.
pub const KS_EPS: [KsEp; 3] = [
    KsEp { ep: EP_SKDL, name: *b"skdl", size: 0x4000, pages: [1, 1, 1, 1] },
    KsEp { ep: EP_SKS, name: *b"sks ", size: 0x8000, pages: [1, 2, 1, 2] },
    KsEp { ep: EP_SCRD, name: *b"scrd", size: 0x4000, pages: [1, 1, 1, 1] },
];
pub const KS_SKDL: usize = 0;
pub const KS_SKS: usize = 1;
pub const KS_SCRD: usize = 2;
/// Largest OOL size of the three (allocation of the kernel buffers).
pub const KS_MAX_SIZE: usize = 0x8000;

/// Index in `KS_EPS` of a keystore EP number.
pub fn ks_index(ep: u8) -> Option<usize> {
    KS_EPS.iter().position(|e| e.ep == ep)
}

/// 4-byte name carried by an xART `0x1d` announce: DATA = first 3 chars (bits 16-23, 8-15, 0-7), PARAM = 4th char.
/// c12: `PARAM 0x6f DATA 0x00736269` = "sbio", `0x6c / 0x00736b64` = "skdl", `0x20 / 0x00736b73` = "sks ",
/// `0x64 / 0x00736372` = "scrd" (`docs/messages.md` « xART au boot », 19/19 boots).
pub fn announce_name(w: &Word) -> [u8; 4] {
    [(w.data >> 16) as u8, (w.data >> 8) as u8, w.data as u8, w.param]
}

/// FD TYPE 1 sizes of the EP = the expected ones (fail-closed before any CNTL for it).
pub fn check_pages(e: &KsEp, sizes_raw: u32) -> Result<()> {
    if sizes_raw.to_le_bytes() == e.pages {
        Ok(())
    } else {
        Err(Error::OutOfRange("FD sizes of a keystore EP", u64::from(sizes_raw)))
    }
}

/// The 4 CNTL words `(TYPE, PARAM, DATA)` opening `e` with buffers at IOVA pages `a_page` (A, AP -> SEP) and `b_page`
/// (B, SEP -> AP), in the macOS order 0x04 / 0x02 / 0x05 / 0x03.
pub fn open_steps(e: &KsEp, a_page: u32, b_page: u32) -> [(u8, u8, u32); 4] {
    [
        (CNTL_SEND_SIZE, e.ep, e.size),
        (CNTL_SEND_ADDR, e.ep, a_page),
        (CNTL_RECV_SIZE, e.ep, e.size),
        (CNTL_RECV_ADDR, e.ep, b_page),
    ]
}

/// Send gate of one opening: admits exactly the 4 words of `open_steps`, in order, once each; nothing else.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpenGate {
    steps: [(u8, u8, u32); 4],
    next: usize,
}

impl OpenGate {
    /// A gate that admits nothing.
    pub const fn closed() -> Self {
        OpenGate { steps: [(0, 0, 0); 4], next: 4 }
    }

    pub fn new(e: &KsEp, a_page: u32, b_page: u32) -> Self {
        OpenGate { steps: open_steps(e, a_page, b_page), next: 0 }
    }

    /// `true` (and the gate advances) iff `(ty, param, data)` is the next expected word.
    pub fn admit(&mut self, ty: u8, param: u8, data: u32) -> bool {
        match self.steps.get(self.next) {
            Some(&s) if s == (ty, param, data) => {
                self.next += 1;
                true
            }
            _ => false,
        }
    }

    pub fn done(&self) -> bool {
        self.next >= self.steps.len()
    }
}

/// Label of a word received on a keystore EP (journal only; the kernel never answers these words).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KsKind {
    /// sks `TAG | 0x80`: an RPC reply. Unexpected here (no request is ever sent).
    SksReply,
    /// sks TAG 0x00: keybag lock-change « unlock » notification (DATA = handle), C8 29/29, C3 34/34.
    SksUnlock,
    /// sks TAG 0x01: lock-change « lock » notification.
    SksLock,
    /// sks TAG 0x09 TYPE 0 DATA 0 (C1 L640, L1619; role unknown).
    Sks09,
    /// skdl TAG 0xfc..0xfe: GenericTransfer frame. Unexpected here (no ping is ever sent).
    SkdlGt,
    /// skdl TAG 0x01 / 0x02 (C1 L700 `TAG 0x02 DATA 0xffffffff`, L1129 `TAG 0x01 DATA 0x1f`; role unknown).
    SkdlNote,
    /// scrd TAG 0x01 (every scrd word of c12, both directions; c12 L242 `< TYPE 0x0f PARAM 0x01` came unprompted).
    Scrd01,
    Other,
}

pub fn classify(w: &Word) -> KsKind {
    match (w.ep, w.tag) {
        (EP_SKS, t) if t & 0x80 != 0 => KsKind::SksReply,
        (EP_SKS, 0x00) => KsKind::SksUnlock,
        (EP_SKS, 0x01) => KsKind::SksLock,
        (EP_SKS, 0x09) => KsKind::Sks09,
        (EP_SKDL, 0xfc..=0xfe) => KsKind::SkdlGt,
        (EP_SKDL, 0x01 | 0x02) => KsKind::SkdlNote,
        (EP_SCRD, 0x01) => KsKind::Scrd01,
        _ => KsKind::Other,
    }
}

pub fn kind_label(k: KsKind) -> &'static str {
    match k {
        KsKind::SksReply => "sks : réponse RPC (TAG|0x80) alors qu'aucune requête n'a été envoyée",
        KsKind::SksUnlock => "sks : notification lock-change TAG 0x00 (déverrouillage, DATA = handle)",
        KsKind::SksLock => "sks : notification lock-change TAG 0x01 (verrouillage, DATA = handle)",
        KsKind::Sks09 => "sks : TAG 0x09 (vu C1, rôle inconnu)",
        KsKind::SkdlGt => "skdl : trame GT (TAG 0xfc-0xfe) alors qu'aucun ping n'a été envoyé",
        KsKind::SkdlNote => "skdl : TAG 0x01/0x02 (vu C1, rôle inconnu)",
        KsKind::Scrd01 => "scrd : TAG 0x01",
        KsKind::Other => "autre (jamais vu)",
    }
}

/// sks RPC word fields as SEEN on the wire (`docs/sks_native_plan.md` §1; reading only, never used to send):
/// TAG = operation (stable request length per TAG), TYPE = transaction counter (global to the boot, +1 per request,
/// mod 256), DATA bits 16-31 = OOL length, bits 0-15 = flag (0 in requests; bit 0 in some replies).
pub fn sks_fields(w: &Word) -> (u8, u8, u32, u16) {
    (w.tag & 0x7f, w.ty, w.data >> 16, w.data as u16)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn announce_names_c12() {
        assert_eq!(&announce_name(&Word::new(0x13, 0, 0x1d, 0x6c, 0x0073_6b64)), b"skdl");
        assert_eq!(&announce_name(&Word::new(0x13, 0, 0x1d, 0x20, 0x0073_6b73)), b"sks ");
        assert_eq!(&announce_name(&Word::new(0x13, 0, 0x1d, 0x64, 0x0073_6372)), b"scrd");
        assert_eq!(&announce_name(&Word::new(0x13, 0, 0x1d, 0x6f, 0x0073_6269)), b"sbio");
    }

    #[test]
    fn pages() {
        assert!(check_pages(&KS_EPS[KS_SKDL], 0x0101_0101).is_ok());
        assert!(check_pages(&KS_EPS[KS_SKS], 0x0201_0201).is_ok());
        assert!(check_pages(&KS_EPS[KS_SCRD], 0x0101_0101).is_ok());
        assert!(check_pages(&KS_EPS[KS_SKS], 0x0101_0101).is_err());
    }

    #[test]
    fn gate_exact_order_once() {
        let e = &KS_EPS[KS_SKS];
        let mut g = OpenGate::new(e, 0x74, 0x80);
        assert!(!g.admit(0x02, 0x12, 0x74), "out of order");
        assert!(!g.admit(0x04, 0x12, 0x4000), "wrong size");
        assert!(!g.admit(0x04, 0x0a, 0x8000), "wrong EP");
        assert!(g.admit(0x04, 0x12, 0x8000));
        assert!(g.admit(0x02, 0x12, 0x74));
        assert!(!g.admit(0x05, 0x12, 0x4000));
        assert!(g.admit(0x05, 0x12, 0x8000));
        assert!(!g.done());
        assert!(!g.admit(0x03, 0x12, 0x81), "wrong IOVA");
        assert!(g.admit(0x03, 0x12, 0x80));
        assert!(g.done());
        assert!(!g.admit(0x03, 0x12, 0x80), "twice");
        let mut c = OpenGate::closed();
        assert!(!c.admit(0x04, 0x17, 0x4000));
    }

    #[test]
    fn classify_words() {
        assert_eq!(classify(&Word::new(0x12, 0xcd, 0x01, 0, 0x005c_0001)), KsKind::SksReply);
        assert_eq!(classify(&Word::new(0x12, 0x00, 0x00, 1, 0xcea0_ab35)), KsKind::SksUnlock);
        assert_eq!(classify(&Word::new(0x12, 0x01, 0x00, 0, 0xffff_fe0b)), KsKind::SksLock);
        assert_eq!(classify(&Word::new(0x12, 0x09, 0, 0, 0)), KsKind::Sks09);
        assert_eq!(classify(&Word::new(0x17, 0xfc, 0x01, 0, 0)), KsKind::SkdlGt);
        assert_eq!(classify(&Word::new(0x17, 0x02, 0x00, 0, 0xffff_ffff)), KsKind::SkdlNote);
        assert_eq!(classify(&Word::new(0x0a, 0x01, 0x0f, 1, 0)), KsKind::Scrd01);
        assert_eq!(classify(&Word::new(0x0a, 0x05, 0, 0, 0)), KsKind::Other);
        assert_eq!(sks_fields(&Word::new(0x12, 0xcd, 0x01, 0, 0x005c_0001)), (0x4d, 0x01, 0x5c, 1));
    }
}
