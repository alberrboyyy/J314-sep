//! SKS (EP 0x12) IPC frames of experiment J10 (`docs/sks_native_plan.md` § J10): the device-identity keybag path,
//! two chained transactions sent right after `get_capabilities` (0x4d) and `set_env` (0x2a), SKIPPING the two
//! `perform_operation` and `null_d_key`:
//!   1. `load_keybag`        (TAG fil 0x03) — imports a 16-byte blob (uuid) and RETURNS a keybag handle;
//!   2. `make_system_keybag` (TAG fil 0x0d) — marks that handle as the system keybag (status only, no handle).
//!
//! No allocation, no `std`: this file is also included as is by the kernel module (`kmod/sep_native.rs`), which uses
//! it to CHECK the two requests written by userspace and to finalize `make_system_keybag` (plug in the handle that
//! `load_keybag` returned, then re-digest). It reuses the IPC header primitives of `sks_ipc` (same header layout,
//! same v2 digest function).
//!
//! **SKELETON — NOT RUNNABLE until three userland values exist.** Byte layout established by DISASSEMBLY
//! (`docs/keybag_native_path.md` § J10, `source: kext` 27.2.1, bundle `com.apple.driver.AppleSEPKeyStore`), VU:
//!   - `__ipc_load_keybag` @0xcdb934 / `_code_ipc_load_keybag` @0xcde92c: header + state(u32=0) + handle_y(u64) +
//!     blob{len=0x10, 16 bytes of uuid}. The reply carries the SEP-assigned handle (a u32); the AP reads it back.
//!   - `__ipc_make_system_keybag_v1` @0xcdbce4 / `_code_ipc_make_system_keybag` @0xce0134: header + state(u32=1,
//!     the codec takes the state==1 branch) + handle_y(u64) + loaded_handle(u32) + type(u32) + blob{len=0} +
//!     flag(u64=0). On the identity path the blob is EMPTY and the flag is 0 (VU x5=x6=0, x7=0).
//!
//! **Three values are USERLAND and NOT derivable from the binary** (`docs/keybag_native_path.md` § J10.1), so none has
//! a default here and the kernel gate NEVER checks their value:
//!   1. `uuid`      — 16 bytes, the `load_keybag` blob (VU constraint: length == 16);
//!   2. `handle_y`  — u64, the parent/session keybag handle (OOL 0x58 of both frames);
//!   3. `type`      — i32, the keybag type (OOL 0x64 of `make_system_keybag`; VU constraint: type <= -10).
//!
//! The fourth field, `loaded_handle` (OOL 0x60 of `make_system_keybag`), is DYNAMIC: it is the handle the SEP
//! returned from `load_keybag`, read at run time and plugged in by the kernel (`finalize_mskb`), never invented.
//!
//! Written from the docs above (`source: kext`, NOT verified on hardware); nothing is copied from Apple code. Every
//! scalar is little-endian. This whole path is a NEW write class → it only runs behind Albert's "go".
use crate::sks_ipc::{
    cdhash_kind, frame_digest, CdhashKind, GetcapFields, CDHASH_LEN, DIGEST_LEN, EP_SKS, HDR_LEN_AP, OFF_ARG,
    OFF_CDHASH, OFF_DIGEST, OFF_F20, OFF_FLAGS, OFF_HLEN, OFF_STATE, OFF_TS, OFF_UID, OFF_UNIQUEID, OFF_VERSION,
    OFF_X48,
};
use crate::word::Word;
use crate::{Error, Result};

/// Negotiated header version (v2; these frames follow get_capabilities/set_env).
pub const HDR_VERSION_V2: u32 = 2;

// --- load_keybag (TAG fil 0x03) ------------------------------------------------------------------------------------
pub const OP_LOAD_KEYBAG: u8 = 0x03;
/// Third transaction of J10 (get_capabilities = 1, set_env = 2, load_keybag = 3).
pub const LKB_TXN: u8 = 0x03;
pub const LKB_LEN: usize = 0x74;
pub const LKB_DATA: u32 = (LKB_LEN as u32) << 16;
/// `handle_y` (u64) lives where the constant u64 of get_capabilities lived (OOL 0x58).
pub const OFF_HANDLE_Y: usize = OFF_ARG; // 0x58
pub const OFF_LKB_BLOBLEN: usize = 0x60;
pub const OFF_LKB_UUID: usize = 0x64;
pub const UUID_LEN: usize = 16;
/// Constant blob length of `load_keybag` (VU `w3 = 0x10`).
pub const LKB_BLOBLEN: u32 = 0x10;
/// State word of `load_keybag` (OOL 0x54): 0.
pub const LKB_STATE: u32 = 0;
/// Reply TAG of `load_keybag` (= request | 0x80).
pub const LKB_REPLY_TAG: u8 = OP_LOAD_KEYBAG | 0x80; // 0x83
/// Offset in OOL B where the SEP-assigned handle is read back (u32). `docs/keybag_native_path.md` § J10.4:
/// the OOL 0x12 was never captured, so this offset is DEDUCED and must be confirmed on hardware.
pub const OFF_RESP_HANDLE: usize = 0x6c;

