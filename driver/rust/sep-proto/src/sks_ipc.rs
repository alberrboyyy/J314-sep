//! SKS (EP 0x12) IPC frame, FIRST exchange only: `get_capabilities` (TAG 0x4d), experiment J9a
//! (`docs/sks_native_plan.md` §4 exp. 2, §6). No allocation, no `std`: this file is also included as is by the kernel
//! module (`kmod/sep_native.rs`), which uses it to CHECK the request written by userspace and to decode the reply.
//!
//! Written from `docs/sks_protocol.md` §1.6 and `docs/sks_ipc_negotiation.md` §3-§4 (`source: kext` 13.5, NOT verified
//! on hardware); nothing is copied from Apple code. Every scalar is little-endian.
//!
//! Request, 0x64 bytes in OOL A, word `> EP 0x12 TAG 0x4d TYPE 0x01 PARAM 0 DATA 0x00640000` (c12 L178):
//!
//! | off  | size | field                                                  | value here                         |
//! |------|------|--------------------------------------------------------|------------------------------------|
//! | 0x00 | 4    | header length                                          | 0x50 (constant)                    |
//! | 0x04 | 16   | SHA-256 (unkeyed) truncated to 16 bytes, base below    | computed                           |
//! | 0x14 | 4    | header version                                         | 1 (constant for this request)      |
//! | 0x18 | 8    | timestamp, µs (`_get_usec_time`: clock NOT documented) | contextual (caller's choice)       |
//! | 0x20 | 4    | flags (bit 0 encrypted, bit 1 extended header)         | 0 (constant)                       |
//! | 0x24 | 8    | context field +0x20                                    | 0 (constant)                       |
//! | 0x2c | 8    | process unique id                                      | contextual                         |
//! | 0x34 | 4    | credential field (user id, deduced)                    | contextual                         |
//! | 0x38 | 20   | cdhash; without a process: SHA-1 of the 8 bytes at 0x2c | contextual                        |
//! | 0x4c | 8    | context +0x48..0x4f                                    | 0 (constant; in the digest only v2)|
//! | 0x54 | 4    | status word                                            | 0 (constant)                       |
//! | 0x58 | 8    | u64 argument                                           | 1 (constant; meaning unknown)      |
//! | 0x60 | 4    | blob length                                            | 0 (constant)                       |
//!
//! Digest base (§1.6.3), in this order: version (4) ‖ timestamp (8) ‖ flags (4) ‖ field +0x20 (8) ‖ process block
//! (0x20 bytes in v1, 0x28 in v2) ‖ payload (everything after the header). In the buffer, version..process block are
//! contiguous: v1 = bytes 0x14..0x4c, v2 = 0x14..0x54; payload = header_end..end (0x54..0x64 for the request).
//!
//! Reply word `< EP 0x12 TAG 0xcd TYPE 0x01 PARAM s DATA 0x005c0001` (c12 L179): PARAM = signed status, DATA low 16 bits
//! = call flags (bit 0 = invalidate cache), high 16 bits = reply length in OOL B. Reply payload: u32 L, L bytes of header
//! (rounded up to 4), u32 status (must be 0), u64 « theirs » (SEP header version), blob (u32 length + data rounded to
//! 4); bytes consumed must equal the announced length. The 0x5c layout (L = 0x48) is DEDUCED from sizes (§1.6.4).
use crate::hash::{sha1, Sha256};
use crate::word::Word;
use crate::{Error, Result};

pub const EP_SKS: u8 = 0x12;
/// IPC operation code of `get_capabilities` = TAG of the request word.
pub const OP_GET_CAPABILITIES: u8 = 0x4d;
/// First transaction of the boot (the AppleKeyStore counter starts at 1).
pub const GETCAP_TXN: u8 = 0x01;
pub const GETCAP_LEN: usize = 0x64;
/// DATA of the request word: OOL length in bits 16-31, 0 in bits 0-15.
pub const GETCAP_DATA: u32 = (GETCAP_LEN as u32) << 16;
/// Value of the header-length field written by the AP encoder.
pub const HDR_LEN_AP: u32 = 0x50;
pub const HDR_VERSION_REQ: u32 = 1;
/// u64 argument of the request (constant at both call sites in the kext).
pub const GETCAP_ARG: u64 = 1;
/// Maximal header version the AP accepts (« ours »); negotiated = min(theirs, OURS).
pub const OURS: u64 = 2;

