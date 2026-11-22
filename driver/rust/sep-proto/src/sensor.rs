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
