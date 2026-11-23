//! J9b, userspace side of `sep_native allow_sks=3` (`docs/sks_native_plan.md` §7): builds the SKS `get_capabilities`
//! request (EP 0x12, TAG 0x4d, 0x64 bytes) and then the `set_env` request (TAG 0x2a, 0x470 bytes), and decodes the
//! combined outcome record that `/dev/sep_sks` returns (get_capabilities part followed by set_env part). The frame
//! formats are in `sep_proto::{sks_ipc, sks_setenv}` (written from `docs/sks_protocol.md` §1.6/§1.7, `source: kext`,
//! NOT verified on hardware). Nothing here talks to a device: see `main.rs`.
//!
//! Neutral contextual values (documented choices, none verified on hardware), shared by both frames:
//! - timestamp: the kext calls `_get_usec_time` (clock NOT documented here). Default = CLOCK_MONOTONIC in µs; the
//!   kernel gate does not check this field.
//! - unique id = 0 and uid = 0: the macOS requests are made by the kernel itself at boot (`init_sep_endpoint`), not by
//!   a user process; 0 is the neutral « no process / root » value. Neither is checked by the kernel gate.
//! - cdhash = SHA-1 of the 8 bytes of the unique id (default): AP path « no process » (§1.6.2 « à défaut »).
//!
//! `set_env`-specific value: `cpx-encryption-mode` (blob +0x04). The kext reads it from the device-tree
//! (`IODeviceTree:/defaults`, OF property `cpx-encryption-mode`), 0 when absent. This tool reads
//! `/proc/device-tree/defaults/cpx-encryption-mode` (a u32 big-endian device-tree cell) at runtime, falling back to 0
//! if the node is absent (the Asahi device-tree does not export `/defaults`); `--cpx N` forces a value. Our ADT shows
//! `cpx-encryption-mode = 2` (`traces/20261108-162919_adt/adt.txt`), so the run script forces `--cpx 2`.
use sep_proto::sks_ipc::{self, CdhashKind, GetcapFields, GetcapReply};
use sep_proto::sks_keybag::{self, KeybagFields, UUID_LEN};
use sep_proto::sks_nulldkey::{self, NulldkeyFields, NulldkeyReply};
use sep_proto::sks_setenv::{self, SetenvFields, SetenvReply};
use sep_proto::word::Word;
use std::fmt::Write as _;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CdhashMode {
    Sha1,
    Zero,
}

fn cdhash(uniqueid: u64, mode: CdhashMode) -> [u8; sks_ipc::CDHASH_LEN] {
    match mode {
        CdhashMode::Sha1 => sks_ipc::cdhash_no_process(uniqueid),
        CdhashMode::Zero => [0; sks_ipc::CDHASH_LEN],
    }
}

pub fn getcap_fields(ts_us: u64, uniqueid: u64, uid: u32, mode: CdhashMode) -> GetcapFields {
    GetcapFields { ts_us, uniqueid, uid, cdhash: cdhash(uniqueid, mode) }
}

pub fn setenv_fields(ts_us: u64, uniqueid: u64, uid: u32, mode: CdhashMode, cpx: u32) -> SetenvFields {
    SetenvFields { ts_us, uniqueid, uid, cdhash: cdhash(uniqueid, mode), cpx }
}

pub fn nulldkey_fields(ts_us: u64, uniqueid: u64, uid: u32, mode: CdhashMode) -> NulldkeyFields {
    NulldkeyFields { ts_us, uniqueid, uid, cdhash: cdhash(uniqueid, mode) }
}

pub fn keybag_fields(ts_us: u64, uniqueid: u64, uid: u32, mode: CdhashMode) -> KeybagFields {
    KeybagFields { ts_us, uniqueid, uid, cdhash: cdhash(uniqueid, mode) }
}

/// The userland values of the J10 device-identity keybag path (`docs/applekeystored_identity.md` §6): the real values
/// are unknown (reversed on the PC); the tool only transports whatever the caller supplies. REQUIRED (no default):
/// `uuid`, `class`, `keybag_type`. With a default: `handle_y` (0 — a fresh create has no parent session handle) and
/// `field2` (0 — the 2nd ambiguous u32). `loaded_handle` is NOT here: it is the handle `create_keybag` returns, read
/// at run time and plugged in by the kernel.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeybagUserland {
    /// `make_system_keybag` blob, exactly 16 bytes (VU length constraint on the `identity_load` OSData).
    pub uuid: [u8; UUID_LEN],
    /// `create_keybag` first u32 scalar (OOL 0x60). §6 does not pin which u32 is the class enum: coded as the class.
    pub class: u32,
    /// `create_keybag` second u32 scalar (OOL 0x64); the other of the ambiguous pair. Default 0.
    pub field2: u32,
    /// u64 at OOL 0x58 of both frames (parent/session handle; 0 for a fresh create). Default 0.
    pub handle_y: u64,
    /// Keybag type (OOL 0x64 of make_system_keybag; VU constraint: <= -10).
    pub keybag_type: i32,
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

