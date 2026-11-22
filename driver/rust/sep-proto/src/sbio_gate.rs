//! Gate of the sbio relay (EP 0x08) and record format of `/dev/sep_sbio`. No allocation, no `std`: this file is
//! also included as is by the kernel module (`kmod/sep_native.rs`), which checks every command userspace submits
//! (opcode, ORDER, exact payload length, fixed payloads) and every fragment the SEP returns BEFORE acting on it. The
//! relay daemon (`driver/rust/sbiod`) builds its commands with the same constants, so both sides agree by construction.
//!
//! Protocol (`docs/sbio_session.md`, `docs/sbio_keyexchange.md`, `docs/j5_params_protocol.md`; 0x17..0x5f
//! hardware-proven under m1n1 by `pending/sep_native_sbio3.sh` .. `sep_native_sbio11.sh` and natively by J5 v2;
//! 0x5d..0x63 natively by J5c (n=1); 2nd pass 0x19..0x63 ×2 = macOS captures only, c12 seq 345-382, identical sizes in
//! 9/9 boots, `docs/j5_params_protocol.md` §8):
//! - command: buffer A8 = gt_packet `OolHeader { valid 1, total = len, offset 0, TYPE = op, len }` + payload, zero
//!   padded; then `> EP 0x08 TAG 0xfc TYPE op PARAM 0 DATA 0`. The c12 templates `000303..000343_08_A.bin` are exactly
//!   this (checked by `sbiod/tests/replay.rs`), so the kernel builds the packet from (op, payload), no template.
//! - reply: `< TAG 0xfc TYPE op`, B8 = gt_packet of the reply (first fragment). If `offset + len < total`, the AP asks
//!   for the next fragment with `> TAG 0xfe TYPE op DATA nfd << 16` (A8 unchanged) and the SEP answers `< TAG 0xfd`
//!   (DATA = (nfd + 1) << 16): c12 seq 313-316 and sbio6/7/11 (0x5f, 22158 bytes in 2 fragments).
//! - AP -> SEP fragmentation, ONLY for the step marked `frag_in` (0x5b, calibration, 0xfc99 bytes): A8 = fragment k
//!   (`OolHeader { 1, total, offset = k * 0x3fe4, 0x5b, len }`), `> fc DATA 0` for k = 0, then after each `< fe DATA
//!   (k - 1) << 16` from the SEP, `> fd DATA k << 16`; the SEP closes with `< fc DATA 0` (empty reply). c12 L388-402,
//!   same words in 23/23 captures. Every other payload is <= 64 bytes, in one chunk.
use crate::crc::crc32;
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
/// Largest single-chunk command payload.
pub const MAX_CMD: usize = 0x40;
/// Calibration blob of 0x5b (c12 `000335/337/339/341_08_A.bin`, identical in 9/9 boots with OOL): length, CRC-32
/// (checked by the kernel), first bytes. Its sha256 (`d5a6117d…ddda`) is checked by sbiod.
pub const CALIB_LEN: usize = 0xfc99;
pub const CALIB_CRC32: u32 = 0x6f98_a221;
pub const CALIB_HEAD: [u8; 8] = [0x03, 0x00, 0x00, 0x00, 0x30, 0x82, 0xfc, 0x91];
/// Fragments of the calibration (0x3fe4 × 3 + 0x3ced, c12).
pub const CALIB_FRAGS: usize = CALIB_LEN.div_ceil(OOL_MAX_CHUNK);
/// Largest command payload of any kind (the calibration).
pub const MAX_CMD_IN: usize = CALIB_LEN;

/// One relayed step: opcode, exact payload length the AP sends (and its bytes when they are fixed), bounds of the
/// reply total the SEP returns, and whether the command goes AP -> SEP in fragments.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Step {
    pub op: u8,
    pub name: &'static str,
    pub cmd_len: usize,
    /// Exact payload (constant in every capture), None = opaque (relayed).
    pub cmd_fixed: Option<&'static [u8]>,
    /// AP -> SEP fragmentation (only 0x5b).
    pub frag_in: bool,
    pub reply_min: usize,
    pub reply_max: usize,
}

const fn step(op: u8, name: &'static str, cmd_len: usize, cmd_fixed: Option<&'static [u8]>, reply: (usize, usize)) -> Step {
    Step { op, name, cmd_len, cmd_fixed, frag_in: false, reply_min: reply.0, reply_max: reply.1 }
}

