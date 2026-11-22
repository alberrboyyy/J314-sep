//! sepd against the `snew-reel` capture (macOS 13.5 under the hypervisor, xART served by macOS from its vault) and
//! against the native branches no capture shows (empty Linux store). Read-only on `traces/`; the store is a temp dir.
use sep_proto::trace::Trace;
use sep_proto::word::{Msg, Word};
use sep_proto::xart::*;
use sep_proto::xart_gate::{declen, MASTER_PREFIX, MAX_SAVES};
use sepd::{master_type, parse_uuid, Daemon, Store};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

const SNEW: &str = "20261111-113919";

fn snew() -> Option<Trace> {
    let tr = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../traces");
    let d = std::fs::read_dir(&tr).ok()?.filter_map(|e| e.ok()).map(|e| e.path()).find(|p| {
        p.file_name().is_some_and(|n| n.to_string_lossy().starts_with(SNEW))
    })?;
    Some(Trace::read(d).unwrap())
}

fn tmpdir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("sepd-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// (request, macOS reply) pairs on EP 0x13, matched by TAG in order (as sep-proto's replay test).
fn pairs(t: &Trace) -> Vec<(Msg, Msg)> {
    let mut pending: BTreeMap<u8, Vec<Msg>> = BTreeMap::new();
    let mut out = Vec::new();
    for m in t.msgs.iter().filter(|m| m.w.ep == EP_XART) {
        if !m.to_sep() {
            pending.entry(m.w.tag).or_default().push(*m);
        } else if let Some(q) = pending.get_mut(&m.w.tag).filter(|q| !q.is_empty()) {
            out.push((q.remove(0), *m));
        }
    }
    out
}

/// Every reply of macOS is reproduced by the daemon, word AND buffer A, when the store holds what macOS served.
#[test]
fn observed_branches_match_macos() {
    let Some(t) = snew() else {
        eprintln!("SKIP: trace {SNEW} absent");
        return;
    };
    // OOL content attached to each message (line number): B for a request, A for a reply.
    let ool: BTreeMap<u32, Vec<u8>> =
        t.load_ool(EP_XART).unwrap().into_iter().filter_map(|r| Some((r.msg?.lineno, r.data))).collect();
    let ps = pairs(&t);
    assert!(ps.len() > 20);
    let mut seen: BTreeMap<u8, u32> = BTreeMap::new();
    for (req, got) in &ps {
        let dir = tmpdir(&format!("obs{}", req.lineno));
        let b_full = ool.get(&req.lineno).cloned().unwrap_or_default();
        let a_full = ool.get(&got.lineno).cloned().unwrap_or_default();
        let len = decode_fetch_len(got.w.param, got.w.data) as usize;
        let mut uuid = [0u8; 16];
        let b: Vec<u8> = match req.w.ty {
            OP_FETCH_GL => b_full[..16].to_vec(),
            ty if is_save(ty) => b_full.get(..declen(&req.w)).map(<[u8]>::to_vec).unwrap_or_else(|| vec![0xa5; declen(&req.w)]),
            _ => vec![],
        };
        match req.w.ty {
            OP_OSUUID => uuid.copy_from_slice(&a_full[..16]),
            OP_FETCH_MASTER if len > MASTER_PREFIX => {
                let name = format!("master_{}.bin", master_type(selector(req.w.data)));
                std::fs::write(dir.join(name), &a_full[MASTER_PREFIX..len]).unwrap();
            }
            OP_FETCH_GL if len > 0 => std::fs::write(dir.join(format!("locker_{}.bin", hexs(&b))), &a_full[..len]).unwrap(),
            _ => {}
        }
        let mut d = Daemon::new(Store::load(&dir).unwrap(), uuid);
        let r = d.answer(&req.w, &b).unwrap_or_else(|e| panic!("line {}: {e}", req.lineno));
        assert_eq!(r.w, got.w, "line {}: reply word", req.lineno);
        match req.w.ty {
            OP_FETCH_MASTER | OP_FETCH_GL => assert_eq!(r.a, a_full[..len], "line {}: A", req.lineno),
            OP_OSUUID => assert_eq!(r.a, uuid),
            _ => assert!(r.a.is_empty()),
        }
        if req.w.ty == OP_SAVE_XART {
            let f = dir.join(format!("master_{}.bin", master_type(selector(req.w.data))));
            assert_eq!(std::fs::read(f).unwrap(), b, "SAVE persisted before the ack");
        }
        *seen.entry(req.w.ty).or_default() += 1;
        let _ = std::fs::remove_dir_all(&dir);
    }
    // every observed request type is covered
    for ty in [OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL, OP_ABSENT, OP_EP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER] {
        assert!(seen.contains_key(&ty), "type {ty:#04x} not exercised");
    }
    println!("[sepd] {} snew pairs reproduced (word + A): {seen:x?}", ps.len());
}

fn hexs(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

const fn rq(tag: u8, ty: u8, param: u8, data: u32) -> Word {
    Word::new(EP_XART, tag, ty, param, data)
}

/// Native branches (empty Linux store): ABSENT forms, SAVE persisted then served, locker SAVE not served.
#[test]
fn native_absent_and_persist() {
    let dir = tmpdir("native");
    let uuid = parse_uuid("4c494e55-5800-0000-0000-000000000000").unwrap();
    let mut d = Daemon::new(Store::load(&dir).unwrap(), uuid);
    let r = d.answer(&rq(2, OP_FWBOOT, 0, 0), &[]).unwrap();
    assert_eq!(r.w, rq(2, 0, 0, 0x100));
    assert_eq!(d.answer(&rq(1, OP_OSUUID, 0, 0), &[]).unwrap().a, uuid);
    // master ABSENT = 0x11 zeros, length 0x11, selector re-emitted
    for sel_data in [0x000, 0x100] {
        let r = d.answer(&rq(3, OP_FETCH_MASTER, 0, sel_data), &[]).unwrap();
        assert_eq!(r.w, rq(3, 0, 0x11, sel_data));
        assert_eq!(r.a, vec![0u8; 0x11]);
    }
    // locker ABSENT = length 0
    let lu = [0x46u8; 16];
    let r = d.answer(&rq(5, OP_FETCH_GL, 0x10, 0x100), &lu).unwrap();
    assert_eq!((r.w, r.a.len()), (rq(5, 0, 0, 0x100), 0));
    assert!(d.answer(&rq(5, OP_FETCH_GL, 0x10, 0x100), &lu[..15]).is_err());
    // SAVE master (sel 1 -> type 2): persisted, acked, then served with the recomputed length
    let blob: Vec<u8> = (0..0x7f).map(|i| i as u8).collect();
    let r = d.answer(&rq(5, OP_SAVE_XART, 0x7f, 0x8929_0100), &blob).unwrap();
    assert_eq!(r.w, rq(5, 0, 0, 0x8929_0100));
    assert_eq!(std::fs::read(dir.join("master_2.bin")).unwrap(), blob);
    assert!(!dir.join(".master_2.bin.tmp").exists());
    let r = d.answer(&rq(3, OP_FETCH_MASTER, 0, 0x100), &[]).unwrap();
    let ln = MASTER_PREFIX + blob.len();
    assert_eq!(r.w, rq(3, 0, ln as u8, (ln >> 8) as u32 | 0x100));
    assert_eq!(&r.a[MASTER_PREFIX..], &blob[..]);
    // reload from disk: same store
    assert_eq!(Store::load(&dir).unwrap().masters.get(&2), Some(&blob));
    // SAVE locker: persisted, keyed by B[0..16], served back verbatim (no 0x11 prefix)
    let mut lb = lu.to_vec();
    lb.extend_from_slice(&[0xee; 0x40]);
    let r = d.answer(&rq(9, OP_SAVE_LOCKER, 0x50, 0x1234_0100), &lb).unwrap();
    assert_eq!(r.w, rq(9, 0, 0, 0x1234_0100));
    assert_eq!(std::fs::read(dir.join(format!("locker_save_{}.bin", hexs(&lu)))).unwrap(), lb);
    let r = d.answer(&rq(5, OP_FETCH_GL, 0x10, 0x100), &lu).unwrap();
    assert_eq!(r.w, rq(5, 0, lb.len() as u8, (lb.len() >> 8) as u32 | 0x100));
    assert_eq!(r.a, lb);
    assert_eq!(Store::load(&dir).unwrap().lockers.get(&lu), Some(&lb));
    // J7b: same store, locker served WITHOUT its UUID (B[16..]), length recomputed
    d.strip_locker_uuid = true;
    let r = d.answer(&rq(5, OP_FETCH_GL, 0x10, 0x100), &lu).unwrap();
    assert_eq!(r.w, rq(5, 0, (lb.len() - 16) as u8, ((lb.len() - 16) >> 8) as u32 | 0x100));
    assert_eq!(r.a, lb[16..]);
    // a stored blob not starting with its UUID: no reply (fail-closed)
    let other = [0x47u8; 16];
    d.store.lockers.insert(other, vec![0x11; 0x30]);
    assert!(d.answer(&rq(5, OP_FETCH_GL, 0x10, 0x100), &other).is_err());
    d.store.lockers.remove(&other);
    d.strip_locker_uuid = false;
    // SAVE with a B length different from the announced one: refused
    assert!(d.answer(&rq(5, OP_SAVE_XART, 0x10, 0x100), &blob).is_err());
    // announce / absent acks
    assert_eq!(d.answer(&rq(0, OP_EP_ANNOUNCE, 0x6f, 0x0073_6269), &[]).unwrap().w, rq(0, 0x16, 0, 0x0073_6200));
    assert_eq!(d.answer(&rq(4, OP_ABSENT, 0, 0), &[]).unwrap().w, rq(4, 0, 0, 0));
    // unknown TYPE: no reply
    assert!(d.answer(&rq(4, 0x42, 0, 0), &[]).is_err());
    // SAVE budget
    d.nsave = MAX_SAVES;
    assert!(d.answer(&rq(5, OP_SAVE_XART, 0x7f, 0x100), &blob).is_err());
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn uuid_parsing() {
    assert!(parse_uuid("").is_err());
    assert!(parse_uuid("4c494e55").is_err());
    assert!(parse_uuid("zz494e55580000000000000000000000").is_err());
    assert_eq!(parse_uuid(" 4c494e55580000000000000000000000\n").unwrap()[..5], *b"LINUX");
}
