//! Gate of the sbio relay (EP 0x08) and record format of `/dev/sep_sbio`. No allocation, no `std`: this file is
//! also included as is by the kernel module (`kmod/sep_native.rs`), which checks every command userspace submits
//! (opcode, ORDER, exact payload length) and every fragment the SEP returns BEFORE acting on it. The relay daemon
//! (`driver/rust/sbiod`) builds its commands with the same constants, so both sides agree by construction.
//!
//! Protocol (`docs/sbio_session.md`, `docs/sbio_keyexchange.md`; hardware-proven under m1n1 by
//! `pending/sep_native_sbio3.sh` .. `sep_native_sbio11.sh`; macOS capture c12, seq 300-316):
//! - command: buffer A8 = gt_packet `OolHeader { valid 1, total = len, offset 0, TYPE = op, len }` + payload, zero
//!   padded; then `> EP 0x08 TAG 0xfc TYPE op PARAM 0 DATA 0`. The c12 templates `000303..000313_08_A.bin` are exactly
//!   this (checked by `tests/sbio_relay.rs`), so the kernel builds the packet from (op, payload), no template.
//! - reply: `< TAG 0xfc TYPE op`, B8 = gt_packet of the reply (first fragment). If `offset + len < total`, the AP asks
//!   for the next fragment with `> TAG 0xfe TYPE op DATA nfd << 16` (A8 unchanged) and the SEP answers `< TAG 0xfd`
//!   (DATA = (nfd + 1) << 16): c12 seq 313-316 and sbio6/7/11 (0x5f, 22158 bytes in 2 fragments).
//! - AP -> SEP fragmentation (`> fc` then `> fd`) is NOT needed by this version: every whitelisted payload is
//!   <= 64 bytes, a longer one is refused.
use crate::gt::{OolHeader, OOL_HDR, OOL_MAX_CHUNK};
use crate::{Error, Result};

pub const EP_SBIO: u8 = 0x08;
pub const OP_HELLO: u8 = 0x73;
/// Size of A8 and B8 (as macOS and the m1n1 harness).
pub const SBIO_OOL_SIZE: usize = 0x4000;
/// Largest reassembled reply accepted (0x5f: 0x568e in c12/sbio6-11, 0x70ce in another macOS boot, sensor_hw.md).
pub const MAX_REPLY: usize = 0x10000;
/// Largest number of SEP -> AP fragments of one reply (MAX_FRAGS of the proven scripts is 16; 0x10000 needs 5).
pub const MAX_FRAGS: usize = 8;
/// Largest command payload of this version.
pub const MAX_CMD: usize = 0x40;

/// One relayed step: opcode, exact payload length the AP sends, bounds of the reply total the SEP returns.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Step {
    pub op: u8,
    pub name: &'static str,
    pub cmd_len: usize,
    pub reply_min: usize,
    pub reply_max: usize,
}

/// The whitelist of this version, IN ORDER (c12 seq 303-316, run by sbio3..sbio11 under m1n1). Each step is
/// admitted once, in this order, after the 0x73 hello (done by the kernel itself). Nothing after 0x5f.
pub const RELAY_SEQUENCE: [Step; 6] = [
    // prepareSession: sensor serial (16 bytes, identity frame [9..25]) -> empty ack.
    Step { op: 0x17, name: "prepareSession", cmd_len: 0x10, reply_min: 0, reply_max: 0 },
    // performKeyExchange (sessionType = 1, `01 00 00 00`) -> 40 opaque bytes for SPI frame 0x72.
    Step { op: 0x15, name: "keyExchange", cmd_len: 4, reply_min: 0x28, reply_max: 0x28 },
    // 40 bytes of the sensor reply -> empty ack.
    Step { op: 0x16, name: "keyExchange2", cmd_len: 0x28, reply_min: 0, reply_max: 0 },
    // initializeSequenceCounter (empty) -> 64 opaque bytes for SPI frame 0x73.
    Step { op: 0x42, name: "initSeqCounter", cmd_len: 0, reply_min: 0x40, reply_max: 0x40 },
    // 64 bytes of the sensor reply -> empty ack.
    Step { op: 0x18, name: "seqCounter2", cmd_len: 0x40, reply_min: 0, reply_max: 0 },
    // LoadPatch (`02 00`) -> patch block (fragmented), pushed raw to the sensor after prelude 0x60.
    Step { op: 0x5f, name: "loadPatch", cmd_len: 2, reply_min: 2, reply_max: MAX_REPLY },
];

/// Step `next` of the sequence, if `op` and `len` are exactly what it allows.
pub fn check_cmd(next: usize, op: u8, len: usize) -> Result<&'static Step> {
    let s = RELAY_SEQUENCE.get(next).ok_or(Error::Unexpected("sbio relay: sequence finished (nothing after 0x5f)"))?;
    if s.op != op {
        return Err(Error::Unexpected("sbio relay: opcode out of order or not whitelisted"));
    }
    if s.cmd_len != len {
        return Err(Error::Unexpected("sbio relay: payload length differs from the whitelisted one"));
    }
    Ok(s)
}

