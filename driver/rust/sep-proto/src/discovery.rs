//! Step 2: discovery endpoint 0xFD -> name <-> EP number table, OOL sizes; CNTL opening sequences.
//!
//! Status: 4-character names and FD TYPE 1 sizes = **hypothesis** (12/12 announcements = public Asahi doc; meaning of
//! the 4 size bytes: hypothesis, source kext). Used for labelling only; **no EP number is hard-coded**: look up by
//! name (`find("sbio")`). The announcement order varies between boots (3 orders over 8 boots).
//!
//! Observed format (SEP -> AP only): TYPE 0x00, PARAM = EP, DATA = 4-byte ASCII name, first char in the MSB.
//! TYPE 0x01, PARAM = EP, DATA = 4 size bytes in 0x4000 pages (byte 0 = LSB): min send, max send, min recv, max recv.
use crate::word::{Dir, Msg};
use crate::{Error, Result};
use alloc::collections::BTreeMap;
use alloc::vec::Vec;

pub const EP_DISCOVERY: u8 = 0xFD;
pub const EP_CNTL: u8 = 0x00;
pub const OOL_PAGE: u32 = 0x4000;
pub const CNTL_SEND_SIZE: u8 = 0x04;
pub const CNTL_SEND_ADDR: u8 = 0x02;
pub const CNTL_RECV_SIZE: u8 = 0x05;
pub const CNTL_RECV_ADDR: u8 = 0x03;

/// 4-byte endpoint name (raw ASCII, trailing spaces kept).
pub fn decode_name(data: u32) -> [u8; 4] {
    data.to_be_bytes()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EpInfo {
    pub ep: u8,
    pub name: [u8; 4],
    /// DATA of TYPE 1, as is.
    pub sizes_raw: Option<u32>,
}

impl EpInfo {
    /// (min send, max send, min recv, max recv) in pages; "hypothesis" reading.
    pub fn pages(&self) -> Option<[u8; 4]> {
        self.sizes_raw.map(|r| r.to_le_bytes())
    }
    pub fn max_send(&self) -> Option<u32> {
        self.pages().map(|p| p[1] as u32 * OOL_PAGE)
    }
    pub fn max_recv(&self) -> Option<u32> {
        self.pages().map(|p| p[3] as u32 * OOL_PAGE)
    }
    /// Name without trailing spaces.
    pub fn name_str(&self) -> &str {
        core::str::from_utf8(&self.name).unwrap_or("????").trim_end()
    }
}

#[derive(Debug, Default, Clone)]
pub struct DiscoveryTable {
    pub by_ep: BTreeMap<u8, EpInfo>,
    /// Announcement order.
    pub order: Vec<u8>,
}

impl DiscoveryTable {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feed one message; messages that are not FD SEP->AP are ignored. Fail-closed on an inconsistent announcement.
    pub fn feed(&mut self, m: &Msg) -> Result<()> {
        if m.w.ep != EP_DISCOVERY || m.dir != Dir::ToAp {
            return Ok(());
        }
        let ep = m.w.param;
        match m.w.ty {
            0x00 => {
                if self.by_ep.contains_key(&ep) {
                    return Err(Error::Unexpected("EP announced twice"));
                }
                self.by_ep.insert(ep, EpInfo { ep, name: decode_name(m.w.data), sizes_raw: None });
                self.order.push(ep);
            }
            0x01 => {
                let e = self.by_ep.get_mut(&ep).ok_or(Error::Unexpected("FD TYPE 1 before TYPE 0"))?;
                e.sizes_raw = Some(m.w.data);
            }
            _ => return Err(Error::Unexpected("unknown FD TYPE")),
        }
        Ok(())
    }

    pub fn from_msgs<'a>(msgs: impl IntoIterator<Item = &'a Msg>) -> Result<Self> {
        let mut t = Self::new();
        for m in msgs {
            t.feed(m)?;
        }
        Ok(t)
    }

    /// EP number by name (up to 4 chars, trailing space allowed: "sks" == "sks ").
    pub fn find(&self, name: &str) -> Option<u8> {
        let n = name.as_bytes();
        if n.len() > 4 {
            return None;
        }
        let mut want = [b' '; 4];
        want[..n.len()].copy_from_slice(n);
        self.by_ep.values().find(|i| i.name == want).map(|i| i.ep)
    }

    pub fn name_of(&self, ep: u8) -> Option<&str> {
        self.by_ep.get(&ep).map(|i| i.name_str())
    }
}

/// One CNTL opening: (send size, send addr, recv size, recv addr). Addresses = DATA << 12.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CntlOpen {
    pub send_size: u64,
    pub send_addr: u64,
    pub recv_size: u64,
    pub recv_addr: u64,
}

/// CNTL opening sequences `> EP=0x00` TYPE 4/2/5/3 (PARAM = EP), AP->SEP requests only.
pub fn cntl_opens<'a>(msgs: impl IntoIterator<Item = &'a Msg>) -> BTreeMap<u8, Vec<CntlOpen>> {
    let mut out: BTreeMap<u8, Vec<CntlOpen>> = BTreeMap::new();
    let mut cur: BTreeMap<u8, [Option<u64>; 4]> = BTreeMap::new();
    for m in msgs {
        if m.w.ep != EP_CNTL || m.dir != Dir::ToSep {
            continue;
        }
        let (slot, v) = match m.w.ty {
            CNTL_SEND_SIZE => (0, m.w.data as u64),
            CNTL_SEND_ADDR => (1, (m.w.data as u64) << 12),
            CNTL_RECV_SIZE => (2, m.w.data as u64),
            CNTL_RECV_ADDR => (3, (m.w.data as u64) << 12),
            _ => continue,
        };
        let c = cur.entry(m.w.param).or_insert([None; 4]);
        c[slot] = Some(v);
        if let [Some(ss), Some(sa), Some(rs), Some(ra)] = *c {
            out.entry(m.w.param).or_default().push(CntlOpen { send_size: ss, send_addr: sa, recv_size: rs, recv_addr: ra });
            *c = [None; 4];
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn name() {
        assert_eq!(&decode_name(0x7362696f), b"sbio");
    }
}
