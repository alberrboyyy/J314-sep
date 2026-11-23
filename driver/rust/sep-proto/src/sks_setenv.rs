//! SKS (EP 0x12) IPC frame, SECOND exchange: `set_env` (TAG 0x2a), experiment J9b (`docs/sks_native_plan.md` §7).
//! No allocation, no `std`: this file is also included as is by the kernel module (`kmod/sep_native.rs`), which uses
//! it to CHECK the request written by userspace and to decode the reply. It reuses the IPC header primitives of
//! `sks_ipc` (same header layout, same digest function with the version as a parameter).
//!
//! Written from `docs/sks_protocol.md` §1.7 (`source: kext` 13.5, NOT verified on hardware); nothing is copied from
//! Apple code. Every scalar is little-endian.
//!
//! `set_env` is the 2nd transaction of the macOS bring-up, sent right after `get_capabilities` negotiated the header
//! version (v2 here: `get_capabilities` returned theirs = 2, confirmed on hardware by J9a). So the header carries
//! **version 2** and the integrity digest covers the v2 base (`sks_ipc::frame_digest` with version 2, process block
//! 0x28, i.e. the whole header 0x14..0x54 then the payload).
//!
//! Request, 0x470 bytes in OOL A, word `> EP 0x12 TAG 0x2a TYPE 0x02 PARAM 0 DATA 0x04700000` (c12 L180):
//!
//! | off   | size  | field                              | value here                                    |
//! |-------|-------|------------------------------------|-----------------------------------------------|
//! | 0x00  | 4     | header length                      | 0x50 (constant)                               |
//! | 0x04  | 16    | SHA-256/16, v2 base                | computed                                      |
//! | 0x14  | 4     | header version                     | 2 (negotiated)                                |
//! | 0x18  | 8     | timestamp µs                       | contextual                                    |
//! | 0x20  | 4     | flags (bit0 encrypted, bit1 ext)   | 0 (constant; set_env clears bit1, no crypt)   |
//! | 0x24  | 8     | context field +0x20                | 0 (constant)                                  |
//! | 0x2c  | 8     | process unique id                  | contextual                                    |
//! | 0x34  | 4     | credential field (user id)         | contextual                                    |
//! | 0x38  | 20    | cdhash; else SHA-1 of the 8 b @0x2c| contextual                                    |
//! | 0x4c  | 8     | context +0x48..0x4f                | 0 (constant; in the v2 digest)                |
//! | 0x54  | 4     | status word                        | 0 (constant)                                  |
//! | 0x58  | 8     | u64 argument                       | 1 (constant; same as get_capabilities)        |
//! | 0x60  | 4     | blob length                        | 0x40c (constant)                              |
//! | 0x64  | 0x40c | environment blob (below)           | constants + cpx-encryption-mode               |
//!
//! Environment blob (0x40c bytes, `docs/sks_protocol.md` §1.7.3):
//!
//! | off blob | size  | field                   | value                                        |
//! |----------|-------|-------------------------|----------------------------------------------|
//! | 0x000    | 4     | structure version       | 1 (constant)                                 |
//! | 0x004    | 4     | cpx-encryption-mode     | contextual (ADT `/defaults`, else 0)         |
//! | 0x008    | 4     | mode                    | 4 = set_env(false) at bring-up (constant)    |
//! | 0x00c    | 0x400 | reserved                | all zero                                     |
//!
//! Reply word `< EP 0x12 TAG 0xaa TYPE 0x02 PARAM 0 DATA 0x00580000` (c12 L181): length 0x58 = header (0x54) + status
//! (4), with NO u64 and NO blob. The kext requires status = 0; `init_sep_endpoint` ignores the return code otherwise.
//! So the reply only confirms acceptance (`docs/sks_protocol.md` §1.7.4).
use crate::sks_ipc::{
    cdhash_kind, frame_digest, CdhashKind, GetcapFields, CDHASH_LEN, DIGEST_LEN, EP_SKS, HDR_LEN_AP,
    HLEN_MIN_V1, HLEN_MIN_V2, OFF_ARG, OFF_BLOBLEN, OFF_CDHASH, OFF_DIGEST, OFF_F20, OFF_FLAGS, OFF_HLEN, OFF_STATE,
    OFF_TS, OFF_UID, OFF_UNIQUEID, OFF_VERSION, OFF_X48,
};
use crate::word::Word;
use crate::{Error, Result};

