//! Device bindings of sbiod: `/dev/sep_sbio` (sep_native), spidev (spi2.0) and the gpio character device
//! (gpio0 = `39b028000.pinctrl`). ioctl numbers and struct layouts are the Linux uapi ones (`linux/spi/spidev.h`,
//! `linux/gpio.h` v2), checked against the headers with a C program on the PC (sizes 32 / 592 / 68 / 16).
//! Nothing here is used by the offline tests.
use crate::{Sensor, Sep};
use sep_proto::sbio_gate::{self, EvtHdr, CMD_MAX, EVT_MAX, KIND_NOTIFY, KIND_REPLY};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

extern "C" {
    fn ioctl(fd: i32, req: u64, ...) -> i32;
}

fn ioc(fd: i32, req: u64, arg: *mut u8, what: &str) -> Result<(), String> {
    // SAFETY: `arg` points to a live buffer of the size encoded in `req` (each caller passes the uapi struct).
    let r = unsafe { ioctl(fd, req, arg) };
    if r < 0 {
        return Err(format!("{what} : {}", std::io::Error::last_os_error()));
    }
    Ok(())
}

// --- spidev -------------------------------------------------------------------------------------------------
const SPI_IOC_MESSAGE_1: u64 = 0x4020_6b00;
const SPI_IOC_WR_MODE32: u64 = 0x4004_6b05;
const SPI_IOC_RD_MODE32: u64 = 0x8004_6b05;
const SPI_IOC_WR_BITS_PER_WORD: u64 = 0x4001_6b03;
const SPI_IOC_WR_MAX_SPEED_HZ: u64 = 0x4004_6b04;
const SPI_IOC_RD_MAX_SPEED_HZ: u64 = 0x8004_6b04;
/// SPI_MODE_1 = CPHA (mesa_transport.h `SPI_MODE_1`, DT `spi-cpha`).
const SPI_MODE_1: u32 = 1;
pub const MESA_HZ: u32 = 8_000_000;
/// Largest SPI message the run needs (patch block, up to MAX_REPLY): spidev's `bufsiz` must be at least this.
pub const NEED_BUFSIZ: usize = sbio_gate::MAX_REPLY;
const BIOSENSOR_NODE: &str = "spi@39b108000/biosensor@0";
const PINCTRL_GPIO0: &str = "39b028000.pinctrl";
pub const PWR_LINE: u32 = 196;
pub const READY_LINE: u32 = 195;

/// spidev bound to the biosensor node (driver_override = spidev). Found through sysfs, never guessed.
pub fn find_spidev() -> Result<PathBuf, String> {
    for e in fs::read_dir("/sys/bus/spi/devices").map_err(|e| format!("/sys/bus/spi/devices : {e}"))?.flatten() {
        let d = e.path();
        let node = fs::canonicalize(d.join("of_node")).unwrap_or_default();
        if !node.to_string_lossy().ends_with(BIOSENSOR_NODE) {
            continue;
        }
        let drv = fs::read_link(d.join("driver")).unwrap_or_default();
        if drv.file_name().is_none_or(|n| n != "spidev") {
            return Err(format!("{} : lié à {:?}, pas à spidev (driver_override ?)", d.display(), drv.file_name()));
        }
        let name = fs::read_dir(d.join("spidev")).map_err(|e| format!("{}/spidev : {e}", d.display()))?.flatten().next();
        return name.map(|n| Path::new("/dev").join(n.file_name())).ok_or_else(|| "spidev sans nœud".into());
    }
    Err(format!("aucun device SPI sur {BIOSENSOR_NODE} (overlay mesa_ovl chargé ?)"))
}

pub fn spidev_bufsiz() -> Result<usize, String> {
    let s = fs::read_to_string("/sys/module/spidev/parameters/bufsiz").map_err(|e| format!("bufsiz de spidev : {e}"))?;
    s.trim().parse().map_err(|e| format!("bufsiz de spidev : {e}"))
}

pub struct Spi {
    f: File,
}

impl Spi {
    pub fn open(p: &Path) -> Result<Self, String> {
        let f = OpenOptions::new().read(true).write(true).open(p).map_err(|e| format!("{} : {e}", p.display()))?;
        let fd = f.as_raw_fd();
        let mut mode = SPI_MODE_1;
        ioc(fd, SPI_IOC_WR_MODE32, (&raw mut mode).cast(), "SPI mode")?;
        let mut bits = 8u8;
        ioc(fd, SPI_IOC_WR_BITS_PER_WORD, &raw mut bits, "SPI bits")?;
        let mut hz = MESA_HZ;
        ioc(fd, SPI_IOC_WR_MAX_SPEED_HZ, (&raw mut hz).cast(), "SPI vitesse")?;
        let (mut m2, mut hz2) = (0u32, 0u32);
        ioc(fd, SPI_IOC_RD_MODE32, (&raw mut m2).cast(), "SPI mode (relu)")?;
        ioc(fd, SPI_IOC_RD_MAX_SPEED_HZ, (&raw mut hz2).cast(), "SPI vitesse (relue)")?;
        if m2 & 3 != SPI_MODE_1 || hz2 != MESA_HZ {
            return Err(format!("SPI relu : mode {m2:#x}, {hz2} Hz (mode 1, 8 MHz attendus)"));
        }
        Ok(Spi { f })
    }