/// Human description of the get_capabilities request (after the same check as the kernel gate).
pub fn describe_getcap(b: &[u8]) -> Result<String, String> {
    let f = sks_ipc::check_getcap(b).map_err(|e| format!("get_capabilities refusé par la porte (identique au noyau) : {e}"))?;
    let mut s = String::new();
    let _ = writeln!(s, "get_capabilities ({:#x} o) — mot > EP 0x12 TAG 0x4d TYPE 0x01 PARAM 0 DATA {:#010x}", b.len(), sks_ipc::GETCAP_DATA);
    let _ = writeln!(s, "  0x04 condensé v1 = {}", hex(&b[sks_ipc::OFF_DIGEST..sks_ipc::OFF_DIGEST + sks_ipc::DIGEST_LEN]));
    let _ = writeln!(s, "  horodatage {} µs ; uniqueid {:#x} ; uid {} ; cdhash {} ({})", f.ts_us, f.uniqueid, f.uid, hex(&f.cdhash), cdhash_label(sks_ipc::cdhash_kind(&f)));
    Ok(s)
}

/// Human description of the set_env request (after the same check as the kernel gate).
pub fn describe_setenv(b: &[u8]) -> Result<String, String> {
    let f = sks_setenv::check_setenv(b).map_err(|e| format!("set_env refusé par la porte (identique au noyau) : {e}"))?;
    let k = {
        let h = GetcapFields { ts_us: f.ts_us, uniqueid: f.uniqueid, uid: f.uid, cdhash: f.cdhash };
        sks_ipc::cdhash_kind(&h)
    };
    let mut s = String::new();
    let _ = writeln!(s, "set_env ({:#x} o) — mot > EP 0x12 TAG 0x2a TYPE 0x02 PARAM 0 DATA {:#010x}", b.len(), sks_setenv::SETENV_DATA);
    let _ = writeln!(s, "  en-tête v2 ; 0x04 condensé v2 = {}", hex(&b[sks_ipc::OFF_DIGEST..sks_ipc::OFF_DIGEST + sks_ipc::DIGEST_LEN]));
    let _ = writeln!(s, "  état 0 ; u64 1 ; blob {:#x} o : version 1, cpx-encryption-mode {}, mode 4, {:#x} o réservés nuls", sks_setenv::BLOB_LEN, f.cpx, sks_setenv::BLOB_RESERVED_LEN);
    let _ = writeln!(s, "  horodatage {} µs ; uniqueid {:#x} ; uid {} ; cdhash {} ({})", f.ts_us, f.uniqueid, f.uid, hex(&f.cdhash), cdhash_label(k));
    s.push_str(&dump(&b[..0x70]));
    let _ = writeln!(s, "  +0x070 .. +0x470 : {:#x} o à zéro (réservé)", sks_setenv::BLOB_RESERVED_LEN);
    Ok(s)
}

/// Human description of the null_d_key request (after the same check as the kernel gate).
pub fn describe_nulldkey(b: &[u8]) -> Result<String, String> {
    let f = sks_nulldkey::check_nulldkey(b).map_err(|e| format!("null_d_key refusé par la porte (identique au noyau) : {e}"))?;
    let k = {
        let h = GetcapFields { ts_us: f.ts_us, uniqueid: f.uniqueid, uid: f.uid, cdhash: f.cdhash };
        sks_ipc::cdhash_kind(&h)
    };
    let mut s = String::new();
    let _ = writeln!(s, "null_d_key ({:#x} o) — mot > EP 0x12 TAG 0x0a TYPE 0x03 PARAM 0 DATA {:#010x}", b.len(), sks_nulldkey::NULLDKEY_DATA);
    let _ = writeln!(s, "  en-tête v2 ; 0x04 condensé v2 = {}", hex(&b[sks_ipc::OFF_DIGEST..sks_ipc::OFF_DIGEST + sks_ipc::DIGEST_LEN]));
    let _ = writeln!(s, "  état 0 ; u64 1 ; PAS de blob (corps = en-tête + état + u64, 0x60 o ; VU au binaire)");
    let _ = writeln!(s, "  horodatage {} µs ; uniqueid {:#x} ; uid {} ; cdhash {} ({})", f.ts_us, f.uniqueid, f.uid, hex(&f.cdhash), cdhash_label(k));
    s.push_str(&dump(b));
    Ok(s)
}

