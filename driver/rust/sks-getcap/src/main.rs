//! sks_getcap — J9a userspace side (see `lib.rs`). Usage:
//!   sks_getcap build [CHAMPS] [--out FILE]   builds the 0x64-byte request, prints it (offline, opens no device)
//!   sks_getcap check FILE                    applies the kernel gate's check to a request file (offline)
//!   sks_getcap decode FILE                   decodes an outcome record read from /dev/sep_sks (offline)
//!   sks_getcap run [CHAMPS] [--dev P] [--wait-s N] [--out-dir DIR]
//!                                            waits for /dev/sep_sks (sep_native allow_sks=2), writes ONE request when
//!                                            the kernel asks for it (fresh timestamp at each EAGAIN retry), then
//!                                            blocks until the kernel verdict and decodes it
//! CHAMPS: --clock monotonic|boottime|realtime (default monotonic) | --ts-us N ; --uniqueid N (default 0) ;
//!         --uid N (default 0) ; --cdhash sha1|zero (default sha1 = SHA-1 of the 8 bytes of the unique id)
//! Exit code: 0 = RÉPONDU, 1 = any other verdict (SILENCE, ERREUR, NON ENVOYÉ), 2 = usage / file / device error.
use sep_proto::sks_ipc;
use sks_getcap::{describe_request, describe_verdict, fields, verdict, CdhashMode, Verdict};
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::exit;
use std::thread::sleep;
use std::time::{Duration, Instant};

#[repr(C)]
struct Timespec {
    tv_sec: i64,
    tv_nsec: i64,
}

extern "C" {
    fn clock_gettime(clk: i32, ts: *mut Timespec) -> i32;
}

const CLOCK_REALTIME: i32 = 0;
const CLOCK_MONOTONIC: i32 = 1;
const CLOCK_BOOTTIME: i32 = 7;
const EAGAIN: i32 = 11;
const EALREADY: i32 = 114;

fn now_us(clk: i32) -> Result<u64, String> {
    let mut ts = Timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: `ts` is a valid, writable timespec (aarch64/x86_64 Linux layout: two 64-bit fields).
    if unsafe { clock_gettime(clk, &mut ts) } != 0 {
        return Err(format!("clock_gettime({clk}) a échoué"));
    }
    Ok(ts.tv_sec as u64 * 1_000_000 + ts.tv_nsec as u64 / 1000)
}

#[derive(Clone, Copy)]
enum Ts {
    Clock(i32),
    Fixed(u64),
}

struct Opts {
    ts: Ts,
    uniqueid: u64,
    uid: u32,
    cdhash: CdhashMode,
    out: Option<PathBuf>,
    dev: PathBuf,
    wait_s: u64,
    out_dir: Option<PathBuf>,
    file: Option<PathBuf>,
}

fn num(s: &str) -> Result<u64, String> {
    let r = match s.strip_prefix("0x") {
        Some(h) => u64::from_str_radix(h, 16),
        None => s.parse(),
    };
    r.map_err(|_| format!("nombre invalide : {s}"))
}

fn parse(args: &[String]) -> Result<Opts, String> {
    let mut o = Opts {
        ts: Ts::Clock(CLOCK_MONOTONIC),
        uniqueid: 0,
        uid: 0,
        cdhash: CdhashMode::Sha1,
        out: None,
        dev: PathBuf::from("/dev/sep_sks"),
        wait_s: 300,
        out_dir: None,
        file: None,
    };
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let mut val = || it.next().cloned().ok_or_else(|| format!("{a} sans valeur"));
        match a.as_str() {
            "--clock" => {
                o.ts = Ts::Clock(match val()?.as_str() {
                    "monotonic" => CLOCK_MONOTONIC,
                    "boottime" => CLOCK_BOOTTIME,
                    "realtime" => CLOCK_REALTIME,
                    x => return Err(format!("horloge inconnue : {x}")),
                })
            }
            "--ts-us" => o.ts = Ts::Fixed(num(&val()?)?),
            "--uniqueid" => o.uniqueid = num(&val()?)?,
            "--uid" => o.uid = u32::try_from(num(&val()?)?).map_err(|_| "uid > u32".to_string())?,
            "--cdhash" => {
                o.cdhash = match val()?.as_str() {
                    "sha1" => CdhashMode::Sha1,
                    "zero" => CdhashMode::Zero,
                    x => return Err(format!("--cdhash sha1|zero, pas {x}")),
                }
            }
            "--out" => o.out = Some(PathBuf::from(val()?)),
            "--dev" => o.dev = PathBuf::from(val()?),
            "--wait-s" => o.wait_s = num(&val()?)?,
            "--out-dir" => o.out_dir = Some(PathBuf::from(val()?)),
            x if !x.starts_with("--") && o.file.is_none() => o.file = Some(PathBuf::from(x)),
            x => return Err(format!("argument inconnu : {x}")),
        }
    }
    Ok(o)
}