pub const OFF_HLEN: usize = 0x00;
pub const OFF_DIGEST: usize = 0x04;
pub const OFF_VERSION: usize = 0x14;
pub const OFF_TS: usize = 0x18;
pub const OFF_FLAGS: usize = 0x20;
pub const OFF_F20: usize = 0x24;
pub const OFF_UNIQUEID: usize = 0x2c;
pub const OFF_UID: usize = 0x34;
pub const OFF_CDHASH: usize = 0x38;
pub const OFF_X48: usize = 0x4c;
pub const OFF_STATE: usize = 0x54;
pub const OFF_ARG: usize = 0x58;
pub const OFF_BLOBLEN: usize = 0x60;
pub const DIGEST_LEN: usize = 16;
pub const CDHASH_LEN: usize = 20;
/// Bytes of the header covered by the digest, from OFF_VERSION: v1 (version 4 + ts 8 + flags 4 + field 8 + process
/// block 0x20) and v2 (process block 0x28).
pub const COVER_V1: usize = 0x38;
pub const COVER_V2: usize = 0x40;
/// Smallest header length L carrying all the v1 covered fields (0x04 + 0x10 + 0x38 - 4 = 0x48).
pub const HLEN_MIN_V1: u32 = 0x48;
pub const HLEN_MIN_V2: u32 = 0x50;
/// Reply length seen on 6/6 macOS boots (c1, c3, c8, c9, c11, c12).
pub const REPLY_LEN_SEEN: u16 = 0x5c;

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

/// The exact request word (and the only word to EP 0x12 the driver may ever send).
pub const fn getcap_word() -> Word {
    Word::new(EP_SKS, OP_GET_CAPABILITIES, GETCAP_TXN, 0, GETCAP_DATA)
}

/// Contextual fields of the request (everything else is constant).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GetcapFields {
    pub ts_us: u64,
    pub uniqueid: u64,
    pub uid: u32,
    pub cdhash: [u8; CDHASH_LEN],
}

/// Which documented AP form the cdhash field has.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CdhashKind {
    /// SHA-1 of the 8 bytes of the unique id (AP path « no process / no cdhash »).
    Sha1OfUniqueid,
    /// All zeros (AP path « process without cdhash », `sks_ipc_negotiation.md` §3.2).
    Zero,
    /// Anything else (a real code-signing hash: impossible on Linux; refused by `check_getcap`).
    Other,
}

/// cdhash the AP writes when there is no process: SHA-1 of the 8 little-endian bytes of the unique id.
pub fn cdhash_no_process(uniqueid: u64) -> [u8; CDHASH_LEN] {
    sha1(&uniqueid.to_le_bytes())
}

pub fn cdhash_kind(f: &GetcapFields) -> CdhashKind {
    if f.cdhash == [0; CDHASH_LEN] {
        CdhashKind::Zero
    } else if f.cdhash == cdhash_no_process(f.uniqueid) {
        CdhashKind::Sha1OfUniqueid
    } else {
        CdhashKind::Other
    }
}

