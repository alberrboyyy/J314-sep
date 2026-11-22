//! Biometric phase (EP 0x08): the MATCH wire sequence (VU in trace C20/C11/C8/C6) and the ENROLL wire sequence
//! (`source: kext`, `docs/sbio_enroll.md`; NO trace exists). This module is a **map + verdict parser only**: it does
//! NOT build commands. Two of the match/enroll payloads are NOT known and cannot be synthesised (see
//! `docs/j6_enroll_match_protocol.md` §4.1, §4.2): the 0x03 `enroll_indata_v2_t` (68 bytes, content
//! unread, from biometrickitd) and the 0x06 `_lastImageProcessingParams` (0xa7 bytes, per-lock nonce at +0x97,
//! origin unread, tied to the keybag).
//! So the driver cannot relay a faithful enroll/match today (D2 + these two blobs). The only `verified` piece is the
//! 0x09 verdict (`docs/verification_status.md`, `match_info_t`): `parse_verdict` is what the driver will read when a
//! real match becomes reachable. Everything else here is a reference table used by the replay tests.
//! Exception (J6a, E-ENROLL-START, decided by Albert): ONE experimental 0x03 with a fixed 68-byte all-zero
//! `enroll_indata_v2_t` lives in `sbio_gate` (`ENROLL_INDATA_MIN`, kernel `allow_sbio_bio=1`). It is a probe, not a
//! faithful enroll: `ENROLL_START.payload` stays `Unknown` here.
use crate::le_u32;

pub const EP_SBIO: u8 = 0x08;

