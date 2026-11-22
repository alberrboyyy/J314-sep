//! sepd: serves EP 0x13 (xART) of `sep_native` through `/dev/sep_native`. See `lib.rs` for the policy and
//! `driver/rust/kmod/SEP_NATIVE.md` for the interface and the test plan.
//!
//! Usage: sepd [--store DIR] [--os-uuid-file FILE] [--dev PATH] [--locker-strip-uuid | --locker-verbatim]
//!   defaults: /var/lib/sepd, /etc/sepd/os_uuid, /dev/sep_native.
//! Every exchange is logged to stderr and appended to DIR/sepd.log. Any error = exit WITHOUT replying.
use sep_proto::xart::op_name;
use sep_proto::xart_gate::{RecHdr, REC_MAX};
use sepd::{parse_uuid, Daemon, Store, DEFAULT_DEV, DEFAULT_STORE, DEFAULT_UUID_FILE};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::exit;
use std::time::{SystemTime, UNIX_EPOCH};

struct Log(Option<File>);

impl Log {
    fn line(&mut self, s: &str) {
        let t = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
        let l = format!("{}.{:03} {s}", t.as_secs(), t.subsec_millis());
        eprintln!("{l}");
        if let Some(f) = self.0.as_mut() {
            let _ = writeln!(f, "{l}").and_then(|()| f.sync_data());
        }
    }
    fn die(&mut self, code: i32, s: &str) -> ! {
        self.line(&format!("STOP: {s}"));
        exit(code)
    }
}

fn main() {
    let (mut store, mut uuid_file, mut dev) = (PathBuf::from(DEFAULT_STORE), PathBuf::from(DEFAULT_UUID_FILE), PathBuf::from(DEFAULT_DEV));
    let mut strip = true; // default since J7b (verified n=2); --locker-strip-uuid kept for the J7b script
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        if a == "--locker-strip-uuid" || a == "--locker-verbatim" {
            strip = a == "--locker-strip-uuid";
            continue;
        }
        let v = args.next().map(PathBuf::from);
        match (a.as_str(), v) {
            ("--store", Some(v)) => store = v,
            ("--os-uuid-file", Some(v)) => uuid_file = v,
            ("--dev", Some(v)) => dev = v,
            _ => {
                eprintln!("usage: sepd [--store DIR] [--os-uuid-file FILE] [--dev PATH] [--locker-strip-uuid | --locker-verbatim]");
                exit(64);
            }
        }
    }
    let mut log = Log(None);
    // Fail-closed: no UUID configured, no daemon (nothing is guessed).
    let uuid = match std::fs::read_to_string(&uuid_file).map_err(|e| e.to_string()).and_then(|s| parse_uuid(&s)) {
        Ok(u) => u,
        Err(e) => log.die(1, &format!("OS UUID unavailable ({}): {e}", uuid_file.display())),
    };
    let st = Store::load(&store).unwrap_or_else(|e| log.die(1, &format!("store {}: {e}", store.display())));
    log.0 = OpenOptions::new().create(true).append(true).open(store.join("sepd.log")).ok();
    log.line(&format!(
        "sepd: store {} (masters {:?}, lockers {}), dev {}, lockers served {}",
        store.display(),
        st.masters.keys().collect::<Vec<_>>(),
        st.lockers.len(),
        dev.display(),
        if strip { "WITHOUT UUID" } else { "VERBATIM (--locker-verbatim)" }
    ));
    let mut d = Daemon::new(st, uuid);
    d.strip_locker_uuid = strip;
    let mut f = OpenOptions::new().read(true).write(true).open(&dev).unwrap_or_else(|e| log.die(2, &format!("{}: {e}", dev.display())));
    let mut buf = vec![0u8; REC_MAX];
    loop {
        let n = match f.read(&mut buf) {
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => log.die(3, &format!("read: {e} (EIO = sep_native Halted, see dmesg)")),
        };
        let (h, b) = RecHdr::decode(&buf[..n]).unwrap_or_else(|e| log.die(3, &format!("bad record from kernel: {e}")));
        let w = h.w;
        log.line(&format!(
            "< seq {} TAG {:#04x} TYPE {:#04x} ({}) PARAM {:#04x} DATA {:#010x} B {} o",
            h.seq, w.tag, w.ty, op_name(w.ty).unwrap_or("?"), w.param, w.data, b.len()
        ));
        let r = d.answer(&w, b).unwrap_or_else(|e| log.die(4, &format!("seq {}: {e} (no reply sent)", h.seq)));
        let mut rec = RecHdr { seq: h.seq, w: r.w, len: r.a.len() as u32 }.encode().to_vec();
        rec.extend_from_slice(&r.a);
        if let Err(e) = f.write_all(&rec) {
            log.die(5, &format!("write seq {}: {e} (reply refused by the kernel? see dmesg)", h.seq));
        }
        log.line(&format!(
            "> seq {} TYPE {:#04x} PARAM {:#04x} DATA {:#010x} A {} o : {}",
            h.seq, r.w.ty, r.w.param, r.w.data, r.a.len(), r.what
        ));
    }
}