/// IPC operation code of `set_env` = TAG of the request word.
pub const OP_SET_ENV: u8 = 0x2a;
/// Second transaction of the boot (the global counter: get_capabilities was 0x01, c12 L180).
pub const SETENV_TXN: u8 = 0x02;
pub const SETENV_LEN: usize = 0x470;
/// DATA of the request word: OOL length in bits 16-31.
pub const SETENV_DATA: u32 = (SETENV_LEN as u32) << 16;
/// Negotiated header version (v2; get_capabilities returned theirs = 2).
pub const HDR_VERSION_V2: u32 = 2;
/// Length of the environment blob.
pub const BLOB_LEN: u32 = 0x40c;
/// u64 argument of the request (constant; same as get_capabilities).
pub const SETENV_ARG: u64 = 1;
/// Reply length seen on macOS (c12 L181): header (0x54) + status (4).
pub const REPLY_LEN_SEEN: u16 = 0x58;

/// Start of the environment blob (right after the blob-length u32 at OFF_BLOBLEN = 0x60).
pub const OFF_BLOB: usize = 0x64;
pub const BLOB_OFF_VERSION: usize = 0x00;
pub const BLOB_OFF_CPX: usize = 0x04;
pub const BLOB_OFF_MODE: usize = 0x08;
pub const BLOB_OFF_RESERVED: usize = 0x0c;
pub const BLOB_RESERVED_LEN: usize = 0x400;
/// Constants of the blob.
pub const BLOB_VERSION: u32 = 1;
/// Mode of `set_env(false)` at bring-up (4); `set_env(true)` would be 6 (not used here).
pub const BLOB_MODE_BRINGUP: u32 = 4;

const _: () = assert!(OFF_BLOB + BLOB_OFF_RESERVED + BLOB_RESERVED_LEN == SETENV_LEN);

fn le32(b: &[u8], o: usize) -> Result<u32> {
    b.get(o..o + 4).map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]])).ok_or(Error::Short)
}
fn le64(b: &[u8], o: usize) -> Result<u64> {
    let s = b.get(o..o + 8).ok_or(Error::Short)?;
    Ok(u64::from_le_bytes([s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7]]))
}
const fn align4(n: usize) -> usize {
    (n + 3) & !3
}

/// The exact request word (and the only `set_env` word the driver may ever send).
pub const fn setenv_word() -> Word {
    Word::new(EP_SKS, OP_SET_ENV, SETENV_TXN, 0, SETENV_DATA)
}

/// Contextual fields of the request. The header fields are the same as `get_capabilities` (reused as `GetcapFields`);
/// `cpx` is the only extra contextual value, read from the ADT at runtime.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SetenvFields {
    pub ts_us: u64,
    pub uniqueid: u64,
    pub uid: u32,
    pub cdhash: [u8; CDHASH_LEN],
    /// `cpx-encryption-mode` (device-tree `/defaults`); the kext uses 0 when the property is absent.
    pub cpx: u32,
}

impl SetenvFields {
    fn header(&self) -> GetcapFields {
        GetcapFields { ts_us: self.ts_us, uniqueid: self.uniqueid, uid: self.uid, cdhash: self.cdhash }
    }
}