/// Writes the command gt_packet (header + payload) at `out[0..]`; the caller zeroes the rest of A8 first.
pub fn build_packet(op: u8, payload: &[u8], out: &mut [u8]) -> Result<usize> {
    if payload.len() > MAX_CMD || payload.len() > OOL_MAX_CHUNK {
        return Err(Error::Unexpected("sbio relay: payload too long for one chunk"));
    }
    let n = OOL_HDR + payload.len();
    let dst = out.get_mut(..n).ok_or(Error::Short)?;
    let len = payload.len() as u32;
    dst[..OOL_HDR].copy_from_slice(&OolHeader { valid: 1, total: len, offset: 0, ty: u32::from(op), len }.to_bytes());
    dst[OOL_HDR..].copy_from_slice(payload);
    Ok(n)
}

/// A checked fragment of a reply: its bytes are `B8[OOL_HDR .. OOL_HDR + len]`, to be placed at `offset`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Fragment {
    pub total: usize,
    pub offset: usize,
    pub len: usize,
}

/// Checks the gt header of a reply fragment (first 0x1c bytes of B8). `got` = bytes already reassembled, `total` =
/// total of the first fragment (None for the first one), `nfrag` = fragments already taken.
pub fn check_fragment(step: &Step, hdr: &[u8], got: usize, total: Option<usize>, nfrag: usize) -> Result<Fragment> {
    let bad = |s| Err(Error::Unexpected(s));
    let h = OolHeader::parse(hdr).ok_or(Error::Short)?;
    if h.valid != 1 {
        return bad("sbio reply: gt header +0x00 != 1");
    }
    if h.ty != u32::from(step.op) {
        return bad("sbio reply: gt opcode +0x14 != command opcode");
    }
    if nfrag >= MAX_FRAGS {
        return bad("sbio reply: too many fragments");
    }
    let (t, off, len) = (h.total as usize, h.offset as usize, h.len as usize);
    if t < step.reply_min || t > step.reply_max {
        return bad("sbio reply: total outside the bounds of this opcode");
    }
    if total.is_some_and(|x| x != t) {
        return bad("sbio reply: total changed between fragments");
    }
    if off != got {
        return bad("sbio reply: fragment out of order");
    }
    if len > OOL_MAX_CHUNK || off.checked_add(len).is_none_or(|e| e > t) {
        return bad("sbio reply: fragment length beyond the total or the page");
    }
    if len == 0 && t != 0 {
        return bad("sbio reply: empty fragment of a non-empty reply");
    }
    Ok(Fragment { total: t, offset: off, len })
}

// --- records of /dev/sep_sbio (little-endian) -----------------------------------------------------------------
/// "SBR1".
pub const MAGIC: u32 = 0x3152_4253;
/// Command written by userspace: `+0 u32 MAGIC | +4 op | +5..8 zero | +8 u32 len` then `len` payload bytes.
pub const CMD_HDR: usize = 12;
pub const CMD_MAX: usize = CMD_HDR + MAX_CMD;
/// Event read by userspace: `+0 u32 MAGIC | +4 kind | +5 tag | +6 type | +7 param | +8 u32 data | +12 u32 len`.
pub const EVT_HDR: usize = 16;
pub const EVT_MAX: usize = EVT_HDR + MAX_REPLY;
/// Complete reply of the command in flight (payload = reassembled reply; word = last word of the SEP).
pub const KIND_REPLY: u8 = 1;
/// Unsolicited sbio word TAG 0x01-0x04 (no payload).
pub const KIND_NOTIFY: u8 = 2;

pub const fn is_notification(tag: u8) -> bool {
    matches!(tag, 0x01..=0x04)
}

pub fn encode_cmd(op: u8, payload: &[u8], out: &mut [u8]) -> Result<usize> {
    let n = CMD_HDR + payload.len();
    if payload.len() > MAX_CMD {
        return Err(Error::Unexpected("sbio command too long"));
    }
    let o = out.get_mut(..n).ok_or(Error::Short)?;
    o[..4].copy_from_slice(&MAGIC.to_le_bytes());
    o[4..8].copy_from_slice(&[op, 0, 0, 0]);
    o[8..12].copy_from_slice(&(payload.len() as u32).to_le_bytes());
    o[CMD_HDR..].copy_from_slice(payload);
    Ok(n)
}

