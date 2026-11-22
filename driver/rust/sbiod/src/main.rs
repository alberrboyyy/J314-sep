//! sbiod — J5 relay (see `lib.rs`). Usage (root):
//!   sbiod preflight                     checks bufsiz of spidev, the spidev node, gpio0 (sysfs only, opens nothing)
//!   sbiod run [--dev P] [--log FILE] [--upto patch|params|calib|pass2] [--calib FILE]
//!                                       run up to the patch (default), the params, the calibration, or the end of the
//!                                       2nd macOS pass (calib and pass2 need --calib); sensor powered off in every
//!                                       path; prints the VERDICT
//!   sbiod calib-prepare --from DIR --out FILE
//!                                       builds the calibration file from the four c12 0x5b A8 files (offline)
//!   sbiod power-off                     drives gpio0 196 low (teardown from the run script's trap)
//! Exit code: 0 = the verdict aimed at (`success`), 1 = any other verdict, 2 = preflight / device / file error
//! (nothing sent).
use sbiod::hw::{self, HwSensor, Line, SepDev, Spi};
use sbiod::{calib_from_c12, check_calib, run, success, Mesa, Upto};
use std::cell::RefCell;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::exit;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

struct Logger(RefCell<Option<File>>);

impl Logger {
    fn line(&self, s: &str) {
        let t = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
        let l = format!("{}.{:03} {s}", t.as_secs(), t.subsec_millis());
        eprintln!("{l}");
        if let Some(f) = self.0.borrow_mut().as_mut() {
            let _ = writeln!(f, "{l}").and_then(|()| f.sync_data());
        }
    }
}

struct Preflight {
    spidev: PathBuf,
    gpio: PathBuf,
}

/// Sensor side always; `dev` (the SEP relay node) only for `run` (the run script calls `preflight` BEFORE loading
/// sep_native, so a sensor-side problem stops everything before the first word to the SEP).
fn preflight(dev: Option<&Path>, log: &Logger) -> Result<Preflight, String> {
    let bufsiz = hw::spidev_bufsiz()?;
    if bufsiz < hw::NEED_BUFSIZ {
        return Err(format!("spidev bufsiz = {bufsiz} < {} (modprobe spidev bufsiz=65536)", hw::NEED_BUFSIZ));
    }
    let spidev = hw::find_spidev()?;
    let gpio = hw::find_gpio0()?;
    if let Some(d) = dev.filter(|d| !d.exists()) {
        return Err(format!("{} absent (sep_native allow_sbio_relay=1 et VERDICT sbio : VIVANT ?)", d.display()));
    }
    log.line(&format!("preflight OK : spidev bufsiz {bufsiz}, {}, gpio0 = {}", spidev.display(), gpio.display()));
    Ok(Preflight { spidev, gpio })
}

/// Powers the sensor off when dropped (every path, panics included).
struct Power<'a> {
    line: Line,
    log: &'a Logger,
}

impl Drop for Power<'_> {
    fn drop(&mut self) {
        let r = self.line.set(false);
        std::thread::sleep(Duration::from_millis(hw::PWR_OFF_MS));
        self.log.line(&format!("capteur éteint (gpio0 {} = 0) : {r:?}", hw::PWR_LINE));
    }
}

fn power_off(log: &Logger) -> Result<(), String> {
    let l = Line::request(&hw::find_gpio0()?, hw::PWR_LINE, Some(false))?;
    std::thread::sleep(Duration::from_millis(hw::PWR_OFF_MS));
    drop(l);
    log.line(&format!("power-off : gpio0 {} = 0", hw::PWR_LINE));
    Ok(())
}