/// Exact total of the 2nd-pass patch (0x5f after 0x19): 0x70ce in 9/9 boots with OOL (c12 seq 358/360) and in the
/// 4 SPI captures C17-C20 (one 0x70ce transfer each).
pub const PATCH2_LEN: usize = 0x70ce;

/// The whitelist, IN ORDER (c12 seq 303-382 = 1st pass, 0x19, 2nd pass of the macOS init = `daemon::INIT_SEQUENCE
/// [1..35]`). Each step is admitted once, at its own position, after the 0x73 hello (done by the kernel itself), up to
/// the limit chosen at load time (`limit`): an opcode of the 2nd pass is only admitted at its place in the 2nd pass,
/// never as a free repetition. Nothing after the 2nd 0x63 of the 2nd pass (no 0x7c / 0x6b / 0x79 / 0x6d, no 0x6c,
/// nothing about enrolment or match).
pub const RELAY_SEQUENCE: [Step; 34] = [
    // prepareSession: sensor serial (16 bytes, identity frame [9..25]) -> empty ack.
    step(0x17, "prepareSession", 0x10, None, (0, 0)),
    // performKeyExchange (sessionType = 1, `01 00 00 00`) -> 40 opaque bytes for SPI frame 0x72.
    step(0x15, "keyExchange", 4, Some(&[1, 0, 0, 0]), (0x28, 0x28)),
    // 40 bytes of the sensor reply -> empty ack.
    step(0x16, "keyExchange2", 0x28, None, (0, 0)),
    // initializeSequenceCounter (empty) -> 64 opaque bytes for SPI frame 0x73.
    step(0x42, "initSeqCounter", 0, None, (0x40, 0x40)),
    // 64 bytes of the sensor reply -> empty ack.
    step(0x18, "seqCounter2", 0x40, None, (0, 0)),
    // LoadPatch (`02 00`) -> patch block (fragmented), pushed raw to the sensor after prelude 0x60.
    step(0x5f, "loadPatch", 2, Some(&[2, 0]), (2, MAX_REPLY)),
    // --- after the patch (LIMIT_PARAMS), docs/j5_params_protocol.md §1 ---
    // applySensorParams (`00 00 00 00`) -> 55 opaque bytes for SPI frame 0x55 (+ CRC16), status only.
    step(0x5d, "sensorParams5d", 4, Some(&[0, 0, 0, 0]), (0x37, 0x37)),
    step(0x5c, "sensorParams5c", 4, Some(&[0, 0, 0, 0]), (0x37, 0x37)),
    // applySensorParams 0x6a: empty -> empty in the 1st pass (9/9), no SPI. Anything else is refused.
    step(0x6a, "sensorParams6a", 0, Some(&[]), (0, 0)),
    // module serial: empty -> 64 opaque bytes for SPI frame 0x55; the 0x75 answer (64 bytes @ 9) -> 0x32 -> 18 bytes.
    step(0x31, "moduleSerial", 0, Some(&[]), (0x40, 0x40)),
    step(0x32, "moduleSerial2", 0x40, None, (0x12, 0x12)),
    // end of loadPatch (empty -> empty), cacheMatchPolicy (empty -> 2 bytes): SEP only.
    step(0x01, "patchDone", 0, Some(&[]), (0, 0)),
    step(0x1f, "matchPolicy", 0, Some(&[]), (2, 2)),
    step(0x31, "moduleSerial", 0, Some(&[]), (0x40, 0x40)),
    step(0x32, "moduleSerial2", 0x40, None, (0x12, 0x12)),
    // --- calibration (LIMIT_CALIB) ---
    // setCalibrationData: the captured blob, AP -> SEP in 4 fragments -> empty reply. SEP only.
    Step { op: 0x5b, name: "setCalibration", cmd_len: CALIB_LEN, cmd_fixed: None, frag_in: true, reply_min: 0, reply_max: 0 },
    // getCalibrationDataInfo: empty -> 28 bytes. Last step of the 1st pass.
    step(0x63, "calibrationInfo", 0, Some(&[]), (0x1c, 0x1c)),
    // --- 2nd pass (LIMIT_PASS2), docs/j5_params_protocol.md §8; c12 seq 345-382, 9/9 boots ---
    // HandleReset: empty -> empty. macOS sends it after powering the sensor off and on (C17-C20).
    step(0x19, "handleReset", 0, Some(&[]), (0, 0)),
    step(0x17, "prepareSession", 0x10, None, (0, 0)),
    step(0x15, "keyExchange", 4, Some(&[1, 0, 0, 0]), (0x28, 0x28)),
    step(0x16, "keyExchange2", 0x28, None, (0, 0)),
    step(0x42, "initSeqCounter", 0, None, (0x40, 0x40)),
    step(0x18, "seqCounter2", 0x40, None, (0, 0)),
    // 2nd patch: 0x70ce bytes exactly (2 fragments 0x3fe4 + 0x30ea).
    step(0x5f, "loadPatch", 2, Some(&[2, 0]), (PATCH2_LEN, PATCH2_LEN)),
    step(0x5d, "sensorParams5d", 4, Some(&[0, 0, 0, 0]), (0x37, 0x37)),
    step(0x5c, "sensorParams5c", 4, Some(&[0, 0, 0, 0]), (0x37, 0x37)),
    // 2nd pass: 0x6a now returns 68 bytes (SPI frame 0x55 of 0x4d), and 0x6f (77 bytes, frame of 0x56) follows.
    step(0x6a, "sensorParams6a", 0, Some(&[]), (0x44, 0x44)),
    step(0x6f, "sensorParams6f", 0, Some(&[]), (0x4d, 0x4d)),
    // ONE module serial pair in the 2nd pass.
    step(0x31, "moduleSerial", 0, Some(&[]), (0x40, 0x40)),
    step(0x32, "moduleSerial2", 0x40, None, (0x12, 0x12)),
    step(0x01, "patchDone", 0, Some(&[]), (0, 0)),
    step(0x1f, "matchPolicy", 0, Some(&[]), (2, 2)),
    // No 0x5b in the 2nd pass; 0x63 twice in a row (same 28 bytes both times). Last step.
    step(0x63, "calibrationInfo", 0, Some(&[]), (0x1c, 0x1c)),
    step(0x63, "calibrationInfo", 0, Some(&[]), (0x1c, 0x1c)),
];