fn cdhash_label(k: CdhashKind) -> &'static str {
    match k {
        CdhashKind::Sha1OfUniqueid => "SHA-1 de l'uniqueid",
        CdhashKind::Zero => "zéros",
        CdhashKind::Other => "autre",
    }
}

/// Verdict of one transaction, computed from an outcome record (same rules as the kernel's « VERDICT »).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GetcapVerdict {
    NotSent,
    Silence,
    Replied(GetcapReply),
    Error(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SetenvVerdict {
    NotSent,
    Silence,
    /// PARAM 0, status 0.
    Accepted(SetenvReply),
    Error(String),
}

/// Decodes the get_capabilities outcome record (0x98 bytes).
pub fn getcap_verdict(rec: &[u8]) -> Result<(GetcapVerdict, u64), String> {
    let (kind, raw, snap) = sks_ipc::decode_outcome(rec).map_err(|e| format!("enregistrement getcap illisible : {e}"))?;
    let v = match kind {
        sks_ipc::OUT_NOT_SENT => GetcapVerdict::NotSent,
        sks_ipc::OUT_SILENCE => GetcapVerdict::Silence,
        _ => {
            let w = Word::decode(raw);
            let rw = sks_ipc::reply_word(&w);
            if !sks_ipc::is_getcap_reply(&w) {
                GetcapVerdict::Error(format!("mot {raw:#018x} non apparié"))
            } else if rw.status != 0 {
                GetcapVerdict::Error(format!("PARAM {} ≠ 0", rw.status))
            } else {
                match sks_ipc::decode_getcap_reply(snap, usize::from(rw.len)) {
                    Ok(r) if r.state == 0 => GetcapVerdict::Replied(r),
                    Ok(r) => GetcapVerdict::Error(format!("état {:#x} ≠ 0 (theirs {})", r.state, r.theirs)),
                    Err(e) => GetcapVerdict::Error(format!("B12 non décodable : {e}")),
                }
            }
        }
    };
    Ok((v, raw))
}

/// Decodes the set_env outcome record (0x98 bytes).
pub fn setenv_verdict(rec: &[u8]) -> Result<(SetenvVerdict, u64, Vec<u8>), String> {
    let (kind, raw, snap) = sks_ipc::decode_outcome(rec).map_err(|e| format!("enregistrement set_env illisible : {e}"))?;
    let snap = snap.to_vec();
    let v = match kind {
        sks_ipc::OUT_NOT_SENT => SetenvVerdict::NotSent,
        sks_ipc::OUT_SILENCE => SetenvVerdict::Silence,
        _ => {
            let w = Word::decode(raw);
            let rw = sks_setenv::reply_word(&w);
            if !sks_setenv::is_setenv_reply(&w) {
                SetenvVerdict::Error(format!("mot {raw:#018x} non apparié (EP/TAG bit 7/TYPE 0x02)"))
            } else if rw.status != 0 {
                SetenvVerdict::Error(format!("PARAM {} = statut signé ≠ 0", rw.status))
            } else {
                match sks_setenv::decode_setenv_reply(&snap, usize::from(rw.len)) {
                    Ok(r) if r.state == 0 => SetenvVerdict::Accepted(r),
                    Ok(r) => SetenvVerdict::Error(format!("état {:#x} ≠ 0", r.state)),
                    Err(e) => SetenvVerdict::Error(format!("B12 non décodable : {e}")),
                }
            }
        }
    };
    Ok((v, raw, snap))
}

pub fn describe_getcap_verdict(v: &GetcapVerdict, raw: u64) -> String {
    match v {
        GetcapVerdict::NotSent => "VERDICT getcap : NON ENVOYÉ\n".into(),
        GetcapVerdict::Silence => "VERDICT getcap : SILENCE\n".into(),
        GetcapVerdict::Replied(r) => {
            format!("VERDICT getcap : RÉPONDU (état 0, theirs {} → négociée v{}, condensé {}) mot {raw:#018x}\n", r.theirs, r.negotiated(), if r.digest_ok { "OK" } else { "FAUX" })
        }
        GetcapVerdict::Error(reason) => format!("VERDICT getcap : ERREUR ({reason}) mot {raw:#018x}\n"),
    }
}

pub fn describe_setenv_verdict(v: &SetenvVerdict, raw: u64, snap: &[u8]) -> String {
    let mut s = String::new();
    match v {
        SetenvVerdict::NotSent => s.push_str("VERDICT setenv : NON ENVOYÉ (aucun mot set_env vers 0x12)\n"),
        SetenvVerdict::Silence => s.push_str("VERDICT setenv : SILENCE (aucune réponse appariée TAG bit 7 / TYPE 0x02)\n"),
        SetenvVerdict::Accepted(r) => {
            let _ = writeln!(
                s,
                "VERDICT setenv : ACCEPTÉ (PARAM 0, état 0 ; L {:#x}, version d'en-tête {}, condensé {}) mot {raw:#018x}",
                r.hlen, r.version, if r.digest_ok { "OK" } else { "FAUX" }
            );
        }
        SetenvVerdict::Error(reason) => {
            let _ = writeln!(s, "VERDICT setenv : ERREUR ({reason}) mot {raw:#018x}");
        }
    }
    if !matches!(v, SetenvVerdict::NotSent | SetenvVerdict::Silence) {
        s.push_str("instantané de B12 (0x80 o) :\n");
        s.push_str(&dump(snap));
    }
    s
}

/// Verdict of the null_d_key transaction. Unlike getcap/setenv, PARAM != 0 is NOT an error here: macOS answers
/// PARAM 0xff (no d-key to null), which is the benign, expected result. `Replied` therefore reports the signed
/// status as is (with the decoded body only when PARAM == 0, which is not expected).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NulldkeyVerdict {
    NotSent,
    Silence,
    Replied { status: i8, len: u16, call_flags: u16, body: Option<NulldkeyReply> },
    Error(String),
}

