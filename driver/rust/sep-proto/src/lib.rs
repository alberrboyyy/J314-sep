//! `sep-proto`: AP<->SEP protocol for the j314c Touch ID driver, in Rust.
//!
//! Port of `driver/sepreplay/` (the Python reference), validated against the same captures in `traces/`.
//! **Pure computation**: no mailbox, no device, no write to the SEP. The core is `no_std`; the parts that
//! need heap collections (`Vec`, `BTreeMap`) are behind the `alloc` feature, so the allocation-free core builds
//! with neither `std` nor `alloc` (the kernel module `kmod/sep_proto_selftest.rs` embeds it that way). Trace
//! reading (`trace`) needs the `std` feature.
//!
//! The status of every message (verified / hypothesis) is the one in `docs/verification_status.md`, repeated in
//! each module. Nothing here is copied from Apple code.
#![cfg_attr(not(feature = "std"), no_std)]
#![forbid(unsafe_code)]

#[cfg(feature = "alloc")]
extern crate alloc;

mod common;
pub use common::{Error, Result};
pub(crate) use common::{le_u16, le_u32};

pub mod bio;
pub mod crc;
pub mod daemon;
pub mod discovery;
pub mod gt;
pub mod hash;
pub mod ks_gate;
pub mod sbio_gate;
pub mod sensor;
pub mod sks_ipc;
pub mod sks_keybag;
pub mod sks_nulldkey;
pub mod sks_setenv;
pub mod word;
pub mod xart;
pub mod xart_responder;
pub mod xart_gate;

#[cfg(feature = "std")]
pub mod trace;

#[cfg(feature = "std")]
impl std::error::Error for Error {}
