//! sepd: policy and store of the xART endpoint (EP 0x13) for `sep_native`. The kernel holds neither: it hands each
//! SEP request (with its copy of buffer B) to this daemon and sends a reply only after checking it with
//! `sep_proto::xart_gate::check_reply`.
//!
//! Policy = `docs/xart_native_policy.md` (authoritative), as run on hardware by `pending/sep_native_persist.sh`:
//! - 0x0e fw-boot      -> ACK, A empty, DATA=0x100
//! - 0x13 OS UUID      -> 16 bytes of UUID in A (UUID from a config file; no file = the daemon refuses to start)
//! - 0x00 FETCH master -> in store: A = 0x11 zeros + payload; else ABSENT = 0x11 zeros (length 0x11)
//! - 0x05 FETCH locker -> UUID read in B; in store (`locker_<uuid>.bin`): served as is; else ABSENT (length 0)
//! - 0x07 absent (SEP) -> ACK
//! - 0x1d EP announce  -> ACK TYPE 0x16, DATA & 0xFFFFFF00
//! - 0x01 SAVE master  -> B persisted (`master_1.bin` USER / `master_2.bin` SEP) BEFORE the ACK is returned
//! - 0x06 SAVE locker  -> B persisted (`locker_save_<uuid>.bin`, UUID = B[0..16], verified J3) BEFORE the ACK, and
//!   served back VERBATIM on a later FETCH 0x05 with that UUID (c9, 2026-11-22: on a chained boot, sbio stays unarmed
//!   if lockers are ABSENT; serving form = hypothesis to confirm on hardware)
//! - anything else     -> error: the daemon stops WITHOUT replying (fail-closed).
use sep_proto::word::Word;
use sep_proto::xart::*;
use sep_proto::xart_gate::{self, check_reply, declen, MASTER_PREFIX, MAX_SAVES, RESP_ANNOUNCE, RESP_DONE, UUID_LEN};
use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub const DEFAULT_STORE: &str = "/var/lib/sepd";
pub const DEFAULT_UUID_FILE: &str = "/etc/sepd/os_uuid";
pub const DEFAULT_DEV: &str = "/dev/sep_native";

/// Master type stored for a selector (script: `2 if sel & 1 else 1`; 1 = USER-xART, 2 = SEP-xART).
pub const fn master_type(sel: u8) -> u8 {
    if sel & 1 != 0 { T_SEP_MASTER } else { T_USER_MASTER }
}

