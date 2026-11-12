#!/usr/bin/env python3
"""Parse l'en-tête gt_packet_t des buffers OOL EP 0x08 (sbio) d'une capture et nomme l'opcode.

Format VÉRIFIÉ contre la trace c12 (voir docs/kext_sepmanager.md §13/§13b) :
  gt_packet_t = en-tête 0x1c o : +0x00 kind(=1) | +0x04 total | +0x08 offset |
  +0x0c flags | +0x10 réservé | +0x14 OPCODE | +0x18 longueur fragment | +0x1c payload.
Les NOMS d'opcodes viennent du kext (docs/kext_sepmanager.md §12c, source: kext).

  sbio_gt_packet.py TRACE_DIR[/sep.log.ool]      # liste les transactions 0x08 A, opcode nommé
"""
import sys, os, glob, struct

# opcode -> nom (kext, §12c/§12d/§13b) ; None = non identifié
OPS = {
    0x01: "init?", 0x03: "commandStartEnroll", 0x06: "forceNoMatch",
    0x07: "asyncCapture", 0x08: "handleEnrollment", 0x09: "handleMatch(MATCH)",
    0x0a: "applyPostponedMatch", 0x0b: "match-subresult", 0x0c: "handleMatch(arm)",
    0x0d: "match-subresult", 0x0e: "match-subresult", 0x0f: "match-subresult",
    0x10: "match-subresult", 0x11: "match-subresult", 0x12: "match-subresult",
    0x14: "match-step", 0x15: "performKeyExchange", 0x16: "keyExchange(2)",
    0x17: "serialNumber", 0x18: "sequenceCounter", 0x19: "HandleReset",
    0x1b: "prepareNotPairedSession/match-fin", 0x1c: "match-fin", 0x1e: "capture-step",
    0x1f: "cacheMatchPolicy", 0x22: "asyncCapture", 0x23: "asyncCapture",
    0x24: "lockRootKey(2)", 0x28: "cacheCaptureData/specificCmd", 0x2b: "cacheProtectedConfig",
    0x30: "lockRootKey", 0x31: "?", 0x32: "switchToProd?", 0x36: "specificCmd",
    0x39: "cacheSysProtectedConfig", 0x3d: "forceBioLockout", 0x42: "initializeSequenceCounter",
    0x43: "establishDiffieHellman", 0x49: "seaCookie", 0x4a: "seaCookie", 0x4b: "seaCookie",
    0x4c: "seaCookie", 0x4d: "seaCookie", 0x4e: "seaCookie", 0x4f: "seaCookie",
    0x53: "seaCookie", 0x58: "cacheCaptureData", 0x5a: "cacheCaptureData",
    0x5c: "?", 0x5d: "applySensorParams", 0x5f: "LoadPatch", 0x63: "setCalibrationData",
    0x65: "asyncCapture/retryMatch", 0x6a: "?", 0x73: "?", 0x74: "capture",
    0x76: "seaCookie", 0x77: "seaCookie", 0x7e: "provisionNavajo",
}

def main():
    d = sys.argv[1]
    if not d.endswith("sep.log.ool"):
        cand = os.path.join(d, "sep.log.ool")
        if os.path.isdir(cand):
            d = cand
    files = sorted(glob.glob(os.path.join(d, "*_08_A.bin")))
    if not files:
        print("aucun buffer *_08_A.bin dans", d); return
    print(f"{'idx':>7} {'kind':>4} {'total':>6} {'off':>5} {'flen':>5}  opcode  opération (kext)")
    for f in files:
        b = open(f, "rb").read()
        if len(b) < 0x1c:
            continue
        kind, tot, off, flg, r10, op, flen = struct.unpack_from("<IIIIIII", b, 0)
        idx = os.path.basename(f).split("_")[0]
        warn = "" if kind == 1 else "  <-- kind != 1 (pas un gt_packet ?)"
        print(f"{idx:>7} {kind:>4} {tot:>#6x} {off:>#5x} {flen:>#5x}  {op:>#5x}  {OPS.get(op,'?')}{warn}")

    # réponses B des matches (opcode 0x09) : verdict match_info_t (VÉRIFIÉ, §13c)
    bresp = sorted(glob.glob(os.path.join(d, "*_08_B.bin")))
    shown = False
    for f in bresp:
        b = open(f, "rb").read()
        if len(b) < 0x20:
            continue
        kind, tot, off, flg, r10, op, flen = struct.unpack_from("<IIIIIII", b, 0)
        if op != 0x09:
            continue
        verdict = struct.unpack_from("<I", b, 0x1c)[0]
        tag = "SUCCES" if verdict == 0x1f5 else ("ECHEC" if verdict == 0xffffffff else "?")
        if not shown:
            print("\n-- réponses de match (opcode 0x09, buffer B) : verdict match_info_t --")
            shown = True
        idx = os.path.basename(f).split("_")[0]
        print(f"{idx:>7}  verdict={verdict:#010x} {tag}  ident={b[0x20:0x30].hex()}")

if __name__ == "__main__":
    main()
