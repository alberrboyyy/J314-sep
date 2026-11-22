//! Step 5: offline "daemon": sbio init sequence + keeping/replaying catacomb blobs (0x6c export -> 0x6d import).
//!
//! NO EMISSION: produces the list of commands a future driver would send, to compare with what macOS sent.
//! Status: init sequence (57 first `> fc` commands) = **verified (macOS)**, K6 (18/18 captures with sbio).
//! 0x6c -> 0x6d loop (`LTFC`) = **verified (macOS)**. Content encrypted/opaque, not interpreted.
//! Import order "small blob (uid -1) then big (user uid)": observed in 5 boots, proposed.
use crate::{le_u32, Error, Result};
#[cfg(feature = "alloc")]
use alloc::{collections::BTreeMap, vec::Vec};

pub const INIT_SEQUENCE: [u8; 57] = [
    0x73, //
    0x17, 0x15, 0x16, 0x42, 0x18, 0x5f, 0x5d, 0x5c, 0x6a, 0x31, 0x32, 0x01, 0x1f, 0x31, 0x32, 0x5b, 0x63, //
    0x19, //
    0x17, 0x15, 0x16, 0x42, 0x18, 0x5f, 0x5d, 0x5c, 0x6a, 0x6f, 0x31, 0x32, 0x01, 0x1f, 0x63, 0x63, //
    0x7c, 0x6b, 0x79, 0x6d, 0x39, 0x6b, 0x79, 0x6b, 0x79, 0x6d, 0x2b, 0x6b, 0x79, 0x54, 0x2b, 0x33, 0x36, 0x6e, 0x7a,
    0x71, 0x28, 0x7c,
];

pub const T_EXPORT: u8 = 0x6C;
pub const T_IMPORT: u8 = 0x6D;
pub const MAGIC: &[u8; 4] = b"LTFC";
pub const UID_NONE: u32 = 0xFFFF_FFFF;

pub fn blob_uid(blob: &[u8]) -> Result<u32> {
    if blob.len() < 12 || &blob[..4] != MAGIC {
        return Err(Error::BadMagic);
    }
    le_u32(blob, 8)
}

/// 0x6c request: 0x18 bytes = uid u32 LE then zeros.
pub fn export_request(uid: u32) -> [u8; 0x18] {
    let mut r = [0u8; 0x18];
    r[..4].copy_from_slice(&uid.to_le_bytes());
    r
}

#[cfg(feature = "alloc")]
/// Last exported blob per uid (the SEP does not keep its templates: the AP does).
#[derive(Debug, Default, Clone)]
pub struct BlobStore {
    pub blobs: BTreeMap<u32, Vec<u8>>,
}

#[cfg(feature = "alloc")]
impl BlobStore {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn on_export(&mut self, blob: &[u8]) -> Result<()> {
        self.blobs.insert(blob_uid(blob)?, blob.to_vec());
        Ok(())
    }
    /// Observed: uid -1 first, then user uids (only 501 tested).
    pub fn import_order(&self) -> Vec<u32> {
        let mut v: Vec<u32> = self.blobs.keys().copied().collect();
        v.sort_by_key(|&u| (u != UID_NONE, u));
        v
    }
}

#[cfg(feature = "alloc")]
/// (TYPE, payload or None) of the init commands. Payloads are only provided for 0x6d (import).
pub fn init_plan(store: &BlobStore) -> Vec<(u8, Option<&[u8]>)> {
    let imports: Vec<&[u8]> = store.import_order().into_iter().map(|u| store.blobs[&u].as_slice()).collect();
    let mut k = 0;
    INIT_SEQUENCE
        .iter()
        .map(|&t| {
            if t == T_IMPORT {
                let p = imports.get(k).copied();
                k += 1;
                (t, p)
            } else {
                (t, None)
            }
        })
        .collect()
}

#[cfg(all(test, feature = "alloc"))]
mod tests {
    use super::*;
    #[test]
    fn plan_without_store() {
        let s = BlobStore::new();
        let p = init_plan(&s);
        assert_eq!(p.iter().map(|c| c.0).collect::<Vec<_>>(), INIT_SEQUENCE);
        assert_eq!(p.iter().filter(|c| c.0 == T_IMPORT).count(), 2);
        assert!(p.iter().all(|c| c.1.is_none()));
    }
    #[test]
    fn wrong_blob() {
        let mut b = b"XXXX".to_vec();
        b.resize(44, 0);
        assert!(BlobStore::new().on_export(&b).is_err());
    }
}