/// Parses an OS UUID: 32 hex digits, dashes and surrounding whitespace allowed.
pub fn parse_uuid(s: &str) -> Result<[u8; UUID_LEN], String> {
    let h: String = s.trim().chars().filter(|&c| c != '-').collect();
    if h.len() != 2 * UUID_LEN || !h.bytes().all(|c| c.is_ascii_hexdigit()) {
        return Err(format!("OS UUID: 32 hex digits expected, got {:?}", s.trim()));
    }
    let mut u = [0u8; UUID_LEN];
    for (i, b) in u.iter_mut().enumerate() {
        *b = u8::from_str_radix(&h[2 * i..2 * i + 2], 16).map_err(|e| e.to_string())?;
    }
    Ok(u)
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// tmp file + fsync + rename + fsync of the directory: the blob is durable before the function returns.
pub fn write_atomic(dir: &Path, name: &str, data: &[u8]) -> io::Result<()> {
    let tmp = dir.join(format!(".{name}.tmp"));
    {
        let mut f = File::create(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    fs::rename(&tmp, dir.join(name))?;
    File::open(dir)?.sync_all()
}

/// The persistent xART store of Linux (a directory).
#[derive(Debug, Default)]
pub struct Store {
    pub dir: PathBuf,
    /// type (1 USER / 2 SEP) -> payload served after the 0x11-byte prefix.
    pub masters: BTreeMap<u8, Vec<u8>>,
    /// UUID -> bytes served as is in A for a locker FETCH.
    pub lockers: BTreeMap<[u8; UUID_LEN], Vec<u8>>,
}

impl Store {
    pub fn load(dir: &Path) -> io::Result<Store> {
        fs::create_dir_all(dir)?;
        let mut st = Store { dir: dir.to_path_buf(), ..Default::default() };
        for e in fs::read_dir(dir)? {
            let e = e?;
            let name = e.file_name().to_string_lossy().into_owned();
            if let Some(t) = name.strip_prefix("master_").and_then(|r| r.strip_suffix(".bin")) {
                if let Ok(t @ (T_USER_MASTER | T_SEP_MASTER)) = t.parse::<u8>() {
                    st.masters.insert(t, fs::read(e.path())?);
                }
            } else if let Some(u) = name.strip_prefix("locker_save_").and_then(|r| r.strip_suffix(".bin")) {
                // B of a locker SAVE, served back verbatim (c9 2026-11-22, after J3: sbio stays unarmed when
                // lockers are answered ABSENT on a chained boot). An explicit `locker_<uuid>.bin` wins.
                if let Ok(u) = parse_uuid(u) {
                    let blob = fs::read(e.path())?;
                    st.lockers.entry(u).or_insert(blob);
                }
            } else if let Some(u) = name.strip_prefix("locker_").and_then(|r| r.strip_suffix(".bin")) {
                if let Ok(u) = parse_uuid(u) {
                    st.lockers.insert(u, fs::read(e.path())?);
                }
            }
        }
        Ok(st)
    }

    fn put_master(&mut self, t: u8, blob: &[u8]) -> io::Result<()> {
        write_atomic(&self.dir, &format!("master_{t}.bin"), blob)?;
        self.masters.insert(t, blob.to_vec());
        Ok(())
    }

    fn put_locker_save(&self, uuid: &[u8], blob: &[u8]) -> io::Result<()> {
        write_atomic(&self.dir, &format!("locker_save_{}.bin", hex(uuid)), blob)
    }
}

/// A reply: mailbox word (EP 0x13, TAG of the request) and the bytes the kernel puts in A.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reply {
    pub w: Word,
    pub a: Vec<u8>,
    /// Human summary for the log.
    pub what: String,
}

pub struct Daemon {
    pub store: Store,
    pub os_uuid: [u8; UUID_LEN],
    pub nsave: u32,
}

impl Daemon {
    pub fn new(store: Store, os_uuid: [u8; UUID_LEN]) -> Self {
        Daemon { store, os_uuid, nsave: 0 }
    }

    /// Reply to the SEP request `req` (`b` = copy of buffer B made by the kernel). For a SAVE the blob is durable
    /// on disk when this returns Ok. Err = stop without replying.
    pub fn answer(&mut self, req: &Word, b: &[u8]) -> Result<Reply, String> {
        let sel = selector(req.data);
        let w = |ty, param, data| Word::new(req.ep, req.tag, ty, param, data);
        let ack = req.data & xart_gate::ACK_MASK;
        let r = match req.ty {
            OP_FWBOOT => Reply { w: w(RESP_DONE, 0, xart_gate::FWBOOT_ACK_DATA), a: vec![], what: "fw-boot ack".into() },
            OP_OSUUID => Reply { w: w(RESP_DONE, 0, 0), a: self.os_uuid.to_vec(), what: format!("OS UUID {}", hex(&self.os_uuid)) },
            OP_FETCH_MASTER => {
                let t = master_type(sel);
                let mut a = vec![0u8; MASTER_PREFIX];
                let what = match self.store.masters.get(&t) {
                    Some(p) => {
                        a.extend_from_slice(p);
                        format!("master t{t} SERVED ({} o)", a.len())
                    }
                    None => format!("master t{t} ABSENT"),
                };
                let (p, d) = encode_fetch_len(a.len(), sel).map_err(|e| e.to_string())?;
                Reply { w: w(RESP_DONE, p, d), a, what }
            }
            OP_FETCH_GL => {
                let uuid: [u8; UUID_LEN] = b.try_into().map_err(|_| format!("FETCH locker: B = {} o, 16 expected", b.len()))?;
                let (a, what) = match self.store.lockers.get(&uuid) {
                    Some(p) => (p.clone(), format!("locker {} SERVED ({} o)", hex(&uuid), p.len())),
                    None => (vec![], format!("locker {} ABSENT", hex(&uuid))),
                };
                let (p, d) = encode_fetch_len(a.len(), sel).map_err(|e| e.to_string())?;
                Reply { w: w(RESP_DONE, p, d), a, what }
            }
            OP_ABSENT => Reply { w: w(RESP_DONE, 0, 0), a: vec![], what: "absent (SEP) ack".into() },
            OP_EP_ANNOUNCE => {
                let mut name: String = [16, 8, 0].iter().map(|s| ((req.data >> s) as u8) as char).collect();
                name.push(req.param as char);
                Reply { w: w(RESP_ANNOUNCE, 0, ack), a: vec![], what: format!("announce '{name}' ack") }
            }
            OP_SAVE_XART | OP_SAVE_LOCKER => {
                if self.nsave >= MAX_SAVES {
                    return Err(format!("SAVE budget reached ({MAX_SAVES}) without stabilisation"));
                }
                if b.len() != declen(req) {
                    return Err(format!("SAVE: B = {} o, length {} announced", b.len(), declen(req)));
                }
                let what = if req.ty == OP_SAVE_XART {
                    let t = master_type(sel);
                    self.store.put_master(t, b).map_err(|e| format!("SAVE master: {e}"))?;
                    format!("SAVE master t{t} PERSISTED ({} o)", b.len())
                } else {
                    let uuid = b.get(..UUID_LEN).ok_or("SAVE locker: B shorter than a UUID")?;
                    self.store.put_locker_save(uuid, b).map_err(|e| format!("SAVE locker: {e}"))?;
                    if let Ok(k) = <[u8; UUID_LEN]>::try_from(uuid) {
                        self.store.lockers.insert(k, b.to_vec());
                    }
                    format!("SAVE locker {} PERSISTED ({} o, served verbatim on FETCH)", hex(uuid), b.len())
                };
                self.nsave += 1;
                Reply { w: w(RESP_DONE, 0, ack), a: vec![], what: format!("{what} [SAVE #{}/{MAX_SAVES}]", self.nsave) }
            }
            t => return Err(format!("unknown 0x13 request TYPE {t:#04x}")),
        };
        // Same gate as the kernel: a reply the kernel would refuse is a daemon bug, caught here first.
        check_reply(req, &r.w, &r.a, true).map_err(|e| format!("reply refused by the gate: {e}"))?;
        Ok(r)
    }
}