    /// One SPI_IOC_MESSAGE(1): one message, one transfer (CS held over the whole transfer).
    pub fn xfer(&mut self, tx: &[u8], rx: bool) -> Result<Vec<u8>, String> {
        let mut out = vec![0u8; if rx { tx.len() } else { 0 }];
        let len = u32::try_from(tx.len()).map_err(|_| "transfert trop long")?;
        // struct spi_ioc_transfer (32 o) : tx_buf u64, rx_buf u64, len u32, speed_hz u32, delay_usecs u16,
        // bits_per_word u8, cs_change u8, tx_nbits u8, rx_nbits u8, word_delay_usecs u8, pad u8.
        let mut t = [0u8; 32];
        t[0..8].copy_from_slice(&(tx.as_ptr() as u64).to_le_bytes());
        t[8..16].copy_from_slice(&(if rx { out.as_mut_ptr() as u64 } else { 0 }).to_le_bytes());
        t[16..20].copy_from_slice(&len.to_le_bytes());
        t[20..24].copy_from_slice(&MESA_HZ.to_le_bytes());
        t[26] = 8;
        ioc(self.f.as_raw_fd(), SPI_IOC_MESSAGE_1, t.as_mut_ptr(), "SPI_IOC_MESSAGE")?;
        Ok(out)
    }
}

// --- gpio cdev v2 ---------------------------------------------------------------------------------------------
const GPIO_GET_CHIPINFO_IOCTL: u64 = 0x8044_b401;
const GPIO_V2_GET_LINE_IOCTL: u64 = 0xc250_b407;
const GPIO_V2_LINE_GET_VALUES_IOCTL: u64 = 0xc010_b40e;
const GPIO_V2_LINE_SET_VALUES_IOCTL: u64 = 0xc010_b40f;
const GPIO_V2_LINE_FLAG_INPUT: u64 = 1 << 2;
const GPIO_V2_LINE_FLAG_OUTPUT: u64 = 1 << 3;
const GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES: u32 = 2;

/// gpiochip of gpio0: the chip directly under `39b028000.pinctrl` (not its gpiolib_shared proxies), checked by label.
pub fn find_gpio0() -> Result<PathBuf, String> {
    for e in fs::read_dir("/sys/bus/gpio/devices").map_err(|e| format!("/sys/bus/gpio/devices : {e}"))?.flatten() {
        let real = fs::canonicalize(e.path()).unwrap_or_default();
        if real.parent().and_then(Path::file_name).is_some_and(|n| n == PINCTRL_GPIO0) {
            return Ok(Path::new("/dev").join(e.file_name()));
        }
    }
    Err(format!("aucun gpiochip sous {PINCTRL_GPIO0}"))
}

pub struct Line {
    fd: OwnedFd,
}

impl Line {
    /// Requests one line of `chip` (label and line count checked), as output with `initial` or as input.
    pub fn request(chip: &Path, line: u32, output: Option<bool>) -> Result<Self, String> {
        let f = File::open(chip).map_err(|e| format!("{} : {e}", chip.display()))?;
        let mut info = [0u8; 68];
        ioc(f.as_raw_fd(), GPIO_GET_CHIPINFO_IOCTL, info.as_mut_ptr(), "GPIO chipinfo")?;
        let label = String::from_utf8_lossy(&info[32..64]).trim_end_matches('\0').to_string();
        let lines = u32::from_le_bytes([info[64], info[65], info[66], info[67]]);
        if label != PINCTRL_GPIO0 || line >= lines {
            return Err(format!("{} : label {label:?}, {lines} lignes ({PINCTRL_GPIO0}, > {line} attendus)", chip.display()));
        }
        // struct gpio_v2_line_request (592 o) : offsets[64] u32 @0, consumer[32] @256, config @288 (flags u64,
        // num_attrs u32, padding, attrs[10] @+32 de 24 o : id u32, pad u32, values u64, mask u64), num_lines @560,
        // event_buffer_size @564, padding, fd @588.
        let mut r = [0u8; 592];
        r[0..4].copy_from_slice(&line.to_le_bytes());
        r[256..256 + 5].copy_from_slice(b"sbiod");
        let flags = if output.is_some() { GPIO_V2_LINE_FLAG_OUTPUT } else { GPIO_V2_LINE_FLAG_INPUT };
        r[288..296].copy_from_slice(&flags.to_le_bytes());
        if let Some(v) = output {
            r[296..300].copy_from_slice(&1u32.to_le_bytes());
            let a = 288 + 32;
            r[a..a + 4].copy_from_slice(&GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES.to_le_bytes());
            r[a + 8..a + 16].copy_from_slice(&u64::from(v).to_le_bytes());
            r[a + 16..a + 24].copy_from_slice(&1u64.to_le_bytes());
        }
        r[560..564].copy_from_slice(&1u32.to_le_bytes());
        ioc(f.as_raw_fd(), GPIO_V2_GET_LINE_IOCTL, r.as_mut_ptr(), &format!("GPIO ligne {line}"))?;
        let fd = i32::from_le_bytes([r[588], r[589], r[590], r[591]]);
        if fd < 0 {
            return Err(format!("GPIO ligne {line} : fd {fd}"));
        }
        // SAFETY: `fd` is the line file descriptor just returned by the kernel, owned by nobody else.
        Ok(Line { fd: unsafe { OwnedFd::from_raw_fd(fd) } })
    }

