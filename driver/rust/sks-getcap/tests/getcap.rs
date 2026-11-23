//! J9a: request built as documented (cross-checked against an independent Python/hashlib construction made from
//! `docs/sks_protocol.md` §1.6.2-§1.6.3), encoder re-read by the kernel gate, and outcome decoding.
use sep_proto::sks_ipc::{self, encode_outcome, OUT_NOT_SENT, OUT_REPLIED, OUT_SILENCE, OUT_SNAP};
use sks_getcap::{describe_request, fields, hex, verdict, CdhashMode, Verdict};

/// Python 3 `hashlib` reference (session ALARM 2026-11-23): ts = 0x1122334455667788, uniqueid 0, uid 0,
/// cdhash = sha1(8 × 0x00), digest = sha256(b[0x14:0x4c] + b[0x54:0x64])[:16].
const PY_REQ: &str = "500000003589e8299dde581216b09f580f817e8301000000887766554433221100000000000000000000000000000000000000000000000005fe405753166f125559e7c9ac558654f107c7e9000000000000000000000000010000000000000000000000";

#[test]
fn request_matches_independent_construction() {
    let req = sks_ipc::encode_getcap(&fields(0x1122_3344_5566_7788, 0, 0, CdhashMode::Sha1));
    assert_eq!(hex(&req), PY_REQ);
    assert_eq!(hex(&sks_ipc::cdhash_no_process(0)), "05fe405753166f125559e7c9ac558654f107c7e9");
}

#[test]
fn encoder_reread_by_gate() {
    for mode in [CdhashMode::Sha1, CdhashMode::Zero] {
        for (ts, uq, uid) in [(0u64, 0u64, 0u32), (123_456_789, 42, 501), (u64::MAX, u64::MAX, u32::MAX)] {
            let f = fields(ts, uq, uid, mode);
            let req = sks_ipc::encode_getcap(&f);
            assert_eq!(sks_ipc::check_getcap(&req).unwrap(), f);
            assert!(describe_request(&req).is_ok());
        }
    }
}

fn reply_snap(theirs: u64, state: u32) -> [u8; OUT_SNAP] {
    let mut b = [0u8; OUT_SNAP];
    b[0..4].copy_from_slice(&0x48u32.to_le_bytes());
    b[0x14..0x18].copy_from_slice(&1u32.to_le_bytes());
    b[0x4c..0x50].copy_from_slice(&state.to_le_bytes());
    b[0x50..0x58].copy_from_slice(&theirs.to_le_bytes());
    let d = sks_ipc::frame_digest(&b, 1, 0x4c, 0x5c).unwrap();
    b[4..20].copy_from_slice(&d);
    b
}

#[test]
fn outcomes() {
    // c12 L179: `< EP=0x12 TAG=0xcd TYPE=0x01 PARAM=0x00 DATA=0x005c0001`.
    let raw = 0x005c_0001_0001_cd12u64;
    let (v, _, _) = verdict(&encode_outcome(OUT_REPLIED, raw, &reply_snap(2, 0))).unwrap();
    match v {
        Verdict::Replied { word, reply } => {
            assert_eq!((word.len, word.call_flags, word.status), (0x5c, 1, 0));
            assert_eq!((reply.theirs, reply.negotiated(), reply.digest_ok), (2, 2, true));
        }
        x => panic!("{x:?}"),
    }
    assert!(matches!(verdict(&encode_outcome(OUT_REPLIED, raw, &reply_snap(2, 1))).unwrap().0, Verdict::Error { .. }));
    // PARAM 0xff = -1.
    let err = 0x0000_0000_ff01_cd12u64;
    assert!(matches!(verdict(&encode_outcome(OUT_REPLIED, err, &[0; OUT_SNAP])).unwrap().0, Verdict::Error { .. }));
    assert_eq!(verdict(&encode_outcome(OUT_SILENCE, 0, &[0; OUT_SNAP])).unwrap().0, Verdict::Silence);
    assert_eq!(verdict(&encode_outcome(OUT_NOT_SENT, 0, &[0; OUT_SNAP])).unwrap().0, Verdict::NotSent);
    assert!(verdict(b"nope").is_err());
}
