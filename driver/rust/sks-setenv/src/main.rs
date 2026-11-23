//! sks_setenv — J9b/J9c userspace side (see `lib.rs`). Usage:
//!   sks_setenv build-getcap [CHAMPS] [--out FILE]   builds the 0x64-byte get_capabilities request (offline)
//!   sks_setenv build-setenv [CHAMPS] [--cpx N] [--out FILE]  builds the 0x470-byte set_env request (offline)
//!   sks_setenv build-nulldkey [CHAMPS] [--out FILE] builds the 0x60-byte null_d_key request (offline)
//!   sks_setenv check-getcap FILE                    applies the kernel gate's check to a getcap request (offline)
//!   sks_setenv check-setenv FILE                    applies the kernel gate's check to a set_env request (offline)
//!   sks_setenv check-nulldkey FILE                  applies the kernel gate's check to a null_d_key request (offline)
//!   sks_setenv decode FILE                          decodes a combined outcome record from /dev/sep_sks (offline)
//!   sks_setenv run [CHAMPS] [--cpx N] [--nulldkey] [--dev P] [--wait-s N] [--out-dir DIR]
//!       waits for /dev/sep_sks, writes the get_capabilities request, then (once the kernel has the getcap reply and
//!       asks for it) the set_env request, then (with --nulldkey, sep_native allow_sks=4) the null_d_key request, then
//!       reads and decodes all verdicts. Without --nulldkey it is the J9b flow (allow_sks=3, two records).
//! CHAMPS: --clock monotonic|boottime|realtime (default monotonic) | --ts-us N ; --uniqueid N (default 0) ;
//!         --uid N (default 0) ; --cdhash sha1|zero (default sha1)
//! --cpx N: force cpx-encryption-mode (default = read /proc/device-tree/defaults/cpx-encryption-mode, else 0).
//! Exit code: run without --nulldkey → 0 = set_env ACCEPTÉ ; run --nulldkey → 0 = null_d_key RÉPONDU (paired reply) ;
//!            1 = any other final verdict ; 2 = usage / file / device error.
use sep_proto::sks_ipc;
use sep_proto::sks_nulldkey as proto_nd;
use sep_proto::sks_setenv as proto_se;
use sks_setenv::{
    describe_getcap, describe_getcap_verdict, describe_nulldkey, describe_nulldkey_verdict, describe_setenv,
    describe_setenv_verdict, getcap_fields, getcap_verdict, nulldkey_fields, nulldkey_verdict, setenv_fields,
    setenv_verdict, CdhashMode, NulldkeyVerdict, SetenvVerdict,
};
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
const CPX_PATH: &str = "/proc/device-tree/defaults/cpx-encryption-mode";

fn now_us(clk: i32) -> Result<u64, String> {
    let mut ts = Timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: `ts` is a valid, writable timespec (aarch64/x86_64 Linux layout: two 64-bit fields).
    if unsafe { clock_gettime(clk, &mut ts) } != 0 {
        return Err(format!("clock_gettime({clk}) a échoué"));
    }
    Ok(ts.tv_sec as u64 * 1_000_000 + ts.tv_nsec as u64 / 1000)
}

