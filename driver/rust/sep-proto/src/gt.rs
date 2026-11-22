//! Step 4: GT fragmentation (TAG 0xfc/0xfd/0xfe) on the sbio EP, OOL reassembly, CRC of the 0x65 slices.
//!
//! Status (`docs/verification_status.md`):
//! - GT word (TAG in {fc,fd,fe}, TYPE = command, PARAM = 0, DATA = counter << 16): **verified (macOS side)**.
//! - OOL header 0x1c bytes (u32 LE: 1, total, offset, 0, 0, TYPE, chunk length): **verified (reading)**.
//! - 0x65 = 12 slices of 0x980, CRC-16/ARC at the end of each slice: **verified (macOS)**, K4.
//! - A = AP->SEP, B = SEP->AP: hypothesis (the direction is the one the tracer wrote).
//!
//! Counter rule: `fc`: DATA = 0; `fe`: counter = number of `fd` already seen in the transfer; `fd`: that number + 1;
//! the transfer restarts at each `> fc` or at an unsolicited `< fc`.
use crate::crc::crc16_arc;
use crate::word::{Dir, Msg};
use crate::{le_u16, le_u32};
use alloc::collections::{BTreeMap, BTreeSet};
use alloc::vec::Vec;

pub const TAG_FC: u8 = 0xFC;
pub const TAG_FD: u8 = 0xFD;
pub const TAG_FE: u8 = 0xFE;
pub const OOL_HDR: usize = 0x1C;
pub const OOL_PAGE: usize = 0x4000;
/// Payload bytes per chunk (0x3fe4).
pub const OOL_MAX_CHUNK: usize = OOL_PAGE - OOL_HDR;
pub const SLICE_LEN: usize = 0x980;
pub const SLICES_PER_IMAGE: usize = 12;
pub const IMAGE_LEN: usize = SLICE_LEN * SLICES_PER_IMAGE; // 0x7200
pub const T_IMAGE: u8 = 0x65;

pub const fn is_gt(tag: u8) -> bool {
    matches!(tag, TAG_FC | TAG_FD | TAG_FE)
}

/// Why a GT word breaks the counter rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CounterFault {
    /// PARAM != 0 or low 16 bits of DATA != 0.
    Format,
    /// `fc` with a non-zero counter.
    FcCounter(u16),
    /// `fe` counter != expected.
    Fe { got: u16, want: u16 },
    /// `fd` counter != expected.
    Fd { got: u16, want: u16 },
}

/// Stateful checker of the GT counter rule for one EP. Usable online (a driver feeds every word) or offline.
#[derive(Debug, Default, Clone)]
pub struct CounterChecker {
    pending: BTreeSet<u8>,
    nfd: u16,
}

impl CounterChecker {
    pub fn new() -> Self {
        Self::default()
    }

    /// Check one GT word (the caller filters on EP and `is_gt`).
    pub fn check(&mut self, m: &Msg) -> core::result::Result<(), CounterFault> {
        if m.w.param != 0 || m.w.data & 0xFFFF != 0 {
            return Err(CounterFault::Format);
        }
        let k = (m.w.data >> 16) as u16;
        match m.w.tag {
            TAG_FC => {
                if m.dir == Dir::ToSep {
                    self.pending.insert(m.w.ty);
                    self.nfd = 0;
                } else if !self.pending.remove(&m.w.ty) {
                    self.nfd = 0;
                }
                if k != 0 {
                    return Err(CounterFault::FcCounter(k));
                }
            }
            TAG_FE => {
                if k != self.nfd {
                    return Err(CounterFault::Fe { got: k, want: self.nfd });
                }
            }
            _ => {
                self.nfd = self.nfd.wrapping_add(1);
                if k != self.nfd {
                    return Err(CounterFault::Fd { got: k, want: self.nfd });
                }
            }
        }
        Ok(())
    }
}

/// Replay the counter rule over the GT messages of `ep`. Returns (number checked, faults with line numbers).
pub fn check_counters<'a>(msgs: impl IntoIterator<Item = &'a Msg>, ep: u8) -> (usize, Vec<(u32, CounterFault)>) {
    let mut c = CounterChecker::new();
    let (mut n, mut bad) = (0, Vec::new());
    for m in msgs {
        if m.w.ep != ep || !is_gt(m.w.tag) {
            continue;
        }
        n += 1;
        if let Err(f) = c.check(m) {
            bad.push((m.lineno, f));
        }
    }
    (n, bad)
}

/// OOL header (0x1c bytes, u32 LE).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OolHeader {
    pub valid: u32,
    pub total: u32,
    pub offset: u32,
    pub ty: u32,
    pub len: u32,
}

impl OolHeader {
    pub fn parse(d: &[u8]) -> Option<Self> {
        if d.len() < OOL_HDR {
            return None;
        }
        Some(OolHeader {
            valid: le_u32(d, 0).ok()?,
            total: le_u32(d, 4).ok()?,
            offset: le_u32(d, 8).ok()?,
            ty: le_u32(d, 20).ok()?,
            len: le_u32(d, 24).ok()?,
        })
    }

    /// Build the header for one outgoing chunk (same layout; words 3 and 4 = 0).
    pub fn to_bytes(&self) -> [u8; OOL_HDR] {
        let mut h = [0u8; OOL_HDR];
        for (i, v) in [self.valid, self.total, self.offset, 0, 0, self.ty, self.len].iter().enumerate() {
            h[i * 4..i * 4 + 4].copy_from_slice(&v.to_le_bytes());
        }
        h
    }
}

/// One OOL buffer read, attached to the message that precedes it.
#[derive(Debug, Clone)]
pub struct OolRecord {
    pub lineno: u32,
    pub dir: Dir,
    /// b'A' or b'B'.
    pub buf: u8,
    pub msg: Option<Msg>,
    pub data: Vec<u8>,
    /// SHA check of the stored file against the trace (None = no file).
    pub sha_ok: Option<bool>,
}

