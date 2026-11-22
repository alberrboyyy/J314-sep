//! Offline tests of the J5 relay against the macOS capture c12 (`traces/20261108-032454_c12-boot-ho`, read-only):
//! - the kernel-built gt_packets (`sbio_gate::build_packet`) are byte-identical to the A8 buffers macOS sent;
//! - the SEP replies in B8 pass `check_fragment`, and the 0x5f patch reassembles to 0x568e bytes (2 fragments);
//! - a full run against a fake SEP (c12 replies, kernel order/length gate) and a fake sensor (frames of C19 shape)
//!   relays the right bytes and reaches each verdict.
use sbiod::{check_patch, run, Mesa, Sensor, Sep, Verdict, KX_SESSION, PATCH_INPUT, SERIAL_J314C};
use sep_proto::gt::OOL_HDR;
use sep_proto::sbio_gate::{build_packet, check_cmd, check_fragment, RELAY_SEQUENCE};
use sep_proto::sensor::IDENTITY_J314C;
use std::path::PathBuf;

fn ool(name: &str) -> Option<Vec<u8>> {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../traces/20261108-032454_c12-boot-ho/sep.log.ool").join(name);
    std::fs::read(p).ok()
}

/// (op, A template, payload the daemon sends; None = taken from the template, live in a real run).
fn templates() -> Vec<(u8, &'static str, Option<Vec<u8>>)> {
    vec![
        (0x73, "000300_08_A.bin", Some(vec![1, 0, 0, 0])),
        (0x17, "000303_08_A.bin", Some(SERIAL_J314C.to_vec())),
        (0x15, "000305_08_A.bin", Some(KX_SESSION.to_vec())),
        (0x16, "000307_08_A.bin", None),
        (0x42, "000309_08_A.bin", Some(vec![])),
        (0x18, "000311_08_A.bin", None),
        (0x5f, "000313_08_A.bin", Some(PATCH_INPUT.to_vec())),
    ]
}

#[test]
fn packets_equal_macos_a8() {
    let Some(_) = ool("000300_08_A.bin") else { return eprintln!("c12 absent: skipped") };
    for (op, f, pay) in templates() {
        let t = ool(f).unwrap();
        let len = u32::from_le_bytes([t[0x18], t[0x19], t[0x1a], t[0x1b]]) as usize;
        let pay = pay.unwrap_or_else(|| t[OOL_HDR..OOL_HDR + len].to_vec());
        let mut a = vec![0u8; t.len()];
        build_packet(op, &pay, &mut a).unwrap();
        assert_eq!(a, t, "gt_packet {op:#04x} != {f}");
    }
    // The whitelist lengths are those of the templates.
    for s in RELAY_SEQUENCE {
        let f = templates().into_iter().find(|t| t.0 == s.op).unwrap().1;
        assert_eq!(ool(f).unwrap()[0x18] as usize, s.cmd_len, "{:#04x}", s.op);
    }
}

/// c12 SEP replies: op -> list of B8 fragments.
fn c12_replies() -> Option<Vec<(u8, Vec<Vec<u8>>)>> {
    let f = |n: &str| ool(n);
    Some(vec![
        (0x17, vec![f("000304_08_B.bin")?]),
        (0x15, vec![f("000306_08_B.bin")?]),
        (0x16, vec![f("000308_08_B.bin")?]),
        (0x42, vec![f("000310_08_B.bin")?]),
        (0x18, vec![f("000312_08_B.bin")?]),
        (0x5f, vec![f("000314_08_B.bin")?, f("000316_08_B.bin")?]),
    ])
}

/// Kernel-side reassembly (same calls as `on_relay`).
fn reassemble(op: u8, frags: &[Vec<u8>]) -> Vec<u8> {
    let step = RELAY_SEQUENCE.iter().find(|s| s.op == op).unwrap();
    let (mut buf, mut total) = (Vec::new(), None);
    for (i, b) in frags.iter().enumerate() {
        let fr = check_fragment(step, &b[..OOL_HDR], buf.len(), total, i).unwrap();
        buf.extend_from_slice(&b[OOL_HDR..OOL_HDR + fr.len]);
        total = Some(fr.total);
    }
    assert_eq!(Some(buf.len()), total);
    buf
}