fn build(o: &Opts) -> Result<[u8; sks_ipc::GETCAP_LEN], String> {
    let ts = match o.ts {
        Ts::Clock(c) => now_us(c)?,
        Ts::Fixed(t) => t,
    };
    Ok(sks_ipc::encode_getcap(&fields(ts, o.uniqueid, o.uid, o.cdhash)))
}

fn log(s: &str) {
    for l in s.lines() {
        eprintln!("sks_getcap: {l}");
    }
}

fn save(dir: &Option<PathBuf>, name: &str, b: &[u8]) {
    if let Some(d) = dir {
        let p = d.join(name);
        match fs::write(&p, b) {
            Ok(()) => log(&format!("écrit {}", p.display())),
            Err(e) => log(&format!("écriture de {} impossible : {e}", p.display())),
        }
    }
}

/// `run`: returns the exit code.
fn run(o: &Opts) -> Result<i32, String> {
    let t0 = Instant::now();
    let deadline = Duration::from_secs(o.wait_s);
    while !o.dev.exists() {
        if t0.elapsed() >= deadline {
            return Err(format!("{} absent après {} s (sep_native allow_sks=2 chargé ?) : rien écrit", o.dev.display(), o.wait_s));
        }
        sleep(Duration::from_millis(50));
    }
    let mut f = OpenOptions::new().read(true).write(true).open(&o.dev).map_err(|e| format!("ouverture de {} : {e}", o.dev.display()))?;
    log(&format!("{} ouvert ; attente du moment où le noyau demande la requête", o.dev.display()));
    let mut tries = 0u32;
    loop {
        let req = build(o)?;
        match f.write(&req) {
            Ok(n) if n == req.len() => {
                log(&format!("requête acceptée par le noyau après {tries} essai(s) EAGAIN :"));
                log(&describe_request(&req)?);
                save(&o.out_dir, "sks_getcap_request.bin", &req);
                break;
            }
            Ok(n) => return Err(format!("écriture partielle ({n} o) : refus")),
            Err(e) if e.raw_os_error() == Some(EAGAIN) => {
                tries += 1;
                if t0.elapsed() >= deadline {
                    return Err(format!("le noyau n'a pas demandé la requête en {} s : rien écrit", o.wait_s));
                }
                sleep(Duration::from_millis(20));
            }
            Err(e) if e.raw_os_error() == Some(EALREADY) => {
                log("le noyau n'attend plus de requête (déjà fait, ou délai dépassé / EP non ouverts) : lecture du verdict");
                break;
            }
            Err(e) => return Err(format!("requête refusée par le noyau : {e} (rien envoyé ; voir dmesg)")),
        }
    }
    let mut rec = [0u8; sks_ipc::OUT_SIZE];
    let n = f.read(&mut rec).map_err(|e| format!("lecture du verdict : {e}"))?;
    save(&o.out_dir, "sks_getcap_outcome.bin", &rec[..n]);
    let (v, raw, snap) = verdict(&rec[..n])?;
    print!("{}", describe_verdict(&v, raw, &snap));
    Ok(if matches!(v, Verdict::Replied { .. }) { 0 } else { 1 })
}

fn read_file(p: &Option<PathBuf>) -> Result<Vec<u8>, String> {
    let p: &Path = p.as_deref().ok_or("fichier manquant")?;
    fs::read(p).map_err(|e| format!("{} : {e}", p.display()))
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let Some(cmd) = args.get(1) else {
        eprintln!("usage : sks_getcap build|check|decode|run … (voir l'en-tête de src/main.rs)");
        exit(2);
    };
    let o = match parse(&args[2..]) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("sks_getcap: {e}");
            exit(2);
        }
    };
    let r: Result<i32, String> = match cmd.as_str() {
        "build" => build(&o).and_then(|req| {
            print!("{}", describe_request(&req)?);
            if let Some(p) = &o.out {
                fs::write(p, req).map_err(|e| format!("{} : {e}", p.display()))?;
            }
            Ok(0)
        }),
        "check" => read_file(&o.file).and_then(|b| describe_request(&b)).map(|s| {
            print!("{s}");
            0
        }),
        "decode" => read_file(&o.file).and_then(|b| verdict(&b)).map(|(v, raw, snap)| {
            print!("{}", describe_verdict(&v, raw, &snap));
            if matches!(v, Verdict::Replied { .. }) { 0 } else { 1 }
        }),
        "run" => run(&o),
        x => Err(format!("commande inconnue : {x}")),
    };
    match r {
        Ok(c) => exit(c),
        Err(e) => {
            eprintln!("sks_getcap: {e}");
            exit(2);
        }
    }
}
