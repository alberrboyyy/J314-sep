//! sbiod: J5 sensor-init relay, AP = pure byte relay between the SEP (`/dev/sep_sbio` of `sep_native`) and the Mesa
//! sensor (spi2 through spidev, power gpio0 196, ready gpio0 195). Steps, in this order, once each:
//! 1. identity read over SPI → serial (identity[9..25]) → sbio 0x17 (prepareSession) → ack;
//! 2. 0x15 → 40 opaque bytes → SPI frame 0x72 → 51-byte reply → 40 bytes @ 9 → 0x16 → ack;
//! 3. 0x42 → 64 opaque bytes → SPI frame 0x73 → 75-byte reply → 64 bytes @ 9 → 0x18 → ack;
//! 4. 0x5f → patch block (reassembled by the kernel) → SPI prelude `80 60 00 07 00 00 00` then the block in ONE
//!    transfer → wait (≤ 1.5 s) for status byte 1 == 0x29 (loaded). STOP there (no 0x5d/0x5c/0x6a/0x5b).
//!
//! Source of every step: `pending/sep_native_sbio3.sh` .. `sep_native_sbio11.sh` (hardware-proven under m1n1 up to
//! the push; the push itself never loaded the patch under m1n1: FIFO through the tunnel, 2.2 s), `docs/sbio_session.md`
//! (§3b success criterion), `docs/sensor_hw.md`, `driver/linux/mesa_transport.h`. Crypto blobs are never interpreted.
//! The hardware is behind the `Sep` and `Sensor` traits: `main.rs` binds them to the devices, the tests to captures.
pub mod hw;

use sep_proto::sbio_gate::{self, RELAY_SEQUENCE};
use sep_proto::sensor::{self, CMD_IDENTITY, CMD_STATUS, CMD_WAKE, IDENTITY_J314C, PATCH_LOADED, PATCH_PRELUDE};
use std::fmt::Write as _;

/// Pause after every SPI exchange (MESA_GAP_MS of mesa_transport.h, GAP_S of mesa_spi_proxy).
pub const GAP_MS: u64 = 10;
/// Wait for the ready pin after wake / identity (MESA_READY_TIMEOUT_MS), then continue anyway.
pub const READY_TIMEOUT_MS: u64 = 50;
/// Status polls for the pending length of a relay reply (sbio4..11 `spi_relay`: 50 × status + 10 ms).
pub const PENDING_POLLS: usize = 50;
/// Wait for the patch to load after the block (WAIT_LOAD_S of sbio11), polling every 50 ms.
pub const WAIT_LOAD_MS: u64 = 1500;
pub const LOAD_POLL_MS: u64 = 50;
/// Expected pending lengths of the relay replies (VU C19), logged when they differ (the extraction decides).
pub const KX_PENDING: usize = 0x33;
pub const CNT_PENDING: usize = 0x4b;
/// Serial of this machine's sensor (c12 template `000303_08_A.bin` payload, identical in every run since).
pub const SERIAL_J314C: [u8; 16] =
    [0x02, 0x19, 0xc0, 0x5c, 0x0f, 0xd2, 0xaa, 0x34, 0x9a, 0x81, 0xc7, 0x6e, 0x03, 0x02, 0x00, 0xd8];
/// sessionType = 1 (`000305_08_A.bin`) and LoadPatch input (`000313_08_A.bin`).
pub const KX_SESSION: [u8; 4] = [1, 0, 0, 0];
pub const PATCH_INPUT: [u8; 2] = [2, 0];

/// The SEP side: one whitelisted sbio command, its complete (reassembled) reply.
pub trait Sep {
    fn cmd(&mut self, op: u8, payload: &[u8]) -> Result<Vec<u8>, String>;
}

/// The sensor side. `xfer` = one SPI message of one transfer (tx; full duplex read of `tx.len()` if `rx`).
pub trait Sensor {
    fn xfer(&mut self, tx: &[u8], rx: bool) -> Result<Vec<u8>, String>;
    /// Ready / IRQ pin (gpio0 195), None if unavailable.
    fn ready(&mut self) -> Option<bool>;
    fn sleep_ms(&mut self, ms: u64);
    fn now_ms(&mut self) -> u64;
}

