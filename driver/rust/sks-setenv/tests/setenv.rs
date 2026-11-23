//! J9b: set_env request built as documented (cross-checked against an independent Python/hashlib construction made
//! from `docs/sks_protocol.md` §1.7.1-§1.7.3), re-read by the kernel gate, and combined-outcome decoding.
use sep_proto::sks_ipc::{self, encode_outcome, OUT_REPLIED, OUT_SIZE, OUT_SNAP};
use sep_proto::sks_keybag as proto_kb;
use sep_proto::sks_setenv as proto_se;
use sks_setenv::{
    describe_mskb_standalone, getcap_verdict, keybag_fields, mskb_std_verdict, setenv_fields, setenv_verdict,
    CdhashMode, GetcapVerdict, MskbVerdict, SetenvVerdict,
};

/// Python 3 `hashlib` reference (session ALARM 2026-11-23): ts = 0x1122334455667788, uniqueid 0, uid 0,
/// cdhash = sha1(8 × 0x00), cpx 2, mode 4, blob version 1. First 0x70 bytes; the remaining 0x400 are zero.
const PY_HEAD_0X70: &str = "500000008261049d2c7363a00481526491c593aa02000000887766554433221100000000000000000000000000000000000000000000000005fe405753166f125559e7c9ac558654f107c7e900000000000000000000000001000000000000000c040000010000000200000004000000";
/// sha256 of the whole 0x470-byte request (stable fingerprint).
const PY_SHA256_REQ: &str = "b911d3ea8788fce2f662814368e282b84112da3e41b5f5845b0b74336df0999a";

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

#[test]
fn request_matches_independent_construction() {
    let req = proto_se::encode_setenv(&setenv_fields(0x1122_3344_5566_7788, 0, 0, CdhashMode::Sha1, 2));
    assert_eq!(hex(&req[..0x70]), PY_HEAD_0X70);
    assert!(req[0x70..].iter().all(|&x| x == 0), "0x400 reserved bytes must be zero");
    assert_eq!(hex(&sep_proto::hash::sha256(&req)), PY_SHA256_REQ);
}

#[test]
fn encoder_reread_by_gate() {
    for mode in [CdhashMode::Sha1, CdhashMode::Zero] {
        for (ts, uq, uid, cpx) in [(0u64, 0u64, 0u32, 0u32), (123_456_789, 42, 501, 2), (u64::MAX, u64::MAX, u32::MAX, 1)] {
            let f = setenv_fields(ts, uq, uid, mode, cpx);
            let req = proto_se::encode_setenv(&f);
            assert_eq!(proto_se::check_setenv(&req).unwrap(), f);
        }
    }
}

/// J11 STANDALONE make_system_keybag: independent Python/hashlib reference (session ALARM 2026-11-23,
/// `scratchpad/mskb_std_vec.py`) on ARBITRARY example values — PAS les vraies. ts = 0x1122334455667788,
/// uniqueid 0, uid 0, cdhash = sha1(8 × 0x00), handle_y = 0x4242424242424242, loaded_handle (--mskb-handle) =
/// 0xdeadbeef, type -16, uuid 00..0f. The v2 digest is sha256(bytes[0x14..0x84])[:16]. loaded_handle is sent AS IS
/// (no kernel finalize in J11), so the full request is pinned by this vector.
const PY_MSKB_STD_HEAD_0X70: &str = "50000000c5fd84961b48bf2de20d818be48d391d02000000887766554433221100000000000000000000000000000000000000000000000005fe405753166f125559e7c9ac558654f107c7e90000000000000000010000004242424242424242efbeaddef0ffffff1000000000010203";
const PY_MSKB_STD_SHA256: &str = "7cb9ba6138cf7464950f27feea9265f296123245f19c61eb5ae48f0bb2000018";

#[test]
fn mskb_standalone_matches_independent_construction() {
    let uuid: [u8; 16] = core::array::from_fn(|i| i as u8);
    // build_mskb_standalone(): loaded_handle = --mskb-handle (here 0xdeadbeef), sent as is (no finalize).
    let req = proto_kb::encode_mskb(&keybag_fields(0x1122_3344_5566_7788, 0, 0, CdhashMode::Sha1), 0x4242_4242_4242_4242, 0xdead_beef, -16, &uuid);
    assert_eq!(hex(&req[..0x70]), PY_MSKB_STD_HEAD_0X70);
    assert_eq!(hex(&sep_proto::hash::sha256(&req)), PY_MSKB_STD_SHA256);
    // The kernel gate re-reads it, and the standalone describe applies the same gate.
    assert_eq!(proto_kb::check_mskb(&req).unwrap().loaded_handle, 0xdead_beef);
    assert!(describe_mskb_standalone(&req).is_ok());
    // Standalone reply decoding: TYPE 0x03.
    let ok = encode_outcome(OUT_REPLIED, 0x0000_0000_0003_8d12, &[0; OUT_SNAP]);
    assert_eq!(mskb_std_verdict(&ok).unwrap().0, MskbVerdict::MarkedSystem);
}

fn gc_snap() -> [u8; OUT_SNAP] {
    let mut b = [0u8; OUT_SNAP];
    b[0..4].copy_from_slice(&0x48u32.to_le_bytes());
    b[0x14..0x18].copy_from_slice(&1u32.to_le_bytes());
    b[0x50..0x58].copy_from_slice(&2u64.to_le_bytes());
    let d = sks_ipc::frame_digest(&b[..0x5c], 1, 0x4c, 0x5c).unwrap();
    b[4..20].copy_from_slice(&d);
    b
}

fn se_snap(state: u32) -> [u8; OUT_SNAP] {
    let mut b = [0u8; OUT_SNAP];
    b[0..4].copy_from_slice(&0x50u32.to_le_bytes());
    b[0x14..0x18].copy_from_slice(&2u32.to_le_bytes());
    b[0x54..0x58].copy_from_slice(&state.to_le_bytes());
    let d = sks_ipc::frame_digest(&b[..0x58], 2, 0x54, 0x58).unwrap();
    b[4..20].copy_from_slice(&d);
    b
}

#[test]
fn combined_record_both_parts() {
    // c12 L179 getcap reply + L181 set_env reply.
    let gc = encode_outcome(OUT_REPLIED, 0x005c_0001_0001_cd12, &gc_snap());
    let se = encode_outcome(OUT_REPLIED, 0x0058_0000_0002_aa12, &se_snap(0));
    let mut rec = Vec::new();
    rec.extend_from_slice(&gc);
    rec.extend_from_slice(&se);
    assert_eq!(rec.len(), OUT_SIZE * 2);
    let (gcv, _) = getcap_verdict(&rec[..OUT_SIZE]).unwrap();
    assert!(matches!(gcv, GetcapVerdict::Replied(r) if r.negotiated() == 2));
    let (sev, _, _) = setenv_verdict(&rec[OUT_SIZE..]).unwrap();
    assert!(matches!(sev, SetenvVerdict::Accepted(r) if r.state == 0 && r.version == 2));

    // set_env rejected (state != 0) → Error.
    let se_bad = encode_outcome(OUT_REPLIED, 0x0058_0000_0002_aa12, &se_snap(0x1234));
    assert!(matches!(setenv_verdict(&se_bad).unwrap().0, SetenvVerdict::Error(_)));
}