/// Reads `cpx-encryption-mode` from the device-tree (big-endian u32 cell). `None` if the node is absent (Asahi) or
/// malformed; the caller then uses 0 (as the kext does when the property is missing).
fn read_cpx_adt() -> Option<u32> {
    let b = fs::read(CPX_PATH).ok()?;
    match b.len() {
        4 => Some(u32::from_be_bytes([b[0], b[1], b[2], b[3]])),
        _ => None,
    }
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
    cpx: Option<u32>,
    out: Option<PathBuf>,
    dev: PathBuf,
    wait_s: u64,
    out_dir: Option<PathBuf>,
    file: Option<PathBuf>,
    nulldkey: bool,
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
        cpx: None,
        out: None,
        dev: PathBuf::from("/dev/sep_sks"),
        wait_s: 300,
        out_dir: None,
        file: None,
        nulldkey: false,
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
            "--cpx" => o.cpx = Some(u32::try_from(num(&val()?)?).map_err(|_| "cpx > u32".to_string())?),
            "--out" => o.out = Some(PathBuf::from(val()?)),
            "--dev" => o.dev = PathBuf::from(val()?),
            "--wait-s" => o.wait_s = num(&val()?)?,
            "--out-dir" => o.out_dir = Some(PathBuf::from(val()?)),
            "--nulldkey" => o.nulldkey = true,
            x if !x.starts_with("--") && o.file.is_none() => o.file = Some(PathBuf::from(x)),
            x => return Err(format!("argument inconnu : {x}")),
        }
    }
    Ok(o)
}

fn ts_us(o: &Opts) -> Result<u64, String> {
    match o.ts {
        Ts::Clock(c) => now_us(c),
        Ts::Fixed(t) => Ok(t),
    }
}

/// Resolves the cpx value and says where it came from.
fn resolve_cpx(o: &Opts) -> (u32, String) {
    match o.cpx {
        Some(v) => (v, format!("--cpx {v}")),
        None => match read_cpx_adt() {
            Some(v) => (v, format!("device-tree {CPX_PATH} = {v}")),
            None => (0, format!("{CPX_PATH} absent → 0 (comme le kext)")),
        },
    }
}

fn build_getcap(o: &Opts) -> Result<[u8; sks_ipc::GETCAP_LEN], String> {
    Ok(sks_ipc::encode_getcap(&getcap_fields(ts_us(o)?, o.uniqueid, o.uid, o.cdhash)))
}

fn build_setenv(o: &Opts, cpx: u32) -> Result<[u8; proto_se::SETENV_LEN], String> {
    Ok(proto_se::encode_setenv(&setenv_fields(ts_us(o)?, o.uniqueid, o.uid, o.cdhash, cpx)))
}

fn build_nulldkey(o: &Opts) -> Result<[u8; proto_nd::NULLDKEY_LEN], String> {
    Ok(proto_nd::encode_nulldkey(&nulldkey_fields(ts_us(o)?, o.uniqueid, o.uid, o.cdhash)))
}

