//! `sep-proto`: AP<->SEP protocol for the j314c Touch ID driver, in Rust.
//!
//! Port of `driver/sepreplay/` (the Python reference), validated against the same captures in `traces/`.
//! **Pure computation**: no mailbox, no device, no write to the SEP. The core is `no_std` + `alloc` so the
//! future kernel module (Rust for Linux) can reuse it as is; trace reading (`trace`) needs the `std` feature.
//!
//! The status of every message (verified / hypothesis) is the one in `docs/verification_status.md`, repeated in
//! each module. Nothing here is copied from Apple code.
#![cfg_attr(not(feature = "std"), no_std)]
#![forbid(unsafe_code)]

extern crate alloc;

pub mod crc;
pub mod daemon;
pub mod discovery;
pub mod gt;
pub mod sensor;
pub mod word;
pub mod xart;
pub mod xart_responder;

#[cfg(feature = "std")]
pub mod trace;

/// Protocol error. No panics on input data: every decoder returns `Result`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// A field does not fit in its width (`field`, value).
    OutOfRange(&'static str, u64),
    /// Buffer too short for the expected structure.
    Short,
    /// Missing magic number or marker.
    BadMagic,
    /// Message or sequence the protocol does not model (fail-closed).
    Unexpected(&'static str),
}

impl core::fmt::Display for Error {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Error::OutOfRange(n, v) => write!(f, "{n} out of range: {v:#x}"),
            Error::Short => f.write_str("buffer too short"),
            Error::BadMagic => f.write_str("bad magic"),
            Error::Unexpected(s) => write!(f, "unexpected: {s}"),
        }
    }
}

#[cfg(feature = "std")]
impl std::error::Error for Error {}

pub type Result<T> = core::result::Result<T, Error>;

/// Little-endian read helpers (no panics).
pub(crate) fn le_u32(b: &[u8], off: usize) -> Result<u32> {
    b.get(off..off + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]])).ok_or(Error::Short)
}
pub(crate) fn le_u16(b: &[u8], off: usize) -> Result<u16> {
    b.get(off..off + 2).map(|s| u16::from_le_bytes([s[0], s[1]])).ok_or(Error::Short)
}