/// SHA-256/16 of a frame `b` (header at 0, header end `hdr_end`, frame end `end`) for header `version` (1 or 2).
pub fn frame_digest(b: &[u8], version: u32, hdr_end: usize, end: usize) -> Result<[u8; DIGEST_LEN]> {
    let cover = match version {
        1 => COVER_V1,
        2 => COVER_V2,
        v => return Err(Error::OutOfRange("SKS IPC header version", u64::from(v))),
    };
    if OFF_VERSION + cover > hdr_end || hdr_end > end {
        return Err(Error::Short);
    }
    let head = b.get(OFF_VERSION..OFF_VERSION + cover).ok_or(Error::Short)?;
    let tail = b.get(hdr_end..end).ok_or(Error::Short)?;
    let mut s = Sha256::new();
    s.update(head);
    s.update(tail);
    let full = s.finalize();
    let mut out = [0u8; DIGEST_LEN];
    out.copy_from_slice(&full[..DIGEST_LEN]);
    Ok(out)
}

/// Builds the 0x64 bytes of the request (constants of §1.6.2, `f` for the contextual fields, digest last).
pub fn encode_getcap(f: &GetcapFields) -> [u8; GETCAP_LEN] {
    let mut b = [0u8; GETCAP_LEN];
    b[OFF_HLEN..OFF_HLEN + 4].copy_from_slice(&HDR_LEN_AP.to_le_bytes());
    b[OFF_VERSION..OFF_VERSION + 4].copy_from_slice(&HDR_VERSION_REQ.to_le_bytes());
    b[OFF_TS..OFF_TS + 8].copy_from_slice(&f.ts_us.to_le_bytes());
    // flags (0x20), field +0x20 (0x24), 0x4c..0x54, status (0x54): zeros.
    b[OFF_UNIQUEID..OFF_UNIQUEID + 8].copy_from_slice(&f.uniqueid.to_le_bytes());
    b[OFF_UID..OFF_UID + 4].copy_from_slice(&f.uid.to_le_bytes());
    b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN].copy_from_slice(&f.cdhash);
    b[OFF_ARG..OFF_ARG + 8].copy_from_slice(&GETCAP_ARG.to_le_bytes());
    // blob length (0x60): 0.
    // Cannot fail: version 1, header end 0x54 >= 0x14 + 0x38, end 0x64.
    let d = frame_digest(&b, HDR_VERSION_REQ, OFF_STATE, GETCAP_LEN).unwrap_or([0; DIGEST_LEN]);
    b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN].copy_from_slice(&d);
    b
}

/// Kernel gate on the 0x64 bytes from userspace: exact length, every CONSTANT field, digest recomputed, cdhash in one
/// of the two documented AP forms. Returns the contextual fields (for the journal).
pub fn check_getcap(b: &[u8]) -> Result<GetcapFields> {
    if b.len() != GETCAP_LEN {
        return Err(Error::OutOfRange("get_capabilities request length", b.len() as u64));
    }
    let want32 = |o: usize, v: u32, what: &'static str| -> Result<()> {
        let x = le32(b, o)?;
        if x == v { Ok(()) } else { Err(Error::OutOfRange(what, u64::from(x))) }
    };
    let want64 = |o: usize, v: u64, what: &'static str| -> Result<()> {
        let x = le64(b, o)?;
        if x == v { Ok(()) } else { Err(Error::OutOfRange(what, x)) }
    };
    want32(OFF_HLEN, HDR_LEN_AP, "header length (0x00) != 0x50")?;
    want32(OFF_VERSION, HDR_VERSION_REQ, "header version (0x14) != 1")?;
    want32(OFF_FLAGS, 0, "flags (0x20) != 0")?;
    want64(OFF_F20, 0, "field +0x20 (0x24) != 0")?;
    want64(OFF_X48, 0, "context 0x48 (0x4c) != 0")?;
    want32(OFF_STATE, 0, "status (0x54) != 0")?;
    want64(OFF_ARG, GETCAP_ARG, "u64 argument (0x58) != 1")?;
    want32(OFF_BLOBLEN, 0, "blob length (0x60) != 0")?;
    let d = frame_digest(b, HDR_VERSION_REQ, OFF_STATE, GETCAP_LEN)?;
    if b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] != d {
        return Err(Error::Unexpected("digest (0x04) != SHA-256/16 of the documented base"));
    }
    let mut cdhash = [0u8; CDHASH_LEN];
    cdhash.copy_from_slice(&b[OFF_CDHASH..OFF_CDHASH + CDHASH_LEN]);
    let f = GetcapFields { ts_us: le64(b, OFF_TS)?, uniqueid: le64(b, OFF_UNIQUEID)?, uid: le32(b, OFF_UID)?, cdhash };
    if cdhash_kind(&f) == CdhashKind::Other {
        return Err(Error::Unexpected("cdhash (0x38) neither zeros nor SHA-1 of the unique id"));
    }
    Ok(f)
}