/// (op, payload) of a command record; the record must be exactly header + len bytes.
pub fn decode_cmd(b: &[u8]) -> Result<(u8, &[u8])> {
    let h = b.get(..CMD_HDR).ok_or(Error::Short)?;
    if crate::le_u32(h, 0)? != MAGIC {
        return Err(Error::BadMagic);
    }
    if h[5..8] != [0, 0, 0] {
        return Err(Error::Unexpected("sbio command: reserved bytes not zero"));
    }
    let len = crate::le_u32(h, 8)? as usize;
    if len > MAX_CMD || b.len() != CMD_HDR + len {
        return Err(Error::Unexpected("sbio command: length field differs from the record"));
    }
    Ok((h[4], &b[CMD_HDR..]))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EvtHdr {
    pub kind: u8,
    pub tag: u8,
    pub ty: u8,
    pub param: u8,
    pub data: u32,
    pub len: u32,
}

impl EvtHdr {
    pub fn encode(&self) -> [u8; EVT_HDR] {
        let mut h = [0u8; EVT_HDR];
        h[..4].copy_from_slice(&MAGIC.to_le_bytes());
        h[4..8].copy_from_slice(&[self.kind, self.tag, self.ty, self.param]);
        h[8..12].copy_from_slice(&self.data.to_le_bytes());
        h[12..16].copy_from_slice(&self.len.to_le_bytes());
        h
    }
    pub fn decode(b: &[u8]) -> Result<(EvtHdr, &[u8])> {
        let h = b.get(..EVT_HDR).ok_or(Error::Short)?;
        if crate::le_u32(h, 0)? != MAGIC {
            return Err(Error::BadMagic);
        }
        let e = EvtHdr { kind: h[4], tag: h[5], ty: h[6], param: h[7], data: crate::le_u32(h, 8)?, len: crate::le_u32(h, 12)? };
        if b.len() != EVT_HDR + e.len as usize {
            return Err(Error::Unexpected("sbio event: length field differs from the record"));
        }
        Ok((e, &b[EVT_HDR..]))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn order_and_lengths() {
        for (i, s) in RELAY_SEQUENCE.iter().enumerate() {
            assert!(check_cmd(i, s.op, s.cmd_len).is_ok());
            assert!(check_cmd(i, s.op, s.cmd_len + 1).is_err());
            assert!(check_cmd(i, OP_HELLO, s.cmd_len).is_err());
        }
        assert!(check_cmd(1, 0x17, 0x10).is_err()); // replay / out of order
        assert!(check_cmd(6, 0x5d, 0).is_err()); // nothing after 0x5f
    }

    #[test]
    fn fragments_5f() {
        let s = &RELAY_SEQUENCE[5];
        let h0 = OolHeader { valid: 1, total: 0x568e, offset: 0, ty: 0x5f, len: 0x3fe4 }.to_bytes();
        let f0 = check_fragment(s, &h0, 0, None, 0).unwrap();
        assert_eq!((f0.total, f0.offset, f0.len), (0x568e, 0, 0x3fe4));
        let h1 = OolHeader { valid: 1, total: 0x568e, offset: 0x3fe4, ty: 0x5f, len: 0x16aa }.to_bytes();
        assert!(check_fragment(s, &h1, 0x3fe4, Some(0x568e), 1).is_ok());
        assert!(check_fragment(s, &h1, 0, Some(0x568e), 1).is_err()); // out of order
        assert!(check_fragment(s, &h1, 0x3fe4, Some(0x568f), 1).is_err()); // total changed
        let h2 = OolHeader { valid: 1, total: 0x568e, offset: 0x3fe4, ty: 0x5f, len: 0x16ab }.to_bytes();
        assert!(check_fragment(s, &h2, 0x3fe4, Some(0x568e), 1).is_err()); // beyond total
        // 0x15 must return exactly 40 bytes.
        let k = OolHeader { valid: 1, total: 0x20, offset: 0, ty: 0x15, len: 0x20 }.to_bytes();
        assert!(check_fragment(&RELAY_SEQUENCE[1], &k, 0, None, 0).is_err());
    }

    #[test]
    fn records() {
        let mut b = [0u8; CMD_MAX];
        let n = encode_cmd(0x15, &[1, 0, 0, 0], &mut b).unwrap();
        assert_eq!(decode_cmd(&b[..n]).unwrap(), (0x15, &[1u8, 0, 0, 0][..]));
        assert!(decode_cmd(&b[..n - 1]).is_err());
        let e = EvtHdr { kind: KIND_REPLY, tag: 0xfd, ty: 0x5f, param: 0, data: 0x10000, len: 2 };
        let mut r = e.encode().to_vec();
        r.extend_from_slice(&[9, 9]);
        assert_eq!(EvtHdr::decode(&r).unwrap(), (e, &[9u8, 9][..]));
    }

    #[test]
    fn packet_hello_shape() {
        let mut a = [0u8; 0x40];
        let n = build_packet(OP_HELLO, &[1, 0, 0, 0], &mut a).unwrap();
        assert_eq!(n, 0x20);
        assert_eq!((a[0], a[4], a[0x14], a[0x18], a[0x1c]), (1, 4, 0x73, 4, 1));
    }
}
