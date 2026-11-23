//! SKS (EP 0x12) IPC frames of experiment J10 (`docs/sks_native_plan.md` § J10): the device-identity keybag path,
//! two chained transactions sent right after `get_capabilities` (0x4d) and `set_env` (0x2a), SKIPPING the two
//! `perform_operation` and `null_d_key`:
//!   1. `create_keybag`      (TAG fil 0x01) — creates a FRESH keybag from a class (no passcode) and RETURNS a handle;
//!   2. `make_system_keybag` (TAG fil 0x0d) — binds that handle to the device identity (uuid), status only.
//!
//! **Change 2026-11-23 (session ALARM, J13)** — the J10 skeleton used to send `load_keybag` (TAG 0x03), which IMPORTS
//! an existing keybag by uuid. The reverse of `applekeystored` (`docs/applekeystored_identity.md` §6) established that
//! the real « create a new one » path for a non-macOS host is `create_keybag` (TAG fil 0x01) NUDE, not `load_keybag`.
//! So `load_keybag` was DROPPED and `create_keybag` put in its place. Consequence for the uuid: `create_keybag` carries
//! NO uuid (it takes a class); the 16-byte uuid is now the blob of `make_system_keybag` (`identity_load` requires a
//! 16-byte OSData, `docs/applekeystored_identity.md` §6.3 — see the DÉDUIT note on `OFF_MSKB_UUID`).
//!
//! No allocation, no `std`: this file is also included as is by the kernel module (`kmod/sep_native.rs`), which uses
//! it to CHECK the two requests written by userspace and to finalize `make_system_keybag` (plug in the handle that
//! `create_keybag` returned, then re-digest). It reuses the IPC header primitives of `sks_ipc` (same header layout,
//! same v2 digest function).
//!
//! **SKELETON — NOT RUNNABLE until the userland values exist.** Byte layout established by DISASSEMBLY
//! (`docs/applekeystored_identity.md` §6, `source: kext` 27.2.1, bundle `com.apple.driver.AppleSEPKeyStore`), VU:
//!   - `__ipc_create_keybag_v4` @0xcf9a34 / codec `_code_ipc_create_keybag` @0xcde0e4: header + state(u32=0) +
//!     handle_y(u64) + two u32 scalars (class + a 2nd field) + THREE empty blobs(len=0 each) + flag(u64=0). The reply
//!     carries the SEP-assigned handle (a u32); the AP reads it back. Create takes NO passcode (`pin` flag = 0 nude).
//!   - `__ipc_make_system_keybag_v1` @0xcdbce4 / `_code_ipc_make_system_keybag` @0xce0134: header + state(u32=1,
//!     the codec takes the state==1 branch) + handle_y(u64) + loaded_handle(u32) + type(u32) + blob{len=0x10, uuid 16} +
//!     flag(u64=0). On the identity path the flag is 0 and the blob is the 16-byte device-identity uuid.
//!
//! **Ambiguity NOT resolved by the binary** (`docs/applekeystored_identity.md` §6.2/§6.4), documented, NOT guessed:
//!   - `create_keybag` has TWO u32 scalars at 0x60/0x64; §6 does not say WHICH is the class enum. Both are coded here
//!     as distinct free fields (`class` at 0x60, `field2` at 0x64) and both are supplied by the tool. If hardware
//!     rejects, swap them. Neither VALUE is known (set by the Swift caller `AKSIdentity`, absent from the kernelcache).
//!   - the SEP-assigned handle is read from OOL B at `OFF_RESP_HANDLE` (0x6c): the create reply OOL was never captured,
//!     so this offset is kept from the former skeleton and is DEDUCED — to be confirmed on hardware.
//!   - the uuid is an `identity_load` input (16-byte OSData, VU obligatory); §6.3 shows the make_system IPC body blob
//!     as EMPTY, so placing the uuid in the make_system blob is DÉDUIT (to be confirmed on hardware).
//!
//! The userland values are NOT derivable from the binary (`docs/sks_userland_values.md` of the PC), so the kernel gate
//! NEVER checks their value: `uuid` (16 bytes), `class` (u32), `keybag_type` (i32, VU hint type <= -10), and `handle_y`
//! (u64, OOL 0x58; a fresh create has no parent session handle → defaults to 0 in the tool). The `loaded_handle`
//! (OOL 0x60 of `make_system_keybag`) is DYNAMIC: it is the handle the SEP returned from `create_keybag`, read at run
//! time and plugged in by the kernel (`finalize_mskb`), never invented.
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