/// Builds the 0x470 bytes of the request (constants of §1.7, `f` for the contextual fields, v2 digest last).
pub fn encode_setenv(f: &SetenvFields) -> [u8; SETENV_LEN] {
    let mut b = [0u8; SETENV_LEN];
    b[OFF_HLEN..OFF_HLEN + 4].copy_from_slice(&HDR_LEN_AP.to_le_bytes());
    b[OFF_VERSION..OFF_VERSION + 4].copy_from_slice(&HDR_VERSION_V2.to_le_bytes());
    b[OFF_TS..OFF_TS + 8].copy_from_slice(&f.ts_us.to_le_bytes());
    // flags (0x20), field +0x20 (0x24), 0x4c..0x54, status (0x54): zeros.
    b[OFF_UNIQUEID..OFF_UNIQUEID + 8].copy_from_slice(&f.uniqueid.to_le_bytes());
    b[OFF_UID..OFF_UID + 4].copy_from_slice(&f.uid.to_le_bytes());
    b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN].copy_from_slice(&f.cdhash);
    b[OFF_ARG..OFF_ARG + 8].copy_from_slice(&SETENV_ARG.to_le_bytes());
    b[OFF_BLOBLEN..OFF_BLOBLEN + 4].copy_from_slice(&BLOB_LEN.to_le_bytes());
    b[OFF_BLOB + BLOB_OFF_VERSION..OFF_BLOB + BLOB_OFF_VERSION + 4].copy_from_slice(&BLOB_VERSION.to_le_bytes());
    b[OFF_BLOB + BLOB_OFF_CPX..OFF_BLOB + BLOB_OFF_CPX + 4].copy_from_slice(&f.cpx.to_le_bytes());
    b[OFF_BLOB + BLOB_OFF_MODE..OFF_BLOB + BLOB_OFF_MODE + 4].copy_from_slice(&BLOB_MODE_BRINGUP.to_le_bytes());
    // reserved (OFF_BLOB + 0x0c .. end): zeros.
    // Cannot fail: version 2, header end 0x54 = 0x14 + 0x40, end 0x470.
    let d = frame_digest(&b, HDR_VERSION_V2, OFF_STATE, SETENV_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// Kernel gate on the 0x470 bytes from userspace: exact length, every CONSTANT field (header AND blob, incl. the
/// 0x400 reserved bytes = 0), v2 digest recomputed, cdhash in one of the two documented AP forms. The only value NOT
/// constrained is `cpx-encryption-mode` (contextual, read from the ADT). Returns the contextual fields (for the log).
pub fn check_setenv(b: &[u8]) -> Result<SetenvFields> {
    if b.len() != SETENV_LEN {
        return Err(Error::OutOfRange("set_env request length", b.len() as u64));
    }
    let want32 = |o: usize, v: u32, what: &'static str| -> Result<()> {
        let x = le32(b, o)?;
        if x == v {
            Ok(())
        } else {
            Err(Error::OutOfRange(what, u64::from(x)))
        }
    };
    let want64 = |o: usize, v: u64, what: &'static str| -> Result<()> {
        let x = le64(b, o)?;
        if x == v {
            Ok(())
        } else {
            Err(Error::OutOfRange(what, x))
        }
    };
    want32(OFF_HLEN, HDR_LEN_AP, "header length (0x00) != 0x50")?;
    want32(OFF_VERSION, HDR_VERSION_V2, "header version (0x14) != 2")?;
    want32(OFF_FLAGS, 0, "flags (0x20) != 0")?;
    want64(OFF_F20, 0, "field +0x20 (0x24) != 0")?;
    want64(OFF_X48, 0, "context 0x48 (0x4c) != 0")?;
    want32(OFF_STATE, 0, "status (0x54) != 0")?;
    want64(OFF_ARG, SETENV_ARG, "u64 argument (0x58) != 1")?;
    want32(OFF_BLOBLEN, BLOB_LEN, "blob length (0x60) != 0x40c")?;
    want32(OFF_BLOB + BLOB_OFF_VERSION, BLOB_VERSION, "blob version (0x64) != 1")?;
    want32(OFF_BLOB + BLOB_OFF_MODE, BLOB_MODE_BRINGUP, "blob mode (0x6c) != 4")?;
    let reserved = b.get(OFF_BLOB + BLOB_OFF_RESERVED..SETENV_LEN).ok_or(Error::Short)?;
    if reserved.iter().any(|&x| x != 0) {
        return Err(Error::Unexpected("blob reserved area (0x70..0x470) is not all zero"));
    }
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, SETENV_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("digest (0x04) != SHA-256/16 of the documented v2 base"));
    }
    let mut cdhash = [0u8; CDHASH_LEN];
    cdhash.copy_from_slice(&b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN]);
    let f = SetenvFields {
        ts_us: le64(b, OFF_TS)?,
        uniqueid: le64(b, OFF_UNIQUEID)?,
        uid: le32(b, OFF_UID)?,
        cdhash,
        cpx: le32(b, OFF_BLOB + BLOB_OFF_CPX)?,
    };
    if cdhash_kind(&f.header()) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    Ok(f)
}