fn main() {
    let mut args = std::env::args().skip(1);
    let cmd = args.next().unwrap_or_default();
    let (mut dev, mut logf) = (PathBuf::from("/dev/sep_sbio"), None::<PathBuf>);
    let (mut upto, mut calibf, mut from, mut out) = (Upto::Patch, None::<PathBuf>, None::<PathBuf>, None::<PathBuf>);
    let usage = || -> ! {
        eprintln!(
            "usage: sbiod preflight|run|power-off [--dev /dev/sep_sbio] [--log FILE] [--upto patch|params|calib|pass2] [--calib FILE]\n       sbiod calib-prepare --from DIR --out FILE"
        );
        exit(64)
    };
    while let Some(a) = args.next() {
        match (a.as_str(), args.next()) {
            ("--dev", Some(v)) => dev = v.into(),
            ("--log", Some(v)) => logf = Some(v.into()),
            ("--calib", Some(v)) => calibf = Some(v.into()),
            ("--from", Some(v)) => from = Some(v.into()),
            ("--out", Some(v)) => out = Some(v.into()),
            ("--upto", Some(v)) => {
                upto = match v.as_str() {
                    "patch" => Upto::Patch,
                    "params" => Upto::Params,
                    "calib" => Upto::Calib,
                    "pass2" => Upto::Pass2,
                    _ => usage(),
                }
            }
            _ => usage(),
        }
    }
    let log = Logger(RefCell::new(logf.and_then(|p| OpenOptions::new().create(true).append(true).open(p).ok())));
    let die = |code: i32, s: &str| -> ! {
        log.line(&format!("STOP : {s}"));
        exit(code)
    };
    match cmd.as_str() {
        "preflight" => {
            preflight(None, &log).unwrap_or_else(|e| die(2, &e));
        }
        "power-off" => power_off(&log).unwrap_or_else(|e| die(2, &e)),
        "calib-prepare" => {
            let (Some(from), Some(out)) = (from, out) else { usage() };
            let blob = calib_from_c12(&from).unwrap_or_else(|e| die(2, &e));
            let tmp = out.with_extension("tmp");
            std::fs::write(&tmp, &blob).and_then(|()| std::fs::rename(&tmp, &out)).unwrap_or_else(|e| die(2, &format!("{} : {e}", out.display())));
            log.line(&format!("calibration écrite : {} ({} o, sha256 {})", out.display(), blob.len(), sbiod::CALIB_SHA256));
        }
        "run" => {
            // Calibration file checked before anything is opened (nothing sent on error).
            let calib = match (upto, &calibf) {
                (Upto::Calib | Upto::Pass2, None) => die(2, "--upto calib|pass2 exige --calib FILE"),
                (_, Some(f)) => {
                    let b = std::fs::read(f).unwrap_or_else(|e| die(2, &format!("{} : {e}", f.display())));
                    check_calib(&b).unwrap_or_else(|e| die(2, &e));
                    log.line(&format!("calibration {} : {} o, sha256 OK", f.display(), b.len()));
                    Some(b)
                }
                (_, None) => None,
            };
            log.line(&format!("cible : {upto:?}"));
            let p = preflight(Some(&dev), &log).unwrap_or_else(|e| die(2, &e));
            let f = OpenOptions::new().read(true).write(true).open(&dev).unwrap_or_else(|e| die(2, &format!("{} : {e}", dev.display())));
            let spi = Spi::open(&p.spidev).unwrap_or_else(|e| die(2, &e));
            let ready = Line::request(&p.gpio, hw::READY_LINE, None)
                .inspect_err(|e| log.line(&format!("broche prête indisponible ({e}) : pauses fixes seulement")))
                .ok();
            let pwr = Line::request(&p.gpio, hw::PWR_LINE, Some(false)).unwrap_or_else(|e| die(2, &e));
            // Power on (mesa_power_on): low 40 ms, high, 60 ms. From here the guard powers off in every path.
            std::thread::sleep(Duration::from_millis(hw::PWR_PRE_MS));
            let power = Power { line: pwr, log: &log };
            if let Err(e) = power.line.set(true) {
                drop(power);
                die(2, &e);
            }
            std::thread::sleep(Duration::from_millis(hw::PWR_ON_MS));
            log.line(&format!("capteur alimenté (gpio0 {} = 1), spi 8 MHz mode 1", hw::PWR_LINE));
            let mut sensor = HwSensor::new(spi, ready, &power.line);
            let (mut l1, mut l2) = (|s: &str| log.line(s), |s: &str| log.line(s));
            let mut sep = SepDev { f, log: &mut l1 };
            let mut m = Mesa { s: &mut sensor, log: &mut l2 };
            let v = run(&mut sep, &mut m, upto, calib.as_deref());
            drop(sensor);
            drop(power);
            log.line(&v.line());
            exit(if success(upto, &v) { 0 } else { 1 });
        }
        _ => usage(),
    }
}
