//! Replay of the captures in `traces/`: same oracles as `driver/tests/*.py` (the Python reference), so the Rust
//! port must reproduce exactly the same counts. Read-only; a missing capture skips the test (prints SKIP).
use sep_proto::discovery::{cntl_opens, CntlOpen, DiscoveryTable};
use sep_proto::gt::{self, check_counters, check_slices, reassemble, Transfer, IMAGE_LEN, SLICES_PER_IMAGE, SLICE_LEN, T_IMAGE};
use sep_proto::daemon::{blob_uid, export_request, init_plan, BlobStore, INIT_SEQUENCE, T_EXPORT, T_IMPORT};
use sep_proto::sensor::{parse_status, status_from_uart_line};
use sep_proto::trace::Trace;
use sep_proto::word::{Dir, Msg, Word};
use sep_proto::xart::{self, *};
use sep_proto::xart_responder::{self as resp, FetchDecision, Kind};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

const C6: &str = "20261107-043828";
const C8: &str = "20261108-004657";
const C9: &str = "20261108-010915";
const C10B: &str = "20261108-012015";
const C11: &str = "20261108-025802";
const C12: &str = "20261108-032454";
const C20: &str = "20261110-003201";
const SNEW: &str = "20261111-113919";
const BOOTS: [&str; 8] = ["20261107-043309", C6, "20261107-045400", C8, C9, C10B, C11, C12];

fn traces() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../traces")
}

fn trace_dir(prefix: &str) -> Option<PathBuf> {
    let mut v: Vec<_> = std::fs::read_dir(traces()).ok()?.filter_map(|e| e.ok()).map(|e| e.file_name().into_string().unwrap()).collect();
    v.sort();
    v.into_iter().find(|d| d.starts_with(prefix) || d.contains(&format!("_{prefix}"))).map(|d| traces().join(d))
}

macro_rules! tr {
    ($p:expr) => {
        match trace_dir($p) {
            Some(d) => Trace::read(d).unwrap(),
            None => {
                eprintln!("SKIP: trace {} absent", $p);
                return;
            }
        }
    };
}

fn all_sep_logs() -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(traces())
        .map(|r| r.filter_map(|e| e.ok()).map(|e| e.path().join("sep.log")).filter(|p| p.is_file()).collect())
        .unwrap_or_default();
    v.sort();
    v
}

// ---- step 1: words -------------------------------------------------------------------------------
#[test]
fn step1_counts_and_roundtrip() {
    for (p, n) in [(C8, 3981), (C11, 6348), (C12, 641)] {
        let t = tr!(p);
        assert_eq!(t.msgs.len(), n, "{p}");
        assert_eq!((t.end_seen, t.end_logged), (Some(n as u64), Some(n as u64)));
        assert!(t.bad_lines.is_empty(), "{p}: {:?}", &t.bad_lines[..t.bad_lines.len().min(5)]);
        for m in &t.msgs {
            assert_eq!(Word::decode(m.w.encode()), m.w);
        }
    }
}

#[test]
fn step1_ool_reads() {
    let t = tr!(C11);
    assert_eq!(t.ool.len(), 994);
    assert!(t.ool.iter().all(|o| o.msg.is_some()));
    assert_eq!(tr!(C8).ool.len(), 480);
    assert_eq!(tr!(C12).ool.len(), 151);
}