/// `true` iff `w` is a reply to our `set_env` as the kext matches it: EP 0x12, TAG bit 7 set, TYPE = our transaction.
pub fn is_setenv_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == SETENV_TXN
}

/// Re-exported from `sks_ipc`: the reply word has the same shape (PARAM = signed status, DATA = len<<16 | call flags).
pub use crate::sks_ipc::reply_word;

/// Decoded `set_env` reply payload (OOL B): header + status, NO u64, NO blob.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SetenvReply {
    pub hlen: u32,
    pub version: u32,
    /// Digest recomputed on the reply (base per the version read in the SEP header).
    pub digest_ok: bool,
    /// Status word: must be 0 for acceptance.
    pub state: u32,
}

/// Decodes `len` bytes of OOL B. Structural errors (lengths, unknown version, extended header, bytes consumed !=
/// length) → `Err`; a wrong digest or a non-zero status are reported in the result (the caller decides).
pub fn decode_setenv_reply(b: &[u8], len: usize) -> Result<SetenvReply> {
    if len > b.len() {
        return Err(Error::OutOfRange("reply length > snapshot of B", len as u64));
    }
    let b = &b[..len];
    let hlen = le32(b, OFF_HLEN)?;
    let hdr_end = 4usize.checked_add(align4(hlen as usize)).ok_or(Error::Short)?;
    if hlen < HLEN_MIN_V1 || hdr_end > len {
        return Err(Error::OutOfRange("reply header length L", u64::from(hlen)));
    }
    let version = le32(b, OFF_VERSION)?;
    match version {
        1 => {}
        2 if hlen >= HLEN_MIN_V2 => {}
        2 => return Err(Error::OutOfRange("reply header v2 shorter than 0x50", u64::from(hlen))),
        v => return Err(Error::OutOfRange("reply header version", u64::from(v))),
    }
    let flags = le32(b, OFF_FLAGS)?;
    if version >= 2 && flags & 2 != 0 {
        return Err(Error::Unexpected("reply carries an extended header (not modelled)"));
    }
    let state = le32(b, hdr_end)?;
    let consumed = hdr_end + 4;
    if consumed != len {
        return Err(Error::OutOfRange("reply bytes consumed != announced length", consumed as u64));
    }
    let d = frame_digest(b, version, hdr_end, len)?;
    Ok(SetenvReply { hlen, version, digest_ok: b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] == d, state })
}

/// Send gate: once armed, admits exactly `setenv_word()`, once; nothing else, ever.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SetenvGate {
    armed: bool,
    used: bool,
}

impl SetenvGate {
    pub const fn closed() -> Self {
        SetenvGate { armed: false, used: false }
    }

    pub fn arm(&mut self) {
        if !self.used {
            self.armed = true;
        }
    }

