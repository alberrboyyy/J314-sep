//! Step 1: the 64-bit mailbox word.
//!
//! Bits 0-7 EP, 8-15 TAG, 16-23 TYPE, 24-31 PARAM, 32-63 DATA. Status: hypothesis (consistent), very solid for reading
//! (`docs/verification_status.md`); the only `verified` status on the macOS side is the GT encoding (see `gt`).
use crate::{Error, Result};

/// Message direction, as written by the tracer (`>` AP->SEP, `<` SEP->AP).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Dir {
    ToSep,
    ToAp,
}

/// A decoded mailbox message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Word {
    pub ep: u8,
    pub tag: u8,
    pub ty: u8,
    pub param: u8,
    pub data: u32,
}

impl Word {
    pub const fn new(ep: u8, tag: u8, ty: u8, param: u8, data: u32) -> Self {
        Word { ep, tag, ty, param, data }
    }

    pub const fn decode(w: u64) -> Self {
        Word {
            ep: w as u8,
            tag: (w >> 8) as u8,
            ty: (w >> 16) as u8,
            param: (w >> 24) as u8,
            data: (w >> 32) as u32,
        }
    }

    pub const fn encode(&self) -> u64 {
        self.ep as u64 | (self.tag as u64) << 8 | (self.ty as u64) << 16 | (self.param as u64) << 24 | (self.data as u64) << 32
    }

    /// Checked construction from wide integers (as the Python `encode_word` does).
    pub fn checked(ep: u64, tag: u64, ty: u64, param: u64, data: u64) -> Result<Self> {
        fn b(n: &'static str, v: u64, max: u64) -> Result<u64> {
            if v > max { Err(Error::OutOfRange(n, v)) } else { Ok(v) }
        }
        Ok(Word::new(
            b("ep", ep, 0xFF)? as u8,
            b("tag", tag, 0xFF)? as u8,
            b("type", ty, 0xFF)? as u8,
            b("param", param, 0xFF)? as u8,
            b("data", data, 0xFFFF_FFFF)? as u32,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn layout() {
        let w = Word::decode(0x11223344_55667788);
        assert_eq!(w, Word::new(0x88, 0x77, 0x66, 0x55, 0x11223344));
        assert_eq!(w.encode(), 0x11223344_55667788);
    }
    #[test]
    fn range() {
        assert!(Word::checked(0x100, 0, 0, 0, 0).is_err());
        assert!(Word::checked(0, 0, 0, 0, 1 << 32).is_err());
    }
}

/// A message seen on the mailbox, with its direction and (for traces) its line number.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Msg {
    pub lineno: u32,
    pub dir: Dir,
    pub w: Word,
}

impl Msg {
    pub const fn new(lineno: u32, dir: Dir, w: Word) -> Self {
        Msg { lineno, dir, w }
    }
    pub const fn to_sep(self) -> bool {
        matches!(self.dir, Dir::ToSep)
    }
}