/// Decodes the null_d_key outcome record (0x98 bytes).
pub fn nulldkey_verdict(rec: &[u8]) -> Result<(NulldkeyVerdict, u64, Vec<u8>), String> {
    let (kind, raw, snap) = sks_ipc::decode_outcome(rec).map_err(|e| format!("enregistrement null_d_key illisible : {e}"))?;
    let snap = snap.to_vec();
    let v = match kind {
        sks_ipc::OUT_NOT_SENT => NulldkeyVerdict::NotSent,
        sks_ipc::OUT_SILENCE => NulldkeyVerdict::Silence,
        _ => {
            let w = Word::decode(raw);
            let rw = sks_nulldkey::reply_word(&w);
            if !sks_nulldkey::is_nulldkey_reply(&w) {
                NulldkeyVerdict::Error(format!("mot {raw:#018x} non apparié (EP/TAG bit 7/TYPE 0x03)"))
            } else {
                // PARAM != 0 (e.g. 0xff) → paired reply, no body. PARAM == 0 → decode the header+status body.
                let body = if rw.status == 0 { sks_nulldkey::decode_nulldkey_reply(&snap, usize::from(rw.len)).ok() } else { None };
                NulldkeyVerdict::Replied { status: rw.status, len: rw.len, call_flags: rw.call_flags, body }
            }
        }
    };
    Ok((v, raw, snap))
}

pub fn describe_nulldkey_verdict(v: &NulldkeyVerdict, raw: u64, snap: &[u8]) -> String {
    let mut s = String::new();
    match v {
        NulldkeyVerdict::NotSent => s.push_str("VERDICT null_d_key : NON ENVOYÉ (aucun mot null_d_key vers 0x12)\n"),
        NulldkeyVerdict::Silence => s.push_str("VERDICT null_d_key : SILENCE (aucune réponse appariée TAG bit 7 / TYPE 0x03)\n"),
        NulldkeyVerdict::Replied { status, len, call_flags, body } => {
            let interp = if *status == -1 {
                "PARAM 0xff = comme macOS (« pas de d-key à annuler ») → les perform_operation (txn3/txn5) N'ÉTAIENT PAS un prérequis"
            } else if body.is_some() {
                "PARAM 0 avec corps (le SEP a décodé un corps : cas non vu sous macOS)"
            } else {
                "PARAM ni 0xff ni 0 : réponse appariée différente de macOS (à interpréter)"
            };
            let _ = writeln!(
                s,
                "VERDICT null_d_key : RÉPONDU (PARAM {status} = statut signé ; longueur {len:#x}, drapeaux d'appel {call_flags:#06x}) mot {raw:#018x}\n  interprétation : {interp}"
            );
            if let Some(r) = body {
                let _ = writeln!(s, "  corps : L {:#x}, version d'en-tête {}, état {:#x}, condensé {}", r.hlen, r.version, r.state, if r.digest_ok { "OK" } else { "FAUX" });
            }
        }
        NulldkeyVerdict::Error(reason) => {
            let _ = writeln!(s, "VERDICT null_d_key : ERREUR ({reason}) mot {raw:#018x}");
        }
    }
    if !matches!(v, NulldkeyVerdict::NotSent | NulldkeyVerdict::Silence) {
        s.push_str("instantané de B12 (0x80 o) :\n");
        s.push_str(&dump(snap));
    }
    s
}

