//! Step 3: sensor frame `[0x80][opcode][index][u32 LE total length][payload]` and status `80 20 00 10000000 ...`.
//!
//! Status: frame and status = **hypothesis** (source kext + uart; 20/20 traces), and the identity exchange is
//! **verified on hardware** (MESA-HELLO under m1n1 and, 2026-11-22, under Linux ALARM). The full status content is
//! UNKNOWN: raw bytes are exposed. `state_byte` / `avail_u32` follow the kext reading and are hypotheses.
use crate::crc::crc16_arc;
use crate::{le_u16, le_u32, Error, Result};

pub const MAGIC: u8 = 0x80;
pub const OP_STATUS: u8 = 0x20;
pub const OP_READ_DATA: u8 = 0x13;
pub const HEADER_LEN: usize = 7;

/// Commands sent by `driver/linux/mesa_probe.c` (verified on hardware).
pub const CMD_WAKE: [u8; 7] = [0x80, 0x78, 0x00, 0x07, 0x00, 0x00, 0x00];
pub const CMD_IDENTITY: [u8; 7] = [0x80, 0x70, 0x00, 0x07, 0x00, 0x00, 0x00];
pub const CMD_STATUS: [u8; 7] = [0x80, 0x10, 0x00, 0x07, 0x00, 0x00, 0x00];
/// Sensor identity read under macOS, m1n1 and Linux.
pub const IDENTITY_J314C: [u8; 27] = [
    0x80, 0xd4, 0x00, 0x1b, 0x00, 0x00, 0x00, 0x00, 0x70, 0x02, 0x19, 0xc0, 0x5c, 0x0f, 0xd2, 0xaa, 0x34, 0x9a, 0x81,
    0xc7, 0x6e, 0x03, 0x02, 0x00, 0xd8, 0x75, 0x76,
];

/// Identity bytes holding the sensor serial sent with sbio 0x17 (c12 template 000303_08_A.bin payload = these 16
/// bytes; proven under m1n1 by sbio3..sbio11).
pub const SERIAL_RANGE: core::ops::Range<usize> = 9..25;
pub const SERIAL_LEN: usize = 16;
/// Status request: 7-byte command padded with 16 zeros, 0x17 bytes read; the status body starts at byte 7.
pub const STATUS_XFER_LEN: usize = 0x17;
pub const STATUS_HEAD: [u8; 4] = [0x80, 0x20, 0x00, 0x10];
/// Opcodes of the relay frames (no CRC; VU C19: 0x72 = 7 + 40 = 0x2f, 0x73 = 7 + 64 = 0x47).
pub const OP_KEY_EXCHANGE: u8 = 0x72;
pub const OP_SEQ_COUNTER: u8 = 0x73;
/// Offset of the opaque payload in the sensor reply of a relay frame (SPI_RESP_OFF of sbio4..11, proven: the SEP
/// acked 0x16 and 0x18 with it).
pub const RELAY_RESP_OFF: usize = 9;
/// Prelude of the patch push (VU C19, sbio7..11), sent alone, then the raw block in ONE transfer.
pub const PATCH_PRELUDE: [u8; 7] = [0x80, 0x60, 0x00, 0x07, 0x00, 0x00, 0x00];
/// Status byte 1 (frame byte 8) after the patch block: 0x29 = loaded (kext `cmp #0x29`, sbio_session.md §3b and
/// C19 `00 29 01 00 7c`); 0x60 = no patch.
pub const PATCH_LOADED: u8 = 0x29;
pub const PATCH_NONE: u8 = 0x60;