/// Whether the AP payload of a step is known (constant or relayed from a known source) or UNKNOWN (cannot be built).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Payload {
    /// No payload (A length 0).
    Empty,
    /// The live sensor image (0x7200, read over SPI; verified structure, relayed opaque).
    Image,
    /// A reply relayed from the SEP/sensor (opaque bytes, length checked elsewhere).
    Relayed,
    /// UNKNOWN origin: cannot be synthesised natively (0x03 enroll_indata, 0x06 image-processing params).
    Unknown(&'static str),
    /// A reply the SEP returns (for steps read B-side): not an AP payload.
    Reply,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BioStep {
    pub op: u8,
    pub name: &'static str,
    pub payload: Payload,
    /// Exact B length when known (VU), else None.
    pub reply_len: Option<usize>,
}

const fn s(op: u8, name: &'static str, payload: Payload, reply_len: Option<usize>) -> BioStep {
    BioStep { op, name, payload, reply_len }
}

/// One MATCH attempt as observed on the wire (C20 ~614 s, C11, C8, C6; `docs/messages.md` §SBIO, verdict VERIFIED).
/// The sensor image is read over SPI BEFORE 0x65. `0x06` is UNKNOWN (D6) → cannot be built natively. `0x1e` appears
/// only on the retry branch (0x07 result `+0x00`=2); the core is 0x23 06 65 07 [1e] 09 1f 22 0b, then `<03` → 0x21.
pub const MATCH_SEQUENCE: [BioStep; 9] = [
    s(0x23, "asyncCapture(start)", Payload::Empty, Some(0)),
    s(0x06, "imageProcessingParams", Payload::Unknown("_lastImageProcessingParams 0xa7, per-lock nonce (D6)"), Some(0)),
    s(0x65, "image", Payload::Image, Some(0)),
    s(0x07, "imageResult", Payload::Empty, Some(0xc0)),
    s(0x1e, "matchStep", Payload::Empty, Some(0)),
    s(0x09, "handleMatch(VERDICT)", Payload::Empty, Some(VERDICT_LEN)),
    s(0x1f, "cacheMatchPolicy", Payload::Empty, Some(2)),
    s(0x22, "enableBgOps", Payload::Empty, Some(0)),
    s(0x0b, "commandCancel", Payload::Empty, Some(0)),
];

/// One ENROLL cycle (`source: kext`, `docs/sbio_enroll.md`; NO trace). Capture is shared with the match
/// (0x23/0x06/0x65/0x07). `0x03` start carries the UNKNOWN 68-byte `enroll_indata_v2_t`; `0x08` returns
/// `enrollment_info_t` (0xc98). The loop ends when `enrollment_info_t +0xbfe != 0` (COMPLETE), N decided by the SEP.
pub const ENROLL_START: BioStep = s(0x03, "commandStartEnroll", Payload::Unknown("enroll_indata_v2_t 68 bytes, from biometrickitd"), Some(0));
pub const ENROLL_CYCLE: [BioStep; 6] = [
    s(0x23, "asyncCapture(start)", Payload::Empty, Some(0)),
    s(0x06, "imageProcessingParams", Payload::Unknown("_lastImageProcessingParams 0xa7 (D6)"), Some(0)),
    s(0x65, "image", Payload::Image, Some(0)),
    s(0x07, "imageResult", Payload::Empty, Some(0xc0)),
    s(0x1e, "enrollStep", Payload::Empty, Some(0)),
    s(0x08, "handleEnrollment", Payload::Empty, Some(ENROLL_INFO_LEN)),
];

/// `enrollment_info_t` length (VU kext assert, `docs/sbio_enroll.md` §5).
pub const ENROLL_INFO_LEN: usize = 0xc98;
/// `match_info_t` length (VU kext, VERIFIED c6/c8/c11).
pub const VERDICT_LEN: usize = 0xca2;
/// uid 501 of this machine (`id -u`), success marker of 0x09 `+0x00`.
pub const UID_MATCH: u32 = 0x1f5;
/// no-match marker of 0x09 `+0x00`.
pub const NO_MATCH: u32 = 0xffff_ffff;

/// True if any step of the two sequences carries a payload we cannot build natively (0x03, 0x06). Used to keep the
/// gate fail-closed: a bio relay is refused while these are Unknown.
pub const fn has_unknown_payload() -> bool {
    true
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    /// Recognised finger: uid and the 16-byte template identifier.
    Match { uid: u32, ident: [u8; 16] },
    /// No match (`+0x00` = 0xffffffff).
    NoMatch,
    /// The 0x09 reply did not have the `match_info_t` length.
    BadLen(usize),
}

/// Reads the verdict of a 0x09 reply. `info` = the reassembled `match_info_t` payload (gt header already stripped, as
/// `gt::Transfer::blob`). VERIFIED (`docs/verification_status.md`): `+0x00` = 0x1f5 (uid) or 0xffffffff, `+0x04` 16 B
/// = template id on success. Nothing else is interpreted (image metadata is never decoded).
pub fn parse_verdict(info: &[u8]) -> Verdict {
    if info.len() != VERDICT_LEN {
        return Verdict::BadLen(info.len());
    }
    match le_u32(info, 0) {
        Ok(UID_MATCH) => {
            let mut id = [0u8; 16];
            id.copy_from_slice(&info[4..20]);
            Verdict::Match { uid: UID_MATCH, ident: id }
        }
        Ok(NO_MATCH) | Ok(_) => Verdict::NoMatch,
        Err(_) => Verdict::BadLen(info.len()),
    }
}

/// Reads the COMPLETE flag of an `enrollment_info_t` (0x08 reply). `+0x02` u16 != 0 = error, `+0xbfe` u32 != 0 =
/// enrolment complete (`docs/sbio_enroll.md` §5). `source: kext`, never run.
pub fn enroll_complete(info: &[u8]) -> Option<bool> {
    if info.len() != ENROLL_INFO_LEN {
        return None;
    }
    le_u32(info, 0xbfe).ok().map(|v| v != 0)
}

pub fn enroll_error(info: &[u8]) -> Option<u16> {
    if info.len() != ENROLL_INFO_LEN {
        return None;
    }
    crate::le_u16(info, 2).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verdict_success_and_fail() {
        let mut m = vec![0u8; VERDICT_LEN];
        m[0..4].copy_from_slice(&UID_MATCH.to_le_bytes());
        let id = [0x11u8, 0x22, 0x33, 0x44, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        m[4..20].copy_from_slice(&id);
        assert_eq!(parse_verdict(&m), Verdict::Match { uid: UID_MATCH, ident: id });
        let mut f = vec![0u8; VERDICT_LEN];
        f[0..4].copy_from_slice(&NO_MATCH.to_le_bytes());
        assert_eq!(parse_verdict(&f), Verdict::NoMatch);
        assert_eq!(parse_verdict(&[0u8; 10]), Verdict::BadLen(10));
    }

    #[test]
    fn enroll_flags() {
        let mut i = vec![0u8; ENROLL_INFO_LEN];
        assert_eq!(enroll_complete(&i), Some(false));
        assert_eq!(enroll_error(&i), Some(0));
        i[0xbfe] = 1;
        i[2] = 5;
        assert_eq!(enroll_complete(&i), Some(true));
        assert_eq!(enroll_error(&i), Some(5));
        assert_eq!(enroll_complete(&[0u8; 3]), None);
    }

    #[test]
    fn sequences_carry_the_unknown_payloads() {
        // The gate must stay fail-closed: both sequences hold at least one Unknown payload.
        assert!(has_unknown_payload());
        assert!(MATCH_SEQUENCE.iter().any(|s| matches!(s.payload, Payload::Unknown(_))));
        assert!(ENROLL_CYCLE.iter().any(|s| matches!(s.payload, Payload::Unknown(_))));
        assert!(matches!(ENROLL_START.payload, Payload::Unknown(_)));
        // The verdict step is 0x09 with the verified length.
        let v = MATCH_SEQUENCE.iter().find(|s| s.op == 0x09).unwrap();
        assert_eq!(v.reply_len, Some(0xca2));
    }
}