// --- make_system_keybag (TAG fil 0x0d) -----------------------------------------------------------------------------
pub const OP_MAKE_SYSTEM_KEYBAG: u8 = 0x0d;
/// Fourth transaction of J10 (load_keybag = 3, make_system_keybag = 4).
pub const MSKB_TXN: u8 = 0x04;
pub const MSKB_LEN: usize = 0x74;
pub const MSKB_DATA: u32 = (MSKB_LEN as u32) << 16;
pub const OFF_MSKB_LOADED: usize = 0x60;
pub const OFF_MSKB_TYPE: usize = 0x64;
pub const OFF_MSKB_BLOBLEN: usize = 0x68;
pub const OFF_MSKB_FLAG: usize = 0x6c;
/// State word of `make_system_keybag` (OOL 0x54): 1 (codec takes the state==1 branch; VU const @0x770fec8).
pub const MSKB_STATE: u32 = 1;
/// Blob length (OOL 0x68): 0 on the identity path (empty blob; VU).
pub const MSKB_BLOBLEN: u32 = 0;
/// Flag (OOL 0x6c, u64): 0 on the identity path (VU x7 = 0).
pub const MSKB_FLAG: u64 = 0;
/// Reply TAG of `make_system_keybag` (= request | 0x80).
pub const MSKB_REPLY_TAG: u8 = OP_MAKE_SYSTEM_KEYBAG | 0x80; // 0x8d

const _: () = assert!(LKB_LEN == 0x54 + 4 + 8 + 4 + UUID_LEN);
const _: () = assert!(MSKB_LEN == 0x54 + 4 + 8 + 4 + 4 + 4 + 8);
const _: () = assert!(OFF_RESP_HANDLE + 4 <= crate::sks_ipc::OUT_SNAP);

fn le32(b: &[u8], o: usize) -> Result<u32> {
    b.get(o..o + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]])).ok_or(Error::Short)
}
fn le64(b: &[u8], o: usize) -> Result<u64> {
    let s = b.get(o..o + 8).ok_or(Error::Short)?;
    Ok(u64::from_le_bytes([s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7]]))
}

/// The common IPC header + process block, shared by both frames (same as get_capabilities/set_env, v2).
fn write_header(b: &mut [u8], f: &KeybagFields) {
    b[OFF_HLEN..OFF_HLEN + 4].copy_from_slice(&HDR_LEN_AP.to_le_bytes());
    b[OFF_VERSION..OFF_VERSION + 4].copy_from_slice(&HDR_VERSION_V2.to_le_bytes());
    b[OFF_TS..OFF_TS + 8].copy_from_slice(&f.ts_us.to_le_bytes());
    // flags (0x20), field +0x20 (0x24), 0x4c..0x54: zeros.
    b[OFF_UNIQUEID..OFF_UNIQUEID + 8].copy_from_slice(&f.uniqueid.to_le_bytes());
    b[OFF_UID..OFF_UID + 4].copy_from_slice(&f.uid.to_le_bytes());
    b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN].copy_from_slice(&f.cdhash);
}

fn check_header_constants(b: &[u8]) -> Result<()> {
    let want32 = |o: usize, v: u32, what: &'static str| -> Result<()> {
        let x = le32(b, o)?;
        if x == v { Ok(()) } else { Err(Error::OutOfRange(what, u64::from(x))) }
    };
    let want64 = |o: usize, v: u64, what: &'static str| -> Result<()> {
        let x = le64(b, o)?;
        if x == v { Ok(()) } else { Err(Error::OutOfRange(what, x)) }
    };
    want32(OFF_HLEN, HDR_LEN_AP, "header length (0x00) != 0x50")?;
    want32(OFF_VERSION, HDR_VERSION_V2, "header version (0x14) != 2")?;
    want32(OFF_FLAGS, 0, "flags (0x20) != 0")?;
    want64(OFF_F20, 0, "field +0x20 (0x24) != 0")?;
    want64(OFF_X48, 0, "context 0x48 (0x4c) != 0")?;
    Ok(())
}

