//! SKS (EP 0x12) IPC frame, THIRD exchange of experiment J9c (`docs/sks_native_plan.md`): `null_d_key` (TAG 0x0a),
//! sent right after `get_capabilities` (TAG 0x4d) and `set_env` (TAG 0x2a), SKIPPING the two `perform_operation`
//! (TAG 0x22, txn3/txn5 of the macOS bring-up). No allocation, no `std`: this file is also included as is by the
//! kernel module (`kmod/sep_native.rs`), which uses it to CHECK the request written by userspace and to decode the
//! reply. It reuses the IPC header primitives of `sks_ipc` (same header layout, same digest function).
//!
//! **Byte layout established by DISASSEMBLY (VU, not a guess)** — kernelcache 27.2.1
//! `macos/kc/26B131__MacBookPro18,4/kernelcache.release.*`, bundle `com.apple.driver.AppleSEPKeyStore`:
//!   - `__ipc_null_d_key` @0xfffffe0009cdbbd0: builds a ctx on the stack with `ctx+0x50 = 0` (status) and
//!     `ctx+0x58 = arg2`, submits op code `w1 = 0xa`.
//!   - `_code_ipc_null_d_key` @0xfffffe0009cdfc38: the generic codec writes ONLY the IPC header (`0xcff530`),
//!     then a u32 from `ctx+0x50` (`__word`, @0xcff1c0) and a u64 from `ctx+0x58` (`__lword`, @0xcff38c).
//!     There is **NO** `__word` for a blob length and **NO** `__blob` (unlike `get_capabilities`, which adds a
//!     blob-length word → 0x64, and `set_env`, which adds a blob → 0x470). So the body is header + status(4) +
//!     u64(8) = 0x54 + 4 + 8 = **0x60**, matching the trace c12 L186 (`> 0x12 TAG 0x0a TYPE 0x04 DATA 0x00600000`).
//!   - The single caller `AppleKeyStore::effaceable_init(bool)` @…cc6f20 passes `x1 = 0` (NULL session → the SEP
//!     default keybag handle) and `x2 = 1` → the u64 at OOL 0x58 is the **constant 1** (same value as
//!     `get_capabilities` and `set_env`). VU.
//!
//! `null_d_key` at the bring-up is the transaction AFTER `set_env`, so its header version = the negotiated v2
//! (`get_capabilities` returned theirs = 2, confirmed on hardware by J9a). The body is therefore byte-for-byte
//! `get_capabilities` MINUS the trailing blob-length word, in v2.
//!
//! In J9c the transaction counter is: get_capabilities = 1, set_env = 2, **null_d_key = 3** (on the wire macOS used
//! 4 because the two perform_operation took 3 and 5; here they are skipped, so the counter has no gap: 1, 2, 3).
//!
//! Request, 0x60 bytes in OOL A, word `> EP 0x12 TAG 0x0a TYPE 0x03 PARAM 0 DATA 0x00600000`:
//!
//! | off  | size | field                              | value here                                     |
//! |------|------|------------------------------------|------------------------------------------------|
//! | 0x00 | 4    | header length                      | 0x50 (constant)                                |
//! | 0x04 | 16   | SHA-256/16, v2 base                | computed                                       |
//! | 0x14 | 4    | header version                     | 2 (negotiated)                                 |
//! | 0x18 | 8    | timestamp µs                       | contextual                                     |
//! | 0x20 | 4    | flags                              | 0 (constant)                                   |
//! | 0x24 | 8    | context field +0x20                | 0 (constant)                                   |
//! | 0x2c | 8    | process unique id                  | contextual                                     |
//! | 0x34 | 4    | credential field (user id)         | contextual                                     |
//! | 0x38 | 20   | cdhash; else SHA-1 of the 8 b @0x2c| contextual                                     |
//! | 0x4c | 8    | context +0x48..0x4f                | 0 (constant; in the v2 digest)                 |
//! | 0x54 | 4    | status word                        | 0 (constant)                                   |
//! | 0x58 | 8    | u64 argument                       | 1 (constant; arg2 of __ipc_null_d_key = VU)    |
//!
//! Total = 0x60 (no blob length, no blob).
//!
//! Expected reply (macOS, c12 L187): `< EP 0x12 TAG 0x8a TYPE 0x04 PARAM 0xff DATA 0x00000000`. Here TYPE = our
//! transaction 0x03. PARAM = signed status; macOS returns **0xff (= -1)** with DATA 0, i.e. no OOL B body: by the
//! matching rule (`docs/sks_protocol.md` §1.6.4) PARAM != 0 means the request returns that code without decoding a
//! body. 0xff here is the benign « no d-key to null » result. So for J9c a paired reply (TAG bit 7, TYPE 0x03) with
//! PARAM 0xff reproduces macOS and means the two skipped perform_operation were NOT a prerequisite. A different
//! paired status, SILENCE or Halted is the interesting negative result (reported as is; the caller interprets).
use crate::sks_ipc::{
    cdhash_kind, frame_digest, CdhashKind, GetcapFields, CDHASH_LEN, DIGEST_LEN, EP_SKS, HDR_LEN_AP, HLEN_MIN_V1,
    HLEN_MIN_V2, OFF_ARG, OFF_CDHASH, OFF_DIGEST, OFF_F20, OFF_FLAGS, OFF_HLEN, OFF_STATE, OFF_TS, OFF_UID,
    OFF_UNIQUEID, OFF_VERSION, OFF_X48,
};
use crate::word::Word;
use crate::{Error, Result};

