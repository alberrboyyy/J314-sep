//! Offline tests of the J5 relay against the macOS capture c12 (`traces/20261108-032454_c12-boot-ho`, read-only):
//! - the kernel-built gt_packets (`sbio_gate::build_packet`) are byte-identical to the A8 buffers macOS sent;
//! - the SEP replies in B8 pass `check_fragment`, and the 0x5f patch reassembles to 0x568e bytes (2 fragments);
//! - a full run against a fake SEP (c12 replies, kernel order/length gate) and a fake sensor (frames of C19 shape)
//!   relays the right bytes and reaches each verdict;
//! - J5c (docs/j5_params_protocol.md): 0x5d..0x63 against c12 (A8 = macOS, 0x5b fragments = macOS A8), a fake sensor
//!   that only accepts 0x55 frames with the right CRC and status reads after its IRQ, and every fail-closed stop;
//! - J5c pass 2 (docs/j5_params_protocol.md §8): 0x19 .. 0x63 ×2 against c12 seq 345-382 (A8 = macOS), a fake sensor
//!   that is power cycled and answers the C18-C20 statuses, the macOS SPI order, and every fail-closed stop.
use sbiod::{
    calib_from_c12, check_calib, check_patch, run, success, Mesa, Sensor, Sep, Upto, Verdict, CAL_INFO_REF, KX_SESSION,
    PATCH_INPUT, PARAMS_INPUT, SERIAL_J314C,
};
use sep_proto::crc::crc16_arc;
use sep_proto::gt::OOL_HDR;
use sep_proto::sbio_gate::{
    build_packet, check_cmd, check_fragment, cmd_frags, fragment_header, LIMIT_CALIB, LIMIT_PARAMS, LIMIT_PASS2,
    LIMIT_PATCH, PATCH2_LEN, RELAY_SEQUENCE, SBIO_OOL_SIZE,
};
use sep_proto::sensor::{IDENTITY_J314C, ST_AFTER_PARAMS, ST_IDENTITY_READY, ST_POWER_ON, ST_SERIAL_READY};
use std::path::PathBuf;

fn c12_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../traces/20261108-032454_c12-boot-ho/sep.log.ool")
}

fn ool(name: &str) -> Option<Vec<u8>> {
    std::fs::read(c12_dir().join(name)).ok()
}

fn calib() -> Option<Vec<u8>> {
    ool("000335_08_A.bin")?;
    Some(calib_from_c12(&c12_dir()).unwrap())
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
        (0x5d, "000317_08_A.bin", Some(PARAMS_INPUT.to_vec())),
        (0x5c, "000319_08_A.bin", Some(PARAMS_INPUT.to_vec())),
        (0x6a, "000321_08_A.bin", Some(vec![])),
        (0x31, "000323_08_A.bin", Some(vec![])),
        (0x32, "000325_08_A.bin", None),
        (0x01, "000327_08_A.bin", Some(vec![])),
        (0x1f, "000329_08_A.bin", Some(vec![])),
        (0x31, "000331_08_A.bin", Some(vec![])),
        (0x32, "000333_08_A.bin", None),
        (0x63, "000343_08_A.bin", Some(vec![])),
        // 2nd pass (c12 seq 345-379).
        (0x19, "000345_08_A.bin", Some(vec![])),
        (0x17, "000347_08_A.bin", Some(SERIAL_J314C.to_vec())),
        (0x15, "000349_08_A.bin", Some(KX_SESSION.to_vec())),
        (0x16, "000351_08_A.bin", None),
        (0x42, "000353_08_A.bin", Some(vec![])),
        (0x18, "000355_08_A.bin", None),
        (0x5f, "000357_08_A.bin", Some(PATCH_INPUT.to_vec())),
        (0x5d, "000362_08_A.bin", Some(PARAMS_INPUT.to_vec())),
        (0x5c, "000365_08_A.bin", Some(PARAMS_INPUT.to_vec())),
        (0x6a, "000367_08_A.bin", Some(vec![])),
        (0x6f, "000369_08_A.bin", Some(vec![])),
        (0x31, "000371_08_A.bin", Some(vec![])),
        (0x32, "000373_08_A.bin", None),
        (0x01, "000375_08_A.bin", Some(vec![])),
        (0x1f, "000377_08_A.bin", Some(vec![])),
        (0x63, "000379_08_A.bin", Some(vec![])),
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
    // The whitelist lengths (and fixed payloads) are those of the templates; 0x5b: the total of its 1st fragment.
    for s in RELAY_SEQUENCE {
        let Some(t) = templates().into_iter().find(|t| t.0 == s.op) else {
            assert!(s.frag_in);
            let a = ool("000335_08_A.bin").unwrap();
            assert_eq!(u32::from_le_bytes([a[4], a[5], a[6], a[7]]) as usize, s.cmd_len);
            continue;
        };
        let a = ool(t.1).unwrap();
        assert_eq!(a[0x18] as usize, s.cmd_len, "{:#04x}", s.op);
        if let Some(f) = s.cmd_fixed {
            assert_eq!(&a[OOL_HDR..OOL_HDR + s.cmd_len], f, "{:#04x}", s.op);
        }
    }
}