fn read_cdhash(b: &[u8]) -> [u8; CDHASH_LEN] {
    let mut cdhash = [0u8; CDHASH_LEN];
    cdhash.copy_from_slice(&b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN]);
    cdhash
}

/// Contextual header fields shared by both frames (same shape as `GetcapFields`). The THREE userland values (uuid,
/// handle_y, type) are carried separately, per frame, because they are free and not part of the header.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeybagFields {
    pub ts_us: u64,
    pub uniqueid: u64,
    pub uid: u32,
    pub cdhash: [u8; CDHASH_LEN],
}

impl KeybagFields {
    fn header(&self) -> GetcapFields {
        GetcapFields { ts_us: self.ts_us, uniqueid: self.uniqueid, uid: self.uid, cdhash: self.cdhash }
    }
}

// =================================================================================================================
// load_keybag
// =================================================================================================================

/// The exact `load_keybag` request word (the only one the driver may ever send for this op).
pub const fn loadkeybag_word() -> Word {
    Word::new(EP_SKS, OP_LOAD_KEYBAG, LKB_TXN, 0, LKB_DATA)
}

/// Builds the 0x74 bytes of `load_keybag`. `handle_y` and `uuid` are USERLAND values (no default); the digest is
/// computed last over the v2 base. The uuid is written verbatim (16 bytes).
pub fn encode_loadkeybag(f: &KeybagFields, handle_y: u64, uuid: &[u8; UUID_LEN]) -> [u8; LKB_LEN] {
    let mut b = [0u8; LKB_LEN];
    write_header(&mut b, f);
    // state (0x54) = 0 (left zero).
    b[OFF_HANDLE_Y..OFF_HANDLE_Y + 8].copy_from_slice(&handle_y.to_le_bytes());
    b[OFF_LKB_BLOBLEN..OFF_LKB_BLOBLEN + 4].copy_from_slice(&LKB_BLOBLEN.to_le_bytes());
    b[OFF_LKB_UUID..OFF_LKB_UUID + UUID_LEN].copy_from_slice(uuid);
    let d = frame_digest(&b, HDR_VERSION_V2, OFF_STATE, LKB_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// What the kernel gate reads back from a `load_keybag` request (the userland values, for the journal only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LoadkeybagReq {
    pub fields: KeybagFields,
    pub handle_y: u64,
    pub uuid: [u8; UUID_LEN],
}

/// Kernel gate on the 0x74 bytes of `load_keybag`: exact length, the CONSTANT fields (header constants, state 0,
/// blob length 0x10), the v2 digest recomputed, cdhash in one of the two documented AP forms. The THREE userland
/// values (handle_y, uuid) are NOT constrained (they are free, supplied by the tool). Returns them for the log.
pub fn check_loadkeybag(b: &[u8]) -> Result<LoadkeybagReq> {
    if b.len() != LKB_LEN {
        return Err(Error::OutOfRange("load_keybag request length", b.len() as u64));
    }
    check_header_constants(b)?;
    let state = le32(b, OFF_STATE)?;
    if state != LKB_STATE {
        return Err(Error::OutOfRange("load_keybag state (0x54) != 0", u64::from(state)));
    }
    let bloblen = le32(b, OFF_LKB_BLOBLEN)?;
    if bloblen != LKB_BLOBLEN {
        return Err(Error::OutOfRange("load_keybag blob length (0x60) != 0x10", u64::from(bloblen)));
    }
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, LKB_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("load_keybag digest (0x04) != SHA-256/16 of the documented v2 base"));
    }
    let fields = KeybagFields { ts_us: le64(b, OFF_TS)?, uniqueid: le64(b, OFF_UNIQUEID)?, uid: le32(b, OFF_UID)?, cdhash: read_cdhash(b) };
    if cdhash_kind(&fields.header()) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    let mut uuid = [0u8; UUID_LEN];
    uuid.copy_from_slice(&b[OFF_LKB_UUID..OFF_LKB_UUID + UUID_LEN]);
    Ok(LoadkeybagReq { fields, handle_y: le64(b, OFF_HANDLE_Y)?, uuid })
}