// ---- step 2: discovery ---------------------------------------------------------------------------
#[test]
fn step2_all_boots_same_12_eps() {
    let expected: BTreeMap<u8, &str> = [(0x00, "cntl"), (0x08, "sbio"), (0x0a, "scrd"), (0x0c, "sse"), (0x0e, "hdcp"),
        (0x10, "xars"), (0x12, "sks"), (0x13, "xarm"), (0x14, "hibe"), (0x15, "pnon"), (0x17, "skdl"), (0x18, "stac")]
        .into_iter().collect();
    let mut orders = Vec::new();
    for p in BOOTS {
        let t = tr!(p);
        let tab = DiscoveryTable::from_msgs(&t.msgs).unwrap();
        let got: BTreeMap<u8, &str> = tab.by_ep.keys().map(|&e| (e, tab.name_of(e).unwrap())).collect();
        assert_eq!(got, expected, "{p}");
        assert_eq!(tab.find("sbio"), Some(0x08));
        assert_eq!(tab.find("sks"), Some(0x12));
        assert_eq!(tab.find("zzzz"), None);
        orders.push(tab.order.clone());
    }
    // the order varies (3 orders over 8 boots), the first 4 are stable: never depend on the order
    assert_eq!(orders.iter().map(|o| o[..4].to_vec()).collect::<BTreeSet<_>>().len(), 1);
    assert_eq!(orders.iter().cloned().collect::<BTreeSet<_>>().len(), 3);
}

#[test]
fn step2_sizes_vs_cntl() {
    let (mut checked, mut bad) = (0, 0);
    for p in BOOTS {
        let t = tr!(p);
        let tab = DiscoveryTable::from_msgs(&t.msgs).unwrap();
        for (ep, seqs) in cntl_opens(&t.msgs) {
            for s in seqs {
                checked += 1;
                let i = &tab.by_ep[&ep];
                if (Some(s.send_size as u32), Some(s.recv_size as u32)) != (i.max_send(), i.max_recv()) {
                    bad += 1;
                }
            }
        }
    }
    assert!(checked > 0);
    assert_eq!(bad, 0);
    println!("[step2] FD sizes <-> CNTL T4/T5: {}/{checked}", checked - bad);
    let t = tr!(C11);
    assert_eq!(cntl_opens(&t.msgs)[&0x08], vec![CntlOpen { send_size: 0x4000, send_addr: 0x64000, recv_size: 0x4000, recv_addr: 0x6c000 }]);
}

// ---- step 3: sensor ------------------------------------------------------------------------------
#[test]
fn step3_all_uart_logs() {
    const STATUS: [u8; 16] = [0x80, 0x20, 0, 0x10, 0, 0, 0, 0, 0x60, 0, 0, 0, 0x52, 0x33, 0, 0];
    let mut logs: Vec<PathBuf> = std::fs::read_dir(traces()).map(|r| r.filter_map(|e| e.ok()).map(|e| e.path().join("hv_uart.log")).filter(|p| p.is_file()).collect()).unwrap_or_default();
    logs.sort();
    if logs.is_empty() { eprintln!("SKIP: no hv_uart.log"); return; }
    let (mut found, mut same) = (0, 0);
    for p in logs {
        let txt = String::from_utf8_lossy(&std::fs::read(p).unwrap()).into_owned();
        for line in txt.lines() {
            if let Some(r) = status_from_uart_line(line) {
                let raw = r.unwrap();
                found += 1;
                same += (raw == STATUS) as usize;
            }
        }
    }
    assert!(found >= 16);
    assert_eq!(found, same);
    assert!(parse_status(&STATUS).is_ok());
    println!("[step3] sensor status identical in {same}/{found} traces");
}

// ---- step 4: GT ----------------------------------------------------------------------------------
fn images(t: &Trace) -> Vec<Transfer> {
    reassemble(&t.load_ool(8).unwrap(), 8, Some(&[T_IMAGE])).into_iter().filter(|x| x.total > 0 && x.dir == Dir::ToSep && x.buf == b'A').collect()
}

#[test]
fn step4_counter_rule_all_traces() {
    let (mut tot, mut ntr) = (0, 0);
    for p in all_sep_logs() {
        let t = Trace::read(&p).unwrap();
        let (n, bad) = check_counters(&t.msgs, 0x08);
        assert!(bad.is_empty(), "{}: {:?}", p.display(), &bad[..bad.len().min(3)]);
        tot += n;
        ntr += (n > 0) as usize;
    }
    if ntr == 0 { eprintln!("SKIP: no traces"); return; }
    assert!(tot > 4006);
    println!("[step4] GT counter: {tot} fc/fd/fe messages over {ntr} traces, 0 exceptions");
}