pub fn hex(b: &[u8]) -> String {
    b.iter().fold(String::new(), |mut s, x| {
        let _ = write!(s, "{x:02x}");
        s
    })
}

/// `n o : <first 16 bytes>…` for the log (blobs are never interpreted).
pub fn short(b: &[u8]) -> String {
    format!("{} o : {}{}", b.len(), hex(&b[..b.len().min(16)]), if b.len() > 16 { "…" } else { "" })
}

/// Final result of a run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verdict {
    /// Status byte 1 == 0x29 after the block.
    Loaded { t_ms: u64, irq_seen: bool },
    /// Ready pin rose after the block but byte 1 never became 0x29 (sensor finished receiving and refused?).
    Refused { st8: Option<u8> },
    /// Ready pin never rose after the block, byte 1 never 0x29.
    NoIrq { st8: Option<u8> },
    /// Stopped (fail-closed) before or during the push, with the reason.
    Stopped(String),
}

impl Verdict {
    pub fn line(&self) -> String {
        let b = |s: &Option<u8>| s.map_or("?".into(), |v| format!("{v:#04x}"));
        match self {
            Verdict::Loaded { t_ms, irq_seen } => {
                format!("VERDICT : patch chargé (0x29 à t+{t_ms} ms ; IRQ 195 {})", if *irq_seen { "vue" } else { "non vue" })
            }
            Verdict::Refused { st8 } => format!("VERDICT : patch refusé (IRQ 195 montée, octet 1 = {}, jamais 0x29)", b(st8)),
            Verdict::NoIrq { st8 } => format!("VERDICT : IRQ absente (IRQ 195 jamais montée, octet 1 = {}, jamais 0x29)", b(st8)),
            Verdict::Stopped(why) => format!("VERDICT : arrêt (fail-closed) : {why}"),
        }
    }
}

/// Sensor transport of `mesa_transport.h` over the `Sensor` trait.
pub struct Mesa<'a, S: Sensor> {
    pub s: &'a mut S,
    pub log: &'a mut dyn FnMut(&str),
}

