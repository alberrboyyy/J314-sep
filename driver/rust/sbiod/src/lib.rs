//! sbiod: J5 sensor-init relay, AP = pure byte relay between the SEP (`/dev/sep_sbio` of `sep_native`) and the Mesa
//! sensor (spi2 through spidev, power gpio0 196, ready gpio0 195). Steps, in this order, once each:
//! 1. identity read over SPI → serial (identity[9..25]) → sbio 0x17 (prepareSession) → ack;
//! 2. 0x15 → 40 opaque bytes → SPI frame 0x72 → 51-byte reply → 40 bytes @ 9 → 0x16 → ack;
//! 3. 0x42 → 64 opaque bytes → SPI frame 0x73 → 75-byte reply → 64 bytes @ 9 → 0x18 → ack;
//! 4. 0x5f → patch block (reassembled by the kernel) → SPI prelude `80 60 00 07 00 00 00` then the block in ONE
//!    transfer, with the macOS status read between them → ready pin → status byte 1 == 0x29 (loaded). STOP there
//!    with `Upto::Patch` (default);
//! 5. `Upto::Params` (only if loaded): 0x5d, 0x5c → 55 bytes → SPI frame 0x55 (+ CRC16) → ready pin → ONE status read;
//!    0x6a (empty, no SPI); 0x31 → 64 bytes → frame 0x55 → pin → status (0x4b pending) → 0x75 answer (CRC16) →
//!    64 bytes @ 9 → 0x32 → 18 bytes; 0x01; 0x1f; 0x31/0x32 again (docs/j5_params_protocol.md §1-3);
//! 6. `Upto::Calib`: 0x5b with the captured calibration file (sha256, sensor serial at [91..107], module serial at
//!    [889..907] == the 0x32 answer), fragmented by the kernel; 0x63 → 28 bytes, compared with macOS. STOP (no 0x19).
//!
//! Source of every step: `pending/sep_native_sbio3.sh` .. `sep_native_sbio11.sh` (hardware-proven under m1n1 up to
//! the push; the push itself never loaded the patch under m1n1: FIFO through the tunnel, 2.2 s), `docs/sbio_session.md`
//! (§3b success criterion), `docs/sensor_hw.md`, `driver/linux/mesa_transport.h`. Crypto blobs are never interpreted.
//! The hardware is behind the `Sep` and `Sensor` traits: `main.rs` binds them to the devices, the tests to captures.
pub mod hw;
pub mod sha256;

use sep_proto::gt::OOL_HDR;
use sep_proto::sbio_gate::{self, CALIB_LEN, RELAY_SEQUENCE};
use sep_proto::sensor::{self, CMD_IDENTITY, CMD_STATUS, CMD_WAKE, IDENTITY_J314C, PATCH_LOADED, PATCH_PRELUDE};
use std::fmt::Write as _;

