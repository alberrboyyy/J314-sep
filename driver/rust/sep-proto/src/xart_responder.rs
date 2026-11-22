//! Step 7: model of the AP reply on EP 0x13 (xART), OBSERVED on macOS and validated by REPRODUCTION
//! (the replay test recomputes every reply of the `snew-reel` capture and compares it line by line).
//!
//! What is NOT validated here: the NATIVE Linux handler policy, which diverges from macOS on two points only
//! (answer ABSENT when the Linux store lacks the locker; PERSIST the SAVE blob). Both TOUCH the SEP (write) and can
//! only be validated on hardware (Albert's go). They are isolated in `native_fetch_decision` / `native_on_save`,
//! marked HYPOTHESIS. This module COMPUTES a reply; it sends NOTHING.
use crate::word::Word;
use crate::xart::{self, *};
use crate::{Error, Result};

/// Reply types of the AP (observed), distinct from the SEP request types.
pub const RESP_DONE: u8 = 0x00;
pub const RESP_ANNOUNCE: u8 = 0x16;
const ACK_MASK: u32 = 0xFFFF_FF00;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    AckFwboot,
    Uuid,
    FetchMaster,
    FetchGl,
    AckAbsent,
    AckSave,
    AckAnnounce,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Response {
    pub tag: u8,
    pub ty: u8,
    pub param: u8,
    pub data: u32,
    pub kind: Kind,
    /// osuuid: 16 bytes of UUID written to buffer A.
    pub writes_uuid: bool,
    /// FETCH: sealed blob written to buffer A.
    pub serves_blob: bool,
}

impl Response {
    const fn new(tag: u8, ty: u8, param: u8, data: u32, kind: Kind) -> Self {
        Response { tag, ty, param, data, kind, writes_uuid: false, serves_blob: false }
    }
    /// Mailbox word of this reply on EP 0x13.
    pub const fn word(&self) -> Word {
        Word::new(EP_XART, self.tag, self.ty, self.param, self.data)
    }
}

/// macOS's reply (observed) to a 0x13 request `req` (SEP->AP). `served_len` = length of the served blob for a FETCH.
/// Fail-closed: an unmodelled request is an error.
pub fn observed_response(req: &Word, served_len: Option<usize>) -> Result<Response> {
    let t = req.tag;
    Ok(match req.ty {
        OP_FWBOOT => Response::new(t, RESP_DONE, 0, 0x100, Kind::AckFwboot),
        OP_OSUUID => Response { writes_uuid: true, ..Response::new(t, RESP_DONE, 0, 0, Kind::Uuid) },
        OP_FETCH_MASTER | OP_FETCH_GL => {
            let len = served_len.ok_or(Error::Unexpected("FETCH: served_len required"))?;
            let (p, d) = encode_fetch_len(len, selector(req.data))?;
            let k = if req.ty == OP_FETCH_MASTER { Kind::FetchMaster } else { Kind::FetchGl };
            Response { serves_blob: true, ..Response::new(t, RESP_DONE, p, d, k) }
        }
        OP_ABSENT => Response::new(t, RESP_DONE, 0, 0, Kind::AckAbsent),
        ty if is_save(ty) => Response::new(t, RESP_DONE, 0, req.data & ACK_MASK, Kind::AckSave),
        OP_EP_ANNOUNCE => Response::new(t, RESP_ANNOUNCE, 0, req.data & ACK_MASK, Kind::AckAnnounce),
        _ => return Err(Error::Unexpected("unmodelled 0x13 request")),
    })
}

// -------------------------------------------------------------------------------------------------
// NATIVE LINUX HANDLER DIVERGENCES — ⚠️ UNTESTED HYPOTHESIS (docs/handler_0x13.md §2/§3).
// No ground truth: no capture shows these branches. Enabling them for real = SEP write = Albert's go.
// -------------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FetchDecision<'a> {
    Serve(&'a Locker),
    Absent,
}

/// HYPOTHESIS. A FETCH on Linux: serve the locker if the store has it, else ABSENT.
pub fn native_fetch_decision<'a>(store: &'a [Locker], req: &Word) -> Result<FetchDecision<'a>> {
    let loc = match req.ty {
        OP_FETCH_MASTER => xart::find_master(store, selector(req.data)),
        OP_FETCH_GL => None, // the real UUID is in buffer B (outside the message); resolved at boot time
        _ => return Err(Error::Unexpected("not a FETCH")),
    };
    Ok(loc.map_or(FetchDecision::Absent, FetchDecision::Serve))
}

/// HYPOTHESIS. A SAVE on Linux should be ACKNOWLEDGED then PERSISTED. ⚠️ The ack advances the SEP's sealed
/// counter = WRITE = Albert's go. Returns only the expected ack DATA; sends nothing.
pub fn native_on_save(req: &Word) -> Result<u32> {
    if !is_save(req.ty) {
        return Err(Error::Unexpected("not a SAVE"));
    }
    Ok(req.data & ACK_MASK)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn absent_when_store_empty() {
        let r = Word::new(EP_XART, 1, OP_FETCH_MASTER, 0, 0x100);
        assert_eq!(native_fetch_decision(&[], &r).unwrap(), FetchDecision::Absent);
    }
    #[test]
    fn save_decision() {
        let r = Word::new(EP_XART, 1, OP_SAVE_XART, 0, 0x89290103);
        assert_eq!(native_on_save(&r).unwrap(), 0x89290100);
    }
    #[test]
    fn unknown_is_error() {
        assert!(observed_response(&Word::new(EP_XART, 1, 0x42, 0, 0), None).is_err());
    }
}