/// Human description of a create_keybag request (after the same check as the kernel gate).
pub fn describe_createkeybag(b: &[u8]) -> Result<String, String> {
    let r = sks_keybag::check_createkeybag(b).map_err(|e| format!("create_keybag refusé par la porte (identique au noyau) : {e}"))?;
    let k = sks_ipc::cdhash_kind(&GetcapFields { ts_us: r.fields.ts_us, uniqueid: r.fields.uniqueid, uid: r.fields.uid, cdhash: r.fields.cdhash });
    let mut s = String::new();
    let _ = writeln!(s, "create_keybag ({:#x} o) — mot > EP 0x12 TAG 0x01 TYPE 0x03 PARAM 0 DATA {:#010x}", b.len(), sks_keybag::CKB_DATA);
    let _ = writeln!(s, "  en-tête v2 ; 0x04 condensé v2 = {}", hex(&b[sks_ipc::OFF_DIGEST..sks_ipc::OFF_DIGEST + sks_ipc::DIGEST_LEN]));
    let _ = writeln!(s, "  variante 4 (discriminant 4) ; handle_y {:#018x} (USERLAND, défaut 0) ; class {:#010x} (USERLAND, 0x60) ; field2 {:#010x} (USERLAND, 0x64) ; 3 blobs vides ; fv_data 0 ; u64 final 0", r.handle_y, r.class, r.field2);
    let _ = writeln!(s, "  AMBIGU (§6.2/§6.4) : lequel de 0x60/0x64 est la classe n'est PAS tranché au binaire — si refus matériel, échanger --class/--field2");
    let _ = writeln!(s, "  horodatage {} µs ; uniqueid {:#x} ; uid {} ; cdhash {} ({})", r.fields.ts_us, r.fields.uniqueid, r.fields.uid, hex(&r.fields.cdhash), cdhash_label(k));
    s.push_str(&dump(b));
    Ok(s)
}

/// Human description of a make_system_keybag request (after the same check as the kernel gate).
pub fn describe_mskb(b: &[u8]) -> Result<String, String> {
    let r = sks_keybag::check_mskb(b).map_err(|e| format!("make_system_keybag refusé par la porte (identique au noyau) : {e}"))?;
    let k = sks_ipc::cdhash_kind(&GetcapFields { ts_us: r.fields.ts_us, uniqueid: r.fields.uniqueid, uid: r.fields.uid, cdhash: r.fields.cdhash });
    let mut s = String::new();
    let _ = writeln!(s, "make_system_keybag ({:#x} o) — mot > EP 0x12 TAG 0x0d TYPE 0x04 PARAM 0 DATA {:#010x}", b.len(), sks_keybag::MSKB_DATA);
    let _ = writeln!(s, "  en-tête v2 ; 0x04 condensé v2 = {}", hex(&b[sks_ipc::OFF_DIGEST..sks_ipc::OFF_DIGEST + sks_ipc::DIGEST_LEN]));
    let _ = writeln!(s, "  état 1 (const) ; handle_y {:#018x} (USERLAND) ; handle chargé {:#010x} (0 = placeholder, posé par le noyau) ; type {} (USERLAND{}) ; blob 0x10 o : uuid {} (USERLAND) ; flag 0", r.handle_y, r.loaded_handle, r.keybag_type, if sks_keybag::type_in_vu_range(r.keybag_type) { "" } else { ", HORS plage VU type<=-10" }, hex(&r.uuid));
    let _ = writeln!(s, "  DÉDUIT : §6.3 montre le blob du corps make_system VIDE ; l'uuid est une entrée d'identity_load dont le placement IPC n'est pas épinglé — à confirmer matériel");
    let _ = writeln!(s, "  horodatage {} µs ; uniqueid {:#x} ; uid {} ; cdhash {} ({})", r.fields.ts_us, r.fields.uniqueid, r.fields.uid, hex(&r.fields.cdhash), cdhash_label(k));
    s.push_str(&dump(b));
    Ok(s)
}