/// Fields of the reply word.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReplyWord {
    /// PARAM read as a signed byte (0 = success).
    pub status: i8,
    /// DATA bits 0-15 (bit 0 = « invalidate cache »).
    pub call_flags: u16,
    /// DATA bits 16-31 = reply length in OOL B.
    pub len: u16,
    /// TAG = 0x4d | 0x80 (the kext only tests bit 7; this is informative).
    pub tag_is_cd: bool,
}

/// `true` iff `w` is a reply to our request as the kext matches it: EP 0x12, TAG bit 7 set, TYPE = our transaction.
pub fn is_getcap_reply(w: &Word) -> bool {
    w.ep == EP_SKS && w.tag & 0x80 != 0 && w.ty == GETCAP_TXN
}

pub fn reply_word(w: &Word) -> ReplyWord {
    ReplyWord {
        status: w.param as i8,
        call_flags: w.data as u16,
        len: (w.data >> 16) as u16,
        tag_is_cd: w.tag == OP_GET_CAPABILITIES | 0x80,
    }
}

/// Decoded reply payload (OOL B).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GetcapReply {
    /// Header length field L.
    pub hlen: u32,
    pub version: u32,
    /// Digest recomputed on the reply (base per the version read in the SEP header) = bytes 0x04..0x14.
    pub digest_ok: bool,
    pub ts_us: u64,
    pub flags: u32,
    pub uniqueid: u64,
    pub uid: u32,
    /// Status word: must be 0 for success.
    pub state: u32,
    /// SEP header version (« theirs »); negotiated = min(theirs, OURS).
    pub theirs: u64,
    pub blob_len: u32,
}

impl GetcapReply {
    pub fn negotiated(&self) -> u64 {
        self.theirs.min(OURS)
    }
}

/// Decodes `len` bytes of OOL B (the snapshot `b` must hold at least `len` bytes). Structural errors (lengths, unknown
/// version, extended header present, bytes consumed != length) → `Err`; a wrong digest or a non-zero status are
/// reported in the result (the caller decides).
pub fn decode_getcap_reply(b: &[u8], len: usize) -> Result<GetcapReply> {
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
    let theirs = le64(b, hdr_end + 4)?;
    let blob_len = le32(b, hdr_end + 12)?;
    let consumed = (hdr_end + 16).checked_add(align4(blob_len as usize)).ok_or(Error::Short)?;
    if consumed != len {
        return Err(Error::OutOfRange("reply bytes consumed != announced length", consumed as u64));
    }
    let d = frame_digest(b, version, hdr_end, len)?;
    Ok(GetcapReply {
        hlen,
        version,
        digest_ok: b[OFF_DIGEST..OFF_DIGEST + DIGEST_LEN] == d,
        ts_us: le64(b, OFF_TS)?,
        flags,
        uniqueid: le64(b, OFF_UNIQUEID)?,
        uid: le32(b, OFF_UID)?,
        state,
        theirs,
        blob_len,
    })
}

/// Send gate: once armed, admits exactly `getcap_word()`, once; nothing else, ever.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GetcapGate {
    armed: bool,
    used: bool,
}

impl GetcapGate {
    pub const fn closed() -> Self {
        GetcapGate { armed: false, used: false }
    }

    /// Arms the gate (no effect once the word has been admitted: one request per boot).
    pub fn arm(&mut self) {
        if !self.used {
            self.armed = true;
        }
    }

