//! Gate of the AP replies on EP 0x13 (xART) and record format of `/dev/sep_native`. No allocation, no `std`:
//! this file is also included as is by the kernel module (`kmod/sep_native.rs`), which runs `check_reply` on every
//! reply the daemon submits BEFORE sending anything. The daemon (`driver/rust/sepd`) builds its replies with the same
//! constants, so both sides agree by construction.
//!
//! Policy = `docs/xart_native_policy.md` (authoritative), itself taken from `pending/sep_native_persist.sh`
//! (hardware-proven under m1n1, n=4). The gate only allows, per request TYPE, the reply word the policy allows;
//! the CONTENT of a served blob is the daemon's business (the kernel holds no store).
use crate::word::Word;
use crate::xart::*;
use crate::{Error, Result};

/// Size of each OOL buffer of EP 0x13 (A = AP->SEP, B = SEP->AP), as `pending/sep_native_persist.sh` (SIZE).
pub const OOL_SIZE: usize = 0x8000;
/// A master FETCH reply starts with 0x11 zero bytes (served AND absent).
pub const MASTER_PREFIX: usize = 0x11;
pub const UUID_LEN: usize = 16;
/// Reply types of the AP.
pub const RESP_DONE: u8 = 0x00;
pub const RESP_ANNOUNCE: u8 = 0x16;
pub const ACK_MASK: u32 = 0xFFFF_FF00;
/// SAVE budget (`MAX_SAVES` of the proven script): the kernel halts right after the 48th acknowledged SAVE.
pub const MAX_SAVES: u32 = 48;
/// fw-boot ack DATA (observed, every capture).
pub const FWBOOT_ACK_DATA: u32 = 0x100;

/// SAVE length / FETCH-locker B length: `PARAM | DATA[0] << 8`.
pub const fn declen(w: &Word) -> usize {
    decode_fetch_len(w.param, w.data) as usize
}

/// Bytes of buffer B the kernel must copy when request `req` arrives (B is overwritten by the next request).
/// Unknown TYPE, or a length outside B, is an error (the kernel halts).
pub fn request_b_len(req: &Word) -> Result<usize> {
    match req.ty {
        OP_FWBOOT | OP_OSUUID | OP_FETCH_MASTER | OP_ABSENT | OP_EP_ANNOUNCE => Ok(0),
        // UUID of the locker, 16 bytes at B+0 (PARAM=0x10 in every capture: 487/487).
        OP_FETCH_GL if declen(req) == UUID_LEN => Ok(UUID_LEN),
        OP_FETCH_GL => Err(Error::Unexpected("FETCH locker: B length != 16")),
        OP_SAVE_XART | OP_SAVE_LOCKER if declen(req) <= OOL_SIZE => Ok(declen(req)),
        OP_SAVE_XART | OP_SAVE_LOCKER => Err(Error::Unexpected("SAVE: length beyond buffer B")),
        _ => Err(Error::Unexpected("unknown 0x13 request TYPE")),
    }
}

/// What the kernel does with buffer A before sending the reply word.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AWrite {
    /// A is left untouched (0x07, 0x1d, SAVE acks), as the proven script.
    Keep,
    /// A is zeroed over its whole size, then the reply bytes are copied at A+0 (script `write_A`).
    Replace,
}

/// Checks the reply `rep` (with `a` = bytes to put in A) against the pending request `req`. Only the word the policy
/// allows for that request passes; everything else is an error. `allow_save_ack` = module parameter.
pub fn check_reply(req: &Word, rep: &Word, a: &[u8], allow_save_ack: bool) -> Result<AWrite> {
    let bad = |s| Err(Error::Unexpected(s));
    if rep.ep != req.ep || rep.tag != req.tag {
        return bad("reply EP/TAG != request");
    }
    if a.len() > OOL_SIZE {
        return bad("A payload beyond buffer A");
    }
    let sel = selector(req.data);
    let word_is = |ty, param, data| rep.ty == ty && rep.param == param && rep.data == data;
    match req.ty {
        OP_FWBOOT if word_is(RESP_DONE, 0, FWBOOT_ACK_DATA) && a.is_empty() => Ok(AWrite::Replace),
        OP_OSUUID if word_is(RESP_DONE, 0, 0) && a.len() == UUID_LEN => Ok(AWrite::Replace),
        OP_FETCH_MASTER => {
            if a.len() < MASTER_PREFIX || a[..MASTER_PREFIX].iter().any(|&b| b != 0) {
                return bad("master FETCH: A must start with 0x11 zero bytes");
            }
            let (p, d) = encode_fetch_len(a.len(), sel)?;
            if word_is(RESP_DONE, p, d) { Ok(AWrite::Replace) } else { bad("master FETCH: word != length of A") }
        }
        OP_FETCH_GL => {
            let (p, d) = encode_fetch_len(a.len(), sel)?;
            if word_is(RESP_DONE, p, d) { Ok(AWrite::Replace) } else { bad("locker FETCH: word != length of A") }
        }
        OP_ABSENT if word_is(RESP_DONE, 0, 0) && a.is_empty() => Ok(AWrite::Keep),
        OP_EP_ANNOUNCE if word_is(RESP_ANNOUNCE, 0, req.data & ACK_MASK) && a.is_empty() => Ok(AWrite::Keep),
        OP_SAVE_XART | OP_SAVE_LOCKER if !allow_save_ack => bad("SAVE ack not allowed (allow_xart_save_ack=0)"),
        OP_SAVE_XART | OP_SAVE_LOCKER if word_is(RESP_DONE, 0, req.data & ACK_MASK) && a.is_empty() => Ok(AWrite::Keep),
        _ => bad("reply not allowed for this request"),
    }
}