    pub fn set(&self, v: bool) -> Result<(), String> {
        let mut b = [0u8; 16];
        b[0..8].copy_from_slice(&u64::from(v).to_le_bytes());
        b[8..16].copy_from_slice(&1u64.to_le_bytes());
        ioc(self.fd.as_raw_fd(), GPIO_V2_LINE_SET_VALUES_IOCTL, b.as_mut_ptr(), "GPIO écriture")
    }

    pub fn get(&self) -> Result<bool, String> {
        let mut b = [0u8; 16];
        b[8..16].copy_from_slice(&1u64.to_le_bytes());
        ioc(self.fd.as_raw_fd(), GPIO_V2_LINE_GET_VALUES_IOCTL, b.as_mut_ptr(), "GPIO lecture")?;
        Ok(b[0] & 1 != 0)
    }
}

/// Power sequence of mesa_transport.h: low 40 ms, high, 60 ms. Off: low, 20 ms.
pub const PWR_PRE_MS: u64 = 40;
pub const PWR_ON_MS: u64 = 60;
pub const PWR_OFF_MS: u64 = 20;

pub struct HwSensor {
    pub spi: Spi,
    pub ready: Option<Line>,
    t0: Instant,
}

impl HwSensor {
    pub fn new(spi: Spi, ready: Option<Line>) -> Self {
        HwSensor { spi, ready, t0: Instant::now() }
    }
}

impl Sensor for HwSensor {
    fn xfer(&mut self, tx: &[u8], rx: bool) -> Result<Vec<u8>, String> {
        self.spi.xfer(tx, rx)
    }
    fn ready(&mut self) -> Option<bool> {
        self.ready.as_ref().and_then(|l| l.get().ok())
    }
    fn sleep_ms(&mut self, ms: u64) {
        std::thread::sleep(Duration::from_millis(ms));
    }
    fn now_ms(&mut self) -> u64 {
        self.t0.elapsed().as_millis() as u64
    }
}

/// `/dev/sep_sbio`: one command record per write (the kernel blocks until the reply is complete), then events
/// are read until the reply; notifications (TAG 0x01-0x04) are logged and skipped.
pub struct SepDev<'a> {
    pub f: File,
    pub log: &'a mut dyn FnMut(&str),
}

impl Sep for SepDev<'_> {
    fn cmd(&mut self, op: u8, payload: &[u8]) -> Result<Vec<u8>, String> {
        let mut rec = vec![0u8; CMD_MAX];
        let n = sbio_gate::encode_cmd(op, payload, &mut rec).map_err(|e| e.to_string())?;
        self.f.write_all(&rec[..n]).map_err(|e| format!("write : {e} (EIO/EINVAL = sep_native Halted, voir dmesg)"))?;
        let mut buf = vec![0u8; EVT_MAX];
        loop {
            let k = match self.f.read(&mut buf) {
                Ok(k) => k,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(format!("read : {e} (EIO = sep_native Halted, voir dmesg)")),
            };
            let (h, p) = EvtHdr::decode(&buf[..k]).map_err(|e| format!("événement illisible : {e}"))?;
            match h.kind {
                KIND_NOTIFY => (self.log)(&format!(
                    "SEP notification TAG {:#04x} TYPE {:#04x} PARAM {:#04x} DATA {:#010x}",
                    h.tag, h.ty, h.param, h.data
                )),
                KIND_REPLY if h.ty == op => {
                    (self.log)(&format!("SEP< mot final TAG {:#04x} TYPE {:#04x} DATA {:#010x}", h.tag, h.ty, h.data));
                    return Ok(p.to_vec());
                }
                _ => return Err(format!("événement inattendu kind {} TYPE {:#04x}", h.kind, h.ty)),
            }
        }
    }
}