/// The four A8 the kernel writes for 0x5b (header + chunk, rest zero) = the macOS A8 of c12 (000341 has stale bytes
/// after its payload in the capture: compared up to the payload, ours is zero after).
#[test]
fn calibration_fragments_equal_macos_a8() {
    let Some(blob) = calib() else { return eprintln!("c12 absent: skipped") };
    let s = &RELAY_SEQUENCE[15];
    assert!(check_cmd(15, LIMIT_CALIB, 0x5b, &blob).is_ok());
    assert!(check_cmd(15, LIMIT_PARAMS, 0x5b, &blob).is_err());
    assert_eq!(cmd_frags(s, blob.len()), 4);
    for (k, f) in sbiod::CALIB_C12_FILES.iter().enumerate() {
        let t = ool(f).unwrap();
        let (h, r) = fragment_header(0x5b, blob.len(), k).unwrap();
        let mut a = vec![0u8; SBIO_OOL_SIZE];
        a[..OOL_HDR].copy_from_slice(&h);
        a[OOL_HDR..OOL_HDR + r.len()].copy_from_slice(&blob[r.clone()]);
        let n = OOL_HDR + r.len();
        assert_eq!(&a[..n], &t[..n], "{f}");
        assert!(a[n..].iter().all(|&b| b == 0));
        if k < 3 {
            assert_eq!(a, t, "{f}");
        }
    }
    // Serials inside the blob: the sensor one (0x17) at 91, the module one (0x32 answer, c12 000326) at 889.
    assert_eq!(&blob[91..107], &SERIAL_J314C);
    let b32 = ool("000326_08_B.bin").unwrap();
    assert_eq!(&blob[889..907], &b32[OOL_HDR..OOL_HDR + 0x12]);
    // A modified blob is refused (sha256 here, CRC-32 by the kernel gate).
    let mut bad = blob.clone();
    bad[1000] ^= 1;
    assert!(check_calib(&bad).is_err());
    assert!(check_cmd(15, LIMIT_CALIB, 0x5b, &bad).is_err());
}

/// c12 SEP replies, in the order of RELAY_SEQUENCE: (op, list of B8 fragments).
fn c12_replies() -> Option<Vec<(u8, Vec<Vec<u8>>)>> {
    let f = |n: &str| ool(n);
    Some(vec![
        (0x17, vec![f("000304_08_B.bin")?]),
        (0x15, vec![f("000306_08_B.bin")?]),
        (0x16, vec![f("000308_08_B.bin")?]),
        (0x42, vec![f("000310_08_B.bin")?]),
        (0x18, vec![f("000312_08_B.bin")?]),
        (0x5f, vec![f("000314_08_B.bin")?, f("000316_08_B.bin")?]),
        (0x5d, vec![f("000318_08_B.bin")?]),
        (0x5c, vec![f("000320_08_B.bin")?]),
        (0x6a, vec![f("000322_08_B.bin")?]),
        (0x31, vec![f("000324_08_B.bin")?]),
        (0x32, vec![f("000326_08_B.bin")?]),
        (0x01, vec![f("000328_08_B.bin")?]),
        (0x1f, vec![f("000330_08_B.bin")?]),
        (0x31, vec![f("000332_08_B.bin")?]),
        (0x32, vec![f("000334_08_B.bin")?]),
        (0x5b, vec![f("000342_08_B.bin")?]),
        (0x63, vec![f("000344_08_B.bin")?]),
        // 2nd pass (c12 seq 346-380). The 2nd 0x63 has no file of its own: B8 unchanged (same sha aa957732 as
        // 000380, sep.log L481 `changed=none`).
        (0x19, vec![f("000346_08_B.bin")?]),
        (0x17, vec![f("000348_08_B.bin")?]),
        (0x15, vec![f("000350_08_B.bin")?]),
        (0x16, vec![f("000352_08_B.bin")?]),
        (0x42, vec![f("000354_08_B.bin")?]),
        (0x18, vec![f("000356_08_B.bin")?]),
        (0x5f, vec![f("000358_08_B.bin")?, f("000360_08_B.bin")?]),
        (0x5d, vec![f("000364_08_B.bin")?]),
        (0x5c, vec![f("000366_08_B.bin")?]),
        (0x6a, vec![f("000368_08_B.bin")?]),
        (0x6f, vec![f("000370_08_B.bin")?]),
        (0x31, vec![f("000372_08_B.bin")?]),
        (0x32, vec![f("000374_08_B.bin")?]),
        (0x01, vec![f("000376_08_B.bin")?]),
        (0x1f, vec![f("000378_08_B.bin")?]),
        (0x63, vec![f("000380_08_B.bin")?]),
        (0x63, vec![f("000380_08_B.bin")?]),
    ])
}