fn log(s: &str) {
    for l in s.lines() {
        eprintln!("sks_setenv: {l}");
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

/// Writes one request, retrying while the kernel answers EAGAIN (not yet the right phase), rebuilding it (fresh
/// timestamp) each try. `Ok(true)` = accepted; `Ok(false)` = EALREADY (kernel no longer expects it).
fn write_request(
    f: &mut std::fs::File,
    build: &mut dyn FnMut() -> Result<Vec<u8>, String>,
    deadline: Instant,
    label: &str,
) -> Result<bool, String> {
    let mut tries = 0u32;
    loop {
        let req = build()?;
        match f.write(&req) {
            Ok(n) if n == req.len() => {
                log(&format!("{label} accepté par le noyau après {tries} essai(s) EAGAIN"));
                return Ok(true);
            }
            Ok(n) => return Err(format!("{label} : écriture partielle ({n} o) : refus")),
            Err(e) if e.raw_os_error() == Some(EAGAIN) => {
                tries += 1;
                if Instant::now() >= deadline {
                    return Err(format!("le noyau n'a pas demandé {label} à temps : rien écrit"));
                }
                sleep(Duration::from_millis(20));
            }
            Err(e) if e.raw_os_error() == Some(EALREADY) => {
                log(&format!("le noyau n'attend plus {label} (déjà fait, délai dépassé, EP non ouverts, ou getcap non RÉPONDU)"));
                return Ok(false);
            }
            Err(e) => return Err(format!("{label} refusé par le noyau : {e} (rien envoyé ; voir dmesg)")),
        }
    }
}

/// `run`: returns the exit code.
fn run(o: &Opts) -> Result<i32, String> {
    let t0 = Instant::now();
    let deadline = t0 + Duration::from_secs(o.wait_s);
    while !o.dev.exists() {
        if Instant::now() >= deadline {
            return Err(format!("{} absent après {} s (sep_native allow_sks=3 chargé ?) : rien écrit", o.dev.display(), o.wait_s));
        }
        sleep(Duration::from_millis(50));
    }
    let (cpx, cpx_src) = resolve_cpx(o);
    log(&format!("cpx-encryption-mode = {cpx} ({cpx_src})"));
    let mut f = OpenOptions::new().read(true).write(true).open(&o.dev).map_err(|e| format!("ouverture de {} : {e}", o.dev.display()))?;
    log(&format!("{} ouvert", o.dev.display()));

    // 1) get_capabilities.
    let accepted = write_request(&mut f, &mut || build_getcap(o).map(|b| b.to_vec()), deadline, "get_capabilities")?;
    if accepted {
        let gc = build_getcap(o)?; // for the record saved to disk (fresh ts, same shape)
        save(&o.out_dir, "sks_getcap_request.bin", &gc);
    }
    // 2) set_env (the kernel accepts it only once it has the getcap reply, i.e. v2 negotiated).
    let mut se_accepted = false;
    if accepted {
        se_accepted = write_request(&mut f, &mut || build_setenv(o, cpx).map(|b| b.to_vec()), deadline, "set_env")?;
        if se_accepted {
            let se = build_setenv(o, cpx)?;
            log(&describe_setenv(&se)?);
            save(&o.out_dir, "sks_setenv_request.bin", &se);
        }
    }
    // 3) null_d_key (--nulldkey, allow_sks=4): the kernel accepts it only once set_env was ACCEPTÉ; the two
    //    perform_operation (txn3/txn5) are SKIPPED.
    if o.nulldkey && se_accepted {
        let nd_accepted = write_request(&mut f, &mut || build_nulldkey(o).map(|b| b.to_vec()), deadline, "null_d_key")?;
        if nd_accepted {
            let nd = build_nulldkey(o)?;
            log(&describe_nulldkey(&nd)?);
            save(&o.out_dir, "sks_nulldkey_request.bin", &nd);
        }
    }

    // 4) Read the combined outcome record. allow_sks=4 → 3 records (getcap, set_env, null_d_key); else 2.
    let records = if o.nulldkey { 3 } else { 2 };
    let need = sks_ipc::OUT_SIZE * records;
    let mut rec = vec![0u8; need];
    let n = f.read(&mut rec).map_err(|e| format!("lecture du verdict : {e}"))?;
    save(&o.out_dir, if o.nulldkey { "sks_nulldkey_outcome.bin" } else { "sks_setenv_outcome.bin" }, &rec[..n]);
    if n < need {
        return Err(format!("enregistrement trop court ({n} o < {need} o) : /dev/sep_sks n'est pas dans le bon mode (allow_sks={})", if o.nulldkey { 4 } else { 3 }));
    }
    let (gcv, gcraw) = getcap_verdict(&rec[..sks_ipc::OUT_SIZE])?;
    let (sev, seraw, sesnap) = setenv_verdict(&rec[sks_ipc::OUT_SIZE..sks_ipc::OUT_SIZE * 2])?;
    print!("{}", describe_getcap_verdict(&gcv, gcraw));
    print!("{}", describe_setenv_verdict(&sev, seraw, &sesnap));
    if o.nulldkey {
        let (ndv, ndraw, ndsnap) = nulldkey_verdict(&rec[sks_ipc::OUT_SIZE * 2..sks_ipc::OUT_SIZE * 3])?;
        print!("{}", describe_nulldkey_verdict(&ndv, ndraw, &ndsnap));
        return Ok(if matches!(ndv, NulldkeyVerdict::Replied { .. }) { 0 } else { 1 });
    }
    Ok(if matches!(sev, SetenvVerdict::Accepted(_)) { 0 } else { 1 })
}

fn read_file(p: &Option<PathBuf>) -> Result<Vec<u8>, String> {
    let p: &Path = p.as_deref().ok_or("fichier manquant")?;
    fs::read(p).map_err(|e| format!("{} : {e}", p.display()))
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let Some(cmd) = args.get(1) else {
        eprintln!("usage : sks_setenv build-getcap|build-setenv|build-nulldkey|check-getcap|check-setenv|check-nulldkey|decode|run … (voir l'en-tête de src/main.rs)");
        exit(2);
    };
    let o = match parse(&args[2..]) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("sks_setenv: {e}");
            exit(2);
        }
    };
    let r: Result<i32, String> = match cmd.as_str() {
        "build-getcap" => build_getcap(&o).and_then(|req| {
            print!("{}", describe_getcap(&req)?);
            if let Some(p) = &o.out {
                fs::write(p, req).map_err(|e| format!("{} : {e}", p.display()))?;
            }
            Ok(0)
        }),
        "build-setenv" => {
            let (cpx, src) = resolve_cpx(&o);
            log(&format!("cpx-encryption-mode = {cpx} ({src})"));
            build_setenv(&o, cpx).and_then(|req| {
                print!("{}", describe_setenv(&req)?);
                if let Some(p) = &o.out {
                    fs::write(p, req).map_err(|e| format!("{} : {e}", p.display()))?;
                }
                Ok(0)
            })
        }
        "build-nulldkey" => build_nulldkey(&o).and_then(|req| {
            print!("{}", describe_nulldkey(&req)?);
            if let Some(p) = &o.out {
                fs::write(p, req).map_err(|e| format!("{} : {e}", p.display()))?;
            }
            Ok(0)
        }),
        "check-getcap" => read_file(&o.file).and_then(|b| describe_getcap(&b)).map(|s| {
            print!("{s}");
            0
        }),
        "check-setenv" => read_file(&o.file).and_then(|b| describe_setenv(&b)).map(|s| {
            print!("{s}");
            0
        }),
        "check-nulldkey" => read_file(&o.file).and_then(|b| describe_nulldkey(&b)).map(|s| {
            print!("{s}");
            0
        }),
        "decode" => read_file(&o.file).and_then(|b| {
            if b.len() < sks_ipc::OUT_SIZE * 2 {
                return Err(format!("enregistrement trop court ({} o < {} o)", b.len(), sks_ipc::OUT_SIZE * 2));
            }
            let (gcv, gcraw) = getcap_verdict(&b[..sks_ipc::OUT_SIZE])?;
            let (sev, seraw, sesnap) = setenv_verdict(&b[sks_ipc::OUT_SIZE..sks_ipc::OUT_SIZE * 2])?;
            print!("{}", describe_getcap_verdict(&gcv, gcraw));
            print!("{}", describe_setenv_verdict(&sev, seraw, &sesnap));
            // A third record (allow_sks=4) → the null_d_key verdict too.
            if b.len() >= sks_ipc::OUT_SIZE * 3 {
                let (ndv, ndraw, ndsnap) = nulldkey_verdict(&b[sks_ipc::OUT_SIZE * 2..sks_ipc::OUT_SIZE * 3])?;
                print!("{}", describe_nulldkey_verdict(&ndv, ndraw, &ndsnap));
                return Ok(if matches!(ndv, NulldkeyVerdict::Replied { .. }) { 0 } else { 1 });
            }
            Ok(if matches!(sev, SetenvVerdict::Accepted(_)) { 0 } else { 1 })
        }),
        "run" => run(&o),
        x => Err(format!("commande inconnue : {x}")),
    };
    match r {
        Ok(c) => exit(c),
        Err(e) => {
            eprintln!("sks_setenv: {e}");
            exit(2);
        }
    }
}