/// Pause after every SPI exchange (MESA_GAP_MS of mesa_transport.h, GAP_S of mesa_spi_proxy).
pub const GAP_MS: u64 = 10;
/// Wait for the ready pin after wake / identity (MESA_READY_TIMEOUT_MS), then continue anyway.
pub const READY_TIMEOUT_MS: u64 = 50;
/// Status polls for the pending length of a relay reply (sbio4..11 `spi_relay`: 50 × status + 10 ms).
pub const PENDING_POLLS: usize = 50;
/// Wait for the ready pin after the block, with NO SPI meanwhile (macOS: 38-55 ms).
pub const WAIT_LOAD_IRQ_MS: u64 = 300;
/// Wait for the ready pin right after the prelude (macOS: ~0.1 ms).
pub const PRELUDE_IRQ_MS: u64 = 50;
/// Diagnostic read when the first post-load status is not 0x29.
pub const LATE_READ_MS: u64 = 500;
/// Expected pending lengths of the relay replies (VU C19), logged when they differ (the extraction decides).
pub const KX_PENDING: usize = 0x33;
pub const CNT_PENDING: usize = 0x4b;
/// Before each 0x55 frame the ready pin must be low (status of the previous step read) within this delay.
pub const PIN_LOW_MS: u64 = 20;
/// Ready pin after a 0x55 frame (macOS C17: 0.3-9.6 ms).
pub const PARAM_IRQ_MS: u64 = 200;
/// 0x5d / 0x5c payload (c12 `000317/000319_08_A.bin`, 9/9 boots).
pub const PARAMS_INPUT: [u8; 4] = [0, 0, 0, 0];
/// 0x1f answer, 9/9 boots (c12 `000330_08_B.bin`).
pub const MATCH_POLICY_REF: [u8; 2] = [5, 5];
/// 0x63 answer after the calibration, 9/9 boots (c12 `000344_08_B.bin`).
pub const CAL_INFO_REF: [u8; 0x1c] = [
    0x03, 0, 0, 0, 0x00, 0xac, 0x60, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0x09, 0, 0, 0, 0x03, 0, 0, 0, 0x03, 0, 0, 0,
];
/// Calibration blob (c12 `000335/337/339/341_08_A.bin` payloads, 9/9 boots): sha256, where it holds the sensor serial
/// (identity [9..25]) and the module serial (0x32 answer). Found by byte search, structure not decoded.
pub const CALIB_SHA256: &str = "d5a6117dc8b5482320ab4d86c94148f190a7b08530c6235735636b9abd23ddda";
pub const CALIB_SERIAL_AT: usize = 91;
pub const CALIB_MODULE_AT: usize = 889;
pub const MODULE_SERIAL_LEN: usize = 0x12;
/// c12 A8 files of the 0x5b fragments, in order.
pub const CALIB_C12_FILES: [&str; 4] = ["000335_08_A.bin", "000337_08_A.bin", "000339_08_A.bin", "000341_08_A.bin"];
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

/// How far a run goes (the kernel level `allow_sbio_params` must allow it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Upto {
    /// Up to the patch (J5 v2).
    Patch,
    /// Then 0x5d .. second 0x32 (kernel level 1).
    Params,
    /// Then 0x5b + 0x63 (kernel level 2), with the calibration file.
    Calib,
}