/// Kernel-side reassembly (same calls as `on_relay`).
fn reassemble(op: u8, frags: &[Vec<u8>]) -> Vec<u8> {
    reassemble_step(RELAY_SEQUENCE.iter().position(|s| s.op == op).unwrap(), frags)
}

fn reassemble_step(i: usize, frags: &[Vec<u8>]) -> Vec<u8> {
    let step = &RELAY_SEQUENCE[i];
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
    let lens: Vec<usize> = r.iter().enumerate().map(|(i, (_, f))| reassemble_step(i, f).len()).collect();
    assert_eq!(
        lens,
        [
            0, 0x28, 0, 0x40, 0, 0x568e, 0x37, 0x37, 0, 0x40, 0x12, 0, 2, 0x40, 0x12, 0, 0x1c, // 1st pass
            0, 0, 0x28, 0, 0x40, 0, PATCH2_LEN, 0x37, 0x37, 0x44, 0x4d, 0x40, 0x12, 0, 2, 0x1c, 0x1c, // 0x19 + 2nd pass
        ]
    );
    assert_eq!(reassemble_step(16, &r[16].1), CAL_INFO_REF);
    assert_eq!(reassemble_step(32, &r[32].1), CAL_INFO_REF);
    // The 2nd-pass module serial is the 1st-pass one; the 2nd patch starts with its length - 2 (`cc 70`).
    assert_eq!(reassemble_step(29, &r[29].1), reassemble_step(10, &r[10].1));
    let p2 = reassemble_step(23, &r[23].1);
    check_patch(&p2).unwrap();
    assert_eq!(&p2[..3], &[0xcc, 0x70, 0x3a]);
    // The 1st-pass 0x6a step refuses the 2nd-pass 68-byte answer, and vice versa.
    assert!(check_fragment(&RELAY_SEQUENCE[8], &r[26].1[0][..OOL_HDR], 0, None, 0).is_err());
    assert!(check_fragment(&RELAY_SEQUENCE[26], &r[8].1[0][..OOL_HDR], 0, None, 0).is_err());
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
    limit: usize,
    sent: Vec<(u8, Vec<u8>)>,
    /// Replace the reply of step `i` (fault injection).
    patch: Option<(usize, Vec<u8>)>,
}

