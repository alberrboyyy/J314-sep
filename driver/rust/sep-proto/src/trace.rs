//! Offline reader of the captures in `traces/` (`sep.log` + `.ool/` files). `std` only; read-only.
//!
//! Line format (defined by the tracer): `<ts> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x..`
//! (`>` AP->SEP, `<` SEP->AP), plus comments `# ool ...`, `# ool learn ...`, `# epname ...`, `# end ... seen=N logged=N`.
use crate::gt::OolRecord;
use crate::word::{Dir, Msg, Word};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// `# ool ...` line: a read of an OOL buffer, attached to the preceding message.
#[derive(Debug, Clone)]
pub struct OolRead {
    pub lineno: u32,
    pub seq: u64,
    pub ep: u8,
    pub dir: Dir,
    pub buf: u8,
    pub sha: String,
    pub length: usize,
    pub changed: String,
    pub file: Option<String>,
    pub msg: Option<Msg>,
}

#[derive(Debug, Clone, Default)]
pub struct Trace {
    pub path: PathBuf,
    pub msgs: Vec<Msg>,
    pub ool: Vec<OolRead>,
    pub end_seen: Option<u64>,
    pub end_logged: Option<u64>,
    pub bad_lines: Vec<u32>,
}

fn hex<T: TryFrom<u64>>(s: &str, prefix: &str, max_digits: usize) -> Option<T> {
    let h = s.strip_prefix(prefix)?;
    if h.is_empty() || h.len() > max_digits || !h.bytes().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    T::try_from(u64::from_str_radix(h, 16).ok()?).ok()
}

fn parse_msg(line: &str, lineno: u32) -> Option<Msg> {
    let mut it = line.split(' ');
    let ts = it.next()?;
    let mut dots = 0;
    if ts.is_empty() || !ts.bytes().all(|c| c.is_ascii_digit() || (c == b'.' && { dots += 1; dots == 1 })) || ts.starts_with('.') || ts.ends_with('.') {
        return None;
    }
    let dir = match it.next()? {
        ">" => Dir::ToSep,
        "<" => Dir::ToAp,
        _ => return None,
    };
    let ep = hex(it.next()?, "EP=0x", 2)?;
    let tag = hex(it.next()?, "TAG=0x", 2)?;
    let ty = hex(it.next()?, "TYPE=0x", 2)?;
    let param = hex(it.next()?, "PARAM=0x", 2)?;
    let data_tok = it.next()?;
    let data = hex(data_tok.trim_end(), "DATA=0x", 8)?;
    if it.any(|t| !t.trim().is_empty()) {
        return None;
    }
    Some(Msg::new(lineno, dir, Word::new(ep, tag, ty, param, data)))
}

/// Capture directory or file -> path of `sep.log`.
pub fn resolve(p: &Path) -> PathBuf {
    if p.is_dir() { p.join("sep.log") } else { p.to_path_buf() }
}

impl Trace {
    pub fn ooldir(&self) -> PathBuf {
        let mut s = self.path.clone().into_os_string();
        s.push(".ool");
        PathBuf::from(s)
    }