/// Verdict of the create_keybag transaction: RÉPONDU with the SEP handle (PARAM 0) or REFUS.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CreatekeybagVerdict {
    NotSent,
    Silence,
    /// PARAM 0: the SEP returned a keybag handle (read at OOL B +0x6c, offset DEDUCED).
    Handle(u32),
    Refus(String),
}

/// Verdict of the make_system_keybag transaction: marqué system (PARAM 0) or REFUS.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MskbVerdict {
    NotSent,
    Silence,
    MarkedSystem,
    Refus(String),
}

pub fn createkeybag_verdict(rec: &[u8]) -> Result<(CreatekeybagVerdict, u64, Vec<u8>), String> {
    let (kind, raw, snap) = sks_ipc::decode_outcome(rec).map_err(|e| format!("enregistrement create_keybag illisible : {e}"))?;
    let snap = snap.to_vec();
    let v = match kind {
        sks_ipc::OUT_NOT_SENT => CreatekeybagVerdict::NotSent,
        sks_ipc::OUT_SILENCE => CreatekeybagVerdict::Silence,
        _ => {
            let w = Word::decode(raw);
            let rw = sks_keybag::reply_word(&w);
            if !sks_keybag::is_createkeybag_reply(&w) {
                CreatekeybagVerdict::Refus(format!("mot {raw:#018x} non apparié (EP/TAG bit 7/TYPE 0x03)"))
            } else if rw.status != 0 {
                CreatekeybagVerdict::Refus(format!("PARAM {} = statut signé ≠ 0", rw.status))
            } else {
                match sks_keybag::reply_handle(&snap) {
                    Ok(h) => CreatekeybagVerdict::Handle(h),
                    Err(e) => CreatekeybagVerdict::Refus(format!("handle illisible à +0x6c : {e}")),
                }
            }
        }
    };
    Ok((v, raw, snap))
}

pub fn mskb_verdict(rec: &[u8]) -> Result<(MskbVerdict, u64, Vec<u8>), String> {
    let (kind, raw, snap) = sks_ipc::decode_outcome(rec).map_err(|e| format!("enregistrement make_system_keybag illisible : {e}"))?;
    let snap = snap.to_vec();
    let v = match kind {
        sks_ipc::OUT_NOT_SENT => MskbVerdict::NotSent,
        sks_ipc::OUT_SILENCE => MskbVerdict::Silence,
        _ => {
            let w = Word::decode(raw);
            let rw = sks_keybag::reply_word(&w);
            if !sks_keybag::is_mskb_reply(&w) {
                MskbVerdict::Refus(format!("mot {raw:#018x} non apparié (EP/TAG bit 7/TYPE 0x04)"))
            } else if rw.status == 0 {
                MskbVerdict::MarkedSystem
            } else {
                MskbVerdict::Refus(format!("PARAM {} = statut signé ≠ 0", rw.status))
            }
        }
    };
    Ok((v, raw, snap))
}

pub fn describe_createkeybag_verdict(v: &CreatekeybagVerdict, raw: u64, snap: &[u8]) -> String {
    let mut s = String::new();
    match v {
        CreatekeybagVerdict::NotSent => s.push_str("VERDICT sks create_keybag : NON ENVOYÉ (aucun mot create_keybag vers 0x12)\n"),
        CreatekeybagVerdict::Silence => s.push_str("VERDICT sks create_keybag : REFUS/SILENCE (aucune réponse appariée TAG bit 7 / TYPE 0x03)\n"),
        CreatekeybagVerdict::Handle(h) => {
            let _ = writeln!(s, "VERDICT sks create_keybag : handle={h:#010x} (PARAM 0 ; lu à OOL B +0x6c, offset DÉDUIT) mot {raw:#018x}");
        }
        CreatekeybagVerdict::Refus(reason) => {
            let _ = writeln!(s, "VERDICT sks create_keybag : REFUS ({reason}) mot {raw:#018x}");
        }
    }
    if !matches!(v, CreatekeybagVerdict::NotSent) {
        s.push_str("instantané de B12 (0x80 o) :\n");
        s.push_str(&dump(snap));
    }
    s
}