#[test]
fn step4_ool_sha_integrity() {
    let mut n = 0;
    for p in [C6, C8, C11, C12] {
        for r in tr!(p).load_ool(8).unwrap() {
            assert_ne!(r.sha_ok, Some(false), "line {}", r.lineno);
            n += (r.sha_ok == Some(true)) as usize;
        }
    }
    assert!(n > 0);
}

#[test]
fn step4_c11_24_images_288_slices() {
    let im = images(&tr!(C11));
    assert_eq!(im.len(), 24);
    assert!(im.iter().all(|t| t.complete() && t.total as usize == IMAGE_LEN && t.blob().len() == IMAGE_LEN));
    assert!(im.iter().all(|t| t.chunks.len() == 2 || t.chunks.len() == 3));
    let ok: usize = im.iter().map(|t| check_slices(&t.blob(), SLICE_LEN, SLICES_PER_IMAGE).iter().filter(|&&b| b).count()).sum();
    assert_eq!(ok, 288);
    // corruption detected in the right slice
    let mut b = im[0].blob();
    b[SLICE_LEN * 5 + 100] ^= 1;
    let res = check_slices(&b, SLICE_LEN, SLICES_PER_IMAGE);
    assert_eq!(res.iter().enumerate().filter(|(_, &o)| !o).map(|(k, _)| k).collect::<Vec<_>>(), vec![5]);
    // re-fragmenting the reassembled image gives back the same payload (sender side)
    let recs: Vec<_> = gt::fragment(T_IMAGE, &im[0].blob()).into_iter().map(|data| gt::OolRecord {
        lineno: 0, dir: Dir::ToSep, buf: b'A', msg: Some(Msg::new(0, Dir::ToSep, Word::new(8, gt::TAG_FC, T_IMAGE, 0, 0))), data, sha_ok: None,
    }).collect();
    assert_eq!(reassemble(&recs, 8, None)[0].blob(), im[0].blob());
}

#[test]
fn step4_all_sessions_39_images_468_slices() {
    let (mut n_img, mut n_ok) = (0, 0);
    for p in [C6, C8, C11] {
        let im = images(&tr!(p));
        n_img += im.iter().filter(|t| t.complete() && t.total as usize == IMAGE_LEN).count();
        n_ok += im.iter().map(|t| check_slices(&t.blob(), SLICE_LEN, SLICES_PER_IMAGE).iter().filter(|&&b| b).count()).sum::<usize>();
    }
    assert_eq!((n_img, n_ok), (39, 468));
    println!("[step4] C6+C8+C11: {n_img}/39 images, {n_ok}/468 slices CRC OK");
}

#[test]
fn step4_fixed_sizes_c11_c12() {
    for p in [C11, C12] {
        let t = tr!(p);
        let ts: Vec<_> = reassemble(&t.load_ool(8).unwrap(), 8, Some(&[0x5B, 0x5F])).into_iter().filter(|x| x.total > 2).collect();
        assert!(ts.iter().all(|x| x.complete()));
        assert_eq!(ts.iter().map(|x| (x.ty, x.total)).collect::<Vec<_>>(), vec![(0x5F, 0x568E), (0x5B, 0xFC99), (0x5F, 0x70CE)]);
    }
}