/// `handle_y` (u64) lives where the constant u64 of get_capabilities lived (OOL 0x58), shared by both frames.
pub const OFF_HANDLE_Y: usize = OFF_ARG; // 0x58
pub const UUID_LEN: usize = 16;

// --- create_keybag (TAG fil 0x01) ----------------------------------------------------------------------------------
pub const OP_CREATE_KEYBAG: u8 = 0x01;
/// Third transaction of J10 (get_capabilities = 1, set_env = 2, create_keybag = 3).
pub const CKB_TXN: u8 = 0x03;
pub const CKB_LEN: usize = 0x7c;
pub const CKB_DATA: u32 = (CKB_LEN as u32) << 16;
/// State word of `create_keybag` (OOL 0x54): 0 (codec `+0x50` état=0, VU §6.2).
pub const CKB_STATE: u32 = 0;
/// First u32 scalar (OOL 0x60). §6 does not pin down which of the two u32 is the class enum: coded here as the class.
pub const OFF_CKB_CLASS: usize = 0x60;
/// Second u32 scalar (OOL 0x64). The other of the ambiguous pair; a free userland value too.
pub const OFF_CKB_FIELD2: usize = 0x64;
/// Three blob lengths (empty on a fresh create), serialized compactly as three u32 lengths = 0.
pub const OFF_CKB_BLOB1: usize = 0x68;
pub const OFF_CKB_BLOB2: usize = 0x6c;
pub const OFF_CKB_BLOB3: usize = 0x70;
/// Flag (OOL 0x74, u64): 0 for a nude create (`pin` = 0 → the wrapper does NOT set 0x100).
pub const OFF_CKB_FLAG: usize = 0x74;
pub const CKB_FLAG: u64 = 0;
/// Reply TAG of `create_keybag` (= request | 0x80).
pub const CKB_REPLY_TAG: u8 = OP_CREATE_KEYBAG | 0x80; // 0x81
/// Offset in OOL B where the SEP-assigned handle is read back (u32). `docs/applekeystored_identity.md` §6.4 gives no
/// capture of the create reply OOL, so this offset is kept from the former load skeleton: DEDUCED, confirm on hardware.
pub const OFF_RESP_HANDLE: usize = 0x6c;

// --- make_system_keybag (TAG fil 0x0d) -----------------------------------------------------------------------------
pub const OP_MAKE_SYSTEM_KEYBAG: u8 = 0x0d;
/// Fourth transaction of J10 (create_keybag = 3, make_system_keybag = 4).
pub const MSKB_TXN: u8 = 0x04;
pub const MSKB_LEN: usize = 0x84;
pub const MSKB_DATA: u32 = (MSKB_LEN as u32) << 16;
pub const OFF_MSKB_LOADED: usize = 0x60;
pub const OFF_MSKB_TYPE: usize = 0x64;
pub const OFF_MSKB_BLOBLEN: usize = 0x68;
/// Device-identity uuid blob (16 bytes) at OOL 0x6c. DÉDUIT: §6.3 shows the make_system IPC body blob EMPTY, while
/// `identity_load` requires a 16-byte OSData whose IPC placement is not pinned down — to be confirmed on hardware.
pub const OFF_MSKB_UUID: usize = 0x6c;
pub const OFF_MSKB_FLAG: usize = 0x7c;
/// State word of `make_system_keybag` (OOL 0x54): 1 (codec takes the state==1 branch; VU const @0x770fec8).
pub const MSKB_STATE: u32 = 1;
/// Blob length (OOL 0x68): 0x10 = the 16-byte uuid (VU: `identity_load` `cmp w0,#0x10 ; b.ne`).
pub const MSKB_BLOBLEN: u32 = 0x10;
/// Flag (OOL 0x7c, u64): 0 on the identity path (VU x7 = 0).
pub const MSKB_FLAG: u64 = 0;
/// Reply TAG of `make_system_keybag` (= request | 0x80).
pub const MSKB_REPLY_TAG: u8 = OP_MAKE_SYSTEM_KEYBAG | 0x80; // 0x8d