    pub fn read(p: impl AsRef<Path>) -> std::io::Result<Trace> {
        let path = resolve(p.as_ref());
        let raw = std::fs::read(&path)?;
        let text = String::from_utf8_lossy(&raw);
        let mut tr = Trace { path, ..Default::default() };
        let mut last: Option<Msg> = None;
        for (i, line) in text.split('\n').enumerate() {
            let n = (i + 1) as u32;
            let line = line.strip_suffix('\r').unwrap_or(line);
            if line.trim().is_empty() {
                continue;
            }
            if let Some(rest) = line.strip_prefix("# ool ") {
                let mut parts = rest.split_whitespace();
                let ts = parts.next().unwrap_or("");
                if !ts.is_empty() && ts.bytes().all(|c| c.is_ascii_digit() || c == b'.') {
                    let kv: BTreeMap<&str, &str> = parts.filter_map(|p| p.split_once('=')).collect();
                    if let (Some(buf), Some(sha)) = (kv.get("buf"), kv.get("sha")) {
                        let rd = (|| {
                            Some(OolRead {
                                lineno: n,
                                seq: kv.get("seq")?.parse().ok()?,
                                ep: u8::from_str_radix(kv.get("EP")?.trim_start_matches("0x"), 16).ok()?,
                                dir: match *kv.get("dir")? { ">" => Dir::ToSep, "<" => Dir::ToAp, _ => return None },
                                buf: *buf.as_bytes().first()?,
                                sha: sha.to_string(),
                                length: usize::from_str_radix(kv.get("len")?.trim_start_matches("0x"), 16).ok()?,
                                changed: kv.get("changed").unwrap_or(&"").to_string(),
                                file: kv.get("file").map(|s| s.to_string()),
                                msg: last,
                            })
                        })();
                        match rd {
                            Some(r) => tr.ool.push(r),
                            None => tr.bad_lines.push(n),
                        }
                    }
                }
                continue;
            }
            if let Some(rest) = line.strip_prefix("# end ") {
                let mut seen = None;
                let mut logged = None;
                for p in rest.split_whitespace().skip(1) {
                    if let Some(v) = p.strip_prefix("seen=") { seen = v.parse().ok(); }
                    if let Some(v) = p.strip_prefix("logged=") { logged = v.parse().ok(); }
                }
                if seen.is_some() && logged.is_some() {
                    tr.end_seen = seen;
                    tr.end_logged = logged;
                }
                continue;
            }
            if line.starts_with('#') {
                continue;
            }
            match parse_msg(line, n) {
                Some(m) => {
                    last = Some(m);
                    tr.msgs.push(m);
                }
                None => tr.bad_lines.push(n),
            }
        }
        Ok(tr)
    }

    /// Attach every `# ool` of `ep` to its content. `changed=none` -> last .bin with the same (buf, len): the tracer
    /// only compares with the previous read of the same buffer and length.
    pub fn load_ool(&self, ep: u8) -> std::io::Result<Vec<OolRecord>> {
        let mut out = Vec::new();
        let mut last: BTreeMap<(u8, usize), String> = BTreeMap::new();
        let dir = self.ooldir();
        for o in self.ool.iter().filter(|o| o.ep == ep) {
            let key = (o.buf, o.length);
            if let Some(f) = &o.file {
                last.insert(key, f.clone());
            }
            let (data, sha_ok) = match last.get(&key) {
                Some(f) => {
                    let d = std::fs::read(dir.join(f))?;
                    let ok = sha256_hex8(&d) == o.sha;
                    (d, Some(ok))
                }
                None => (Vec::new(), None),
            };
            out.push(OolRecord { lineno: o.lineno, dir: o.dir, buf: o.buf, msg: o.msg, data, sha_ok });
        }
        Ok(out)
    }
}

/// First 8 hex digits of SHA-256 (the tracer's `sha=`). Minimal implementation, used only for checking traces.
pub fn sha256_hex8(data: &[u8]) -> String {
    let h = sha256(data);
    format!("{:02x}{:02x}{:02x}{:02x}", h[0], h[1], h[2], h[3])
}

pub fn sha256(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98,
        0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8,
        0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
        0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] =
        [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    let mut msg = data.to_vec();
    let bits = (data.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bits.to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[4 * i], chunk[4 * i + 1], chunk[4 * i + 2], chunk[4 * i + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v = [t1.wrapping_add(t2), v[0], v[1], v[2], v[3].wrapping_add(t1), v[4], v[5], v[6]];
        }
        for i in 0..8 {
            h[i] = h[i].wrapping_add(v[i]);
        }
    }
    let mut out = [0u8; 32];
    for i in 0..8 {
        out[4 * i..4 * i + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sha256_vector() {
        assert_eq!(sha256_hex8(b"abc"), "ba7816bf");
        assert_eq!(sha256_hex8(b""), "e3b0c442");
    }
    #[test]
    fn line() {
        let m = parse_msg("12.5 > EP=0x08 TAG=0xfc TYPE=0x73 PARAM=0x00 DATA=0x0", 3).unwrap();
        assert_eq!(m.w, Word::new(8, 0xfc, 0x73, 0, 0));
        assert!(m.to_sep());
        assert!(parse_msg("12.5 ! EP=0x08 TAG=0xfc TYPE=0x73 PARAM=0x00 DATA=0x0", 3).is_none());
    }
}