/// `true` iff `w` is a reply to our `load_keybag` as the kext matches it: EP 0x12, TAG bit 7 set, TYPE = our txn.
pub fn is_loadkeybag_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == LKB_TXN
}

/// Reads the SEP-assigned keybag handle from a `load_keybag` reply snapshot (OOL B), at `OFF_RESP_HANDLE` (DEDUCED,
/// never captured). Only meaningful when the reply word had PARAM 0.
pub fn reply_handle(snap: &[u8]) -> Result<u32> {
    le32(snap, OFF_RESP_HANDLE)
}

// =================================================================================================================
// make_system_keybag
// =================================================================================================================

/// The exact `make_system_keybag` request word (the only one the driver may ever send for this op).
pub const fn mskb_word() -> Word {
    Word::new(EP_SKS, OP_MAKE_SYSTEM_KEYBAG, MSKB_TXN, 0, MSKB_DATA)
}

/// Builds the 0x74 bytes of `make_system_keybag`. `handle_y` and `type` are USERLAND values (no default);
/// `loaded_handle` is the handle `load_keybag` returned (the tool puts a placeholder — default 0 — because the
/// KERNEL plugs in the real one at send time via `finalize_mskb`, then re-digests). Digest computed last.
pub fn encode_mskb(f: &KeybagFields, handle_y: u64, loaded_handle: u32, keybag_type: i32) -> [u8; MSKB_LEN] {
    let mut b = [0u8; MSKB_LEN];
    write_header(&mut b, f);
    b[OFF_STATE..OFF_STATE + 4].copy_from_slice(&MSKB_STATE.to_le_bytes());
    b[OFF_HANDLE_Y..OFF_HANDLE_Y + 8].copy_from_slice(&handle_y.to_le_bytes());
    b[OFF_MSKB_LOADED..OFF_MSKB_LOADED + 4].copy_from_slice(&loaded_handle.to_le_bytes());
    b[OFF_MSKB_TYPE..OFF_MSKB_TYPE + 4].copy_from_slice(&keybag_type.to_le_bytes());
    // blob length (0x68) = 0, flag (0x6c) = 0: left zero.
    let d = frame_digest(&b, HDR_VERSION_V2, OFF_STATE, MSKB_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// Writes the real `loaded_handle` (the one `load_keybag` returned) into a checked `make_system_keybag` request and
/// recomputes the v2 digest. Called by the kernel at send time (never invents a handle). Returns the finalized bytes.
pub fn finalize_mskb(b: &mut [u8; MSKB_LEN], loaded_handle: u32) {
    b[OFF_MSKB_LOADED..OFF_MSKB_LOADED + 4].copy_from_slice(&loaded_handle.to_le_bytes());
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, MSKB_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
}

/// What the kernel gate reads back from a `make_system_keybag` request (userland values, for the log only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MskbReq {
    pub fields: KeybagFields,
    pub handle_y: u64,
    pub loaded_handle: u32,
    pub keybag_type: i32,
}

/// Kernel gate on the 0x74 bytes of `make_system_keybag`: exact length, the CONSTANT fields (header constants,
/// state 1, blob length 0 = empty blob, flag 0), the v2 digest recomputed, cdhash in one of the two documented AP
/// forms. NOT constrained: handle_y and type (userland, free) and loaded_handle (dynamic, overwritten by the kernel
/// via `finalize_mskb`). The digest is checked over the bytes AS SUPPLIED (loaded_handle placeholder); the kernel
/// re-digests after plugging in the real handle.
pub fn check_mskb(b: &[u8]) -> Result<MskbReq> {
    if b.len() != MSKB_LEN {
        return Err(Error::OutOfRange("make_system_keybag request length", b.len() as u64));
    }
    check_header_constants(b)?;
    let state = le32(b, OFF_STATE)?;
    if state != MSKB_STATE {
        return Err(Error::OutOfRange("make_system_keybag state (0x54) != 1", u64::from(state)));
    }
    let bloblen = le32(b, OFF_MSKB_BLOBLEN)?;
    if bloblen != MSKB_BLOBLEN {
        return Err(Error::OutOfRange("make_system_keybag blob length (0x68) != 0 (empty blob)", u64::from(bloblen)));
    }
    let flag = le64(b, OFF_MSKB_FLAG)?;
    if flag != MSKB_FLAG {
        return Err(Error::OutOfRange("make_system_keybag flag (0x6c) != 0", flag));
    }
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, MSKB_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("make_system_keybag digest (0x04) != SHA-256/16 of the documented v2 base"));
    }
    let fields = KeybagFields { ts_us: le64(b, OFF_TS)?, uniqueid: le64(b, OFF_UNIQUEID)?, uid: le32(b, OFF_UID)?, cdhash: read_cdhash(b) };
    if cdhash_kind(&fields.header()) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    Ok(MskbReq {
        fields,
        handle_y: le64(b, OFF_HANDLE_Y)?,
        loaded_handle: le32(b, OFF_MSKB_LOADED)?,
        keybag_type: le32(b, OFF_MSKB_TYPE)? as i32,
    })
}