impl<S: Sensor> Mesa<'_, S> {
    fn x(&mut self, what: &str, tx: &[u8], rx: bool) -> Result<Vec<u8>, String> {
        let r = self.s.xfer(tx, rx).map_err(|e| format!("SPI {what} : {e}"))?;
        (self.log)(&format!("SPI> {what} {}", short(tx)));
        if rx {
            (self.log)(&format!("SPI< {what} {}", short(&r)));
        }
        self.s.sleep_ms(GAP_MS);
        Ok(r)
    }

    /// Status (0x10 + 16 zeros, 0x17 bytes read); body = bytes 7.. (16 bytes). None if the header is not
    /// `80 20 00 10` (all-zero answers were seen right after the block, journal sbio11).
    pub fn status(&mut self) -> Result<Option<[u8; 16]>, String> {
        let mut tx = [0u8; sensor::STATUS_XFER_LEN];
        tx[..7].copy_from_slice(&CMD_STATUS);
        let r = self.x("état", &tx, true)?;
        let body = r.get(7..23).ok_or("état : réponse courte")?;
        if body[..4] != sensor::STATUS_HEAD {
            return Ok(None);
        }
        let mut b = [0u8; 16];
        b.copy_from_slice(body);
        Ok(Some(b))
    }

    fn pending(st: &Option<[u8; 16]>) -> usize {
        st.map_or(0, |b| b[12] as usize | (b[13] as usize) << 8)
    }

    fn wait_ready(&mut self) {
        let t0 = self.s.now_ms();
        while self.s.now_ms() - t0 < READY_TIMEOUT_MS {
            match self.s.ready() {
                Some(true) | None => return,
                Some(false) => self.s.sleep_ms(1),
            }
        }
        (self.log)("broche « donnée prête » pas montée en 50 ms (repli pauses fixes)");
    }

    /// Read a pending answer of `n` bytes: request 0x13, then `n` bytes full duplex.
    fn read_pending(&mut self, what: &str, n: usize) -> Result<Vec<u8>, String> {
        let n32 = u32::try_from(n).map_err(|_| "longueur en attente hors u32")?;
        self.x(&format!("demande 0x13 ({what})"), &sensor::build_read_request(n32), false)?;
        self.x(&format!("lecture ({what})"), &vec![0u8; n], true)
    }

    /// Identity sequence of mesa_probe.c (wake, status, 0x70, status, 0x13, read 0x1b, status). Fail-closed:
    /// the identity must be the one read under macOS, m1n1 and Linux.
    pub fn identity(&mut self) -> Result<Vec<u8>, String> {
        self.x("réveil 0x78", &CMD_WAKE, false)?;
        self.wait_ready();
        self.status()?;
        self.x("identité 0x70", &CMD_IDENTITY, false)?;
        self.wait_ready();
        let st = self.status()?;
        let n = Self::pending(&st);
        if n != IDENTITY_J314C.len() {
            return Err(format!("identité : le capteur annonce {n} octets (0x1b attendu)"));
        }
        let id = self.read_pending("identité", n)?;
        self.status()?;
        if id != IDENTITY_J314C {
            return Err(format!("identité inattendue {}", hex(&id)));
        }
        Ok(id)
    }

    /// Relay frame `op` carrying `blob`, then the sensor's answer (raw), as `spi_relay` of sbio4..11.
    pub fn relay(&mut self, op: u8, blob: &[u8], want_pending: usize) -> Result<Vec<u8>, String> {
        let mut f = [0u8; 0x100];
        let n = sensor::build_relay_frame(op, blob, &mut f).map_err(|e| e.to_string())?;
        self.x(&format!("trame {op:#04x}"), &f[..n], false)?;
        let mut pending = 0;
        for _ in 0..PENDING_POLLS {
            let st = self.status()?;
            pending = Self::pending(&st);
            if pending != 0 {
                break;
            }
            self.s.sleep_ms(GAP_MS);
        }
        (self.log)(&format!("trame {op:#04x} : réponse en attente {pending:#x} (attendu {want_pending:#x})"));
        if pending == 0 {
            return Err(format!("trame {op:#04x} : aucune réponse annoncée"));
        }
        self.read_pending(&format!("réponse {op:#04x}"), pending)
    }
}

fn extract(resp: &[u8], len: usize, what: &str) -> Result<Vec<u8>, String> {
    let off = sensor::RELAY_RESP_OFF;
    resp.get(off..off + len).map(<[u8]>::to_vec).ok_or_else(|| format!("{what} : réponse capteur {} o, trop courte pour {len} o @ {off}", resp.len()))
}

/// Patch block check before pushing it (sbio6..11 `verify_reassembled_patch`): u16 LE prefix == length - 2.
pub fn check_patch(block: &[u8]) -> Result<(), String> {
    if block.len() < 2 || u16::from_le_bytes([block[0], block[1]]) as usize != (block.len() - 2) & 0xffff {
        return Err(format!("patch : préfixe != longueur-2 ({})", short(block)));
    }
    Ok(())
}

fn sep_cmd(sep: &mut dyn Sep, log: &mut dyn FnMut(&str), op: u8, payload: &[u8]) -> Result<Vec<u8>, String> {
    let name = RELAY_SEQUENCE.iter().find(|s| s.op == op).map_or("?", |s| s.name);
    log(&format!("SEP> {op:#04x} {name} {}", short(payload)));
    let r = sep.cmd(op, payload).map_err(|e| format!("sbio {op:#04x} : {e}"))?;
    log(&format!("SEP< {op:#04x} {name} {}", short(&r)));
    Ok(r)
}

