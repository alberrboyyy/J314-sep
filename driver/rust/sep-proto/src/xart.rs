//! Step 6: codec of the xART stream (EP 0x13) + parser of the gigalocker vault (.gl).
//!
//! SCOPE = OBSERVED only (`docs/gigalocker.md`: vault parsed on disk, FETCH reply format correlated on c24). This
//! module DECODES / ENCODES and READS the vault. It decides nothing and sends nothing. The native handler POLICY
//! (answer "absent", ack + persist SAVE) is an untested hypothesis: see `xart_responder::native_*`.
use crate::crc::crc32;
use crate::{le_u32, Error, Result};
use alloc::vec::Vec;

pub const EP_XART: u8 = 0x13;

pub const OP_FWBOOT: u8 = 0x0e;
pub const OP_OSUUID: u8 = 0x13;
pub const OP_FETCH_MASTER: u8 = 0x00;
pub const OP_FETCH_GL: u8 = 0x05;
pub const OP_ABSENT: u8 = 0x07;
pub const OP_EP_ANNOUNCE: u8 = 0x1d;
/// SAVE of an xART master (re-sealing): a WRITE if acknowledged.
pub const OP_SAVE_XART: u8 = 0x01;
/// SAVE of a gigalocker: a WRITE if acknowledged.
pub const OP_SAVE_LOCKER: u8 = 0x06;

pub const SEL_USER: u8 = 0;
pub const SEL_SEP: u8 = 1;

pub fn op_name(ty: u8) -> Option<&'static str> {
    Some(match ty {
        OP_FWBOOT => "fwboot",
        OP_OSUUID => "osuuid",
        OP_FETCH_MASTER => "fetch_master",
        OP_FETCH_GL => "fetch_gl",
        OP_ABSENT => "absent",
        OP_EP_ANNOUNCE => "ep_announce",
        OP_SAVE_XART => "save_xart",
        OP_SAVE_LOCKER => "save_locker",
        _ => return None,
    })
}

/// Selector carried by DATA[1] (master: 0=USER, 1=SEP). Observed: re-emitted as is in the reply.
pub const fn selector(data: u32) -> u8 {
    (data >> 8) as u8
}

/// An acknowledged SAVE = a SEP write (sealed counter). The codec only recognises it.
pub const fn is_save(ty: u8) -> bool {
    matches!(ty, OP_SAVE_XART | OP_SAVE_LOCKER)
}

/// FETCH reply length = PARAM | (DATA[byte0] << 8).
pub const fn decode_fetch_len(param: u8, data: u32) -> u16 {
    param as u16 | ((data & 0xFF) as u16) << 8
}

/// Real blob size -> (param, data). The driver RECOMPUTES it (does not replay the capture). `flag` goes to DATA[1].
pub fn encode_fetch_len(length: usize, flag: u8) -> Result<(u8, u32)> {
    if length > 0xFFFF {
        return Err(Error::OutOfRange("fetch length", length as u64));
    }
    Ok((length as u8, ((length >> 8) as u32 & 0xFF) | (flag as u32) << 8))
}

pub const SLOT: usize = 0x9000;
pub const HDR: usize = 0x22;
pub const T_USER_MASTER: u8 = 0x01;
pub const T_SEP_MASTER: u8 = 0x02;
pub const fn is_gigalocker_type(t: u8) -> bool {
    matches!(t, 0x03 | 0x04)
}