// ---- bio (J6): the match wire sequence and the 0x09 verdict ------------------------------------
#[test]
fn bio_verdict_c20_c11_c8_c6() {
    use sep_proto::bio::{parse_verdict, Verdict, UID_MATCH, VERDICT_LEN};
    let mut total = 0;
    for p in [C20, C11, C8, C6] {
        let t = tr!(p);
        let verdicts: Vec<Transfer> =
            reassemble(&t.load_ool(8).unwrap(), 8, Some(&[0x09])).into_iter().filter(|x| x.buf == b'B' && x.dir == Dir::ToAp && x.total as usize == VERDICT_LEN).collect();
        for v in &verdicts {
            // The tracer may cap an OOL dump (C20: 0x400 bytes), while the gt header declares the real total 0xca2;
            // the driver always gets the complete reply. The verdict fields are in the first 20 bytes, so pad the
            // (possibly truncated) dump to the declared length before parsing (tail = image metadata, not read).
            let mut info = v.blob();
            assert!(info.len() >= 20, "{p} line {}: 0x09 dump too short ({} bytes)", v.line, info.len());
            info.resize(VERDICT_LEN, 0);
            match parse_verdict(&info) {
                // every documented verdict is either a 501 success or a clean no-match (0 false positive).
                Verdict::Match { uid, .. } => assert_eq!(uid, UID_MATCH, "{p} line {}", v.line),
                Verdict::NoMatch => {}
                Verdict::BadLen(n) => panic!("{p} line {}: match_info_t {n} bytes", v.line),
            }
        }
        total += verdicts.len();
    }
    if total == 0 {
        eprintln!("SKIP: no finger traces");
        return;
    }
    assert!(total >= 7, "{total} verdicts");
    println!("[bio] {total} 0x09 verdicts parsed (match_info_t 0xca2), 0 bad length, 0 false positive");
}

#[test]
fn bio_match_wire_sequence_c20() {
    use sep_proto::bio::MATCH_SEQUENCE;
    let t = tr!(C20);
    // The ordered opcodes of the match core must appear as a subsequence of C20's sbio commands (AP->SEP, TAG 0xfc).
    let core: Vec<u8> = MATCH_SEQUENCE.iter().map(|s| s.op).collect();
    let cmds: Vec<u8> = t.msgs.iter().filter(|m| m.w.ep == 8 && m.to_sep() && m.w.tag == gt::TAG_FC).map(|m| m.w.ty).collect();
    // find the first window where 0x23..0x09 appears in order (0x1e optional between 0x07 and 0x09).
    let mut found = false;
    for start in 0..cmds.len() {
        let mut i = start;
        let mut ok = true;
        for &op in &core {
            if op == 0x1e {
                // optional retry step
                if cmds.get(i) == Some(&0x1e) {
                    i += 1;
                }
                continue;
            }
            match cmds[i..].iter().position(|&c| c == op) {
                Some(0) => i += 1,
                _ => {
                    ok = false;
                    break;
                }
            }
        }
        if ok {
            found = true;
            break;
        }
    }
    assert!(found, "match core 0x23 06 65 07 [1e] 09 1f 22 0b not found in order in C20");
    println!("[bio] C20: match core sequence (0x23 06 65 07 [1e] 09 1f 22 0b) found in order");
}

// ---- step 5: daemon ------------------------------------------------------------------------------
fn ap_cmds(t: &Trace) -> Vec<u8> {
    t.msgs.iter().filter(|m| m.w.ep == 8 && m.w.tag == 0xFC && m.to_sep()).map(|m| m.w.ty).collect()
}
fn imports(t: &Trace) -> Vec<Transfer> {
    reassemble(&t.load_ool(8).unwrap(), 8, Some(&[T_IMPORT])).into_iter().filter(|x| x.total > 0 && x.dir == Dir::ToSep && x.buf == b'A').collect()
}
fn exports(t: &Trace) -> Vec<(Transfer, Transfer)> {
    let ts = reassemble(&t.load_ool(8).unwrap(), 8, Some(&[T_EXPORT]));
    let mut out = Vec::new();
    for (i, x) in ts.iter().enumerate() {
        if x.total > 0x18 && x.dir == Dir::ToAp && x.buf == b'B' {
            let req = ts[..i].iter().rev().find(|r| r.total == 0x18).unwrap().clone();
            out.push((req, x.clone()));
        }
    }
    out
}