#[test]
fn c12_replies_pass_the_gate() {
    let Some(r) = c12_replies() else { return eprintln!("c12 absent: skipped") };
    let lens: Vec<usize> = r.iter().map(|(op, f)| reassemble(*op, f).len()).collect();
    assert_eq!(lens, [0, 0x28, 0, 0x40, 0, 0x568e]);
    let patch = reassemble(0x5f, &r[5].1);
    check_patch(&patch).unwrap();
    assert_eq!(&patch[..3], &[0x8c, 0x56, 0x3a]);
    // Out-of-order second fragment is refused.
    let step = &RELAY_SEQUENCE[5];
    assert!(check_fragment(step, &r[5].1[1][..OOL_HDR], 0, None, 0).is_err());
}

struct FakeSep {
    replies: Vec<(u8, Vec<Vec<u8>>)>,
    next: usize,
    sent: Vec<(u8, Vec<u8>)>,
}

impl Sep for FakeSep {
    fn cmd(&mut self, op: u8, payload: &[u8]) -> Result<Vec<u8>, String> {
        check_cmd(self.next, op, payload.len()).map_err(|e| e.to_string())?;
        self.next += 1;
        self.sent.push((op, payload.to_vec()));
        let f = &self.replies.iter().find(|r| r.0 == op).unwrap().1;
        Ok(reassemble(op, f))
    }
}

#[derive(Default)]
struct FakeSensor {
    t: u64,
    pending: Option<Vec<u8>>,
    armed: usize,
    prelude: bool,
    mid_read: bool,
    t_block: u64,
    block: Option<Vec<u8>>,
    accept: bool,
    polls_after: u32,
    frames: Vec<Vec<u8>>,
}

fn relay_answer(op: u8, n: usize, total: usize) -> Vec<u8> {
    let mut r = vec![0x80, op | 0x80, 0, total as u8, 0, 0, 0, 0, op];
    r.extend((0..n).map(|i| (i as u8) ^ op));
    r.extend_from_slice(&[0xee, 0xee]);
    r
}

impl Sensor for FakeSensor {
    fn xfer(&mut self, tx: &[u8], rx: bool) -> Result<Vec<u8>, String> {
        self.frames.push(tx.to_vec());
        let mut out = vec![0u8; if rx { tx.len() } else { 0 }];
        if self.armed > 0 && rx && tx.iter().all(|&b| b == 0) && tx.len() == self.armed {
            out.copy_from_slice(&self.pending.take().unwrap());
            self.armed = 0;
            return Ok(out);
        }
        if self.prelude && tx.len() > 7 && tx[0] != 0x80 {
            self.block = Some(tx.to_vec());
            self.t_block = self.t;
            self.prelude = false;
            return Ok(out);
        }
        match (tx[0], tx[1]) {
            (0x80, 0x10) => {
                // Like macOS (C17..C20): the block is only accepted if the status was read between prelude and block.
                if self.prelude {
                    self.mid_read = true;
                }
                let st8 = if self.block.is_some() && self.accept && self.mid_read { 0x29 } else { 0x60 };
                if self.block.is_some() {
                    self.polls_after += 1;
                }
                let n = self.pending.as_ref().map_or(0, Vec::len);
                let body = [0x80, 0x20, 0, 0x10, 0, 0, 0, if n > 0 { 7 } else { 0 }, st8, 0, 0, 0, n as u8, (n >> 8) as u8, 0, 0];
                out[7..23].copy_from_slice(&body);
            }
            (0x80, 0x78) => {}
            (0x80, 0x70) => self.pending = Some(IDENTITY_J314C.to_vec()),
            (0x80, 0x13) => self.armed = u32::from_le_bytes([tx[7], tx[8], tx[9], tx[10]]) as usize,
            (0x80, 0x72) if tx.len() == 0x2f => self.pending = Some(relay_answer(0x72, 40, 0x33)),
            (0x80, 0x73) if tx.len() == 0x47 => self.pending = Some(relay_answer(0x73, 64, 0x4b)),
            (0x80, 0x60) if tx.len() == 7 => self.prelude = true,
            _ => return Err(format!("trame inattendue {:02x?}", &tx[..tx.len().min(8)])),
        }
        Ok(out)
    }
    fn ready(&mut self) -> Option<bool> {
        // Pin: up after the prelude until the status read, then down while loading (5 ms), then up.
        let loading = self.block.is_some() && self.t < self.t_block + 5;
        Some((self.prelude && !self.mid_read) || (self.block.is_some() && !loading))
    }
    fn sleep_ms(&mut self, ms: u64) {
        self.t += ms;
    }
    fn now_ms(&mut self) -> u64 {
        self.t += 1;
        self.t
    }
}