/// `true` iff `w` is a reply to our `make_system_keybag`: EP 0x12, TAG bit 7 set, TYPE = our txn.
pub fn is_mskb_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == MSKB_TXN
}

/// Re-exported from `sks_ipc`: reply word shape (PARAM = signed status, DATA = len<<16 | call flags).
pub use crate::sks_ipc::reply_word;

/// VU constraint on `type` (`docs/keybag_native_path.md` § J10.1): `identity_load` rejects `type > -10`. This is a
/// hint for the tool (the kernel gate does NOT enforce it — `type` is a free userland value); `true` = within range.
pub fn type_in_vu_range(keybag_type: i32) -> bool {
    keybag_type <= -10
}

// --- send gates (one word each, once per boot) ---------------------------------------------------------------------

macro_rules! one_word_gate {
    ($name:ident, $word:expr) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct $name {
            armed: bool,
            used: bool,
        }
        impl $name {
            pub const fn closed() -> Self {
                $name { armed: false, used: false }
            }
            pub fn arm(&mut self) {
                if !self.used {
                    self.armed = true;
                }
            }
            pub fn admit(&mut self, w: &Word) -> bool {
                let ok = self.armed && !self.used && *w == $word;
                if ok {
                    self.armed = false;
                    self.used = true;
                }
                ok
            }
            pub fn used(&self) -> bool {
                self.used
            }
        }
    };
}