/// Encrypted sensor command (sbio 0x5d / 0x5c / 0x31 in the 1st pass): `80 55 <total BE16> 00 00 00` + SEP blob +
/// CRC-16/ARC of header + blob, little-endian; total = 7 + len + 2 (VU C19, 4 frames recomputed; sbio9;
/// docs/j5_params_protocol.md §2).
pub const OP_PARAMS: u8 = 0x55;
pub const PARAM_CRC_LEN: usize = 2;
/// Sensor answer to the 0x31 frame: `80 d4 00 4b 00000000 75` + 64 bytes + CRC16 (VU C18-C20, 2 per boot).
pub const OP_SERIAL_ANSWER: u8 = 0x75;
pub const SERIAL_ANSWER_LEN: usize = 0x4b;
pub const SERIAL_ANSWER_HEAD: [u8; 9] = [0x80, 0xd4, 0x00, 0x4b, 0, 0, 0, 0, OP_SERIAL_ANSWER];
/// Status bodies (9 bytes after `80 20 00 10 00 00 00`) read by macOS after each frame, C18/C19/C20 3/3 identical.
pub const ST_AFTER_PARAMS: [u8; 9] = [0x00, 0x00, 0x21, 0x00, 0x0c, 0x52, 0x33, 0x00, 0x16];
pub const ST_SERIAL_READY: [u8; 9] = [0x07, 0x00, 0x21, 0x00, 0x8c, 0x4b, 0x00, 0x00, 0x00];
/// Status byte 0 (frame byte 7) when an answer is pending; only then do bytes 5-6 hold its length (at rest they read
/// `52 33`).
pub const ST_ANSWER_READY: u8 = 0x07;

/// Frame 0x55 carrying `blob` (+ CRC). Totals < 0x100 only (all frames of the 1st pass: 0x40, 0x49).
pub fn build_param_frame(blob: &[u8], out: &mut [u8]) -> Result<usize> {
    let n = HEADER_LEN + blob.len() + PARAM_CRC_LEN;
    if n >= 0x100 {
        return Err(Error::Unexpected("param frame too long"));
    }
    let o = out.get_mut(..n).ok_or(Error::Short)?;
    o[..HEADER_LEN].copy_from_slice(&[MAGIC, OP_PARAMS, 0, n as u8, 0, 0, 0]);
    o[HEADER_LEN..n - PARAM_CRC_LEN].copy_from_slice(blob);
    let c = crc16_arc(&o[..n - PARAM_CRC_LEN]);
    o[n - PARAM_CRC_LEN..].copy_from_slice(&c.to_le_bytes());
    Ok(n)
}

/// The 64-byte payload of the sensor answer to a 0x31 frame, after checking its exact shape and CRC.
pub fn serial_answer_payload(r: &[u8]) -> Result<&[u8]> {
    if r.len() != SERIAL_ANSWER_LEN {
        return Err(Error::Unexpected("0x75 answer: length is not 0x4b"));
    }
    if r[..9] != SERIAL_ANSWER_HEAD {
        return Err(Error::Unexpected("0x75 answer: header is not 80 d4 00 4b 00000000 75"));
    }
    let n = r.len() - PARAM_CRC_LEN;
    if le_u16(r, n)? != crc16_arc(&r[..n]) {
        return Err(Error::Unexpected("0x75 answer: CRC16 mismatch"));
    }
    Ok(&r[RELAY_RESP_OFF..n])
}

/// Relay frame `80 op 00 TT 00 00 00 + blob`, TT = total length (7 + blob). Written into `out`, returns its length.
/// Only totals < 0x100 are built: there the two readings of the header (u16 BE at 2 in the scripts, u32 LE at 3 in
/// `parse_frame`) give the same bytes; a longer frame is refused (never needed by 0x72 / 0x73).
pub fn build_relay_frame(op: u8, blob: &[u8], out: &mut [u8]) -> Result<usize> {
    let n = HEADER_LEN + blob.len();
    if n >= 0x100 {
        return Err(Error::Unexpected("relay frame too long"));
    }
    let o = out.get_mut(..n).ok_or(Error::Short)?;
    o[..HEADER_LEN].copy_from_slice(&[MAGIC, op, 0, n as u8, 0, 0, 0]);
    o[HEADER_LEN..].copy_from_slice(blob);
    Ok(n)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Frame<'a> {
    pub op: u8,
    pub index: u8,
    pub total_len: u32,
    pub payload: &'a [u8],
    pub raw: &'a [u8],
}

impl Frame<'_> {
    pub fn length_ok(&self) -> bool {
        self.total_len as usize == self.raw.len()
    }
}