/// Steps 1-3 (SEP + sensor relay) and the patch fetch. Returns the patch block.
pub fn session<S: Sensor>(sep: &mut dyn Sep, m: &mut Mesa<'_, S>) -> Result<Vec<u8>, String> {
    let id = m.identity()?;
    let serial = &id[sensor::SERIAL_RANGE];
    (m.log)(&format!("identité OK, n° de série {}", hex(serial)));
    if serial != SERIAL_J314C {
        return Err("n° de série != gabarit c12 : 0x17 non envoyé".into());
    }
    let r = sep_cmd(sep, m.log, 0x17, serial)?;
    if !r.is_empty() {
        return Err(format!("0x17 : réponse de {} o (0 attendu)", r.len()));
    }
    let kx = sep_cmd(sep, m.log, 0x15, &KX_SESSION)?;
    if kx.len() != 0x28 {
        return Err(format!("0x15 : blob de {} o (40 attendu)", kx.len()));
    }
    let resp = m.relay(sensor::OP_KEY_EXCHANGE, &kx, KX_PENDING)?;
    let back = extract(&resp, 0x28, "0x72")?;
    let r = sep_cmd(sep, m.log, 0x16, &back)?;
    if !r.is_empty() {
        return Err(format!("0x16 : réponse de {} o (0 attendu)", r.len()));
    }
    let cnt = sep_cmd(sep, m.log, 0x42, &[])?;
    if cnt.len() != 0x40 {
        return Err(format!("0x42 : blob de {} o (64 attendu)", cnt.len()));
    }
    let resp = m.relay(sensor::OP_SEQ_COUNTER, &cnt, CNT_PENDING)?;
    let back = extract(&resp, 0x40, "0x73")?;
    let r = sep_cmd(sep, m.log, 0x18, &back)?;
    if !r.is_empty() {
        return Err(format!("0x18 : réponse de {} o (0 attendu)", r.len()));
    }
    let patch = sep_cmd(sep, m.log, 0x5f, &PATCH_INPUT)?;
    check_patch(&patch)?;
    (m.log)(&format!("patch reçu et réassemblé : {:#x} o", patch.len()));
    Ok(patch)
}

/// Step 4: push (prelude, then the block in ONE transfer), then wait for byte 1 == 0x29 (reads only).
pub fn push_patch<S: Sensor>(m: &mut Mesa<'_, S>, block: &[u8]) -> Result<Verdict, String> {
    let before = m.status()?;
    (m.log)(&format!("état avant le push : {}", before.map_or("non reconnu".into(), |b| hex(&b))));
    m.x("prélude 0x60", &PATCH_PRELUDE, false)?;
    let t = m.s.now_ms();
    // Not through `x()`: no gap before the wait starts, and the block is logged by length only.
    m.s.xfer(block, false).map_err(|e| format!("SPI bloc du patch : {e}"))?;
    let dt = m.s.now_ms() - t;
    (m.log)(&format!("SPI> bloc du patch en UN transfert : {} en {dt} ms", short(block)));
    let (t0, mut irq_seen, mut st8) = (m.s.now_ms(), false, None);
    loop {
        let el = m.s.now_ms() - t0;
        let irq = m.s.ready();
        if irq == Some(true) && !irq_seen {
            irq_seen = true;
            (m.log)(&format!("IRQ 195 haute à t+{el} ms"));
        }
        let st = m.status()?;
        (m.log)(&format!("t+{el} ms irq {irq:?} état {}", st.map_or("non reconnu".into(), |b| hex(&b))));
        if let Some(b) = st {
            st8 = Some(b[8]);
            if b[8] == PATCH_LOADED {
                return Ok(Verdict::Loaded { t_ms: el, irq_seen });
            }
        }
        if el >= WAIT_LOAD_MS {
            break;
        }
        m.s.sleep_ms(LOAD_POLL_MS);
    }
    Ok(if irq_seen { Verdict::Refused { st8 } } else { Verdict::NoIrq { st8 } })
}

/// Whole J5 run (the caller powers the sensor on before and off after, in every path).
pub fn run<S: Sensor>(sep: &mut dyn Sep, m: &mut Mesa<'_, S>) -> Verdict {
    match session(sep, m) {
        Ok(p) => push_patch(m, &p).unwrap_or_else(|e| Verdict::Stopped(format!("push : {e}"))),
        Err(e) => Verdict::Stopped(e),
    }
}

/// Number of steps of the kernel whitelist (sanity for the tests: the daemon uses all of them, in order).
pub const STEPS: usize = sbio_gate::RELAY_SEQUENCE.len();
