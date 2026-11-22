//! CRC-16/ARC (reflected poly 0xA001, init 0, no final XOR) and CRC-32/ISO-HDLC, written from the standard
//! definitions. Status: 0x65 slice checks = `verified (macOS)` (K4, 468/468 slices); locker CRC-32 = verified 12/12.

const fn table16() -> [u16; 256] {
    let mut t = [0u16; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u16;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 { (c >> 1) ^ 0xA001 } else { c >> 1 };
            k += 1;
        }
        t[i] = c;
        i += 1;
    }
    t
}

const fn table32() -> [u32; 256] {
    let mut t = [0u32; 256];
    let mut i = 0;
    while i < 256 {
        let mut c = i as u32;
        let mut k = 0;
        while k < 8 {
            c = if c & 1 != 0 { (c >> 1) ^ 0xEDB8_8320 } else { c >> 1 };
            k += 1;
        }
        t[i] = c;
        i += 1;
    }
    t
}

static T16: [u16; 256] = table16();
static T32: [u32; 256] = table32();

pub fn crc16_arc(data: &[u8]) -> u16 {
    data.iter().fold(0u16, |c, &b| (c >> 8) ^ T16[((c ^ u16::from(b)) & 0xFF) as usize])
}

/// CRC-32/ISO-HDLC (= zlib.crc32).
pub fn crc32(data: &[u8]) -> u32 {
    !data.iter().fold(!0u32, |c, &b| (c >> 8) ^ T32[((c ^ u32::from(b)) & 0xFF) as usize])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn catalogue_check_values() {
        assert_eq!(crc16_arc(b"123456789"), 0xBB3D);
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
    }
}