/// IPC operation code of `null_d_key` = TAG of the request word.
pub const OP_NULL_D_KEY: u8 = 0x0a;
/// Third transaction of J9c (get_capabilities = 1, set_env = 2, null_d_key = 3).
pub const NULLDKEY_TXN: u8 = 0x03;
pub const NULLDKEY_LEN: usize = 0x60;
/// DATA of the request word: OOL length in bits 16-31.
pub const NULLDKEY_DATA: u32 = (NULLDKEY_LEN as u32) << 16;
/// Negotiated header version (v2; null_d_key follows get_capabilities/set_env).
pub const HDR_VERSION_V2: u32 = 2;
/// u64 argument at OOL 0x58: the constant 1 (arg2 passed by `effaceable_init`; same as get_capabilities/set_env). VU.
pub const NULLDKEY_ARG: u64 = 1;
/// Reply length seen on macOS: 0 (PARAM 0xff, no body). We still accept a body if the SEP ever returns PARAM 0.
pub const REPLY_LEN_SEEN: u16 = 0;

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

/// The exact request word (and the only `null_d_key` word the driver may ever send).
pub const fn nulldkey_word() -> Word {
    Word::new(EP_SKS, OP_NULL_D_KEY, NULLDKEY_TXN, 0, NULLDKEY_DATA)
}

/// Contextual fields of the request (same shape as `get_capabilities`; there is no blob).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NulldkeyFields {
    pub ts_us: u64,
    pub uniqueid: u64,
    pub uid: u32,
    pub cdhash: [u8; CDHASH_LEN],
}

impl NulldkeyFields {
    fn header(&self) -> GetcapFields {
        GetcapFields { ts_us: self.ts_us, uniqueid: self.uniqueid, uid: self.uid, cdhash: self.cdhash }
    }
}

/// Builds the 0x60 bytes of the request (constants above, `f` for the contextual fields, v2 digest last).
pub fn encode_nulldkey(f: &NulldkeyFields) -> [u8; NULLDKEY_LEN] {
    let mut b = [0u8; NULLDKEY_LEN];
    b[OFF_HLEN..OFF_HLEN + 4].copy_from_slice(&HDR_LEN_AP.to_le_bytes());
    b[OFF_VERSION..OFF_VERSION + 4].copy_from_slice(&HDR_VERSION_V2.to_le_bytes());
    b[OFF_TS..OFF_TS + 8].copy_from_slice(&f.ts_us.to_le_bytes());
    // flags (0x20), field +0x20 (0x24), 0x4c..0x54, status (0x54): zeros.
    b[OFF_UNIQUEID..OFF_UNIQUEID + 8].copy_from_slice(&f.uniqueid.to_le_bytes());
    b[OFF_UID..OFF_UID + 4].copy_from_slice(&f.uid.to_le_bytes());
    b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN].copy_from_slice(&f.cdhash);
    b[OFF_ARG..OFF_ARG + 8].copy_from_slice(&NULLDKEY_ARG.to_le_bytes());
    // Cannot fail: version 2, header end 0x54 = 0x14 + 0x40, end 0x60.
    let d = frame_digest(&b, HDR_VERSION_V2, OFF_STATE, NULLDKEY_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// Kernel gate on the 0x60 bytes from userspace: exact length, every CONSTANT field, v2 digest recomputed, cdhash in
/// one of the two documented AP forms. There is no contextual value other than the header fields (no blob, no cpx).
pub fn check_nulldkey(b: &[u8]) -> Result<NulldkeyFields> {
    if b.len() != NULLDKEY_LEN {
        return Err(Error::OutOfRange("null_d_key request length", b.len() as u64));
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
    want64(OFF_ARG, NULLDKEY_ARG, "u64 argument (0x58) != 1")?;
    let d = frame_digest(b, HDR_VERSION_V2, OFF_STATE, NULLDKEY_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("digest (0x04) != SHA-256/16 of the documented v2 base"));
    }
    let mut cdhash = [0u8; CDHASH_LEN];
    cdhash.copy_from_slice(&b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN]);
    let f = NulldkeyFields { ts_us: le64(b, OFF_TS)?, uniqueid: le64(b, OFF_UNIQUEID)?, uid: le32(b, OFF_UID)?, cdhash };
    if cdhash_kind(&f.header()) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    Ok(f)
}