#[test]
fn step5_57_commands_on_all_captures() {
    let trs: Vec<Trace> = all_sep_logs().into_iter().map(|p| Trace::read(p).unwrap()).filter(|t| !ap_cmds(t).is_empty()).collect();
    if trs.is_empty() { eprintln!("SKIP"); return; }
    let n = trs.iter().filter(|t| ap_cmds(t).get(..57) == Some(&INIT_SEQUENCE[..])).count();
    assert!(trs.len() >= 18); // 18 when the Python test was written (C1-C12); 23 since c13-c25
    assert_eq!(n, trs.len());
    println!("[step5] 57-command init sequence reproduced exactly: {n}/{} captures with sbio", trs.len());
}

fn plan_imports(store: &BlobStore) -> Vec<Option<Vec<u8>>> {
    init_plan(store).into_iter().filter(|c| c.0 == T_IMPORT).map(|c| c.1.map(<[u8]>::to_vec)).collect()
}

#[test]
fn step5_c11_to_c12_exact_and_headers() {
    let c11 = tr!(C11);
    let ex = exports(&c11);
    assert_eq!(ex.len(), 14);
    let mut store = BlobStore::new();
    for (req, r) in &ex {
        assert_eq!(req.blob(), export_request(blob_uid(&r.blob()).unwrap()));
        assert!(r.complete());
        store.on_export(&r.blob()).unwrap();
    }
    assert_eq!(ex.iter().map(|(_, r)| blob_uid(&r.blob()).unwrap()).collect::<BTreeSet<_>>(), [501, 0xFFFF_FFFF].into());
    let sent: Vec<Vec<u8>> = imports(&tr!(C12)).iter().map(Transfer::blob).collect();
    assert_eq!(sent.len(), 2);
    let plan = plan_imports(&store);
    assert_eq!(plan.iter().zip(&sent).filter(|(p, s)| p.as_ref() == Some(*s)).count(), 2);
}

#[test]
fn step5_c9_persistence_to_c11() {
    let mut store = BlobStore::new();
    for t in imports(&tr!(C9)) {
        store.on_export(&t.blob()).unwrap();
    }
    let sent: Vec<Vec<u8>> = imports(&tr!(C11)).iter().map(Transfer::blob).collect();
    assert_eq!(plan_imports(&store).iter().zip(&sent).filter(|(p, s)| p.as_ref() == Some(*s)).count(), 2);
    assert_eq!(imports(&tr!(C10B)).len(), 2);
}

#[test]
fn step5_c8_to_c9_partial() {
    let exp = exports(&tr!(C8));
    let mut store = BlobStore::new();
    for (_, r) in &exp {
        if r.complete() {
            store.on_export(&r.blob()).unwrap();
        }
    }
    let sent = imports(&tr!(C9));
    assert_eq!(plan_imports(&store)[0].as_deref(), Some(&sent[0].blob()[..]));
    let last = exp.iter().map(|(_, r)| r).rev().find(|r| blob_uid(&r.blob()).unwrap() == 501).unwrap();
    assert!(!last.complete());
    assert_eq!(last.total, sent[1].total);
    assert_eq!(last.chunks.keys().copied().collect::<Vec<_>>(), vec![0, 16356, 32712]);
    for (off, piece) in &last.chunks {
        assert_eq!(&sent[1].chunks[off][..piece.len()], &piece[..]);
    }
}

// ---- steps 6-7: xART ------------------------------------------------------------------------------
fn coffre() -> Option<Vec<u8>> {
    let mut hits: Vec<PathBuf> = std::fs::read_dir(traces()).ok()?.filter_map(|e| e.ok()).map(|e| e.path())
        .filter(|p| p.file_name().unwrap().to_string_lossy().ends_with("_xart_read")).flat_map(|d| std::fs::read_dir(d).unwrap())
        .filter_map(|e| e.ok()).map(|e| e.path()).filter(|p| p.to_string_lossy().ends_with(".gl.bin")).collect();
    hits.sort();
    hits.first().map(|p| std::fs::read(p).unwrap())
}