/// Header of a record of `/dev/sep_native` (16 bytes, little endian), followed by `len` payload bytes.
/// read : a SEP request; payload = copy of buffer B (`request_b_len` bytes).
/// write: the reply to the request `seq`; payload = bytes to put in A (empty if A is kept).
/// Layout: +0 u32 seq | +4 ep | +5 tag | +6 type | +7 param | +8 u32 data | +12 u32 len.
pub const REC_HDR: usize = 16;
/// Largest record (header + full buffer).
pub const REC_MAX: usize = REC_HDR + OOL_SIZE;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecHdr {
    pub seq: u32,
    pub w: Word,
    pub len: u32,
}

impl RecHdr {
    pub fn encode(&self) -> [u8; REC_HDR] {
        let mut h = [0u8; REC_HDR];
        h[0..4].copy_from_slice(&self.seq.to_le_bytes());
        h[4] = self.w.ep;
        h[5] = self.w.tag;
        h[6] = self.w.ty;
        h[7] = self.w.param;
        h[8..12].copy_from_slice(&self.w.data.to_le_bytes());
        h[12..16].copy_from_slice(&self.len.to_le_bytes());
        h
    }

    /// Decodes a whole record and returns (header, payload). The payload must be exactly `len` bytes.
    pub fn decode(b: &[u8]) -> Result<(RecHdr, &[u8])> {
        let h = b.get(..REC_HDR).ok_or(Error::Short)?;
        let u32_at = |o: usize| u32::from_le_bytes([h[o], h[o + 1], h[o + 2], h[o + 3]]);
        let r = RecHdr { seq: u32_at(0), w: Word::new(h[4], h[5], h[6], h[7], u32_at(8)), len: u32_at(12) };
        let payload = &b[REC_HDR..];
        if payload.len() != r.len as usize || payload.len() > OOL_SIZE {
            return Err(Error::Unexpected("record length"));
        }
        Ok((r, payload))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const fn rq(ty: u8, param: u8, data: u32) -> Word {
        Word::new(EP_XART, 5, ty, param, data)
    }
    const fn rp(ty: u8, param: u8, data: u32) -> Word {
        Word::new(EP_XART, 5, ty, param, data)
    }
    #[test]
    fn b_lengths() {
        assert_eq!(request_b_len(&rq(OP_FETCH_GL, 0x10, 0x100)), Ok(16));
        assert!(request_b_len(&rq(OP_FETCH_GL, 0x11, 0x100)).is_err());
        assert_eq!(request_b_len(&rq(OP_SAVE_LOCKER, 0x63, 0xbfd9_0101)), Ok(0x163));
        assert_eq!(request_b_len(&rq(OP_FWBOOT, 0, 0)), Ok(0));
        assert!(request_b_len(&rq(0x42, 0, 0)).is_err());
    }
    #[test]
    fn gate() {
        assert_eq!(check_reply(&rq(OP_FWBOOT, 0, 0), &rp(0, 0, 0x100), &[], false), Ok(AWrite::Replace));
        assert!(check_reply(&rq(OP_FWBOOT, 0, 0), &rp(0, 0, 0x0), &[], false).is_err());
        let mut tagged = rp(0, 0, 0x100);
        tagged.tag = 6;
        assert!(check_reply(&rq(OP_FWBOOT, 0, 0), &tagged, &[], false).is_err());
        // master ABSENT = prefix only, length 0x11, selector re-emitted
        assert_eq!(check_reply(&rq(OP_FETCH_MASTER, 0, 0x100), &rp(0, 0x11, 0x100), &[0; 0x11], false), Ok(AWrite::Replace));
        assert!(check_reply(&rq(OP_FETCH_MASTER, 0, 0x100), &rp(0, 0x11, 0x100), &[1; 0x11], false).is_err());
        assert!(check_reply(&rq(OP_FETCH_MASTER, 0, 0x100), &rp(0, 0, 0x100), &[], false).is_err());
        // locker ABSENT = length 0
        assert_eq!(check_reply(&rq(OP_FETCH_GL, 0x10, 0x100), &rp(0, 0, 0x100), &[], false), Ok(AWrite::Replace));
        assert_eq!(check_reply(&rq(OP_EP_ANNOUNCE, 0x6f, 0x736269), &rp(0x16, 0, 0x736200), &[], false), Ok(AWrite::Keep));
        // SAVE: refused without the parameter, exact ack with it
        let save = rq(OP_SAVE_XART, 0x7f, 0x8929_0100);
        assert!(check_reply(&save, &rp(0, 0, 0x8929_0100), &[], false).is_err());
        assert_eq!(check_reply(&save, &rp(0, 0, 0x8929_0100), &[], true), Ok(AWrite::Keep));
        assert!(check_reply(&save, &rp(0, 0, 0x8929_0101), &[], true).is_err());
        assert!(check_reply(&rq(0x42, 0, 0), &rp(0, 0, 0), &[], true).is_err());
    }
    #[test]
    fn record_roundtrip() {
        let h = RecHdr { seq: 7, w: rq(OP_SAVE_XART, 0x7f, 0x100), len: 3 };
        let mut b = [0u8; REC_HDR + 3];
        b[..REC_HDR].copy_from_slice(&h.encode());
        b[REC_HDR..].copy_from_slice(&[1, 2, 3]);
        let (g, p) = RecHdr::decode(&b).unwrap();
        assert_eq!((g, p), (h, &[1u8, 2, 3][..]));
        assert!(RecHdr::decode(&b[..REC_HDR + 2]).is_err());
    }
}