const _: () = assert!(CKB_LEN == 0x54 + 4 + 8 + 4 + 4 + 4 + 4 + 4 + 8);
const _: () = assert!(MSKB_LEN == 0x54 + 4 + 8 + 4 + 4 + 4 + UUID_LEN + 8);
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

/// Contextual header fields shared by both frames (same shape as `GetcapFields`). The userland values (uuid, class,
/// type, handle_y) are carried separately, per frame, because they are free and not part of the header.
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
// create_keybag
// =================================================================================================================

/// The exact `create_keybag` request word (the only one the driver may ever send for this op).
pub const fn createkeybag_word() -> Word {
    Word::new(EP_SKS, OP_CREATE_KEYBAG, CKB_TXN, 0, CKB_DATA)
}

/// Builds the 0x7c bytes of `create_keybag`. `handle_y`, `class` and `field2` are USERLAND values (no default here);
/// the three blobs are empty (fresh create) and the flag is 0 (nude create). The digest is computed last over the v2
/// base.
pub fn encode_createkeybag(f: &KeybagFields, handle_y: u64, class: u32, field2: u32) -> [u8; CKB_LEN] {
    let mut b = [0u8; CKB_LEN];
    write_header(&mut b, f);
    // state (0x54) = 0 (left zero).
    b[OFF_HANDLE_Y..OFF_HANDLE_Y + 8].copy_from_slice(&handle_y.to_le_bytes());
    b[OFF_CKB_CLASS..OFF_CKB_CLASS + 4].copy_from_slice(&class.to_le_bytes());
    b[OFF_CKB_FIELD2..OFF_CKB_FIELD2 + 4].copy_from_slice(&field2.to_le_bytes());
    // three blob lengths (0x68/0x6c/0x70) = 0, flag (0x74) = 0: left zero.
    let d = frame_digest(&b, HDR_VERSION_V2, OFF_STATE, CKB_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// What the kernel gate reads back from a `create_keybag` request (the userland values, for the journal only).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CreatekeybagReq {
    pub fields: KeybagFields,
    pub handle_y: u64,
    pub class: u32,
    pub field2: u32,
}

/// Kernel gate on the 0x7c bytes of `create_keybag`: exact length, the CONSTANT fields (header constants, state 0,
/// three blob lengths 0, flag 0), the v2 digest recomputed, cdhash in one of the two documented AP forms. The userland
/// values (handle_y, class, field2) are NOT constrained (they are free, supplied by the tool). Returns them for the log.
pub fn check_createkeybag(b: &[u8]) -> Result<CreatekeybagReq> {
    if b.len() != CKB_LEN {
        return Err(Error::OutOfRange("create_keybag request length", b.len() as u64));
    }
    check_header_constants(b)?;
    let state = le32(b, OFF_STATE)?;
    if state != CKB_STATE {
        return Err(Error::OutOfRange("create_keybag state (0x54) != 0", u64::from(state)));
    }
    for (o, what) in [
        (OFF_CKB_BLOB1, "create_keybag blob 1 length (0x68) != 0"),
        (OFF_CKB_BLOB2, "create_keybag blob 2 length (0x6c) != 0"),
        (OFF_CKB_BLOB3, "create_keybag blob 3 length (0x70) != 0"),
    ] {
        let v = le32(b, o)?;
        if v != 0 {
            return Err(Error::OutOfRange(what, u64::from(v)));
        }
    }
    let flag = le64(b, OFF_CKB_FLAG)?;
    if flag != CKB_FLAG {
        return Err(Error::OutOfRange("create_keybag flag (0x74) != 0", flag));
    }
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, CKB_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("create_keybag digest (0x04) != SHA-256/16 of the documented v2 base"));
    }
    let fields = KeybagFields { ts_us: le64(b, OFF_TS)?, uniqueid: le64(b, OFF_UNIQUEID)?, uid: le32(b, OFF_UID)?, cdhash: read_cdhash(b) };
    if cdhash_kind(&fields.header()) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    Ok(CreatekeybagReq { fields, handle_y: le64(b, OFF_HANDLE_Y)?, class: le32(b, OFF_CKB_CLASS)?, field2: le32(b, OFF_CKB_FIELD2)? })
}