pub fn parse_frame(raw: &[u8]) -> Result<Frame<'_>> {
    if raw.len() < HEADER_LEN {
        return Err(Error::Short);
    }
    if raw[0] != MAGIC {
        return Err(Error::BadMagic);
    }
    Ok(Frame { op: raw[1], index: raw[2], total_len: le_u32(raw, 3)?, payload: &raw[HEADER_LEN..], raw })
}

/// Read-data request: 11 bytes (hypothesis, kext; same bytes as mesa_probe's verified `80 13 00 0b ...`).
pub fn build_read_request(size: u32) -> [u8; 11] {
    let mut r = [MAGIC, OP_READ_DATA, 0, 0x0B, 0, 0, 0, 0, 0, 0, 0];
    r[7..].copy_from_slice(&size.to_le_bytes());
    r
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Status<'a> {
    pub frame: Frame<'a>,
}

impl Status<'_> {
    /// Hypothesis (kext): 7 = data available.
    pub fn state_byte(&self) -> Option<u8> {
        self.frame.raw.get(7).copied()
    }
    /// Status byte 1 (frame byte 8): 0x29 after a loaded patch, 0x60 without (see `PATCH_LOADED`).
    pub fn patch_byte(&self) -> Option<u8> {
        self.frame.raw.get(8).copied()
    }
    /// Hypothesis (kext).
    pub fn avail_u32(&self) -> Option<u32> {
        le_u32(self.frame.raw, 12).ok()
    }
    pub fn trailer_u16(&self) -> Option<u16> {
        self.frame.raw.len().checked_sub(2).and_then(|o| le_u16(self.frame.raw, o).ok())
    }
    /// False on the observed init status (full status format unknown).
    pub fn trailer_is_crc16_arc(&self) -> bool {
        let r = self.frame.raw;
        r.len() >= 2 && self.trailer_u16() == Some(crc16_arc(&r[..r.len() - 2]))
    }
}

pub fn parse_status(raw: &[u8]) -> Result<Status<'_>> {
    let f = parse_frame(raw)?;
    if f.op != OP_STATUS {
        return Err(Error::Unexpected("opcode is not status"));
    }
    Ok(Status { frame: f })
}

#[cfg(feature = "alloc")]
/// Bytes of a uart line `... SensorStatus:    16B | 80 20 ...`, None if absent.
pub fn status_from_uart_line(line: &str) -> Option<Result<alloc::vec::Vec<u8>>> {
    let i = line.find("SensorStatus:")?;
    let rest = line[i + "SensorStatus:".len()..].trim_start();
    let b = rest.find('B')?;
    let n: usize = rest[..b].parse().ok()?;
    let after = rest[b + 1..].trim_start().strip_prefix('|')?;
    let mut raw = alloc::vec::Vec::new();
    for tok in after.split_whitespace() {
        if tok.len() != 2 {
            break;
        }
        match u8::from_str_radix(tok, 16) {
            Ok(v) if tok.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) => raw.push(v),
            _ => break,
        }
    }
    if raw.is_empty() {
        return None;
    }
    Some(if raw.len() == n { Ok(raw) } else { Err(Error::Unexpected("announced length differs")) })
}

#[cfg(test)]
mod tests {
    use super::*;
    const STATUS: [u8; 16] = [0x80, 0x20, 0, 0x10, 0, 0, 0, 0, 0x60, 0, 0, 0, 0x52, 0x33, 0, 0];

    #[test]
    fn status_constant() {
        let s = parse_status(&STATUS).unwrap();
        assert_eq!((s.frame.op, s.frame.index, s.frame.total_len), (0x20, 0, 0x10));
        assert!(s.frame.length_ok());
        assert_eq!(s.frame.payload.len(), 9);
        assert_eq!((s.state_byte(), s.avail_u32()), (Some(0), Some(0x3352)));
        assert!(!s.trailer_is_crc16_arc());
        assert_eq!(crc16_arc(&STATUS[..14]), 0x35DE);
    }

    #[test]
    fn bad() {
        assert!(parse_frame(&[0, 0x20, 0]).is_err());
        assert!(parse_status(&[0x80, 0x13, 0, 0x0B, 0, 0, 0]).is_err());
    }