#[test]
fn step6_coffre() {
    let Some(raw) = coffre() else { eprintln!("SKIP: no .gl vault"); return };
    let ls = xart::parse_coffre(&raw).unwrap();
    assert_eq!(ls.len(), 12);
    assert_eq!(ls.iter().filter(|l| l.is_master()).count(), 2);
    let sep = find_master(&ls, SEL_SEP).unwrap();
    let usr = find_master(&ls, SEL_USER).unwrap();
    assert_eq!((sep.ty, sep.length, sep.payload.len()), (0x02, 0x352, 0x352));
    assert_eq!((usr.ty, usr.length), (0x01, 0x540));
    let uuid = [0x86, 0x24, 0x49, 0x7a, 0x8c, 0x2f, 0xf2, 0x58, 0x26, 0x25, 0xa0, 0x36, 0xfa, 0xb3, 0xb8, 0xe3];
    assert!(is_gigalocker_type(find_gigalocker(&ls, &uuid).unwrap().ty));
    assert!(find_gigalocker(&ls, &[0; 16]).is_none());
    for l in &ls {
        assert!(l.crc_ok(), "CRC slot {}", l.slot);
        assert_eq!(serialize_locker(l).unwrap(), raw[l.slot * SLOT..(l.slot + 1) * SLOT], "slot {}", l.slot);
    }
    assert!(matches!(resp::native_fetch_decision(&ls, &Word::new(EP_XART, 0, OP_FETCH_MASTER, 0, 0x100)).unwrap(), FetchDecision::Serve(l) if l.is_master()));
}

fn xart_pairs(t: &Trace) -> Vec<(Msg, Msg)> {
    let mut pending: BTreeMap<u8, Vec<Msg>> = BTreeMap::new();
    let mut out = Vec::new();
    for m in t.msgs.iter().filter(|m| m.w.ep == EP_XART) {
        if !m.to_sep() {
            pending.entry(m.w.tag).or_default().push(*m);
        } else if let Some(q) = pending.get_mut(&m.w.tag) {
            if !q.is_empty() {
                out.push((q.remove(0), *m));
            }
        }
    }
    out
}

#[test]
fn step6_snew_opening() {
    let t = tr!(SNEW);
    let reqs: Vec<&Msg> = t.msgs.iter().filter(|m| m.w.ep == EP_XART && !m.to_sep()).collect();
    assert!(reqs.len() > 5);
    assert_eq!(op_name(reqs[0].w.ty), Some("fwboot"));
    assert_eq!(op_name(reqs[1].w.ty), Some("osuuid"));
    assert!(reqs.iter().filter(|m| m.w.ty == OP_FETCH_MASTER).all(|m| matches!(selector(m.w.data), SEL_USER | SEL_SEP)));
}

#[test]
fn step7_responder_reproduces_snew() {
    let pairs = xart_pairs(&tr!(SNEW));
    assert!(pairs.len() > 20);
    let (mut acks, mut fetches, mut kinds) = (0, 0, BTreeSet::new());
    for (req, got) in &pairs {
        let fetch = matches!(req.w.ty, OP_FETCH_MASTER | OP_FETCH_GL);
        let served = fetch.then(|| decode_fetch_len(got.w.param, got.w.data) as usize);
        let r = resp::observed_response(&req.w, served).unwrap();
        kinds.insert(format!("{:?}", r.kind));
        // the full reply word is reproduced exactly (EP, TAG, TYPE, PARAM, DATA)
        assert_eq!(r.word(), got.w, "req {:?}", req.w);
        if fetch { fetches += 1 } else { acks += 1 }
        if r.kind == Kind::AckSave { assert_eq!(got.w.data, req.w.data & 0xFFFF_FF00) }
    }
    assert!(acks > 8 && fetches > 5);
    println!("[step7] {} 0x13 pairs reproduced exactly ({acks} acks, {fetches} FETCH); {kinds:?}", pairs.len());
}