/// Number of steps admitted for each level of the kernel parameter `allow_sbio_params`.
pub const LIMIT_PATCH: usize = 6;
pub const LIMIT_PARAMS: usize = 15;
pub const LIMIT_CALIB: usize = 17;
pub const LIMIT_PASS2: usize = 34;

/// Steps admitted for `allow_sbio_params` = 0 (up to 0x5f), 1 (up to the 2nd 0x32), 2 (up to 0x63), 3 (then 0x19 and
/// the 2nd pass, up to its 2nd 0x63).
pub const fn limit(level: u32) -> Option<usize> {
    match level {
        0 => Some(LIMIT_PATCH),
        1 => Some(LIMIT_PARAMS),
        2 => Some(LIMIT_CALIB),
        3 => Some(LIMIT_PASS2),
        _ => None,
    }
}

/// Step `next` of the sequence, if it is below `limit` and `op` / `payload` are exactly what it allows.
pub fn check_cmd(next: usize, limit: usize, op: u8, payload: &[u8]) -> Result<&'static Step> {
    if next >= limit.min(RELAY_SEQUENCE.len()) {
        return Err(Error::Unexpected("sbio relay: sequence finished for this level (allow_sbio_params)"));
    }
    let s = &RELAY_SEQUENCE[next];
    if s.op != op {
        return Err(Error::Unexpected("sbio relay: opcode out of order or not whitelisted"));
    }
    if s.cmd_len != payload.len() {
        return Err(Error::Unexpected("sbio relay: payload length differs from the whitelisted one"));
    }
    if s.cmd_fixed.is_some_and(|f| f != payload) {
        return Err(Error::Unexpected("sbio relay: payload differs from the fixed one of this opcode"));
    }
    if s.frag_in && (payload.len() != CALIB_LEN || payload[..CALIB_HEAD.len()] != CALIB_HEAD || crc32(payload) != CALIB_CRC32) {
        return Err(Error::Unexpected("sbio relay: calibration blob is not the captured one (length / head / CRC-32)"));
    }
    if !s.frag_in && payload.len() > MAX_CMD {
        return Err(Error::Unexpected("sbio relay: payload too long for one chunk"));
    }
    Ok(s)
}

/// Number of AP -> SEP fragments of a command (1 unless `frag_in`).
pub fn cmd_frags(s: &Step, len: usize) -> usize {
    if s.frag_in { len.div_ceil(OOL_MAX_CHUNK).max(1) } else { 1 }
}

