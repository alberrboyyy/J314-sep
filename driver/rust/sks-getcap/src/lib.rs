//! J9a, userspace side of `sep_native allow_sks=2` (`docs/sks_native_plan.md` §6): builds the 0x64-byte SKS
//! `get_capabilities` request (EP 0x12, TAG 0x4d) and decodes the outcome record that `/dev/sep_sks` returns.
//! The frame format itself is in `sep_proto::sks_ipc` (written from `docs/sks_protocol.md` §1.6, `source: kext`,
//! NOT verified on hardware). Nothing here talks to a device: see `main.rs`.
//!
//! Neutral values (all documented choices, none verified on hardware):
//! - timestamp: the kext calls `_get_usec_time`, whose clock is NOT documented here. Default = CLOCK_MONOTONIC in µs
//!   (time since boot, the closest Linux analogue of a kernel uptime clock); `--clock realtime|boottime` or `--ts-us N`
//!   change it. The kernel gate does not check this field.
//! - unique id = 0 and uid = 0: the macOS request is made by the kernel itself at boot (`init_sep_endpoint`), i.e. not
//!   by a user process; 0 is the neutral « no process / root » value. Neither is checked by the kernel gate.
//! - cdhash = SHA-1 of the 8 bytes of the unique id (default): the AP path « no process » (§1.6.2 « à défaut »), which
//!   needs no code signature. `--cdhash zero` = the other documented AP path (process without a cdhash,
//!   `sks_ipc_negotiation.md` §3.2). Which one macOS takes for a kernel caller is NOT known.
use sep_proto::sks_ipc::{self, CdhashKind, GetcapFields, GetcapReply, ReplyWord};
use sep_proto::word::Word;
use std::fmt::Write as _;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CdhashMode {
    Sha1,
    Zero,
}