impl Sep for FakeSep {
    fn cmd(&mut self, op: u8, payload: &[u8]) -> Result<Vec<u8>, String> {
        // Same gate as the kernel (Halted there; here an error the daemon reports as a stop).
        check_cmd(self.next, self.limit, op, payload).map_err(|e| e.to_string())?;
        let i = self.next;
        self.next += 1;
        self.sent.push((op, payload.to_vec()));
        if let Some((j, r)) = &self.patch {
            if *j == i {
                return Ok(r.clone());
            }
        }
        Ok(reassemble_step(i, &self.replies[i].1))
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
    /// Ready pin: high from this time on, until a status read (None = low).
    irq_at: Option<u64>,
    /// Body (9 bytes) of the next status after a 0x55 frame.
    st_param: Option<[u8; 9]>,
    /// A status was read while the sensor was still processing (before its IRQ).
    early_read: bool,
    /// Fault injection: status body returned after the n-th 0x55 frame (1-based).
    bad_status_at: Option<usize>,
    n_param: usize,
    /// Fault injection: corrupt the 0x75 answer CRC.
    bad_crc: bool,
    /// Powered off (by `power(false)`); `false` at start (the caller powered it on).
    off: bool,
    /// `frames.len()` at each power-on.
    power_on_at: Vec<usize>,
    power_offs: usize,
    /// Fault injection: 1st status after power-on not the macOS one; no ready pin after power-on.
    bad_wake: bool,
    no_wake_irq: bool,
    /// Patch blocks received; fault injection: refuse block n (1-based).
    blocks: usize,
    refuse_block: Option<usize>,
}

fn relay_answer(op: u8, n: usize, total: usize) -> Vec<u8> {
    let mut r = vec![0x80, op | 0x80, 0, total as u8, 0, 0, 0, 0, op];
    r.extend((0..n).map(|i| (i as u8) ^ op));
    r.extend_from_slice(&[0xee, 0xee]);
    r
}

/// Answer of C18-C20 shape to a 0x31 frame: `80 d4 00 4b 00000000 75` + 64 bytes + CRC16 LE.
fn serial_answer(bad: bool) -> Vec<u8> {
    let mut r = vec![0x80, 0xd4, 0, 0x4b, 0, 0, 0, 0, 0x75];
    r.extend((0..64).map(|i| (i as u8) ^ 0x75));
    let c = crc16_arc(&r) ^ u16::from(bad);
    r.extend_from_slice(&c.to_le_bytes());
    r
}

impl Sensor for FakeSensor {
    fn power(&mut self, on: bool) -> Result<(), String> {
        if on {
            self.off = false;
            self.power_on_at.push(self.frames.len());
            // C17: ready pin ~8 ms after power-on; C18-C20: first status `ST_POWER_ON`.
            self.irq_at = if self.no_wake_irq { None } else { Some(self.t + 8) };
            self.st_param = Some(if self.bad_wake { [0; 9] } else { ST_POWER_ON });
        } else {
            // Everything the sensor held is lost (patch, pending answer, prelude).
            self.off = true;
            self.power_offs += 1;
            (self.pending, self.armed, self.prelude, self.mid_read, self.block) = (None, 0, false, false, None);
            (self.irq_at, self.st_param) = (None, None);
        }
        Ok(())
    }
    fn xfer(&mut self, tx: &[u8], rx: bool) -> Result<Vec<u8>, String> {
        if self.off {
            return Err("capteur éteint".into());
        }
        self.frames.push(tx.to_vec());
        let mut out = vec![0u8; if rx { tx.len() } else { 0 }];
        if self.armed > 0 && rx && tx.iter().all(|&b| b == 0) && tx.len() == self.armed {
            out.copy_from_slice(&self.pending.take().unwrap());
            self.armed = 0;
            return Ok(out);
        }
        if self.prelude && tx.len() > 7 && tx[0] != 0x80 {
            self.block = Some(tx.to_vec());
            self.blocks += 1;
            self.t_block = self.t;
            self.prelude = false;
            self.irq_at = Some(self.t + 5);
            return Ok(out);
        }
        match (tx[0], tx[1]) {
            (0x80, 0x10) => {
                if self.irq_at.is_some_and(|at| self.t < at) {
                    self.early_read = true;
                }
                // Like macOS (C17..C20): the block is only accepted if the status was read between prelude and block.
                if self.prelude {
                    self.mid_read = true;
                }
                self.irq_at = None;
                let ok = self.accept && self.mid_read && self.refuse_block != Some(self.blocks);
                let st8 = if self.block.is_some() && ok { 0x29 } else { 0x60 };
                if self.block.is_some() {
                    self.polls_after += 1;
                }
                let n = self.pending.as_ref().map_or(0, Vec::len);
                let mut body = [0x80, 0x20, 0, 0x10, 0, 0, 0, if n > 0 { 7 } else { 0 }, st8, 0, 0, 0, n as u8, (n >> 8) as u8, 0, 0];
                if n == 0 && self.block.is_none() {
                    body[12..14].copy_from_slice(&[0x52, 0x33]); // at rest (J5 log): not a length
                }
                if let Some(p) = self.st_param.take() {
                    body[7..16].copy_from_slice(&p);
                }
                out[7..23].copy_from_slice(&body);
            }
            (0x80, 0x78) => {}
            (0x80, 0x70) => {
                self.pending = Some(IDENTITY_J314C.to_vec());
                self.st_param = Some(ST_IDENTITY_READY);
                self.irq_at = Some(self.t);
            }
            (0x80, 0x13) => self.armed = u32::from_le_bytes([tx[7], tx[8], tx[9], tx[10]]) as usize,
            (0x80, 0x72) if tx.len() == 0x2f => self.pending = Some(relay_answer(0x72, 40, 0x33)),
            (0x80, 0x73) if tx.len() == 0x47 => self.pending = Some(relay_answer(0x73, 64, 0x4b)),
            (0x80, 0x60) if tx.len() == 7 => {
                self.prelude = true;
                self.irq_at = Some(self.t);
            }
            (0x80, 0x55) => {
                // Only frames of the C19 shape: total byte = length, CRC16 LE of header + blob.
                let n = tx.len();
                if tx[2] != 0 || tx[3] as usize != n || tx[4..7] != [0, 0, 0] || crc16_arc(&tx[..n - 2]).to_le_bytes() != tx[n - 2..] {
                    return Err(format!("trame 0x55 refusée {:02x?}", &tx[..8]));
                }
                self.n_param += 1;
                let mut st = match n {
                    // 0x5d / 0x5c, and the 2nd-pass 0x6a (0x4d) / 0x6f (0x56): status only (C18-C20).
                    0x40 | 0x4d | 0x56 => ST_AFTER_PARAMS,
                    0x49 => {
                        self.pending = Some(serial_answer(self.bad_crc));
                        ST_SERIAL_READY
                    }
                    _ => return Err(format!("trame 0x55 de {n:#x} o inattendue")),
                };
                if self.bad_status_at == Some(self.n_param) {
                    st = [0; 9];
                }
                self.st_param = Some(st);
                self.irq_at = Some(self.t + 2);
            }
            _ => return Err(format!("trame inattendue {:02x?}", &tx[..tx.len().min(8)])),
        }
        Ok(out)
    }
    fn ready(&mut self) -> Option<bool> {
        Some(self.irq_at.is_some_and(|at| self.t >= at))
    }
    fn sleep_ms(&mut self, ms: u64) {
        self.t += ms;
    }
    fn now_ms(&mut self) -> u64 {
        self.t += 1;
        self.t
    }
}

fn run_with(upto: Upto, limit: usize, s: FakeSensor, patch: Option<(usize, Vec<u8>)>) -> Option<(Verdict, FakeSep, FakeSensor)> {
    let mut sep = FakeSep { replies: c12_replies()?, next: 0, limit, sent: vec![], patch };
    let mut s = s;
    let cal = calib()?;
    let mut log = |l: &str| eprintln!("{l}");
    let v = run(&mut sep, &mut Mesa { s: &mut s, log: &mut log }, upto, Some(&cal));
    Some((v, sep, s))
}

fn run_fake(accept: bool) -> Option<(Verdict, FakeSep, FakeSensor)> {
    run_with(Upto::Patch, LIMIT_PATCH, FakeSensor { accept, ..Default::default() }, None)
}

fn run_calib(s: FakeSensor, patch: Option<(usize, Vec<u8>)>) -> Option<(Verdict, FakeSep, FakeSensor)> {
    run_with(Upto::Calib, LIMIT_CALIB, s, patch)
}

fn ok_sensor() -> FakeSensor {
    FakeSensor { accept: true, ..Default::default() }
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

#[test]
fn j5c_full_run_up_to_0x63() {
    let Some((v, sep, s)) = run_calib(ok_sensor(), None) else { return eprintln!("c12 absent: skipped") };
    assert_eq!(v, Verdict::Calibrated { info_ref: true }, "{v:?}");
    assert!(success(Upto::Calib, &v));
    let ops: Vec<u8> = sep.sent.iter().map(|c| c.0).collect();
    assert_eq!(ops, [0x17, 0x15, 0x16, 0x42, 0x18, 0x5f, 0x5d, 0x5c, 0x6a, 0x31, 0x32, 0x01, 0x1f, 0x31, 0x32, 0x5b, 0x63]);
    assert!(!s.early_read, "état lu avant l'IRQ");
    let r = c12_replies().unwrap();
    // 0x55 frames = 80 55 <total> 000000 + the SEP blob verbatim + CRC (the fake refuses any other shape).
    let p: Vec<&Vec<u8>> = s.frames.iter().filter(|f| f.len() > 2 && f[..2] == [0x80, 0x55]).collect();
    assert_eq!(p.len(), 4);
    for (f, i) in p.iter().zip([6usize, 7, 9, 13]) {
        assert_eq!(&f[7..f.len() - 2], &reassemble_step(i, &r[i].1)[..]);
    }
    assert_eq!(p.iter().map(|f| f[3]).collect::<Vec<_>>(), [0x40, 0x40, 0x49, 0x49]);
    // The 0x75 answers (64 bytes @ 9) go to 0x32 verbatim; 0x5b = the captured blob.
    assert_eq!(sep.sent[10].1, serial_answer(false)[9..73]);
    assert_eq!(sep.sent[14].1, serial_answer(false)[9..73]);
    assert_eq!(sep.sent[15].1, calib().unwrap());
    // After the loaded-status read: per frame ONE status read (after the IRQ), plus 0x13 + read for 0x31; nothing
    // after the 2nd 0x75 answer.
    let i = s.frames.iter().position(|f| f.len() > 2 && f[..2] == [0x80, 0x55]).unwrap();
    let kinds: Vec<String> = s.frames[i..]
        .iter()
        .map(|f| match (f[0], f.get(1)) {
            (0x80, Some(0x55)) => format!("55/{:x}", f.len()),
            (0x80, Some(0x10)) => "st".into(),
            (0x80, Some(0x13)) => "13".into(),
            _ => format!("rd/{:x}", f.len()),
        })
        .collect();
    assert_eq!(kinds, ["55/40", "st", "55/40", "st", "55/49", "st", "13", "rd/4b", "55/49", "st", "13", "rd/4b"]);
}

#[test]
fn j5c_params_level_stops_before_calibration() {
    let Some((v, sep, _)) = run_with(Upto::Params, LIMIT_PARAMS, ok_sensor(), None) else { return };
    assert_eq!(v, Verdict::ParamsDone);
    assert_eq!(sep.next, LIMIT_PARAMS);
    assert!(!sep.sent.iter().any(|c| c.0 == 0x5b));
}

#[test]
fn j5c_kernel_level_too_low_stops() {
    // sbiod asked for params but the kernel level is 0: the gate refuses 0x5d (Halted in the kernel).
    let Some((v, sep, _)) = run_with(Upto::Params, LIMIT_PATCH, ok_sensor(), None) else { return };
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x5d")), "{v:?}");
    assert_eq!(sep.next, LIMIT_PATCH);
}

#[test]
fn j5c_fail_closed() {
    let Some(_) = calib() else { return };
    // Status after 0x5d not the macOS one (all zero, as sbio8/9 under m1n1): stop before 0x5c.
    let (v, sep, _) = run_calib(FakeSensor { bad_status_at: Some(1), ..ok_sensor() }, None).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x5d") && e.contains("macOS")), "{v:?}");
    assert_eq!(sep.next, 7);
    // Bad CRC of the 0x75 answer: 0x32 never sent.
    let (v, sep, _) = run_calib(FakeSensor { bad_crc: true, ..ok_sensor() }, None).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("CRC")), "{v:?}");
    assert_eq!(sep.next, 10);
    // 0x5d blob of another length.
    let (v, sep, _) = run_calib(ok_sensor(), Some((6, vec![0; 0x36]))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x5d")), "{v:?}");
    assert_eq!(sep.next, 7);
    // Module serial (0x32) not the one of the calibration blob: stop before 0x01 (so before 0x5b).
    let (v, sep, _) = run_calib(ok_sensor(), Some((10, b"XXXXXXXXXXXXXXXXXX".to_vec()))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("889")), "{v:?}");
    assert_eq!(sep.next, 11);
    // 0x1f answer not 05 05.
    let (v, sep, _) = run_calib(ok_sensor(), Some((12, vec![5, 6]))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x1f")), "{v:?}");
    assert_eq!(sep.next, 13);
    // 0x63 different from macOS: reported, not a success, nothing after.
    let (v, sep, _) = run_calib(ok_sensor(), Some((16, vec![0; 0x1c]))).unwrap();
    assert_eq!(v, Verdict::Calibrated { info_ref: false });
    assert!(!success(Upto::Calib, &v));
    assert_eq!(sep.next, 17);
    // Patch refused: nothing after 0x5f.
    let (v, sep, _) = run_calib(FakeSensor { accept: false, ..Default::default() }, None).unwrap();
    assert_eq!(v, Verdict::Refused { st8: Some(0x60) });
    assert_eq!(sep.next, LIMIT_PATCH);
}

#[test]
fn j5c_wrong_calibration_file_sends_nothing() {
    let Some(mut cal) = calib() else { return };
    cal[5] ^= 1;
    let mut sep = FakeSep { replies: c12_replies().unwrap(), next: 0, limit: LIMIT_CALIB, sent: vec![], patch: None };
    let mut s = ok_sensor();
    let mut log = |l: &str| eprintln!("{l}");
    let v = run(&mut sep, &mut Mesa { s: &mut s, log: &mut log }, Upto::Calib, Some(&cal));
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("sha256")), "{v:?}");
    assert!(sep.sent.is_empty() && s.frames.is_empty());
    let v = run(&mut sep, &mut Mesa { s: &mut s, log: &mut log }, Upto::Calib, None);
    assert!(matches!(v, Verdict::Stopped(_)));
    assert!(sep.sent.is_empty());
}