    pub fn admit(&mut self, w: &Word) -> bool {
        let ok = self.armed && !self.used && *w == getcap_word();
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

// --- record read from /dev/sep_sks (kernel -> userspace) -----------------------------------------------------------
pub const OUT_MAGIC: [u8; 4] = *b"SKG1";
/// Bytes of OOL B snapshotted when the reply word arrives.
pub const OUT_SNAP: usize = 0x80;
pub const OUT_HDR: usize = 0x18;
pub const OUT_SIZE: usize = OUT_HDR + OUT_SNAP;
/// Outcome kinds.
pub const OUT_REPLIED: u32 = 1;
pub const OUT_SILENCE: u32 = 2;
pub const OUT_NOT_SENT: u32 = 3;

/// Record: magic (4) ‖ kind u32 ‖ raw reply word u64 (0 if none) ‖ snapshot length u32 ‖ 0 u32 ‖ snapshot (0x80).
pub fn encode_outcome(kind: u32, raw: u64, snap: &[u8; OUT_SNAP]) -> [u8; OUT_SIZE] {
    let mut r = [0u8; OUT_SIZE];
    r[0..4].copy_from_slice(&OUT_MAGIC);
    r[4..8].copy_from_slice(&kind.to_le_bytes());
    r[8..16].copy_from_slice(&raw.to_le_bytes());
    r[16..20].copy_from_slice(&(OUT_SNAP as u32).to_le_bytes());
    r[OUT_HDR..].copy_from_slice(snap);
    r
}

pub fn decode_outcome(r: &[u8]) -> Result<(u32, u64, &[u8])> {
    if r.len() < OUT_HDR {
        return Err(Error::Short);
    }
    if r[0..4] != OUT_MAGIC {
        return Err(Error::BadMagic);
    }
    let kind = le32(r, 4)?;
    let raw = le64(r, 8)?;
    let n = le32(r, 16)? as usize;
    let snap = r.get(OUT_HDR..OUT_HDR + n).ok_or(Error::Short)?;
    if !(OUT_REPLIED..=OUT_NOT_SENT).contains(&kind) {
        return Err(Error::OutOfRange("outcome kind", u64::from(kind)));
    }
    Ok((kind, raw, snap))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hash::sha256;

    fn fields() -> GetcapFields {
        GetcapFields { ts_us: 0x0011_2233_4455_6677, uniqueid: 0, uid: 0, cdhash: cdhash_no_process(0) }
    }

    #[test]
    fn word_is_c12_l178() {
        // c12 L178: `> EP=0x12 TAG=0x4d TYPE=0x01 PARAM=0x00 DATA=0x00640000`.
        assert_eq!(getcap_word(), Word::new(0x12, 0x4d, 0x01, 0x00, 0x0064_0000));
        assert_eq!(GETCAP_LEN, 0x54 + 4 + 8 + 4);
    }

    #[test]
    fn encoder_layout_and_reread() {
        let f = fields();
        let b = encode_getcap(&f);
        assert_eq!(le32(&b, 0x00).unwrap(), 0x50);
        assert_eq!(le32(&b, 0x14).unwrap(), 1);
        assert_eq!(le64(&b, 0x18).unwrap(), 0x0011_2233_4455_6677);
        assert_eq!(le32(&b, 0x20).unwrap(), 0);
        assert_eq!(le64(&b, 0x24).unwrap(), 0);
        assert_eq!(le64(&b, 0x2c).unwrap(), 0);
        assert_eq!(le32(&b, 0x34).unwrap(), 0);
        assert_eq!(&b[0x38..0x4c], &cdhash_no_process(0));
        assert_eq!(le64(&b, 0x4c).unwrap(), 0);
        assert_eq!(le32(&b, 0x54).unwrap(), 0);
        assert_eq!(le64(&b, 0x58).unwrap(), 1);
        assert_eq!(le32(&b, 0x60).unwrap(), 0);
        assert_eq!(check_getcap(&b).unwrap(), f);
        let z = GetcapFields { cdhash: [0; 20], uniqueid: 7, uid: 501, ..f };
        assert_eq!(check_getcap(&encode_getcap(&z)).unwrap(), z);
        assert_eq!(cdhash_kind(&z), CdhashKind::Zero);
        assert_eq!(cdhash_kind(&f), CdhashKind::Sha1OfUniqueid);
    }

    /// Digest base = version ‖ ts ‖ flags ‖ field +0x20 ‖ process block (0x20 o) ‖ payload, built here field by field
    /// independently of the encoder (§1.6.3).
    #[test]
    fn digest_base_is_the_documented_one() {
        let f = GetcapFields { ts_us: 0x1234_5678_9abc_def0, uniqueid: 0x0102_0304_0506_0708, uid: 0x4242, cdhash: [0; 20] };
        let f = GetcapFields { cdhash: cdhash_no_process(f.uniqueid), ..f };
        let b = encode_getcap(&f);
        let mut base = Vec::new();
        base.extend_from_slice(&1u32.to_le_bytes()); // version
        base.extend_from_slice(&f.ts_us.to_le_bytes()); // timestamp
        base.extend_from_slice(&0u32.to_le_bytes()); // flags
        base.extend_from_slice(&0u64.to_le_bytes()); // field +0x20
        base.extend_from_slice(&f.uniqueid.to_le_bytes()); // process block: unique id
        base.extend_from_slice(&f.uid.to_le_bytes()); //                  uid
        base.extend_from_slice(&f.cdhash); //                            cdhash (20)
        assert_eq!(base.len(), 4 + 8 + 4 + 8 + 0x20);
        base.extend_from_slice(&0u32.to_le_bytes()); // payload: status
        base.extend_from_slice(&1u64.to_le_bytes()); //          u64 = 1
        base.extend_from_slice(&0u32.to_le_bytes()); //          blob length
        assert_eq!(base.len(), 0x48);
        assert_eq!(&b[0x04..0x14], &sha256(&base)[..16]);
        // The 8 bytes at 0x4c are NOT covered in v1.
        let mut c = b;
        c[0x4c] = 1;
        assert_eq!(frame_digest(&c, 1, 0x54, 0x64).unwrap(), frame_digest(&b, 1, 0x54, 0x64).unwrap());
    }

    #[test]
    fn gate_refuses_every_constant_change() {
        let good = encode_getcap(&fields());
        for &o in &[0x00usize, 0x14, 0x20, 0x24, 0x4c, 0x54, 0x58, 0x60] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_getcap(&b).is_err(), "offset {o:#x}");
        }
        // Contextual fields changed without recomputing the digest → refused (digest).
        for &o in &[0x18usize, 0x2c, 0x34, 0x38] {
            let mut b = good;
            b[o] ^= 0x01;
            assert!(check_getcap(&b).is_err(), "offset {o:#x}");
        }
        // A cdhash that is neither form → refused even with a correct digest.
        let mut b = good;
        b[0x38] ^= 0xff;
        let d = frame_digest(&b, 1, 0x54, 0x64).unwrap();
        b[4..20].copy_from_slice(&d);
        assert!(check_getcap(&b).is_err());
        assert!(check_getcap(&good[..0x63]).is_err());
        assert!(check_getcap(&[good.as_slice(), &[0]].concat()).is_err());
    }