    #[test]
    fn read_request() {
        let r = build_read_request(0x7200);
        let f = parse_frame(&r).unwrap();
        assert_eq!((f.op, f.total_len), (0x13, 0x0B));
        assert_eq!(u32::from_le_bytes([r[7], r[8], r[9], r[10]]), 0x7200);
        // Same request as mesa_probe for the 0x1b-byte identity (verified on hardware).
        assert_eq!(build_read_request(0x1b), [0x80, 0x13, 0, 0x0b, 0, 0, 0, 0x1b, 0, 0, 0]);
    }

    #[test]
    fn relay_frames() {
        let mut b = [0u8; 0x80];
        let n = build_relay_frame(OP_KEY_EXCHANGE, &[0xaa; 40], &mut b).unwrap();
        assert_eq!((n, &b[..7]), (0x2f, &[0x80, 0x72, 0, 0x2f, 0, 0, 0][..]));
        let n = build_relay_frame(OP_SEQ_COUNTER, &[0xbb; 64], &mut b).unwrap();
        assert_eq!((n, &b[..7]), (0x47, &[0x80, 0x73, 0, 0x47, 0, 0, 0][..]));
        assert!(build_relay_frame(0x72, &[0; 0xf9], &mut [0u8; 0x200]).is_err());
        assert_eq!(&IDENTITY_J314C[SERIAL_RANGE], &[0x02, 0x19, 0xc0, 0x5c, 0x0f, 0xd2, 0xaa, 0x34, 0x9a, 0x81, 0xc7, 0x6e, 0x03, 0x02, 0x00, 0xd8]);
        let st = [0x80, 0x20, 0, 0x10, 0, 0, 0, 0, 0x29, 1, 0, 0x7c, 0x52, 0x33, 0, 0x16];
        assert_eq!(parse_status(&st).unwrap().patch_byte(), Some(PATCH_LOADED));
    }

    /// Frames and answers of the macOS capture C19 (`analysis/sio_dialog.py … --sep --full`, sio.log seq 774/792/808).
    #[cfg(feature = "alloc")]
    #[test]
    fn param_frames_c19() {
        let h = |s: &str| (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect::<alloc::vec::Vec<u8>>();
        let f5d = h("805500400000003a0000000000001e572d5946f00000174c07d774f7122921bd098849d431eaab2a7a1b8604710a8bab6724333fda700166ca6c00f3a41d0017");
        let f31 = h("805500490000003a0000000000001e572d5946f200002069474d093c068973e1478dc1564ac68f74586fd8369e48f53db3ddd733c2a05138876e87a892b9f39c0fa224a8ad8a12959a");
        for f in [&f5d, &f31] {
            let mut b = [0u8; 0x100];
            let n = build_param_frame(&f[7..f.len() - 2], &mut b).unwrap();
            assert_eq!(&b[..n], &f[..]);
        }
        assert_eq!((f5d.len(), f31.len()), (0x40, 0x49));
        let a = h("80d4004b00000000753a8000000000001e572d5946f00000201c14945eba10d2cb015fa8282f9b8d65c4aa2b3fb576d34b5160f0a730fbb638beb44a91fc608015df4e3640e8fb5281df7e");
        assert_eq!(serial_answer_payload(&a).unwrap(), &a[9..73]);
        let mut bad = a.clone();
        bad[20] ^= 1;
        assert!(serial_answer_payload(&bad).is_err());
        assert!(serial_answer_payload(&a[..74]).is_err());
        assert!(build_param_frame(&[0; 0xf7], &mut [0u8; 0x200]).is_err());
    }

    #[test]
    fn identity_frame() {
        let f = parse_frame(&IDENTITY_J314C).unwrap();
        assert_eq!((f.op, f.total_len), (0xd4, 0x1b));
        assert!(f.length_ok());
    }

    #[cfg(feature = "alloc")]
    #[test]
    fn uart_line() {
        let l = "x SensorStatus:    16B | 80 20 00 10 00 00 00 00 60 00 00 00 52 33 00 00";
        assert_eq!(status_from_uart_line(l).unwrap().unwrap(), STATUS);
        assert!(status_from_uart_line("nothing").is_none());
    }
}