/// `true` iff `w` is a reply to our `null_d_key` as the kext matches it: EP 0x12, TAG bit 7 set, TYPE = our txn 0x03.
pub fn is_nulldkey_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == NULLDKEY_TXN
}

/// Re-exported from `sks_ipc`: the reply word has the same shape (PARAM = signed status, DATA = len<<16 | call flags).
pub use crate::sks_ipc::reply_word;

/// Decoded `null_d_key` reply payload (OOL B), ONLY meaningful when PARAM = 0 (macOS returns PARAM 0xff with no body,
/// so this is normally not decoded). Same shape as the generic frame: header + status, no u64, no blob.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NulldkeyReply {
    pub hlen: u32,
    pub version: u32,
    pub digest_ok: bool,
    pub state: u32,
}

/// Decodes `len` bytes of OOL B (only called when PARAM = 0). Structural errors → `Err`; a wrong digest or non-zero
/// status are reported in the result.
pub fn decode_nulldkey_reply(b: &[u8], len: usize) -> Result<NulldkeyReply> {
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
    Ok(NulldkeyReply { hlen, version, digest_ok: b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] == d, state })
}

/// Send gate: once armed, admits exactly `nulldkey_word()`, once; nothing else, ever.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NulldkeyGate {
    armed: bool,
    used: bool,
}

impl NulldkeyGate {
    pub const fn closed() -> Self {
        NulldkeyGate { armed: false, used: false }
    }

    pub fn arm(&mut self) {
        if !self.used {
            self.armed = true;
        }
    }