    /// Builds a 0x5c reply as DEDUCED in §1.6.4 (L = 0x48, v1) and decodes it back.
    fn reply(theirs: u64, state: u32) -> [u8; 0x5c] {
        let mut b = [0u8; 0x5c];
        b[0..4].copy_from_slice(&0x48u32.to_le_bytes());
        b[0x14..0x18].copy_from_slice(&1u32.to_le_bytes());
        b[0x18..0x20].copy_from_slice(&99u64.to_le_bytes());
        b[0x4c..0x50].copy_from_slice(&state.to_le_bytes());
        b[0x50..0x58].copy_from_slice(&theirs.to_le_bytes());
        let d = frame_digest(&b, 1, 0x4c, 0x5c).unwrap();
        b[4..20].copy_from_slice(&d);
        b
    }

    #[test]
    fn reply_decode() {
        let w = Word::decode(0x005c_0001_0001_cd12);
        assert_eq!(w, Word::new(0x12, 0xcd, 0x01, 0x00, 0x005c_0001));
        assert!(is_getcap_reply(&w));
        let rw = reply_word(&w);
        assert_eq!(rw, ReplyWord { status: 0, call_flags: 1, len: 0x5c, tag_is_cd: true });
        assert!(!is_getcap_reply(&Word::new(0x12, 0x4d, 0x01, 0, 0)));
        assert!(!is_getcap_reply(&Word::new(0x12, 0xaa, 0x02, 0, 0)));
        assert_eq!(reply_word(&Word::new(0x12, 0xcd, 1, 0xff, 0)).status, -1);

        let mut snap = [0u8; OUT_SNAP];
        snap[..0x5c].copy_from_slice(&reply(2, 0));
        let r = decode_getcap_reply(&snap, 0x5c).unwrap();
        assert_eq!((r.hlen, r.version, r.digest_ok, r.state, r.theirs, r.blob_len), (0x48, 1, true, 0, 2, 0));
        assert_eq!(r.ts_us, 99);
        assert_eq!(r.negotiated(), 2);
        assert_eq!(decode_getcap_reply(&reply(5, 0), 0x5c).unwrap().negotiated(), 2);
        assert_eq!(decode_getcap_reply(&reply(1, 3), 0x5c).unwrap().state, 3);
        let mut bad = reply(2, 0);
        bad[0x50] = 3;
        assert!(!decode_getcap_reply(&bad, 0x5c).unwrap().digest_ok);
        assert!(decode_getcap_reply(&reply(2, 0), 0x58).is_err(), "consumed != len");
        assert!(decode_getcap_reply(&snap, 0x81).is_err(), "len > snapshot");
        let mut v9 = reply(2, 0);
        v9[0x14] = 9;
        assert!(decode_getcap_reply(&v9, 0x5c).is_err());
        let mut short = reply(2, 0);
        short[0] = 0x40;
        assert!(decode_getcap_reply(&short, 0x5c).is_err());
    }