#[derive(Debug, Clone)]
pub struct Transfer {
    pub dir: Dir,
    pub buf: u8,
    pub ty: u8,
    pub line: u32,
    pub total: u32,
    pub chunks: BTreeMap<u32, Vec<u8>>,
    pub truncated: bool,
    pub conflict: bool,
}

impl Transfer {
    pub fn blob(&self) -> Vec<u8> {
        self.chunks.values().flatten().copied().collect()
    }
    pub fn contiguous(&self) -> bool {
        let mut pos = 0u64;
        for (&off, c) in &self.chunks {
            if off as u64 != pos {
                return false;
            }
            pos += c.len() as u64;
        }
        true
    }
    pub fn complete(&self) -> bool {
        self.contiguous() && self.chunks.values().map(Vec::len).sum::<usize>() == self.total as usize && !self.truncated
    }
}

/// Reassemble the GT transfers whose first payload (offset 0) has been seen; one entry per transfer.
/// `types` = None for all types.
pub fn reassemble<'a>(recs: impl IntoIterator<Item = &'a OolRecord>, ep: u8, types: Option<&[u8]>) -> Vec<Transfer> {
    let mut out: Vec<Transfer> = Vec::new();
    let mut cur: BTreeMap<(bool, u8, u8), usize> = BTreeMap::new();
    for r in recs {
        let Some(m) = r.msg else { continue };
        let d = &r.data;
        if m.w.ep != ep || !is_gt(m.w.tag) || d.len() < OOL_HDR || d[0] != 1 {
            continue;
        }
        let Some(h) = OolHeader::parse(d) else { continue };
        if h.ty != m.w.ty as u32 || types.is_some_and(|t| !t.contains(&m.w.ty)) {
            continue;
        }
        let key = (r.dir == Dir::ToSep, r.buf, m.w.ty);
        if h.offset == 0 {
            out.push(Transfer {
                dir: r.dir,
                buf: r.buf,
                ty: m.w.ty,
                line: m.lineno,
                total: h.total,
                chunks: BTreeMap::new(),
                truncated: false,
                conflict: false,
            });
            cur.insert(key, out.len() - 1);
        }
        let Some(&i) = cur.get(&key) else { continue };
        let t = &mut out[i];
        if h.total != t.total {
            continue;
        }
        let end = core::cmp::min(d.len(), OOL_HDR.saturating_add(h.len as usize));
        let piece = d[OOL_HDR..end].to_vec();
        if piece.len() < h.len as usize {
            t.truncated = true;
        }
        if let Some(old) = t.chunks.get(&h.offset) {
            if *old != piece {
                t.conflict = true;
            }
        }
        t.chunks.insert(h.offset, piece);
    }
    out
}

/// Check the sensor slices of an image: header `80 52 NN`, u32 LE at +3 = slice_len, final CRC-16/ARC LE.
/// Returns one bool per slice.
pub fn check_slices(blob: &[u8], slice_len: usize, n: usize) -> Vec<bool> {
    (0..n)
        .map(|k| {
            let Some(s) = blob.get(k * slice_len..(k + 1) * slice_len) else { return false };
            s[0] == 0x80
                && s[1] == 0x52
                && le_u32(s, 3).ok() == Some(slice_len as u32)
                && le_u16(s, slice_len - 2).ok() == Some(crc16_arc(&s[..slice_len - 2]))
        })
        .collect()
}

/// Split a payload into GT chunks (header + piece), as an AP sender would put them in buffer A, one per page.
/// Pure computation: returns the bytes, sends nothing.
pub fn fragment(ty: u8, payload: &[u8]) -> Vec<Vec<u8>> {
    let total = payload.len() as u32;
    let mut out = Vec::new();
    let mut off = 0usize;
    loop {
        let end = core::cmp::min(payload.len(), off + OOL_MAX_CHUNK);
        let h = OolHeader { valid: 1, total, offset: off as u32, ty: ty as u32, len: (end - off) as u32 };
        let mut c = h.to_bytes().to_vec();
        c.extend_from_slice(&payload[off..end]);
        out.push(c);
        off = end;
        if off >= payload.len() {
            break;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::word::Word;

    #[test]
    fn counter_detects_error() {
        let ms = [
            Msg::new(1, Dir::ToSep, Word::new(8, 0xFC, 0x6D, 0, 0)),
            Msg::new(2, Dir::ToAp, Word::new(8, 0xFE, 0x6D, 0, 0)),
            Msg::new(3, Dir::ToSep, Word::new(8, 0xFD, 0x6D, 0, 0x20000)),
        ];
        let (n, bad) = check_counters(&ms, 8);
        assert_eq!((n, bad.len()), (3, 1));
    }

    #[test]
    fn fragment_roundtrip() {
        let payload: Vec<u8> = (0..IMAGE_LEN).map(|i| i as u8).collect();
        let chunks = fragment(T_IMAGE, &payload);
        assert_eq!(chunks.len(), 2); // 0x7200 / 0x3fe4 -> 2 chunks
        let recs: Vec<OolRecord> = chunks
            .into_iter()
            .map(|data| OolRecord {
                lineno: 0,
                dir: Dir::ToSep,
                buf: b'A',
                msg: Some(Msg::new(0, Dir::ToSep, Word::new(8, TAG_FC, T_IMAGE, 0, 0))),
                data,
                sha_ok: None,
            })
            .collect();
        let t = reassemble(&recs, 8, None);
        assert_eq!(t.len(), 1);
        assert!(t[0].complete());
        assert_eq!(t[0].blob(), payload);
    }
}
