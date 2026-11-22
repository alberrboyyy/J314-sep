// SPDX-License-Identifier: GPL-2.0
//! sep_proto_selftest : module de diagnostic. Embarque le cœur sans allocation de la crate `sep-proto`
//! (`../sep-proto/src/`, compilée sans les features `std` ni `alloc`) et, au chargement, vérifie des vecteurs
//! connus par CALCUL PUR, puis affiche le résultat. Ne se lie à AUCUN périphérique, ne lit pas le device tree,
//! n'ouvre aucun mailbox, n'envoie RIEN au SEP. Renvoie toujours Ok (diagnostic : les échecs sont affichés).
//!
//! Les modules de `sep-proto` sont inclus tels quels (`#[path]`) à la racine de ce crate, comme dans la crate
//! d'origine, pour que leurs chemins `crate::...` se résolvent à l'identique. Les parties qui demandent
//! `Vec`/`BTreeMap` sont derrière `#[cfg(feature = "alloc")]` et disparaissent ici (le noyau n'a pas de crate
//! `alloc`).

use kernel::prelude::{module, pr_info, ThisModule};

// --- cœur de sep-proto, sans allocation -------------------------------------------------------------------
#[path = "../sep-proto/src/common.rs"]
#[allow(dead_code, unreachable_pub)]
mod common;
use common::{le_u16, le_u32, Error, Result};

#[path = "../sep-proto/src/crc.rs"]
#[allow(dead_code, unreachable_pub)]
mod crc;
#[path = "../sep-proto/src/daemon.rs"]
#[allow(dead_code, unreachable_pub)]
mod daemon;
#[path = "../sep-proto/src/discovery.rs"]
#[allow(dead_code, unreachable_pub)]
mod discovery;
#[path = "../sep-proto/src/gt.rs"]
#[allow(dead_code, unreachable_pub)]
mod gt;
#[path = "../sep-proto/src/sensor.rs"]
#[allow(dead_code, unreachable_pub)]
mod sensor;
#[path = "../sep-proto/src/word.rs"]
#[allow(dead_code, unreachable_pub)]
mod word;
#[path = "../sep-proto/src/xart.rs"]
#[allow(dead_code, unreachable_pub)]
mod xart;
#[path = "../sep-proto/src/xart_responder.rs"]
#[allow(dead_code, unreachable_pub)]
mod xart_responder;

module! {
    type: SepProtoSelftest,
    name: "sep_proto_selftest",
    authors: ["Albert Braimi"],
    description: "Offline self-test of the sep-proto protocol core (pure computation, touches no hardware)",
    license: "GPL",
}

/// Compteur des vérifications ; chaque résultat est affiché.
struct Tally {
    ok: u32,
    total: u32,
}

impl Tally {
    fn check(&mut self, name: &str, pass: bool) {
        self.total += 1;
        if pass {
            self.ok += 1;
            pr_info!("ok   {}\n", name);
        } else {
            pr_info!("FAIL {}\n", name);
        }
    }
}

/// Statut capteur d'init observé (même constante que le test hôte `sensor::tests::STATUS`).
const STATUS: [u8; 16] = [0x80, 0x20, 0, 0x10, 0, 0, 0, 0, 0x60, 0, 0, 0, 0x52, 0x33, 0, 0];