fn run_fake(accept: bool) -> Option<(Verdict, FakeSep, FakeSensor)> {
    let mut sep = FakeSep { replies: c12_replies()?, next: 0, sent: vec![] };
    let mut s = FakeSensor { accept, ..Default::default() };
    let mut log = |l: &str| eprintln!("{l}");
    let v = run(&mut sep, &mut Mesa { s: &mut s, log: &mut log });
    Some((v, sep, s))
}

#[test]
fn full_run_relays_the_right_bytes() {
    let Some((v, sep, s)) = run_fake(true) else { return eprintln!("c12 absent: skipped") };
    assert!(matches!(v, Verdict::Loaded { irq_seen: true, .. }), "{v:?}");
    let ops: Vec<u8> = sep.sent.iter().map(|c| c.0).collect();
    assert_eq!(ops, [0x17, 0x15, 0x16, 0x42, 0x18, 0x5f]);
    assert_eq!(sep.sent[0].1, SERIAL_J314C);
    let r = c12_replies().unwrap();
    let kx = reassemble(0x15, &r[1].1);
    let cnt = reassemble(0x42, &r[3].1);
    // SPI frames: header of C19 shape + the SEP blob verbatim.
    let f72 = s.frames.iter().find(|f| f.len() == 0x2f).unwrap();
    assert_eq!((&f72[..7], &f72[7..]), (&[0x80, 0x72, 0, 0x2f, 0, 0, 0][..], &kx[..]));
    let f73 = s.frames.iter().find(|f| f.len() == 0x47 && f[1] == 0x73).unwrap();
    assert_eq!((&f73[..7], &f73[7..]), (&[0x80, 0x73, 0, 0x47, 0, 0, 0][..], &cnt[..]));
    // Sensor answers (40 / 64 bytes @ 9) go back to the SEP verbatim.
    assert_eq!(sep.sent[2].1, relay_answer(0x72, 40, 0x33)[9..49]);
    assert_eq!(sep.sent[4].1, relay_answer(0x73, 64, 0x4b)[9..73]);
    // Prelude alone, then the whole block in ONE transfer.
    // macOS order: prelude, ONE status read, the whole block in ONE transfer, then ONE status read.
    let i = s.frames.iter().position(|f| f[..] == [0x80, 0x60, 0, 7, 0, 0, 0]).unwrap();
    assert_eq!(&s.frames[i + 1][..2], &[0x80, 0x10]);
    assert_eq!(s.frames[i + 2], reassemble(0x5f, &r[5].1));
    assert_eq!(&s.frames[i + 3][..2], &[0x80, 0x10]);
    assert_eq!(s.frames.len(), i + 4, "aucune lecture en plus après le chargement");
}

#[test]
fn full_run_patch_not_loaded() {
    let Some((v, sep, _)) = run_fake(false) else { return eprintln!("c12 absent: skipped") };
    assert_eq!(v, Verdict::Refused { st8: Some(0x60) });
    assert_eq!(sep.next, 6);
}