    pub fn admit(&mut self, w: &Word) -> bool {
        let ok = self.armed && !self.used && *w == setenv_word();
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hash::sha256;
    use crate::sks_ipc::cdhash_no_process;

    fn fields() -> SetenvFields {
        SetenvFields { ts_us: 0x1122_3344_5566_7788, uniqueid: 0, uid: 0, cdhash: cdhash_no_process(0), cpx: 2 }
    }

    #[test]
    fn word_is_c12_l180() {
        // c12 L180: `> EP=0x12 TAG=0x2a TYPE=0x02 PARAM=0x00 DATA=0x04700000`.
        assert_eq!(setenv_word(), Word::new(0x12, 0x2a, 0x02, 0x00, 0x0470_0000));
        assert_eq!(SETENV_LEN, 0x54 + 4 + 8 + 4 + 0x40c);
    }

    #[test]
    fn encoder_layout_and_reread() {
        let f = fields();
        let b = encode_setenv(&f);
        assert_eq!(le32(&b, 0x00).unwrap(), 0x50);
        assert_eq!(le32(&b, 0x14).unwrap(), 2);
        assert_eq!(le64(&b, 0x18).unwrap(), 0x1122_3344_5566_7788);
        assert_eq!(le32(&b, 0x20).unwrap(), 0);
        assert_eq!(le64(&b, 0x24).unwrap(), 0);
        assert_eq!(le64(&b, 0x2c).unwrap(), 0);
        assert_eq!(le32(&b, 0x34).unwrap(), 0);
        assert_eq!(&b[0x38..0x4c], &cdhash_no_process(0));
        assert_eq!(le64(&b, 0x4c).unwrap(), 0);
        assert_eq!(le32(&b, 0x54).unwrap(), 0);
        assert_eq!(le64(&b, 0x58).unwrap(), 1);
        assert_eq!(le32(&b, 0x60).unwrap(), 0x40c);
        assert_eq!(le32(&b, 0x64).unwrap(), 1); // blob version
        assert_eq!(le32(&b, 0x68).unwrap(), 2); // cpx
        assert_eq!(le32(&b, 0x6c).unwrap(), 4); // mode
        assert!(b[0x70..].iter().all(|&x| x == 0)); // reserved
        assert_eq!(check_setenv(&b).unwrap(), f);
    }

    /// Full-request fingerprint against an independent Python/hashlib construction (session ALARM 2026-11-23):
    /// ts = 0x1122334455667788, uniqueid 0, uid 0, cdhash = sha1(8 × 0x00), cpx 2, mode 4, blob version 1.
    #[test]
    fn request_matches_independent_construction() {
        let b = encode_setenv(&fields());
        assert_eq!(&b[0x04..0x14], &hex16("8261049d2c7363a00481526491c593aa"));
        assert_eq!(sha256(&b), hex32("b911d3ea8788fce2f662814368e282b84112da3e41b5f5845b0b74336df0999a"));
    }

    /// v2 digest base, built here field by field independently of the encoder (§1.6.3 + §1.7.1).
    #[test]
    fn digest_base_is_the_documented_v2_one() {
        let f = SetenvFields { ts_us: 0x1234, uniqueid: 0x0102_0304_0506_0708, uid: 0x4242, cdhash: [0; 20], cpx: 1 };
        let b = encode_setenv(&f);
        let mut base = Vec::new();
        base.extend_from_slice(&2u32.to_le_bytes()); // version
        base.extend_from_slice(&f.ts_us.to_le_bytes()); // timestamp
        base.extend_from_slice(&0u32.to_le_bytes()); // flags
        base.extend_from_slice(&0u64.to_le_bytes()); // field +0x20
        base.extend_from_slice(&f.uniqueid.to_le_bytes()); // process block: unique id
        base.extend_from_slice(&f.uid.to_le_bytes()); //                  uid
        base.extend_from_slice(&f.cdhash); //                            cdhash (20)
        base.extend_from_slice(&0u64.to_le_bytes()); // v2 only: the 8 bytes at 0x4c
        assert_eq!(base.len(), 4 + 8 + 4 + 8 + 0x28); // process block is 0x28 in v2
        base.extend_from_slice(&0u32.to_le_bytes()); // payload: status
        base.extend_from_slice(&1u64.to_le_bytes()); //          u64 = 1
        base.extend_from_slice(&0x40cu32.to_le_bytes()); //      blob length
        base.extend_from_slice(&1u32.to_le_bytes()); //          blob version
        base.extend_from_slice(&f.cpx.to_le_bytes()); //         cpx
        base.extend_from_slice(&4u32.to_le_bytes()); //          mode
        base.resize(base.len() + 0x400, 0); //                   reserved
        assert_eq!(&b[0x04..0x14], &sha256(&base)[..16]);
        // In v2 the 8 bytes at 0x4c ARE covered (unlike v1): flipping one changes the digest.
        let mut c = b;
        c[0x4c] = 1;
        assert_ne!(frame_digest(&c, 2, 0x54, 0x470).unwrap(), frame_digest(&b, 2, 0x54, 0x470).unwrap());
    }

    #[test]
    fn gate_refuses_every_constant_change() {
        let good = encode_setenv(&fields());
        // Header + body constants, and the two blob constants.
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x58, 0x60, 0x64, 0x6c] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_setenv(&b).is_err(), "offset {o:#x}");
        }
        // A non-zero byte anywhere in the reserved area → refused.
        for &o in &[0x70usize, 0x200, 0x46f] {
            let mut b = good;
            b[o] = 1;
            assert!(check_setenv(&b).is_err(), "reserved {o:#x}");
        }
        // cpx is contextual: changing it (and recomputing the digest) is accepted with the new value.
        let other = SetenvFields { cpx: 0, ..fields() };
        assert_eq!(check_setenv(&encode_setenv(&other)).unwrap().cpx, 0);
        // Contextual header fields changed without recomputing the digest → refused.
        for &o in &[0x18usize, 0x2c, 0x34, 0x38] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_setenv(&b).is_err(), "offset {o:#x}");
        }
        // Bad cdhash even with a correct digest → refused.
        let mut b = good;
        b[0x38] ^= 0xff;
        let d = frame_digest(&b, 2, 0x54, 0x470).unwrap();
        b[4..20].copy_from_slice(&d);
        assert!(check_setenv(&b).is_err());
        assert!(check_setenv(&good[..0x46f]).is_err());
    }

    /// Builds a 0x58 reply as seen in c12 L181 (L = 0x50, v2, header + status) and decodes it back.
    fn reply(state: u32) -> [u8; 0x58] {
        let mut b = [0u8; 0x58];
        b[0..4].copy_from_slice(&0x50u32.to_le_bytes());
        b[0x14..0x18].copy_from_slice(&2u32.to_le_bytes());
        b[0x54..0x58].copy_from_slice(&state.to_le_bytes());
        let d = frame_digest(&b, 2, 0x54, 0x58).unwrap();
        b[4..20].copy_from_slice(&d);
        b
    }

    #[test]
    fn reply_decode() {
        let w = Word::decode(0x0058_0000_0002_aa12);
        assert_eq!(w, Word::new(0x12, 0xaa, 0x02, 0x00, 0x0058_0000));
        assert!(is_setenv_reply(&w));
        let rw = reply_word(&w);
        assert_eq!((rw.status, rw.len, rw.call_flags), (0, 0x58, 0));
        assert!(!is_setenv_reply(&Word::new(0x12, 0x2a, 0x02, 0, 0))); // request, bit 7 clear
        assert!(!is_setenv_reply(&Word::new(0x12, 0xcd, 0x01, 0, 0))); // get_capabilities reply (TYPE 0x01)

        let mut snap = [0u8; 0x80];
        snap[..0x58].copy_from_slice(&reply(0));
        let r = decode_setenv_reply(&snap, 0x58).unwrap();
        assert_eq!((r.hlen, r.version, r.digest_ok, r.state), (0x50, 2, true, 0));
        assert_eq!(decode_setenv_reply(&reply(5), 0x58).unwrap().state, 5);
        let mut bad = reply(0);
        bad[0x54] = 9;
        assert!(!decode_setenv_reply(&bad, 0x58).unwrap().digest_ok);
        assert!(decode_setenv_reply(&reply(0), 0x54).is_err(), "consumed != len");
        assert!(decode_setenv_reply(&snap, 0x81).is_err(), "len > snapshot");
    }

    #[test]
    fn gate_once() {
        let mut g = SetenvGate::closed();
        assert!(!g.admit(&setenv_word()), "closed");
        g.arm();
        assert!(!g.admit(&Word::new(0x12, 0x2a, 0x01, 0, SETENV_DATA)), "wrong TYPE");
        assert!(!g.admit(&Word::new(0x12, 0x4d, 0x02, 0, SETENV_DATA)), "wrong TAG");
        assert!(!g.admit(&Word::new(0x12, 0x2a, 0x02, 0, 0x0470_0001)), "wrong DATA");
        assert!(g.admit(&setenv_word()));
        assert!(g.used());
        assert!(!g.admit(&setenv_word()), "twice");
        g.arm();
        assert!(!g.admit(&setenv_word()), "re-armed after use");
    }

    // --- small test helpers (std only; the module itself is no_std) ---
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
}