    pub fn admit(&mut self, w: &Word) -> bool {
        let ok = self.armed && !self.used && *w == nulldkey_word();
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

    fn fields() -> NulldkeyFields {
        NulldkeyFields { ts_us: 0x1122_3344_5566_7788, uniqueid: 0, uid: 0, cdhash: cdhash_no_process(0) }
    }

    #[test]
    fn word_is_c12_shape() {
        // c12 L186 word, with our J9c transaction number 0x03 instead of macOS' 0x04.
        assert_eq!(nulldkey_word(), Word::new(0x12, 0x0a, 0x03, 0x00, 0x0060_0000));
        // Body = header(0x54) + status(4) + u64(8), NO blob length (unlike get_capabilities' 0x64).
        assert_eq!(NULLDKEY_LEN, 0x54 + 4 + 8);
    }

    #[test]
    fn encoder_layout_and_reread() {
        let f = fields();
        let b = encode_nulldkey(&f);
        assert_eq!(le32(&b, 0x00).unwrap(), 0x50);
        assert_eq!(le32(&b, 0x14).unwrap(), 2);
        assert_eq!(le64(&b, 0x18).unwrap(), 0x1122_3344_5566_7788);
        assert_eq!(le32(&b, 0x20).unwrap(), 0);
        assert_eq!(le64(&b, 0x24).unwrap(), 0);
        assert_eq!(le64(&b, 0x2c).unwrap(), 0);
        assert_eq!(le32(&b, 0x34).unwrap(), 0);
        assert_eq!(&b[0x38..0x4c], &cdhash_no_process(0));
        assert_eq!(le64(&b, 0x4c).unwrap(), 0);
        assert_eq!(le32(&b, 0x54).unwrap(), 0); // status
        assert_eq!(le64(&b, 0x58).unwrap(), 1); // u64 = 1
        assert_eq!(check_nulldkey(&b).unwrap(), f);
    }

    /// Full-request fingerprint against an independent Python/hashlib construction (session ALARM 2026-11-23):
    /// ts = 0x1122334455667788, uniqueid 0, uid 0, cdhash = sha1(8 × 0x00), v2, u64 = 1.
    #[test]
    fn request_matches_independent_construction() {
        let b = encode_nulldkey(&fields());
        assert_eq!(&b[0x04..0x14], &hex16("d51461e0ab398833f4f0e23b6ce34b18"));
        assert_eq!(sha256(&b), hex32("e90ebe700cacdeb3a9081f10ecdf433ce0984a45cb2c4cbd77bc4f09d103dbfa"));
    }

    /// v2 digest base built here field by field independently of the encoder (§1.6.3 + §1.7.1): identical to the
    /// get_capabilities/set_env base but the payload is only status(4) + u64(8) (no blob length word).
    #[test]
    fn digest_base_is_the_documented_v2_one() {
        let f = NulldkeyFields { ts_us: 0x1234, uniqueid: 0x0102_0304_0506_0708, uid: 0x4242, cdhash: [0; 20] };
        let b = encode_nulldkey(&f);
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
        base.extend_from_slice(&1u64.to_le_bytes()); //          u64 = 1 (NO blob length word)
        assert_eq!(base.len(), 0x4c);
        assert_eq!(&b[0x04..0x14], &sha256(&base)[..16]);
        // In v2 the 8 bytes at 0x4c ARE covered: flipping one changes the digest.
        let mut c = b;
        c[0x4c] = 1;
        assert_ne!(frame_digest(&c, 2, 0x54, 0x60).unwrap(), frame_digest(&b, 2, 0x54, 0x60).unwrap());
    }

    #[test]
    fn gate_refuses_every_constant_change() {
        let good = encode_nulldkey(&fields());
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x58] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_nulldkey(&b).is_err(), "offset {o:#x}");
        }
        // Contextual header fields changed without recomputing the digest → refused.
        for &o in &[0x18usize, 0x2c, 0x34, 0x38] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_nulldkey(&b).is_err(), "offset {o:#x}");
        }
        // Bad cdhash even with a correct digest → refused.
        let mut b = good;
        b[0x38] ^= 0xff;
        let d = frame_digest(&b, 2, 0x54, 0x60).unwrap();
        b[4..20].copy_from_slice(&d);
        assert!(check_nulldkey(&b).is_err());
        // Wrong length.
        assert!(check_nulldkey(&good[..0x5f]).is_err());
        assert!(check_nulldkey(&[good.as_slice(), &[0]].concat()).is_err());
    }

    #[test]
    fn reply_match_and_decode() {
        // macOS c12 L187 shape, with our TYPE 0x03: `< 0x12 TAG 0x8a TYPE 0x03 PARAM 0xff DATA 0`.
        let w = Word::decode(0x0000_0000_03_8a_12 | (0xffu64 << 24));
        assert_eq!(w, Word::new(0x12, 0x8a, 0x03, 0xff, 0x0000_0000));
        assert!(is_nulldkey_reply(&w));
        let rw = reply_word(&w);
        assert_eq!((rw.status, rw.len, rw.call_flags), (-1, 0, 0));
        // Not a reply: request word (bit 7 clear), or wrong TYPE (getcap/set_env replies).
        assert!(!is_nulldkey_reply(&Word::new(0x12, 0x0a, 0x03, 0, 0)));
        assert!(!is_nulldkey_reply(&Word::new(0x12, 0xcd, 0x01, 0, 0)));
        assert!(!is_nulldkey_reply(&Word::new(0x12, 0xaa, 0x02, 0, 0)));

        // If the SEP ever answered PARAM 0 with a 0x58 body, it decodes like the generic header + status frame.
        let mut snap = [0u8; 0x80];
        snap[0..4].copy_from_slice(&0x50u32.to_le_bytes());
        snap[0x14..0x18].copy_from_slice(&2u32.to_le_bytes());
        snap[0x54..0x58].copy_from_slice(&0u32.to_le_bytes());
        let d = frame_digest(&snap[..0x58], 2, 0x54, 0x58).unwrap();
        snap[4..20].copy_from_slice(&d);
        let r = decode_nulldkey_reply(&snap, 0x58).unwrap();
        assert_eq!((r.hlen, r.version, r.digest_ok, r.state), (0x50, 2, true, 0));
        assert!(decode_nulldkey_reply(&snap, 0x81).is_err());
    }

    #[test]
    fn gate_once() {
        let mut g = NulldkeyGate::closed();
        assert!(!g.admit(&nulldkey_word()), "closed");
        g.arm();
        assert!(!g.admit(&Word::new(0x12, 0x0a, 0x04, 0, NULLDKEY_DATA)), "wrong TYPE");
        assert!(!g.admit(&Word::new(0x12, 0x4d, 0x03, 0, NULLDKEY_DATA)), "wrong TAG");
        assert!(!g.admit(&Word::new(0x12, 0x0a, 0x03, 0, 0x0060_0001)), "wrong DATA");
        assert!(g.admit(&nulldkey_word()));
        assert!(g.used());
        assert!(!g.admit(&nulldkey_word()), "twice");
        g.arm();
        assert!(!g.admit(&nulldkey_word()), "re-armed after use");
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