fn run_pass2(s: FakeSensor, patch: Option<(usize, Vec<u8>)>) -> Option<(Verdict, FakeSep, FakeSensor)> {
    run_with(Upto::Pass2, LIMIT_PASS2, s, patch)
}

fn kind(f: &[u8]) -> String {
    match (f[0], f.get(1)) {
        (0x80, Some(0x55)) => format!("55/{:x}", f.len()),
        (0x80, Some(0x10)) => "st".into(),
        (0x80, Some(0x13)) => "13".into(),
        (0x80, Some(0x60)) => "60".into(),
        (0x80, Some(&op)) if f.len() == 7 => format!("{op:02x}"),
        (0x80, Some(&op)) => format!("{op:02x}/{:x}", f.len()),
        _ => format!("rd/{:x}", f.len()),
    }
}

#[test]
fn pass2_full_run_to_the_macos_rest_state() {
    let Some((v, sep, s)) = run_pass2(ok_sensor(), None) else { return eprintln!("c12 absent: skipped") };
    assert_eq!(v, Verdict::Pass2Done { info_ref: true }, "{v:?}");
    assert!(success(Upto::Pass2, &v));
    // SEP side: exactly the macOS order 0x17 .. 0x63 (1st pass), 0x19, 2nd pass .. 0x63 ×2.
    let ops: Vec<u8> = sep.sent.iter().map(|c| c.0).collect();
    assert_eq!(ops, sep_proto::daemon::INIT_SEQUENCE[1..35]);
    assert_eq!(sep.next, LIMIT_PASS2);
    assert_eq!(sep.sent[18].1, SERIAL_J314C);
    assert!(!s.early_read, "état lu avant l'IRQ");
    // One power cycle, right after the 1st-pass 0x63 (no SPI between the last 0x75 answer and the power-off).
    assert_eq!((s.power_offs, s.power_on_at.len()), (1, 1));
    let i = s.power_on_at[0];
    assert_eq!(kind(&s.frames[i - 1]), "rd/4b");
    // Sensor side of the 2nd pass = the macOS order (C17 timeline, C18-C20 contents): two statuses, (0x19 to the
    // SEP), identity WITHOUT 0x78, the relays, prelude / status / block / status, the five 0x55 frames.
    let k: Vec<String> = s.frames[i..].iter().map(|f| kind(f)).collect();
    assert_eq!(
        k,
        [
            "st", "st", "70", "st", "13", "rd/1b", "st", // wake
            "72/2f", "st", "13", "rd/33", "73/47", "st", "13", "rd/4b", // key exchange, counter
            "st", "60", "st", "rd/70ce", "st", // patch n°2
            "55/40", "st", "55/40", "st", "55/4d", "st", "55/56", "st", "55/49", "st", "13", "rd/4b", // params
        ]
    );
    let r = c12_replies().unwrap();
    // The 0x55 frames carry the 2nd-pass SEP blobs verbatim; the block is the 2nd patch.
    let p: Vec<&Vec<u8>> = s.frames[i..].iter().filter(|f| f.len() > 2 && f[..2] == [0x80, 0x55]).collect();
    for (f, j) in p.iter().zip([24usize, 25, 26, 27, 28]) {
        assert_eq!(&f[7..f.len() - 2], &reassemble_step(j, &r[j].1)[..]);
    }
    assert!(s.frames[i..].iter().any(|f| *f == reassemble_step(23, &r[23].1)));
    // 0x32 of the 2nd pass gets the 0x75 answer verbatim.
    assert_eq!(sep.sent[29].1, serial_answer(false)[9..73]);
}