/// Final result of a run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Verdict {
    /// `Upto::Params`: every step of 0x5d .. 0x32 passed its check.
    ParamsDone,
    /// `Upto::Calib`: 0x5b acked; `info_ref` = the 0x63 answer is the macOS one.
    Calibrated { info_ref: bool },
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
            Verdict::ParamsDone => "VERDICT : patch chargé + paramètres 0x5d/0x5c/0x6a + n° de série module (0x31/0x32 ×2) + 0x01/0x1f appliqués, états = macOS".into(),
            Verdict::Calibrated { info_ref: true } => {
                "VERDICT : capteur initialisé et calibré (1re passe ; 0x5b acquitté, 0x63 = référence macOS)".into()
            }
            Verdict::Calibrated { info_ref: false } => {
                "VERDICT : 0x5b acquitté mais 0x63 ≠ référence macOS (calibration douteuse ; rien envoyé après)".into()
            }
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
        let r = self.status_xfer()?;
        self.s.sleep_ms(GAP_MS);
        Self::status_body(&r)
    }

    /// Status read without the GAP_MS pause (patch push timing).
    pub fn status_raw(&mut self) -> Result<Option<[u8; 16]>, String> {
        let r = self.status_xfer()?;
        Self::status_body(&r)
    }

    fn status_xfer(&mut self) -> Result<Vec<u8>, String> {
        let mut tx = [0u8; sensor::STATUS_XFER_LEN];
        tx[..7].copy_from_slice(&CMD_STATUS);
        let r = self.s.xfer(&tx, true).map_err(|e| format!("SPI état : {e}"))?;
        (self.log)(&format!("SPI> état {}", short(&tx)));
        (self.log)(&format!("SPI< état {}", short(&r)));
        Ok(r)
    }

    fn status_body(r: &[u8]) -> Result<Option<[u8; 16]>, String> {
        let body = r.get(7..23).ok_or("état : réponse courte")?;
        if body[..4] != sensor::STATUS_HEAD {
            return Ok(None);
        }
        let mut b = [0u8; 16];
        b.copy_from_slice(body);
        Ok(Some(b))
    }

    /// Length of the pending answer: bytes 12-13 of the body, ONLY when the state byte (body[7]) is 0x07 (at rest those
    /// bytes read `52 33`, docs/j5_params_protocol.md §3).
    fn pending(st: &Option<[u8; 16]>) -> usize {
        st.filter(|b| b[7] == sensor::ST_ANSWER_READY).map_or(0, |b| b[12] as usize | (b[13] as usize) << 8)
    }

    /// Wait until the ready pin reads `level` (1 ms polling), at most `ms`. Returns the last reading.
    fn wait_pin(&mut self, level: bool, ms: u64) -> Option<bool> {
        let t0 = self.s.now_ms();
        loop {
            let p = self.s.ready();
            if p.is_none() || p == Some(level) || self.s.now_ms() - t0 >= ms {
                return p;
            }
            self.s.sleep_ms(1);
        }
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
    pub fn read_pending(&mut self, what: &str, n: usize) -> Result<Vec<u8>, String> {
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

impl<S: Sensor> Mesa<'_, S> {
    /// One 0x55 frame as macOS (C17 `spi2_gpio_timeline.py --params`): ready pin low first (previous status read),
    /// the frame alone (no pause), wait for the ready pin, then ONE status read, which must be `want` exactly.
    pub fn param_frame(&mut self, what: &str, blob: &[u8], want: &[u8; 9]) -> Result<[u8; 16], String> {
        let low = self.wait_pin(false, PIN_LOW_MS);
        if low != Some(false) {
            return Err(format!("{what} : IRQ 195 {} avant la trame (état précédent non acquitté) : trame non envoyée", pin(low)));
        }
        let mut f = [0u8; 0x100];
        let n = sensor::build_param_frame(blob, &mut f).map_err(|e| format!("{what} : {e}"))?;
        self.s.xfer(&f[..n], false).map_err(|e| format!("SPI trame 0x55 ({what}) : {e}"))?;
        (self.log)(&format!("SPI> trame 0x55 ({what}) {} (CRC {})", short(&f[..n]), hex(&f[n - 2..n])));
        let t = self.s.now_ms();
        let up = self.wait_pin(true, PARAM_IRQ_MS);
        (self.log)(&format!("IRQ 195 après la trame ({what}) : {} (t+{} ms)", pin(up), self.s.now_ms() - t));
        if up != Some(true) {
            return Err(format!("{what} : IRQ 195 jamais montée en {PARAM_IRQ_MS} ms après la trame (aucune lecture faite)"));
        }
        let st = self.status_raw()?.ok_or_else(|| format!("{what} : état non reconnu (en-tête ≠ 80 20 00 10)"))?;
        (self.log)(&format!("état après la trame ({what}) : {}", hex(&st)));
        if st[7..16] != want[..] {
            return Err(format!("{what} : état {} ≠ macOS {}", hex(&st[7..16]), hex(want)));
        }
        self.s.sleep_ms(GAP_MS);
        Ok(st)
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

/// Checks of the calibration file that need no hardware: length, sha256, head (the kernel checks length, head and
/// CRC-32 again).
pub fn check_calib(blob: &[u8]) -> Result<(), String> {
    if blob.len() != CALIB_LEN {
        return Err(format!("calibration : {} o ({CALIB_LEN} attendus)", blob.len()));
    }
    let h = hex(&sha256::sha256(blob));
    if h != CALIB_SHA256 {
        return Err(format!("calibration : sha256 {h} ≠ {CALIB_SHA256} (blob capturé c12)"));
    }
    if blob[CALIB_SERIAL_AT..CALIB_SERIAL_AT + sensor::SERIAL_LEN] != SERIAL_J314C {
        return Err("calibration : n° de série capteur absent à l'offset 91".into());
    }
    Ok(())
}

/// The calibration blob from the four c12 A8 files of 0x5b (each gt header checked: version 1, op 0x5b, total
/// 0xfc99, offsets contiguous), then `check_calib`.
pub fn calib_from_c12(dir: &std::path::Path) -> Result<Vec<u8>, String> {
    let mut blob = Vec::with_capacity(CALIB_LEN);
    for f in CALIB_C12_FILES {
        let p = dir.join(f);
        let b = std::fs::read(&p).map_err(|e| format!("{} : {e}", p.display()))?;
        let h = sep_proto::gt::OolHeader::parse(&b).ok_or_else(|| format!("{f} : en-tête court"))?;
        let len = h.len as usize;
        if h.valid != 1 || h.ty != 0x5b || h.total as usize != CALIB_LEN || h.offset as usize != blob.len() || OOL_HDR + len > b.len() {
            return Err(format!("{f} : en-tête gt inattendu {h:?}"));
        }
        blob.extend_from_slice(&b[OOL_HDR..OOL_HDR + len]);
    }
    check_calib(&blob)?;
    Ok(blob)
}

/// Steps 1-3 (SEP + sensor relay) and the patch fetch. Returns the patch block. With a calibration blob, the live
/// sensor serial must be the one it holds (checked before the first command to the SEP).
pub fn session<S: Sensor>(sep: &mut dyn Sep, m: &mut Mesa<'_, S>, calib: Option<&[u8]>) -> Result<Vec<u8>, String> {
    let id = m.identity()?;
    let serial = &id[sensor::SERIAL_RANGE];
    (m.log)(&format!("identité OK, n° de série {}", hex(serial)));
    if serial != SERIAL_J314C {
        return Err("n° de série != gabarit c12 : 0x17 non envoyé".into());
    }
    if let Some(c) = calib {
        if c.get(CALIB_SERIAL_AT..CALIB_SERIAL_AT + sensor::SERIAL_LEN) != Some(serial) {
            return Err("n° de série capteur ≠ celui du blob de calibration : rien envoyé au SEP".into());
        }
        (m.log)("n° de série capteur = celui du blob de calibration (offset 91)");
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

/// Step 4, macOS sequence (C17..C20, 8/8 pushes, `analysis/spi2_gpio_timeline.py`): prelude → wait for the ready pin
/// (the prelude raises it) → ONE status read (acknowledges it) → the block at once, in ONE transfer → NO SPI until
/// the ready pin rises again (macOS: 38-55 ms after the block) → ONE status read, byte 1 == 0x29 = loaded.
/// J5 v1 skipped the middle read and polled during the load: refused (journal 2026-11-22 20:16 / 21:00).
pub fn push_patch<S: Sensor>(m: &mut Mesa<'_, S>, block: &[u8]) -> Result<Verdict, String> {
    let before = m.status()?;
    (m.log)(&format!("état avant le push : {}", before.map_or("non reconnu".into(), |b| hex(&b))));
    // Prelude without the GAP_MS pause (macOS: IRQ ~0.1 ms after, status read ~1.2 ms after).
    m.s.xfer(&PATCH_PRELUDE, false).map_err(|e| format!("SPI prélude 0x60 : {e}"))?;
    (m.log)(&format!("SPI> prélude 0x60 {}", short(&PATCH_PRELUDE)));
    let t = m.s.now_ms();
    let up = m.wait_pin(true, PRELUDE_IRQ_MS);
    (m.log)(&format!("IRQ 195 après le prélude : {} (t+{} ms)", pin(up), m.s.now_ms() - t));
    let mid = m.status_raw()?;
    (m.log)(&format!("état entre prélude et bloc : {}", mid.map_or("non reconnu".into(), |b| hex(&b))));
    if mid.is_none() {
        return Err("état entre prélude et bloc non reconnu : bloc non envoyé".into());
    }
    let low = m.s.ready();
    let t = m.s.now_ms();
    m.s.xfer(block, false).map_err(|e| format!("SPI bloc du patch : {e}"))?;
    let t_done = m.s.now_ms();
    (m.log)(&format!("SPI> bloc du patch en UN transfert : {} en {} ms (IRQ 195 avant : {})", short(block), t_done - t, pin(low)));
    // No SPI while the sensor processes the block: wait for the ready pin only. If it is still high (prelude IRQ
    // not cleared), first wait for it to drop, so that a stale level is not taken for "load done".
    if m.s.ready() == Some(true) {
        let down = m.wait_pin(false, WAIT_LOAD_IRQ_MS);
        (m.log)(&format!("IRQ 195 encore haute après le bloc ; retombée : {} (t+{} ms)", pin(down), m.s.now_ms() - t_done));
    }
    let up = m.wait_pin(true, WAIT_LOAD_IRQ_MS);
    let el = m.s.now_ms() - t_done;
    (m.log)(&format!("IRQ 195 après le bloc : {} (t+{el} ms)", pin(up)));
    let irq_seen = up == Some(true);
    let st = m.status_raw()?;
    (m.log)(&format!("t+{el} ms état après le chargement : {}", st.map_or("non reconnu".into(), |b| hex(&b))));
    let st8 = st.map(|b| b[8]);
    if st8 == Some(PATCH_LOADED) {
        return Ok(Verdict::Loaded { t_ms: el, irq_seen });
    }
    // Diagnostic only (the sensor is done by now): one late read.
    m.s.sleep_ms(LATE_READ_MS);
    let late = m.status_raw()?;
    (m.log)(&format!("t+{} ms état tardif : {}", m.s.now_ms() - t_done, late.map_or("non reconnu".into(), |b| hex(&b))));
    if let Some(b) = late {
        if b[8] == PATCH_LOADED {
            return Ok(Verdict::Loaded { t_ms: m.s.now_ms() - t_done, irq_seen });
        }
    }
    let st8 = late.map(|b| b[8]).or(st8);
    Ok(if irq_seen { Verdict::Refused { st8 } } else { Verdict::NoIrq { st8 } })
}

fn pin(p: Option<bool>) -> &'static str {
    match p {
        Some(true) => "haute",
        Some(false) => "basse",
        None => "indisponible",
    }
}

fn expect_len(op: u8, r: &[u8], n: usize) -> Result<(), String> {
    if r.len() != n {
        return Err(format!("{op:#04x} : réponse de {} o ({n} attendus)", r.len()));
    }
    Ok(())
}

/// 0x31 → frame 0x55 → 0x75 answer → 0x32. Returns the 18-byte module serial the SEP answers.
fn module_serial<S: Sensor>(sep: &mut dyn Sep, m: &mut Mesa<'_, S>, n: u8) -> Result<Vec<u8>, String> {
    let what = format!("0x31 n°{n}");
    let blob = sep_cmd(sep, m.log, 0x31, &[])?;
    expect_len(0x31, &blob, 0x40)?;
    let st = m.param_frame(&what, &blob, &sensor::ST_SERIAL_READY)?;
    let pending = Mesa::<S>::pending(&Some(st));
    if pending != sensor::SERIAL_ANSWER_LEN {
        return Err(format!("{what} : réponse en attente {pending:#x} (0x4b attendu)"));
    }
    let resp = m.read_pending(&format!("réponse 0x75 ({what})"), pending)?;
    let back = sensor::serial_answer_payload(&resp).map_err(|e| format!("{what} : {e}"))?.to_vec();
    let serial = sep_cmd(sep, m.log, 0x32, &back)?;
    expect_len(0x32, &serial, MODULE_SERIAL_LEN)?;
    Ok(serial)
}

/// Step 5 (docs/j5_params_protocol.md §1, §6), only after a loaded patch. Returns the module serial.
pub fn params<S: Sensor>(sep: &mut dyn Sep, m: &mut Mesa<'_, S>, calib: Option<&[u8]>) -> Result<Vec<u8>, String> {
    for op in [0x5d, 0x5c] {
        let blob = sep_cmd(sep, m.log, op, &PARAMS_INPUT)?;
        expect_len(op, &blob, 0x37)?;
        m.param_frame(&format!("{op:#04x}"), &blob, &sensor::ST_AFTER_PARAMS)?;
    }
    let r = sep_cmd(sep, m.log, 0x6a, &[])?;
    expect_len(0x6a, &r, 0)?;
    let s1 = module_serial(sep, m, 1)?;
    if let Some(c) = calib {
        if c[CALIB_MODULE_AT..CALIB_MODULE_AT + MODULE_SERIAL_LEN] != s1[..] {
            return Err("0x32 : n° de série module ≠ celui du blob de calibration (offset 889) : arrêt avant 0x01".into());
        }
        (m.log)("0x32 : n° de série module = celui du blob de calibration (offset 889)");
    }
    let r = sep_cmd(sep, m.log, 0x01, &[])?;
    expect_len(0x01, &r, 0)?;
    let r = sep_cmd(sep, m.log, 0x1f, &[])?;
    if r != MATCH_POLICY_REF {
        return Err(format!("0x1f : réponse {} ≠ macOS {}", hex(&r), hex(&MATCH_POLICY_REF)));
    }
    let s2 = module_serial(sep, m, 2)?;
    if s2 != s1 {
        return Err("0x32 n°2 : n° de série module différent du n°1".into());
    }
    Ok(s1)
}

/// Step 6: 0x5b (whole blob; the kernel fragments it) then 0x63. Nothing on SPI.
pub fn calibrate(sep: &mut dyn Sep, log: &mut dyn FnMut(&str), blob: &[u8]) -> Result<Verdict, String> {
    check_calib(blob)?;
    let r = sep_cmd(sep, log, 0x5b, blob)?;
    expect_len(0x5b, &r, 0)?;
    let info = sep_cmd(sep, log, 0x63, &[])?;
    expect_len(0x63, &info, 0x1c)?;
    let same = info[..] == CAL_INFO_REF[..];
    log(&format!("0x63 : {} ({})", hex(&info), if same { "= macOS" } else { "≠ macOS" }));
    Ok(Verdict::Calibrated { info_ref: same })
}

/// Whole J5 run (the caller powers the sensor on before and off after, in every path). `calib` is required (and
/// checked first) for `Upto::Calib`; the later steps run only after a loaded patch.
pub fn run<S: Sensor>(sep: &mut dyn Sep, m: &mut Mesa<'_, S>, upto: Upto, calib: Option<&[u8]>) -> Verdict {
    if upto == Upto::Calib {
        match calib.map(check_calib) {
            Some(Ok(())) => {}
            Some(Err(e)) => return Verdict::Stopped(e),
            None => return Verdict::Stopped("--upto calib sans fichier de calibration".into()),
        }
    }
    let calib = if upto == Upto::Patch { None } else { calib };
    let loaded = match session(sep, m, calib) {
        Ok(p) => match push_patch(m, &p) {
            Ok(v) => v,
            Err(e) => return Verdict::Stopped(format!("push : {e}")),
        },
        Err(e) => return Verdict::Stopped(e),
    };
    if upto == Upto::Patch || !matches!(loaded, Verdict::Loaded { .. }) {
        return loaded;
    }
    (m.log)(&loaded.line());
    // macOS reads nothing between the "loaded" status and the 0x5d frame (C17): the pin must be low already.
    if let Err(e) = params(sep, m, calib) {
        return Verdict::Stopped(format!("paramètres : {e}"));
    }
    if upto == Upto::Params {
        return Verdict::ParamsDone;
    }
    let Some(c) = calib else { return Verdict::Stopped("calibration absente".into()) };
    calibrate(sep, m.log, c).unwrap_or_else(|e| Verdict::Stopped(format!("calibration : {e}")))
}

/// True when `v` is the verdict a run up to `upto` aims at.
pub fn success(upto: Upto, v: &Verdict) -> bool {
    match upto {
        Upto::Patch => matches!(v, Verdict::Loaded { .. }),
        Upto::Params => *v == Verdict::ParamsDone,
        Upto::Calib => *v == Verdict::Calibrated { info_ref: true },
    }
}

/// Number of steps of the kernel whitelist (sanity for the tests: the daemon uses all of them, in order).
pub const STEPS: usize = sbio_gate::RELAY_SEQUENCE.len();