/// `true` iff `w` is a reply to our `create_keybag` as the kext matches it: EP 0x12, TAG bit 7 set, TYPE = our txn.
pub fn is_createkeybag_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == CKB_TXN
}

/// Reads the SEP-assigned keybag handle from a `create_keybag` reply snapshot (OOL B), at `OFF_RESP_HANDLE` (DEDUCED,
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

/// Builds the 0x84 bytes of `make_system_keybag`. `handle_y`, `keybag_type` and `uuid` are USERLAND values (no default);
/// `loaded_handle` is the handle `create_keybag` returned (the tool puts a placeholder — default 0 — because the
/// KERNEL plugs in the real one at send time via `finalize_mskb`, then re-digests). The uuid is the 16-byte blob
/// (len 0x10). Digest computed last.
pub fn encode_mskb(f: &KeybagFields, handle_y: u64, loaded_handle: u32, keybag_type: i32, uuid: &[u8; UUID_LEN]) -> [u8; MSKB_LEN] {
    let mut b = [0u8; MSKB_LEN];
    write_header(&mut b, f);
    b[OFF_STATE..OFF_STATE + 4].copy_from_slice(&MSKB_STATE.to_le_bytes());
    b[OFF_HANDLE_Y..OFF_HANDLE_Y + 8].copy_from_slice(&handle_y.to_le_bytes());
    b[OFF_MSKB_LOADED..OFF_MSKB_LOADED + 4].copy_from_slice(&loaded_handle.to_le_bytes());
    b[OFF_MSKB_TYPE..OFF_MSKB_TYPE + 4].copy_from_slice(&keybag_type.to_le_bytes());
    b[OFF_MSKB_BLOBLEN..OFF_MSKB_BLOBLEN + 4].copy_from_slice(&MSKB_BLOBLEN.to_le_bytes());
    b[OFF_MSKB_UUID..OFF_MSKB_UUID + UUID_LEN].copy_from_slice(uuid);
    // flag (0x7c) = 0: left zero.
    let d = frame_digest(&b, HDR_VERSION_V2, OFF_STATE, MSKB_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// Writes the real `loaded_handle` (the one `create_keybag` returned) into a checked `make_system_keybag` request and
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
    pub uuid: [u8; UUID_LEN],
}

/// Kernel gate on the 0x84 bytes of `make_system_keybag`: exact length, the CONSTANT fields (header constants,
/// state 1, blob length 0x10 = the uuid, flag 0), the v2 digest recomputed, cdhash in one of the two documented AP
/// forms. NOT constrained: handle_y, type and uuid (userland, free) and loaded_handle (dynamic, overwritten by the
/// kernel via `finalize_mskb`). The digest is checked over the bytes AS SUPPLIED (loaded_handle placeholder); the
/// kernel re-digests after plugging in the real handle.
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
        return Err(Error::OutOfRange("make_system_keybag blob length (0x68) != 0x10 (uuid)", u64::from(bloblen)));
    }
    let flag = le64(b, OFF_MSKB_FLAG)?;
    if flag != MSKB_FLAG {
        return Err(Error::OutOfRange("make_system_keybag flag (0x7c) != 0", flag));
    }
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, MSKB_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("make_system_keybag digest (0x04) != SHA-256/16 of the documented v2 base"));
    }
    let fields = KeybagFields { ts_us: le64(b, OFF_TS)?, uniqueid: le64(b, OFF_UNIQUEID)?, uid: le32(b, OFF_UID)?, cdhash: read_cdhash(b) };
    if cdhash_kind(&fields.header()) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    let mut uuid = [0u8; UUID_LEN];
    uuid.copy_from_slice(&b[OFF_MSKB_UUID..OFF_MSKB_UUID + UUID_LEN]);
    Ok(MskbReq {
        fields,
        handle_y: le64(b, OFF_HANDLE_Y)?,
        loaded_handle: le32(b, OFF_MSKB_LOADED)?,
        keybag_type: le32(b, OFF_MSKB_TYPE)? as i32,
        uuid,
    })
}