#[test]
fn pass2_kernel_level_too_low_stops_at_0x19() {
    let Some((v, sep, s)) = run_with(Upto::Pass2, LIMIT_CALIB, ok_sensor(), None) else { return };
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x19")), "{v:?}");
    assert_eq!(sep.next, LIMIT_CALIB);
    // The sensor-side wake was done (no SEP word), nothing after.
    let k: Vec<String> = s.frames[s.power_on_at[0]..].iter().map(|f| kind(f)).collect();
    assert_eq!(k, ["st", "st"]);
}

#[test]
fn pass2_fail_closed() {
    let Some(_) = calib() else { return };
    // Calibration level: no power cycle, nothing after 0x63.
    let (v, sep, s) = run_calib(ok_sensor(), None).unwrap();
    assert_eq!((v, sep.next, s.power_offs), (Verdict::Calibrated { info_ref: true }, LIMIT_CALIB, 0));
    // 1st-pass 0x63 not the macOS one: no 2nd pass at all.
    let (v, sep, s) = run_pass2(ok_sensor(), Some((16, vec![0; 0x1c]))).unwrap();
    assert_eq!((v, sep.next, s.power_offs), (Verdict::Calibrated { info_ref: false }, LIMIT_CALIB, 0));
    // Status after power-on not the macOS one: stop before 0x19.
    let (v, sep, _) = run_pass2(FakeSensor { bad_wake: true, ..ok_sensor() }, None).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("rallumage (1)")), "{v:?}");
    assert_eq!(sep.next, LIMIT_CALIB);
    // No ready pin after power-on: no read, stop before 0x19.
    let (v, sep, s) = run_pass2(FakeSensor { no_wake_irq: true, ..ok_sensor() }, None).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("rallumage")), "{v:?}");
    assert_eq!(sep.next, LIMIT_CALIB);
    assert_eq!(s.frames.len(), s.power_on_at[0], "aucune SPI sans l'IRQ");
    // 0x19 answered with data: stop before the identity.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((17, vec![0]))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x19")), "{v:?}");
    assert_eq!(sep.next, 18);
    // 2nd patch of another length (the 1st-pass size): not pushed, nothing after 0x5f.
    let r = c12_replies().unwrap();
    let (v, sep, s) = run_pass2(ok_sensor(), Some((23, reassemble_step(5, &r[5].1)))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("patch n°2")), "{v:?}");
    assert_eq!(sep.next, 24);
    assert!(!s.frames[s.power_on_at[0]..].iter().any(|f| f[..] == [0x80, 0x60, 0, 7, 0, 0, 0]));
    // 2nd patch refused by the sensor (1st one loaded): nothing after 0x5f.
    let (v, sep, s) = run_pass2(FakeSensor { refuse_block: Some(2), ..ok_sensor() }, None).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("patch n°2 non chargé")), "{v:?}");
    assert_eq!((sep.next, s.blocks), (24, 2));
    assert!(!s.frames.iter().skip(s.power_on_at[0]).any(|f| f.len() > 2 && f[..2] == [0x80, 0x55]));
    // Status after the 1st 0x55 frame of the 2nd pass not the macOS one (4 frames in the 1st pass): stop before 0x5c.
    let (v, sep, _) = run_pass2(FakeSensor { bad_status_at: Some(5), ..ok_sensor() }, None).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x5d (2e passe)") && e.contains("macOS")), "{v:?}");
    assert_eq!(sep.next, 25);
    // 0x6a of the 2nd pass with the 1st-pass (empty) answer: stop before any frame of it.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((26, vec![]))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x6a")), "{v:?}");
    assert_eq!(sep.next, 27);
    // 0x6f blob of another length.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((27, vec![0; 0x44]))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x6f")), "{v:?}");
    assert_eq!(sep.next, 28);
    // Module serial of the 2nd pass different from the 1st: stop before 0x01.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((29, b"YYYYYYYYYYYYYYYYYY".to_vec()))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("1re passe")), "{v:?}");
    assert_eq!(sep.next, 30);
    // 0x1f not 05 05.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((31, vec![5, 6]))).unwrap();
    assert!(matches!(v, Verdict::Stopped(ref e) if e.contains("0x1f")), "{v:?}");
    assert_eq!(sep.next, 32);
    // 1st 0x63 of the 2nd pass different: reported, the 2nd one is NOT sent.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((32, vec![0; 0x1c]))).unwrap();
    assert_eq!(v, Verdict::Pass2Done { info_ref: false });
    assert!(!success(Upto::Pass2, &v));
    assert_eq!(sep.next, 33);
    // 2nd 0x63 different: reported, not a success.
    let (v, sep, _) = run_pass2(ok_sensor(), Some((33, vec![0; 0x1c]))).unwrap();
    assert_eq!((v, sep.next), (Verdict::Pass2Done { info_ref: false }, LIMIT_PASS2));
}

#[test]
fn pass2_needs_the_calibration_file() {
    let mut sep = FakeSep { replies: vec![], next: 0, limit: LIMIT_PASS2, sent: vec![], patch: None };
    let mut s = ok_sensor();
    let mut log = |l: &str| eprintln!("{l}");
    let v = run(&mut sep, &mut Mesa { s: &mut s, log: &mut log }, Upto::Pass2, None);
    assert!(matches!(v, Verdict::Stopped(_)));
    assert!(sep.sent.is_empty() && s.frames.is_empty());
}

#[test]
fn pass2_patch_is_pushed_like_the_first() {
    let Some((_, _, s)) = run_pass2(ok_sensor(), None) else { return };
    let r = c12_replies().unwrap();
    let p2 = reassemble_step(23, &r[23].1);
    let i = s.frames.iter().position(|f| *f == p2).unwrap();
    assert_eq!(p2.len(), PATCH2_LEN);
    assert_eq!(kind(&s.frames[i - 2]), "60");
    assert_eq!(kind(&s.frames[i - 1]), "st");
    assert_eq!(kind(&s.frames[i + 1]), "st");
    assert_eq!(kind(&s.frames[i + 2]), "55/40");
}