/// Header of AP -> SEP fragment `k` of a `total`-byte command, and the payload range it carries.
pub fn fragment_header(op: u8, total: usize, k: usize) -> Result<([u8; OOL_HDR], core::ops::Range<usize>)> {
    let off = k.checked_mul(OOL_MAX_CHUNK).ok_or(Error::Short)?;
    if total > MAX_CMD_IN || off >= total.max(1) || k >= CALIB_FRAGS {
        return Err(Error::Unexpected("sbio relay: fragment index out of range"));
    }
    let end = (off + OOL_MAX_CHUNK).min(total);
    let h = OolHeader { valid: 1, total: total as u32, offset: off as u32, ty: u32::from(op), len: (end - off) as u32 };
    Ok((h.to_bytes(), off..end))
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
/// Command written by userspace: `+0 u32 MAGIC | +4 op | +5..8 zero | +8 u32 len` then `len` payload bytes
/// (<= 64, or the 0xfc99-byte calibration).
pub const CMD_HDR: usize = 12;
pub const CMD_MAX: usize = CMD_HDR + MAX_CMD_IN;
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
    if payload.len() > MAX_CMD_IN {
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
    if len > MAX_CMD_IN || b.len() != CMD_HDR + len {
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

    fn payload(s: &Step) -> [u8; MAX_CMD + 1] {
        let mut p = [0xa5u8; MAX_CMD + 1];
        if let Some(f) = s.cmd_fixed {
            p[..f.len()].copy_from_slice(f);
        }
        p
    }

    #[test]
    fn order_and_lengths() {
        for (i, s) in RELAY_SEQUENCE.iter().enumerate().filter(|(_, s)| !s.frag_in) {
            let p = payload(s);
            assert!(check_cmd(i, LIMIT_PASS2, s.op, &p[..s.cmd_len]).is_ok(), "{i}");
            assert!(check_cmd(i, LIMIT_PASS2, s.op, &p[..s.cmd_len + 1]).is_err());
            assert!(check_cmd(i, LIMIT_PASS2, OP_HELLO, &p[..s.cmd_len]).is_err());
            assert_eq!(check_cmd(i, LIMIT_CALIB, s.op, &p[..s.cmd_len]).is_ok(), i < LIMIT_CALIB);
        }
        let p = [0u8; 0x10];
        assert!(check_cmd(1, LIMIT_CALIB, 0x17, &p).is_err()); // replay / out of order
        assert!(check_cmd(6, LIMIT_PATCH, 0x5d, &[0; 4]).is_err()); // level 0: nothing after 0x5f
        assert!(check_cmd(6, LIMIT_PARAMS, 0x5d, &[0; 4]).is_ok());
        assert!(check_cmd(6, LIMIT_PARAMS, 0x5d, &[0, 0, 0, 1]).is_err()); // fixed payload
        assert!(check_cmd(1, LIMIT_PATCH, 0x15, &[2, 0, 0, 0]).is_err());
        assert!(check_cmd(15, LIMIT_PARAMS, 0x5b, &[0; 4]).is_err()); // level 1: nothing after 2nd 0x32
        assert!(check_cmd(16, LIMIT_CALIB, 0x63, &[]).is_ok());
        assert!(check_cmd(17, LIMIT_CALIB, 0x19, &[]).is_err()); // level 2: nothing after 0x63
        assert!(check_cmd(17, LIMIT_PASS2, 0x19, &[]).is_ok());
        assert!(check_cmd(33, LIMIT_PASS2, 0x63, &[]).is_ok());
        assert!(check_cmd(34, LIMIT_PASS2, 0x63, &[]).is_err()); // nothing after the 2nd 0x63 of the 2nd pass
        assert!(check_cmd(34, LIMIT_PASS2, 0x7c, &[]).is_err());
        assert_eq!((limit(0), limit(1), limit(2), limit(3), limit(4)), (Some(6), Some(15), Some(17), Some(34), None));
        // c12 order of the 1st pass, 0x19 and the 2nd pass (daemon::INIT_SEQUENCE[1..35]).
        let ops: [u8; 34] = core::array::from_fn(|i| RELAY_SEQUENCE[i].op);
        assert_eq!(ops[..], crate::daemon::INIT_SEQUENCE[1..35]);
        assert_eq!(RELAY_SEQUENCE[LIMIT_PATCH - 1].op, 0x5f);
        assert_eq!(RELAY_SEQUENCE[LIMIT_PARAMS - 1].op, 0x32);
        assert_eq!(RELAY_SEQUENCE[LIMIT_CALIB].op, 0x19);
        assert_eq!(INIT_SEQUENCE_NEXT, 0x7c);
    }

    const INIT_SEQUENCE_NEXT: u8 = crate::daemon::INIT_SEQUENCE[35];

    #[test]
    fn second_pass_is_linear() {
        // A 2nd-pass opcode is admitted only at its own position: not as a repetition right after the 1st pass,
        // not out of order inside the 2nd pass.
        assert!(check_cmd(17, LIMIT_PASS2, 0x17, &[0; 0x10]).is_err()); // 0x17 before 0x19
        assert!(check_cmd(18, LIMIT_PASS2, 0x15, &[1, 0, 0, 0]).is_err()); // skipping 0x17
        assert!(check_cmd(27, LIMIT_PASS2, 0x31, &[]).is_err()); // 0x31 where 0x6f is due
        assert!(check_cmd(32, LIMIT_PASS2, 0x5b, &[]).is_err()); // no calibration in the 2nd pass
        assert!(check_cmd(27, LIMIT_PASS2, 0x6f, &[]).is_ok());
        assert!(check_cmd(27, LIMIT_PASS2, 0x6f, &[0]).is_err());
        // Reply bounds of the 2nd pass: 0x6a = 0x44 (and no longer 0), 0x6f = 0x4d, 0x5f = 0x70ce exactly.
        let h = |op: u8, t: u32| OolHeader { valid: 1, total: t, offset: 0, ty: u32::from(op), len: t.min(0x3fe4) }.to_bytes();
        assert!(check_fragment(&RELAY_SEQUENCE[26], &h(0x6a, 0x44), 0, None, 0).is_ok());
        assert!(check_fragment(&RELAY_SEQUENCE[26], &h(0x6a, 0), 0, None, 0).is_err());
        assert!(check_fragment(&RELAY_SEQUENCE[8], &h(0x6a, 0x44), 0, None, 0).is_err()); // 1st pass: empty only
        assert!(check_fragment(&RELAY_SEQUENCE[27], &h(0x6f, 0x4d), 0, None, 0).is_ok());
        assert!(check_fragment(&RELAY_SEQUENCE[23], &h(0x5f, 0x70ce), 0, None, 0).is_ok());
        assert!(check_fragment(&RELAY_SEQUENCE[23], &h(0x5f, 0x568e), 0, None, 0).is_err());
        assert!(check_fragment(&RELAY_SEQUENCE[5], &h(0x5f, 0x568e), 0, None, 0).is_ok());
        assert_eq!(RELAY_SEQUENCE.iter().filter(|s| s.frag_in).count(), 1);
    }

    #[test]
    fn calibration_gate_and_fragments() {
        let s = &RELAY_SEQUENCE[15];
        assert!(s.frag_in && RELAY_SEQUENCE.iter().filter(|s| s.frag_in).count() == 1);
        // A blob of the right length but another content is refused (CRC-32 / head).
        let mut fake = [0u8; CALIB_LEN];
        fake[..8].copy_from_slice(&CALIB_HEAD);
        assert!(check_cmd(15, LIMIT_CALIB, 0x5b, &fake).is_err());
        assert!(check_cmd(15, LIMIT_CALIB, 0x5b, &fake[..100]).is_err());
        assert_eq!((CALIB_FRAGS, cmd_frags(s, CALIB_LEN), cmd_frags(&RELAY_SEQUENCE[0], 16)), (4, 4, 1));
        let want = [(0, 0x3fe4), (0x3fe4, 0x3fe4), (0x7fc8, 0x3fe4), (0xbfac, 0x3ced)];
        for (k, (off, len)) in want.iter().enumerate() {
            let (h, r) = fragment_header(0x5b, CALIB_LEN, k).unwrap();
            let p = OolHeader::parse(&h).unwrap();
            assert_eq!((p.valid, p.total, p.offset as usize, p.ty, p.len as usize), (1, 0xfc99, *off, 0x5b, *len));
            assert_eq!(r, *off..off + len);
        }
        assert!(fragment_header(0x5b, CALIB_LEN, 4).is_err());
    }

    #[test]
    fn fragments_5f() {
        let s = &RELAY_SEQUENCE[5];
        assert_eq!(s.op, 0x5f);
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