/// `true` iff `w` is a reply to our `make_system_keybag`: EP 0x12, TAG bit 7 set, TYPE = our txn.
pub fn is_mskb_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == MSKB_TXN
}

/// Re-exported from `sks_ipc`: reply word shape (PARAM = signed status, DATA = len<<16 | call flags).
pub use crate::sks_ipc::reply_word;

/// VU constraint on `type` (`docs/applekeystored_identity.md` §6.4): `identity_load` rejects `type > -10`. This is a
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

one_word_gate!(CreatekeybagGate, createkeybag_word());
one_word_gate!(MskbGate, mskb_word());

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hash::sha256;
    use crate::sks_ipc::cdhash_no_process;

    // ARBITRARY example values — « exemple de test, PAS les vraies » (the real uuid/class/type are unknown).
    const EX_TS: u64 = 0x1122_3344_5566_7788;
    const EX_HANDLE_Y: u64 = 0x4242_4242_4242_4242;
    const EX_CLASS: u32 = 0x0000_0002;
    const EX_FIELD2: u32 = 0x0000_0000;
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
        assert_eq!(createkeybag_word(), Word::new(0x12, 0x01, 0x03, 0x00, 0x007c_0000));
        assert_eq!(mskb_word(), Word::new(0x12, 0x0d, 0x04, 0x00, 0x0084_0000));
        assert_eq!(CKB_LEN, 0x7c);
        assert_eq!(MSKB_LEN, 0x84);
        assert_eq!(CKB_REPLY_TAG, 0x81);
        assert_eq!(MSKB_REPLY_TAG, 0x8d);
    }

    #[test]
    fn createkeybag_layout_and_reread() {
        let f = fields();
        let b = encode_createkeybag(&f, EX_HANDLE_Y, EX_CLASS, EX_FIELD2);
        assert_eq!(le32(&b, 0x00).unwrap(), 0x50);
        assert_eq!(le32(&b, 0x14).unwrap(), 2);
        assert_eq!(le64(&b, 0x18).unwrap(), EX_TS);
        assert_eq!(le32(&b, 0x54).unwrap(), 0); // state
        assert_eq!(le64(&b, 0x58).unwrap(), EX_HANDLE_Y); // handle_y
        assert_eq!(le32(&b, 0x60).unwrap(), EX_CLASS);
        assert_eq!(le32(&b, 0x64).unwrap(), EX_FIELD2);
        assert_eq!(le32(&b, 0x68).unwrap(), 0); // blob 1 len
        assert_eq!(le32(&b, 0x6c).unwrap(), 0); // blob 2 len
        assert_eq!(le32(&b, 0x70).unwrap(), 0); // blob 3 len
        assert_eq!(le64(&b, 0x74).unwrap(), 0); // flag
        let r = check_createkeybag(&b).unwrap();
        assert_eq!((r.fields, r.handle_y, r.class, r.field2), (f, EX_HANDLE_Y, EX_CLASS, EX_FIELD2));
    }

    #[test]
    fn mskb_layout_and_reread() {
        let f = fields();
        let b = encode_mskb(&f, EX_HANDLE_Y, 0, EX_TYPE, &ex_uuid());
        assert_eq!(le32(&b, 0x54).unwrap(), 1); // state const 1
        assert_eq!(le64(&b, 0x58).unwrap(), EX_HANDLE_Y); // handle_y
        assert_eq!(le32(&b, 0x60).unwrap(), 0); // loaded handle placeholder
        assert_eq!(le32(&b, 0x64).unwrap() as i32, EX_TYPE); // type
        assert_eq!(le32(&b, 0x68).unwrap(), 0x10); // blob len = uuid
        assert_eq!(&b[0x6c..0x7c], &ex_uuid());
        assert_eq!(le64(&b, 0x7c).unwrap(), 0); // flag
        let r = check_mskb(&b).unwrap();
        assert_eq!((r.fields, r.handle_y, r.loaded_handle, r.keybag_type, r.uuid), (f, EX_HANDLE_Y, 0, EX_TYPE, ex_uuid()));
    }

    /// Full-request fingerprint vs an independent Python/hashlib construction (session ALARM 2026-11-23,
    /// `/tmp/kbvec/vec.py`). Values are the ARBITRARY example set, NOT the real userland values.
    #[test]
    fn requests_match_independent_construction() {
        let ckb = encode_createkeybag(&fields(), EX_HANDLE_Y, EX_CLASS, EX_FIELD2);
        assert_eq!(&ckb[0x04..0x14], &hex16("578eef9c567db26dec3ae75c2f6c4c32"));
        assert_eq!(sha256(&ckb), hex32("40575643c34efbf798efc47e86327a746ea4c4eecec1c13556f39ef1808687f4"));

        let mskb = encode_mskb(&fields(), EX_HANDLE_Y, 0, EX_TYPE, &ex_uuid());
        assert_eq!(&mskb[0x04..0x14], &hex16("d186ead7fd1410b8151f600e73ea8e29"));
        assert_eq!(sha256(&mskb), hex32("260983793bbe663b9a70d97ebffee16bec8d1dc4e193c47576f49dc566b48746"));
    }

    /// v2 digest base built field by field independently of the encoder (§1.6.3/§1.7.1): for v2 it is simply
    /// SHA-256 of OOL bytes 0x14..end (header v2 + payload, contiguous), truncated to 16.
    #[test]
    fn digest_base_is_the_documented_v2_one() {
        let b = encode_createkeybag(&fields(), EX_HANDLE_Y, EX_CLASS, EX_FIELD2);
        assert_eq!(&b[0x04..0x14], &sha256(&b[0x14..])[..16]);
        let b2 = encode_mskb(&fields(), EX_HANDLE_Y, 0x1234_5678, EX_TYPE, &ex_uuid());
        assert_eq!(&b2[0x04..0x14], &sha256(&b2[0x14..])[..16]);
    }

    /// The kernel plugs in the real handle and re-digests: `finalize_mskb` must match a fresh `encode_mskb` with that
    /// handle, and the re-digest must agree with the independent Python vector for handle 0xdeadbeef.
    #[test]
    fn finalize_matches_fresh_encode_and_python() {
        let mut b = encode_mskb(&fields(), EX_HANDLE_Y, 0, EX_TYPE, &ex_uuid());
        finalize_mskb(&mut b, 0xdead_beef);
        assert_eq!(b, encode_mskb(&fields(), EX_HANDLE_Y, 0xdead_beef, EX_TYPE, &ex_uuid()));
        assert_eq!(&b[0x04..0x14], &hex16("c5fd84961b48bf2de20d818be48d391d"));
        assert_eq!(sha256(&b), hex32("7cb9ba6138cf7464950f27feea9265f296123245f19c61eb5ae48f0bb2000018"));
        assert_eq!(check_mskb(&b).unwrap().loaded_handle, 0xdead_beef);
    }

    #[test]
    fn gates_refuse_constant_changes() {
        // create_keybag: header constants, state, three blob lengths, flag are checked; handle_y/class/field2 are NOT.
        let good = encode_createkeybag(&fields(), EX_HANDLE_Y, EX_CLASS, EX_FIELD2);
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x68, 0x6c, 0x70, 0x74] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_createkeybag(&b).is_err(), "ckb offset {o:#x}");
        }
        // handle_y (0x58), class (0x60) and field2 (0x64) are free: changing them (and re-digesting) is accepted.
        let other = encode_createkeybag(&fields(), 0x99, 0xdead, 0xbeef);
        let r = check_createkeybag(&other).unwrap();
        assert_eq!((r.handle_y, r.class, r.field2), (0x99, 0xdead, 0xbeef));
        // Contextual header field changed without re-digesting → refused (digest).
        let mut b = good;
        b[0x18] ^= 0x01;
        assert!(check_createkeybag(&b).is_err());
        assert!(check_createkeybag(&good[..0x7b]).is_err());

        // make_system_keybag: header constants, state 1, blob length 0x10, flag 0 checked; handle_y/loaded/type/uuid NOT.
        let good2 = encode_mskb(&fields(), EX_HANDLE_Y, 0, EX_TYPE, &ex_uuid());
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x68, 0x7c] {
            let mut b = good2;
            b[o] ^= 0x01;
            assert!(check_mskb(&b).is_err(), "mskb offset {o:#x}");
        }
        // handle_y/loaded/type/uuid free: a different type and uuid (and re-digest) is accepted.
        let other2 = encode_mskb(&fields(), 0x7, 0x8, -42, &[0xee; UUID_LEN]);
        let r2 = check_mskb(&other2).unwrap();
        assert_eq!((r2.handle_y, r2.loaded_handle, r2.keybag_type, r2.uuid), (0x7, 0x8, -42, [0xee; UUID_LEN]));
    }

    #[test]
    fn reply_matching_and_handle() {
        // create_keybag reply: `< 0x12 TAG 0x81 TYPE 0x03 PARAM 0 DATA (len<<16)`.
        let w = Word::decode(0x0010_0000_0003_8112);
        assert!(is_createkeybag_reply(&w));
        assert_eq!(reply_word(&w).status, 0);
        assert!(!is_createkeybag_reply(&Word::new(0x12, 0x01, 0x03, 0, 0))); // request, bit 7 clear
        assert!(!is_createkeybag_reply(&Word::new(0x12, 0x8d, 0x04, 0, 0))); // mskb reply (TYPE 4)
        let mut snap = [0u8; crate::sks_ipc::OUT_SNAP];
        snap[OFF_RESP_HANDLE..OFF_RESP_HANDLE + 4].copy_from_slice(&0x0abc_def0u32.to_le_bytes());
        assert_eq!(reply_handle(&snap).unwrap(), 0x0abc_def0);

        // make_system_keybag reply: `< 0x12 TAG 0x8d TYPE 0x04 PARAM s DATA ...`. PARAM 0 = OK, != 0 = refus.
        let ok = Word::new(0x12, 0x8d, 0x04, 0x00, 0);
        assert!(is_mskb_reply(&ok));
        assert_eq!(reply_word(&ok).status, 0);
        assert_eq!(reply_word(&Word::new(0x12, 0x8d, 0x04, 0xff, 0)).status, -1);
        assert!(!is_mskb_reply(&Word::new(0x12, 0x81, 0x03, 0, 0))); // ckb reply (TYPE 3)
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
        let mut g = CreatekeybagGate::closed();
        assert!(!g.admit(&createkeybag_word()), "closed");
        g.arm();
        assert!(!g.admit(&Word::new(0x12, 0x01, 0x04, 0, CKB_DATA)), "wrong TYPE");
        assert!(!g.admit(&Word::new(0x12, 0x0d, 0x03, 0, CKB_DATA)), "wrong TAG");
        assert!(!g.admit(&Word::new(0x12, 0x01, 0x03, 0, 0x007c_0001)), "wrong DATA");
        assert!(g.admit(&createkeybag_word()));
        assert!(g.used());
        assert!(!g.admit(&createkeybag_word()), "twice");

        let mut m = MskbGate::closed();
        m.arm();
        assert!(!m.admit(&Word::new(0x12, 0x0d, 0x03, 0, MSKB_DATA)), "wrong TYPE");
        assert!(m.admit(&mskb_word()));
        assert!(!m.admit(&mskb_word()), "twice");
    }
}