/// CRC stored at +0x16 = CRC-32/ISO-HDLC of the payload only. VERIFIED: 12/12 CRCs of the real vault.
pub fn slot_crc(payload: &[u8]) -> u32 {
    crc32(payload)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Locker {
    pub slot: usize,
    pub ty: u8,
    /// 16 bytes for a gigalocker, empty for a master.
    pub uuid: Vec<u8>,
    pub length: u32,
    pub crc: u32,
    /// Sealed payload, opaque (never decrypted).
    pub payload: Vec<u8>,
    /// Original raw header [+0x00:+0x22] (kept for an exact round-trip).
    pub header: Vec<u8>,
}

impl Locker {
    pub fn is_master(&self) -> bool {
        matches!(self.ty, T_USER_MASTER | T_SEP_MASTER)
    }
    pub fn crc_ok(&self) -> bool {
        self.crc == slot_crc(&self.payload)
    }
}

/// Bytes of the .gl file -> lockers. Pure reading; the payload stays opaque.
pub fn parse_coffre(data: &[u8]) -> Result<Vec<Locker>> {
    let mut out = Vec::new();
    for k in 0..=data.len() / SLOT {
        let base = k * SLOT;
        if base + HDR > data.len() {
            continue;
        }
        let slot = &data[base..core::cmp::min(base + SLOT, data.len())];
        if slot.iter().all(|&b| b == 0) {
            continue;
        }
        let ty = data[base + 1];
        let uuid = if is_gigalocker_type(ty) { data[base + 2..base + 0x12].to_vec() } else { Vec::new() };
        let length = le_u32(data, base + 0x12)?;
        let crc = le_u32(data, base + 0x16)?;
        let start = base + HDR;
        let end = core::cmp::min(data.len(), start.saturating_add(length as usize));
        out.push(Locker {
            slot: k,
            ty,
            uuid,
            length,
            crc,
            payload: data[start..end].to_vec(),
            header: data[base..base + HDR].to_vec(),
        });
    }
    Ok(out)
}

/// Header [+0x00:+0x22] for a NEW locker. `extra` = u16 at +0x1a whose ROLE IS UNKNOWN (0 by default; to be
/// confirmed on hardware before any real native SAVE).
pub fn build_header(ty: u8, uuid: &[u8], payload: &[u8], extra: u16) -> [u8; HDR] {
    let mut h = [0u8; HDR];
    h[1] = ty;
    if is_gigalocker_type(ty) {
        let n = core::cmp::min(16, uuid.len());
        h[2..2 + n].copy_from_slice(&uuid[..n]);
    }
    h[0x12..0x16].copy_from_slice(&(payload.len() as u32).to_le_bytes());
    h[0x16..0x1a].copy_from_slice(&slot_crc(payload).to_le_bytes());
    h[0x1a..0x1c].copy_from_slice(&extra.to_le_bytes());
    h
}

/// Locker -> bytes of ONE slot. A parsed locker reproduces its original slot byte for byte.
pub fn serialize_locker(l: &Locker) -> Result<Vec<u8>> {
    let mut body = if l.header.len() == HDR { l.header.clone() } else { build_header(l.ty, &l.uuid, &l.payload, 0).to_vec() };
    body.extend_from_slice(&l.payload);
    if body.len() > SLOT {
        return Err(Error::OutOfRange("locker size", body.len() as u64));
    }
    body.resize(SLOT, 0);
    Ok(body)
}

pub fn find_master(lockers: &[Locker], sel: u8) -> Option<&Locker> {
    let want = if sel == SEL_SEP { T_SEP_MASTER } else { T_USER_MASTER };
    lockers.iter().find(|l| l.ty == want)
}

pub fn find_gigalocker<'a>(lockers: &'a [Locker], uuid: &[u8]) -> Option<&'a Locker> {
    lockers.iter().find(|l| !l.uuid.is_empty() && l.uuid == uuid)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn documented_examples() {
        assert_eq!(decode_fetch_len(0x64, 0x03), 0x364);
        assert_eq!(decode_fetch_len(0x14, 0x08), 0x814);
        assert_eq!(decode_fetch_len(0x0c, 0x0c), 0xc0c);
    }
    #[test]
    fn roundtrip_with_flag() {
        let (p, d) = encode_fetch_len(0x364, SEL_SEP).unwrap();
        assert_eq!((p, d), (0x64, 0x0103));
        assert_eq!(decode_fetch_len(p, d), 0x364);
        assert_eq!(selector(d), SEL_SEP);
        for ln in [0x28, 0x2014, 0x540, 0x352] {
            let (p, d) = encode_fetch_len(ln, 0).unwrap();
            assert_eq!(decode_fetch_len(p, d) as usize, ln);
        }
    }
    #[test]
    fn new_header() {
        let payload: Vec<u8> = [0xde, 0xad, 0xbe, 0xef].repeat(20);
        let h = build_header(T_SEP_MASTER, &[], &payload, 0);
        assert_eq!(h[1], T_SEP_MASTER);
        assert_eq!(le_u32(&h, 0x12).unwrap(), payload.len() as u32);
        assert_eq!(le_u32(&h, 0x16).unwrap(), slot_crc(&payload));
    }
}