fn run(t: &mut Tally) {
    use gt::{CounterChecker, CounterFault, OolHeader};
    use word::{Dir, Msg, Word};

    // word : disposition des bits EP/TAG/TYPE/PARAM/DATA.
    let w = Word::decode(0x1122_3344_5566_7788);
    t.check("word.decode", w == Word::new(0x88, 0x77, 0x66, 0x55, 0x1122_3344));
    t.check("word.encode", w.encode() == 0x1122_3344_5566_7788);
    t.check(
        "word.checked",
        Word::checked(0x100, 0, 0, 0, 0).is_err()
            && Word::checked(0, 0, 0, 0, 1 << 32).is_err()
            && Word::checked(0xFF, 0xFF, 0xFF, 0xFF, 0xFFFF_FFFF) == Ok(Word::decode(u64::MAX)),
    );

    // crc : valeurs de contrôle du catalogue.
    t.check("crc.crc16_arc", crc::crc16_arc(b"123456789") == 0xBB3D);
    t.check("crc.crc32", crc::crc32(b"123456789") == 0xCBF4_3926);

    // sensor : trame d'identité, requête de lecture, statut.
    t.check(
        "sensor.identity",
        matches!(sensor::parse_frame(&sensor::IDENTITY_J314C),
                 Ok(f) if f.op == 0xd4 && f.index == 0 && f.total_len == 0x1b && f.length_ok()),
    );
    t.check(
        "sensor.read_request",
        sensor::build_read_request(0x1b) == [0x80, 0x13, 0, 0x0b, 0, 0, 0, 0x1b, 0, 0, 0],
    );
    t.check(
        "sensor.status",
        matches!(sensor::parse_status(&STATUS),
                 Ok(s) if s.frame.length_ok() && s.state_byte() == Some(0) && s.avail_u32() == Some(0x3352)
                     && !s.trailer_is_crc16_arc())
            && crc::crc16_arc(&STATUS[..14]) == 0x35DE,
    );
    t.check(
        "sensor.reject",
        sensor::parse_frame(&[0x80, 0x20, 0]) == Err(Error::Short)
            && sensor::parse_frame(&[0, 0x20, 0, 7, 0, 0, 0]) == Err(Error::BadMagic)
            && sensor::parse_status(&sensor::CMD_IDENTITY).is_err(),
    );

    // xart : longueur de FETCH, en-tête de casier.
    t.check(
        "xart.decode_fetch_len",
        xart::decode_fetch_len(0x64, 0x03) == 0x364
            && xart::decode_fetch_len(0x14, 0x08) == 0x814
            && xart::decode_fetch_len(0x0c, 0x0c) == 0xc0c,
    );
    t.check(
        "xart.encode_fetch_len",
        xart::encode_fetch_len(0x364, xart::SEL_SEP) == Ok((0x64, 0x0103))
            && xart::selector(0x0103) == xart::SEL_SEP
            && xart::encode_fetch_len(0x1_0000, 0).is_err(),
    );
    let payload = [0xde, 0xad, 0xbe, 0xef, 0x01, 0x02, 0x03, 0x04];
    let h = xart::build_header(xart::T_SEP_MASTER, &[], &payload, 0);
    t.check(
        "xart.build_header",
        h[1] == xart::T_SEP_MASTER
            && le_u32(&h, 0x12) == Ok(payload.len() as u32)
            && le_u32(&h, 0x16) == Ok(crc::crc32(&payload))
            && le_u16(&h, 0x1a) == Ok(0),
    );

    // xart_responder : réponses observées de macOS (calculées, rien n'est envoyé).
    let fwboot = Word::new(xart::EP_XART, 3, xart::OP_FWBOOT, 0, 0);
    let fetch = Word::new(xart::EP_XART, 4, xart::OP_FETCH_MASTER, 0, 0x100);
    t.check(
        "xart_responder.observed",
        matches!(xart_responder::observed_response(&fwboot, None),
                 Ok(r) if r.word() == Word::new(xart::EP_XART, 3, xart_responder::RESP_DONE, 0, 0x100))
            && matches!(xart_responder::observed_response(&fetch, Some(0x364)),
                        Ok(r) if r.param == 0x64 && r.data == 0x0103 && r.serves_blob)
            && xart_responder::observed_response(&fetch, None).is_err()
            && xart_responder::observed_response(&Word::new(xart::EP_XART, 1, 0x42, 0, 0), None).is_err(),
    );
    t.check(
        "xart_responder.save_ack",
        xart_responder::native_on_save(&Word::new(xart::EP_XART, 1, xart::OP_SAVE_XART, 0, 0x8929_0103))
            == Ok(0x8929_0100),
    );

    // daemon : séquence d'init sbio, requête d'export, uid de blob.
    let seq = &daemon::INIT_SEQUENCE;
    t.check(
        "daemon.init_sequence",
        seq.len() == 57
            && seq.iter().filter(|&&c| c == daemon::T_IMPORT).count() == 2
            && seq.first() == Some(&0x73)
            && seq.last() == Some(&0x7c),
    );
    let mut blob = [0u8; 12];
    blob[..4].copy_from_slice(daemon::MAGIC);
    blob[8..].copy_from_slice(&501u32.to_le_bytes());
    t.check(
        "daemon.blob_uid",
        daemon::blob_uid(&blob) == Ok(501)
            && daemon::blob_uid(&[0u8; 12]) == Err(Error::BadMagic)
            && daemon::export_request(daemon::UID_NONE)[..4] == [0xFF; 4],
    );

    // discovery : nom d'EP sur 4 caractères.
    t.check("discovery.decode_name", &discovery::decode_name(0x7362_696f) == b"sbio");

    // gt : règle des compteurs sur une petite séquence synthétique, et en-tête OOL.
    let gtw = |dir, tag, k: u32| Msg::new(0, dir, Word::new(8, tag, 0x6D, 0, k << 16));
    let good = [
        gtw(Dir::ToSep, gt::TAG_FC, 0),
        gtw(Dir::ToAp, gt::TAG_FE, 0),
        gtw(Dir::ToSep, gt::TAG_FD, 1),
        gtw(Dir::ToAp, gt::TAG_FE, 1),
        gtw(Dir::ToSep, gt::TAG_FD, 2),
        gtw(Dir::ToAp, gt::TAG_FC, 0),
    ];
    let mut c = CounterChecker::new();
    t.check("gt.counter_good", good.iter().all(|m| c.check(m).is_ok()));
    let mut c = CounterChecker::new();
    let bad = [gtw(Dir::ToSep, gt::TAG_FC, 0), gtw(Dir::ToSep, gt::TAG_FD, 2)];
    t.check(
        "gt.counter_bad",
        c.check(&bad[0]).is_ok()
            && c.check(&bad[1]) == Err(CounterFault::Fd { got: 2, want: 1 })
            && CounterChecker::new().check(&Msg::new(0, Dir::ToSep, Word::new(8, gt::TAG_FC, 0x6D, 1, 0)))
                == Err(CounterFault::Format),
    );
    let oh = OolHeader { valid: 1, total: 0x7200, offset: 0x3fe4, ty: u32::from(gt::T_IMAGE), len: 0x321c };
    t.check("gt.ool_header", OolHeader::parse(&oh.to_bytes()) == Some(oh) && OolHeader::parse(&[0u8; 4]).is_none());

    // Result de sep-proto utilisé tel quel (vérifie que le type est bien celui du cœur embarqué).
    let r: Result<u32> = le_u32(&[1, 0, 0], 0);
    t.check("common.le_short", r == Err(Error::Short));
}

struct SepProtoSelftest;

impl kernel::Module for SepProtoSelftest {
    fn init(_module: &'static ThisModule) -> kernel::error::Result<Self> {
        pr_info!("auto-test du cœur sep-proto (calcul pur, aucun accès matériel)\n");
        let mut t = Tally { ok: 0, total: 0 };
        run(&mut t);
        pr_info!("{}/{} OK\n", t.ok, t.total);
        Ok(SepProtoSelftest)
    }
}