one_word_gate!(LoadkeybagGate, loadkeybag_word());
one_word_gate!(MskbGate, mskb_word());

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hash::sha256;
    use crate::sks_ipc::cdhash_no_process;

    // ARBITRARY example values — « exemple de test, PAS les vraies » (the real uuid/handle/type are unknown).
    const EX_TS: u64 = 0x1122_3344_5566_7788;
    const EX_HANDLE_Y: u64 = 0x4242_4242_4242_4242;
    const EX_TYPE: i32 = -16;
    fn ex_uuid() -> [u8; UUID_LEN] {
        let mut u = [0u8; UUID_LEN];
        for (i, x) in u.iter_mut().enumerate() {
            *x = i as u8;
        }
        u
    }
    fn fields() -> KeybagFields {
        KeybagFields { ts_us: EX_TS, uniqueid: 0, uid: 0, cdhash: cdhash_no_process(0) }
    }
    fn hex16(s: &str) -> [u8; 16] {
        let mut o = [0u8; 16];
        for (i, x) in o.iter_mut().enumerate() {
            *x = u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap();
        }
        o
    }
    fn hex32(s: &str) -> [u8; 32] {
        let mut o = [0u8; 32];
        for (i, x) in o.iter_mut().enumerate() {
            *x = u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap();
        }
        o
    }

    #[test]
    fn words_and_lengths() {
        assert_eq!(loadkeybag_word(), Word::new(0x12, 0x03, 0x03, 0x00, 0x0074_0000));
        assert_eq!(mskb_word(), Word::new(0x12, 0x0d, 0x04, 0x00, 0x0074_0000));
        assert_eq!(LKB_LEN, 0x74);
        assert_eq!(MSKB_LEN, 0x74);
        assert_eq!(LKB_REPLY_TAG, 0x83);
        assert_eq!(MSKB_REPLY_TAG, 0x8d);
    }

    #[test]
    fn loadkeybag_layout_and_reread() {
        let f = fields();
        let b = encode_loadkeybag(&f, EX_HANDLE_Y, &ex_uuid());
        assert_eq!(le32(&b, 0x00).unwrap(), 0x50);
        assert_eq!(le32(&b, 0x14).unwrap(), 2);
        assert_eq!(le64(&b, 0x18).unwrap(), EX_TS);
        assert_eq!(le32(&b, 0x54).unwrap(), 0); // state
        assert_eq!(le64(&b, 0x58).unwrap(), EX_HANDLE_Y); // handle_y
        assert_eq!(le32(&b, 0x60).unwrap(), 0x10); // blob len
        assert_eq!(&b[0x64..0x74], &ex_uuid());
        let r = check_loadkeybag(&b).unwrap();
        assert_eq!((r.fields, r.handle_y, r.uuid), (f, EX_HANDLE_Y, ex_uuid()));
    }

    #[test]
    fn mskb_layout_and_reread() {
        let f = fields();
        let b = encode_mskb(&f, EX_HANDLE_Y, 0, EX_TYPE);
        assert_eq!(le32(&b, 0x54).unwrap(), 1); // state const 1
        assert_eq!(le64(&b, 0x58).unwrap(), EX_HANDLE_Y); // handle_y
        assert_eq!(le32(&b, 0x60).unwrap(), 0); // loaded handle placeholder
        assert_eq!(le32(&b, 0x64).unwrap() as i32, EX_TYPE); // type
        assert_eq!(le32(&b, 0x68).unwrap(), 0); // blob len (empty)
        assert_eq!(le64(&b, 0x6c).unwrap(), 0); // flag
        let r = check_mskb(&b).unwrap();
        assert_eq!((r.fields, r.handle_y, r.loaded_handle, r.keybag_type), (f, EX_HANDLE_Y, 0, EX_TYPE));
    }

    /// Full-request fingerprint vs an independent Python/hashlib construction (session ALARM 2026-11-23,
    /// `/tmp/kb_vectors.py`). Values are the ARBITRARY example set, NOT the real userland values.
    #[test]
    fn requests_match_independent_construction() {
        let lkb = encode_loadkeybag(&fields(), EX_HANDLE_Y, &ex_uuid());
        assert_eq!(&lkb[0x04..0x14], &hex16("5fd02233027b4e0ab5d1197a292fcdcd"));
        assert_eq!(sha256(&lkb), hex32("0be85f870bd1271abc5d1578efa97b62ee5aa798c371e16fcd3d81cbc8602653"));

        let mskb = encode_mskb(&fields(), EX_HANDLE_Y, 0, EX_TYPE);
        assert_eq!(&mskb[0x04..0x14], &hex16("1dd1815887a6cbb6bcde7f7ba1e025a6"));
        assert_eq!(sha256(&mskb), hex32("e63f99788abbb84f295a395557f53817d4f09e1aee084fa93e7bd22ee0ca5250"));
    }

    /// v2 digest base built field by field independently of the encoder (§1.6.3/§1.7.1): for v2 it is simply
    /// SHA-256 of OOL bytes 0x14..end (header v2 + payload, contiguous), truncated to 16.
    #[test]
    fn digest_base_is_the_documented_v2_one() {
        let b = encode_loadkeybag(&fields(), EX_HANDLE_Y, &ex_uuid());
        assert_eq!(&b[0x04..0x14], &sha256(&b[0x14..])[..16]);
        let b2 = encode_mskb(&fields(), EX_HANDLE_Y, 0x1234_5678, EX_TYPE);
        assert_eq!(&b2[0x04..0x14], &sha256(&b2[0x14..])[..16]);
    }

    /// The kernel plugs in the real handle and re-digests: `finalize_mskb` must match a fresh `encode_mskb` with that
    /// handle, and the re-digest must agree with the independent Python vector for handle 0xdeadbeef.
    #[test]
    fn finalize_matches_fresh_encode_and_python() {
        let mut b = encode_mskb(&fields(), EX_HANDLE_Y, 0, EX_TYPE);
        finalize_mskb(&mut b, 0xdead_beef);
        assert_eq!(b, encode_mskb(&fields(), EX_HANDLE_Y, 0xdead_beef, EX_TYPE));
        assert_eq!(&b[0x04..0x14], &hex16("6199ea7f49ef764522e9077999ca9885"));
        assert_eq!(sha256(&b), hex32("95209ec0f003e4630fdec02a4a3672ebde087a8bbfba3d9c761af9c0dae9e54b"));
        assert_eq!(check_mskb(&b).unwrap().loaded_handle, 0xdead_beef);
    }

    #[test]
    fn gates_refuse_constant_changes() {
        // load_keybag: header constants, state, blob length are checked; handle_y and uuid are NOT.
        let good = encode_loadkeybag(&fields(), EX_HANDLE_Y, &ex_uuid());
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x60] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_loadkeybag(&b).is_err(), "lkb offset {o:#x}");
        }
        // handle_y (0x58) and uuid (0x64) are free: changing them (and re-digesting) is accepted.
        let other = encode_loadkeybag(&fields(), 0x99, &[0xee; UUID_LEN]);
        let r = check_loadkeybag(&other).unwrap();
        assert_eq!((r.handle_y, r.uuid), (0x99, [0xee; UUID_LEN]));
        // Contextual header field changed without re-digesting → refused (digest).
        let mut b = good;
        b[0x18] ^= 0x01;
        assert!(check_loadkeybag(&b).is_err());
        assert!(check_loadkeybag(&good[..0x73]).is_err());

        // make_system_keybag: header constants, state 1, blob length 0, flag 0 checked; handle_y/loaded/type NOT.
        let good2 = encode_mskb(&fields(), EX_HANDLE_Y, 0, EX_TYPE);
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x68, 0x6c] {
            let mut b = good2;
            b[o] ^= 0x01;
            assert!(check_mskb(&b).is_err(), "mskb offset {o:#x}");
        }
        // handle_y/loaded/type free: a different type (and re-digest) is accepted.
        let other2 = encode_mskb(&fields(), 0x7, 0x8, -42);
        let r2 = check_mskb(&other2).unwrap();
        assert_eq!((r2.handle_y, r2.loaded_handle, r2.keybag_type), (0x7, 0x8, -42));
    }

    #[test]
    fn reply_matching_and_handle() {
        // load_keybag reply: `< 0x12 TAG 0x83 TYPE 0x03 PARAM 0 DATA (len<<16)`.
        let w = Word::decode(0x0010_0000_0003_8312);
        assert!(is_loadkeybag_reply(&w));
        assert_eq!(reply_word(&w).status, 0);
        assert!(!is_loadkeybag_reply(&Word::new(0x12, 0x03, 0x03, 0, 0))); // request, bit 7 clear
        assert!(!is_loadkeybag_reply(&Word::new(0x12, 0x8d, 0x04, 0, 0))); // mskb reply (TYPE 4)
        let mut snap = [0u8; crate::sks_ipc::OUT_SNAP];
        snap[OFF_RESP_HANDLE..OFF_RESP_HANDLE + 4].copy_from_slice(&0x0abc_def0u32.to_le_bytes());
        assert_eq!(reply_handle(&snap).unwrap(), 0x0abc_def0);

        // make_system_keybag reply: `< 0x12 TAG 0x8d TYPE 0x04 PARAM s DATA ...`. PARAM 0 = OK, != 0 = refus.
        let ok = Word::new(0x12, 0x8d, 0x04, 0x00, 0);
        assert!(is_mskb_reply(&ok));
        assert_eq!(reply_word(&ok).status, 0);
        assert_eq!(reply_word(&Word::new(0x12, 0x8d, 0x04, 0xff, 0)).status, -1);
        assert!(!is_mskb_reply(&Word::new(0x12, 0x83, 0x03, 0, 0))); // lkb reply (TYPE 3)
    }

    #[test]
    fn type_hint() {
        assert!(type_in_vu_range(-10));
        assert!(type_in_vu_range(-16));
        assert!(!type_in_vu_range(-9));
        assert!(!type_in_vu_range(0));
    }

    #[test]
    fn gates_once() {
        let mut g = LoadkeybagGate::closed();
        assert!(!g.admit(&loadkeybag_word()), "closed");
        g.arm();
        assert!(!g.admit(&Word::new(0x12, 0x03, 0x04, 0, LKB_DATA)), "wrong TYPE");
        assert!(!g.admit(&Word::new(0x12, 0x0d, 0x03, 0, LKB_DATA)), "wrong TAG");
        assert!(!g.admit(&Word::new(0x12, 0x03, 0x03, 0, 0x0074_0001)), "wrong DATA");
        assert!(g.admit(&loadkeybag_word()));
        assert!(g.used());
        assert!(!g.admit(&loadkeybag_word()), "twice");

        let mut m = MskbGate::closed();
        m.arm();
        assert!(!m.admit(&Word::new(0x12, 0x0d, 0x03, 0, MSKB_DATA)), "wrong TYPE");
        assert!(m.admit(&mskb_word()));
        assert!(!m.admit(&mskb_word()), "twice");
    }
}