pub fn fields(ts_us: u64, uniqueid: u64, uid: u32, mode: CdhashMode) -> GetcapFields {
    let cdhash = match mode {
        CdhashMode::Sha1 => sks_ipc::cdhash_no_process(uniqueid),
        CdhashMode::Zero => [0; sks_ipc::CDHASH_LEN],
    };
    GetcapFields { ts_us, uniqueid, uid, cdhash }
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// Hex dump, 16 bytes per line, with offsets.
pub fn dump(b: &[u8]) -> String {
    let mut s = String::new();
    for (i, c) in b.chunks(16).enumerate() {
        let _ = writeln!(s, "  +{:#05x} : {}", i * 16, c.iter().map(|x| format!("{x:02x}")).collect::<Vec<_>>().join(" "));
    }
    s
}

/// Human description of a request (after the same check as the kernel gate).
pub fn describe_request(b: &[u8]) -> Result<String, String> {
    let f = sks_ipc::check_getcap(b).map_err(|e| format!("requête refusée par la porte (identique au noyau) : {e}"))?;
    let kind = match sks_ipc::cdhash_kind(&f) {
        CdhashKind::Sha1OfUniqueid => "SHA-1 de l'uniqueid (chemin « pas de processus »)",
        CdhashKind::Zero => "zéros (chemin « pas de cdhash »)",
        CdhashKind::Other => "autre",
    };
    let mut s = String::new();
    let _ = writeln!(s, "requête get_capabilities ({:#x} o) — mot > EP 0x12 TAG 0x4d TYPE 0x01 PARAM 0 DATA {:#010x}", b.len(), sks_ipc::GETCAP_DATA);
    let _ = writeln!(s, "  0x00 longueur en-tête 0x50 ; 0x14 version 1 ; 0x20 drapeaux 0 ; 0x24 champ +0x20 0 ; 0x4c 0 ; 0x54 état 0 ; 0x58 u64 1 ; 0x60 blob 0");
    let _ = writeln!(s, "  0x04 condensé SHA-256/16 = {}", hex(&b[sks_ipc::OFF_DIGEST..sks_ipc::OFF_DIGEST + sks_ipc::DIGEST_LEN]));
    let _ = writeln!(s, "  0x18 horodatage = {} µs ; 0x2c uniqueid = {:#x} ; 0x34 uid = {}", f.ts_us, f.uniqueid, f.uid);
    let _ = writeln!(s, "  0x38 cdhash = {} ({kind})", hex(&f.cdhash));
    s.push_str(&dump(b));
    Ok(s)
}

/// Verdict computed from an outcome record, same rules as the kernel's « VERDICT sks getcap ».
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verdict {
    NotSent,
    Silence,
    /// PARAM = 0, B decoded, status 0.
    Replied { word: ReplyWord, reply: GetcapReply },
    /// PARAM != 0, or status != 0, or B not decodable (reason).
    Error { word: ReplyWord, reason: String },
}

pub fn verdict(rec: &[u8]) -> Result<(Verdict, u64, Vec<u8>), String> {
    let (kind, raw, snap) = sks_ipc::decode_outcome(rec).map_err(|e| format!("enregistrement /dev/sep_sks illisible : {e}"))?;
    let snap = snap.to_vec();
    let v = match kind {
        sks_ipc::OUT_NOT_SENT => Verdict::NotSent,
        sks_ipc::OUT_SILENCE => Verdict::Silence,
        _ => {
            let w = Word::decode(raw);
            let rw = sks_ipc::reply_word(&w);
            if !sks_ipc::is_getcap_reply(&w) {
                Verdict::Error { word: rw, reason: format!("mot {raw:#018x} non apparié (EP/TAG bit 7/TYPE)") }
            } else if rw.status != 0 {
                Verdict::Error { word: rw, reason: format!("PARAM {} = statut signé ≠ 0", rw.status) }
            } else {
                match sks_ipc::decode_getcap_reply(&snap, usize::from(rw.len)) {
                    Ok(r) if r.state == 0 => Verdict::Replied { word: rw, reply: r },
                    Ok(r) => Verdict::Error { word: rw, reason: format!("état {:#x} ≠ 0 (theirs {})", r.state, r.theirs) },
                    Err(e) => Verdict::Error { word: rw, reason: format!("B12 non décodable : {e}") },
                }
            }
        }
    };
    Ok((v, raw, snap))
}

pub fn describe_verdict(v: &Verdict, raw: u64, snap: &[u8]) -> String {
    let mut s = String::new();
    match v {
        Verdict::NotSent => s.push_str("VERDICT sks getcap : NON ENVOYÉ (aucun mot vers 0x12)\n"),
        Verdict::Silence => s.push_str("VERDICT sks getcap : SILENCE (aucune réponse appariée en 10 s)\n"),
        Verdict::Replied { word, reply: r } => {
            let _ = writeln!(
                s,
                "VERDICT sks getcap : RÉPONDU (PARAM 0, état 0, theirs {} → négociée v{} ; L {:#x}, version d'en-tête {}, condensé {}, blob {} o ; longueur {:#x}, drapeaux d'appel {:#06x}, TAG {}) mot {raw:#018x}",
                r.theirs, r.negotiated(), r.hlen, r.version, if r.digest_ok { "OK" } else { "FAUX" }, r.blob_len, word.len,
                word.call_flags, if word.tag_is_cd { "0xcd" } else { "≠ 0xcd (bit 7 seul)" }
            );
            let _ = writeln!(
                s,
                "  en-tête du SEP : horodatage {} µs, drapeaux {:#x}, uniqueid {:#x}, uid {}",
                r.ts_us, r.flags, r.uniqueid, r.uid
            );
            if word.len != sks_ipc::REPLY_LEN_SEEN || r.hlen != sks_ipc::HLEN_MIN_V1 {
                let _ = writeln!(s, "  NB : macOS (6/6 boots) avait longueur 0x5c ; disposition L = 0x48 seulement DÉDUITE");
            }
        }
        Verdict::Error { word, reason } => {
            let _ = writeln!(
                s,
                "VERDICT sks getcap : ERREUR ({reason} ; PARAM {}, longueur {:#x}, drapeaux d'appel {:#06x}) mot {raw:#018x}",
                word.status, word.len, word.call_flags
            );
        }
    }
    if !matches!(v, Verdict::NotSent | Verdict::Silence) {
        s.push_str("instantané de B12 (0x80 o) :\n");
        s.push_str(&dump(snap));
    }
    s
}