    #[test]
    fn gate_once() {
        let mut g = GetcapGate::closed();
        assert!(!g.admit(&getcap_word()), "closed");
        g.arm();
        assert!(!g.admit(&Word::new(0x12, 0x4d, 0x02, 0, GETCAP_DATA)), "wrong TYPE");
        assert!(!g.admit(&Word::new(0x12, 0x2a, 0x01, 0, GETCAP_DATA)), "wrong TAG");
        assert!(!g.admit(&Word::new(0x12, 0x4d, 0x01, 1, GETCAP_DATA)), "wrong PARAM");
        assert!(!g.admit(&Word::new(0x12, 0x4d, 0x01, 0, 0x0064_0001)), "wrong DATA");
        assert!(!g.admit(&Word::new(0x17, 0x4d, 0x01, 0, GETCAP_DATA)), "wrong EP");
        assert!(g.admit(&getcap_word()));
        assert!(g.used());
        assert!(!g.admit(&getcap_word()), "twice");
        g.arm();
        assert!(!g.admit(&getcap_word()), "re-armed after use");
    }

    #[test]
    fn outcome_roundtrip() {
        let mut snap = [0u8; OUT_SNAP];
        snap[0] = 0x48;
        let r = encode_outcome(OUT_REPLIED, 0x005c_0001_0001_cd12, &snap);
        let (k, raw, s) = decode_outcome(&r).unwrap();
        assert_eq!((k, raw, s.len(), s[0]), (OUT_REPLIED, 0x005c_0001_0001_cd12, OUT_SNAP, 0x48));
        let mut bad = r;
        bad[0] = b'X';
        assert_eq!(decode_outcome(&bad), Err(Error::BadMagic));
    }
}