pub fn describe_mskb_verdict(v: &MskbVerdict, raw: u64, snap: &[u8]) -> String {
    let mut s = String::new();
    match v {
        MskbVerdict::NotSent => s.push_str("VERDICT sks make_system_keybag : NON ENVOYÉ (create_keybag sans handle, ou valeurs userland manquantes)\n"),
        MskbVerdict::Silence => s.push_str("VERDICT sks make_system_keybag : SILENCE (aucune réponse appariée TAG bit 7 / TYPE 0x04)\n"),
        MskbVerdict::MarkedSystem => {
            let _ = writeln!(s, "VERDICT sks make_system_keybag : marqué system (PARAM 0) mot {raw:#018x}");
        }
        MskbVerdict::Refus(reason) => {
            let _ = writeln!(s, "VERDICT sks make_system_keybag : REFUS ({reason}) mot {raw:#018x}");
        }
    }
    if !matches!(v, MskbVerdict::NotSent) {
        s.push_str("instantané de B12 (0x80 o) :\n");
        s.push_str(&dump(snap));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;
    use sep_proto::sks_ipc::{encode_outcome, OUT_NOT_SENT, OUT_REPLIED, OUT_SILENCE, OUT_SNAP};

    #[test]
    fn requests_build_and_describe() {
        for mode in [CdhashMode::Sha1, CdhashMode::Zero] {
            for cpx in [0u32, 2] {
                let gc = sks_ipc::encode_getcap(&getcap_fields(123, 0, 0, mode));
                let se = sks_setenv::encode_setenv(&setenv_fields(123, 0, 0, mode, cpx));
                assert!(describe_getcap(&gc).is_ok());
                assert!(describe_setenv(&se).is_ok());
                assert_eq!(sks_setenv::check_setenv(&se).unwrap().cpx, cpx);
            }
        }
    }

    fn se_reply_snap(state: u32) -> [u8; OUT_SNAP] {
        let mut b = [0u8; OUT_SNAP];
        b[0..4].copy_from_slice(&0x50u32.to_le_bytes());
        b[0x14..0x18].copy_from_slice(&2u32.to_le_bytes());
        b[0x54..0x58].copy_from_slice(&state.to_le_bytes());
        let d = sks_ipc::frame_digest(&b, 2, 0x54, 0x58).unwrap();
        b[4..20].copy_from_slice(&d);
        b
    }

    #[test]
    fn setenv_outcomes() {
        // c12 L181: `< EP=0x12 TAG=0xaa TYPE=0x02 PARAM=0x00 DATA=0x00580000`.
        let raw = 0x0058_0000_0002_aa12u64;
        let (v, _, _) = setenv_verdict(&encode_outcome(OUT_REPLIED, raw, &se_reply_snap(0))).unwrap();
        match v {
            SetenvVerdict::Accepted(r) => assert_eq!((r.hlen, r.version, r.digest_ok, r.state), (0x50, 2, true, 0)),
            x => panic!("{x:?}"),
        }
        assert!(matches!(setenv_verdict(&encode_outcome(OUT_REPLIED, raw, &se_reply_snap(1))).unwrap().0, SetenvVerdict::Error(_)));
        // PARAM 0xff = -1.
        let err = 0x0000_0000_ff02_aa12u64;
        assert!(matches!(setenv_verdict(&encode_outcome(OUT_REPLIED, err, &[0; OUT_SNAP])).unwrap().0, SetenvVerdict::Error(_)));
        assert_eq!(setenv_verdict(&encode_outcome(OUT_SILENCE, 0, &[0; OUT_SNAP])).unwrap().0, SetenvVerdict::Silence);
        assert_eq!(setenv_verdict(&encode_outcome(OUT_NOT_SENT, 0, &[0; OUT_SNAP])).unwrap().0, SetenvVerdict::NotSent);
    }

    #[test]
    fn nulldkey_build_describe_and_outcomes() {
        for mode in [CdhashMode::Sha1, CdhashMode::Zero] {
            let nd = sks_nulldkey::encode_nulldkey(&nulldkey_fields(123, 0, 0, mode));
            assert!(describe_nulldkey(&nd).is_ok());
            assert_eq!(sks_nulldkey::check_nulldkey(&nd).unwrap(), nulldkey_fields(123, 0, 0, mode));
        }
        // macOS c12 L187 shape with our TYPE 0x03: `< 0x12 TAG 0x8a TYPE 0x03 PARAM 0xff DATA 0`.
        let raw = 0x0000_0000_ff03_8a12u64;
        let (v, _, _) = nulldkey_verdict(&encode_outcome(OUT_REPLIED, raw, &[0; OUT_SNAP])).unwrap();
        match v {
            NulldkeyVerdict::Replied { status, body, .. } => {
                assert_eq!(status, -1);
                assert!(body.is_none());
            }
            x => panic!("{x:?}"),
        }
        assert_eq!(nulldkey_verdict(&encode_outcome(OUT_SILENCE, 0, &[0; OUT_SNAP])).unwrap().0, NulldkeyVerdict::Silence);
        assert_eq!(nulldkey_verdict(&encode_outcome(OUT_NOT_SENT, 0, &[0; OUT_SNAP])).unwrap().0, NulldkeyVerdict::NotSent);
        // Non-paired word → Error.
        assert!(matches!(nulldkey_verdict(&encode_outcome(OUT_REPLIED, 0x0000_0000_0003_0a12, &[0; OUT_SNAP])).unwrap().0, NulldkeyVerdict::Error(_)));
    }

    #[test]
    fn keybag_build_describe_and_outcomes() {
        // ARBITRARY example values — PAS les vraies (uuid/class/type inconnus, reversés sur le PC).
        let uuid: [u8; UUID_LEN] = core::array::from_fn(|i| i as u8);
        let ckb = sks_keybag::encode_createkeybag(&keybag_fields(123, 0, 0, CdhashMode::Sha1), 0x4242, 2, 0);
        assert!(describe_createkeybag(&ckb).is_ok());
        let mskb = sks_keybag::encode_mskb(&keybag_fields(123, 0, 0, CdhashMode::Sha1), 0x4242, 0, -16, &uuid);
        assert!(describe_mskb(&mskb).is_ok());

        // create_keybag reply PARAM 0 with a handle at OOL B +0x6c.
        let mut snap = [0u8; OUT_SNAP];
        snap[sks_keybag::OFF_RESP_HANDLE..sks_keybag::OFF_RESP_HANDLE + 4].copy_from_slice(&0x0abc_def0u32.to_le_bytes());
        let raw = 0x0010_0000_0003_8112u64; // TAG 0x81 TYPE 0x03 PARAM 0
        let (v, _, _) = createkeybag_verdict(&encode_outcome(OUT_REPLIED, raw, &snap)).unwrap();
        assert_eq!(v, CreatekeybagVerdict::Handle(0x0abc_def0));
        // PARAM 0xff → REFUS.
        let refus = 0x0000_0000_ff03_8112u64;
        assert!(matches!(createkeybag_verdict(&encode_outcome(OUT_REPLIED, refus, &[0; OUT_SNAP])).unwrap().0, CreatekeybagVerdict::Refus(_)));
        assert_eq!(createkeybag_verdict(&encode_outcome(OUT_SILENCE, 0, &[0; OUT_SNAP])).unwrap().0, CreatekeybagVerdict::Silence);
        assert_eq!(createkeybag_verdict(&encode_outcome(OUT_NOT_SENT, 0, &[0; OUT_SNAP])).unwrap().0, CreatekeybagVerdict::NotSent);

        // make_system_keybag reply PARAM 0 → marqué system ; PARAM != 0 → REFUS.
        let ok = 0x0000_0000_0000_8d12u64 | (0x04u64 << 16); // TAG 0x8d TYPE 0x04 PARAM 0
        assert_eq!(mskb_verdict(&encode_outcome(OUT_REPLIED, ok, &[0; OUT_SNAP])).unwrap().0, MskbVerdict::MarkedSystem);
        let bad = ok | (0xffu64 << 24);
        assert!(matches!(mskb_verdict(&encode_outcome(OUT_REPLIED, bad, &[0; OUT_SNAP])).unwrap().0, MskbVerdict::Refus(_)));
        assert_eq!(mskb_verdict(&encode_outcome(OUT_NOT_SENT, 0, &[0; OUT_SNAP])).unwrap().0, MskbVerdict::NotSent);
    }

    #[test]
    fn getcap_outcomes() {
        let mut snap = [0u8; OUT_SNAP];
        snap[0..4].copy_from_slice(&0x48u32.to_le_bytes());
        snap[0x14..0x18].copy_from_slice(&1u32.to_le_bytes());
        snap[0x50..0x58].copy_from_slice(&2u64.to_le_bytes());
        let d = sks_ipc::frame_digest(&snap[..0x5c], 1, 0x4c, 0x5c).unwrap();
        snap[4..20].copy_from_slice(&d);
        let raw = 0x005c_0001_0001_cd12u64;
        let (v, _) = getcap_verdict(&encode_outcome(OUT_REPLIED, raw, &snap)).unwrap();
        match v {
            GetcapVerdict::Replied(r) => assert_eq!((r.theirs, r.negotiated(), r.digest_ok), (2, 2, true)),
            x => panic!("{x:?}"),
        }
    }
}
