//! SHA-256 and SHA-1 (FIPS 180-4), written from the standard, streaming, without allocation and without `std`: this
//! file is also included as is by the kernel module (`kmod/sep_native.rs`). Used only for the SKS IPC frame digest
//! (`sks_ipc`): an unkeyed SHA-256 truncated to 16 bytes, and the SHA-1 of the 8-byte process id that the AP puts in
//! the cdhash field when there is no process (`docs/sks_protocol.md` §1.6.2-§1.6.3). Nothing secret is computed here.

const K256: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98,
    0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8,
    0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
    0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
    0xc67178f2,
];

/// 64-byte block buffer shared by both hashes (big-endian length padding, as in FIPS 180-4 §5.1.1).
#[derive(Clone)]
struct Blocks {
    buf: [u8; 64],
    n: usize,
    total: u64,
}

impl Blocks {
    const fn new() -> Self {
        Blocks { buf: [0; 64], n: 0, total: 0 }
    }

    fn update(&mut self, mut data: &[u8], mut compress: impl FnMut(&[u8; 64])) {
        self.total = self.total.wrapping_add(data.len() as u64);
        while !data.is_empty() {
            let take = (64 - self.n).min(data.len());
            self.buf[self.n..self.n + take].copy_from_slice(&data[..take]);
            self.n += take;
            data = &data[take..];
            if self.n == 64 {
                compress(&self.buf);
                self.n = 0;
            }
        }
    }

    fn finish(&mut self, mut compress: impl FnMut(&[u8; 64])) {
        let bits = self.total.wrapping_mul(8);
        self.buf[self.n] = 0x80;
        self.n += 1;
        if self.n > 56 {
            self.buf[self.n..].fill(0);
            compress(&self.buf);
            self.n = 0;
        }
        self.buf[self.n..56].fill(0);
        self.buf[56..].copy_from_slice(&bits.to_be_bytes());
        compress(&self.buf);
        self.n = 0;
    }
}

fn be_words<const N: usize>(block: &[u8; 64]) -> [u32; N] {
    let mut w = [0u32; N];
    for (i, c) in block.as_chunks::<4>().0.iter().enumerate() {
        w[i] = u32::from_be_bytes([c[0], c[1], c[2], c[3]]);
    }
    w
}

/// Streaming SHA-256.
#[derive(Clone)]
pub struct Sha256 {
    h: [u32; 8],
    b: Blocks,
}

impl Default for Sha256 {
    fn default() -> Self {
        Self::new()
    }
}

impl Sha256 {
    pub const fn new() -> Self {
        Sha256 {
            h: [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19],
            b: Blocks::new(),
        }
    }

    fn compress(h: &mut [u32; 8], block: &[u8; 64]) {
        let mut w: [u32; 64] = be_words(block);
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let mut v = *h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K256[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v = [t1.wrapping_add(t2), v[0], v[1], v[2], v[3].wrapping_add(t1), v[4], v[5], v[6]];
        }
        for (x, y) in h.iter_mut().zip(v) {
            *x = x.wrapping_add(y);
        }
    }

    pub fn update(&mut self, data: &[u8]) {
        let h = &mut self.h;
        self.b.update(data, |blk| Self::compress(h, blk));
    }

    pub fn finalize(mut self) -> [u8; 32] {
        let h = &mut self.h;
        self.b.finish(|blk| Self::compress(h, blk));
        let mut out = [0u8; 32];
        for (o, x) in out.as_chunks_mut::<4>().0.iter_mut().zip(self.h) {
            o.copy_from_slice(&x.to_be_bytes());
        }
        out
    }
}

pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut s = Sha256::new();
    s.update(data);
    s.finalize()
}

/// Streaming SHA-1 (used only as the AP does for the cdhash field when there is no process; not for integrity).
#[derive(Clone)]
pub struct Sha1 {
    h: [u32; 5],
    b: Blocks,
}

impl Default for Sha1 {
    fn default() -> Self {
        Self::new()
    }
}

impl Sha1 {
    pub const fn new() -> Self {
        Sha1 { h: [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0], b: Blocks::new() }
    }

    fn compress(h: &mut [u32; 5], block: &[u8; 64]) {
        let mut w = [0u32; 80];
        w[..16].copy_from_slice(&be_words::<16>(block));
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let [mut a, mut b, mut c, mut d, mut e] = *h;
        for (i, &wi) in w.iter().enumerate() {
            let (f, k) = match i {
                0..=19 => ((b & c) | (!b & d), 0x5a827999),
                20..=39 => (b ^ c ^ d, 0x6ed9eba1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8f1bbcdc),
                _ => (b ^ c ^ d, 0xca62c1d6),
            };
            let t = a.rotate_left(5).wrapping_add(f).wrapping_add(e).wrapping_add(k).wrapping_add(wi);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = t;
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e]) {
            *x = x.wrapping_add(y);
        }
    }

    pub fn update(&mut self, data: &[u8]) {
        let h = &mut self.h;
        self.b.update(data, |blk| Self::compress(h, blk));
    }

    pub fn finalize(mut self) -> [u8; 20] {
        let h = &mut self.h;
        self.b.finish(|blk| Self::compress(h, blk));
        let mut out = [0u8; 20];
        for (o, x) in out.as_chunks_mut::<4>().0.iter_mut().zip(self.h) {
            o.copy_from_slice(&x.to_be_bytes());
        }
        out
    }
}

pub fn sha1(data: &[u8]) -> [u8; 20] {
    let mut s = Sha1::new();
    s.update(data);
    s.finalize()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hs(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    // FIPS 180-2 appendix vectors ("abc", 448-bit message, one million 'a') and the empty string.
    #[test]
    fn sha256_vectors() {
        assert_eq!(hs(&sha256(b"")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(hs(&sha256(b"abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(
            hs(&sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
        let mut s = Sha256::new();
        for _ in 0..1000 {
            s.update(&[b'a'; 1000]);
        }
        assert_eq!(hs(&s.finalize()), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    }

    #[test]
    fn sha1_vectors() {
        assert_eq!(hs(&sha1(b"")), "da39a3ee5e6b4b0d3255bfef95601890afd80709");
        assert_eq!(hs(&sha1(b"abc")), "a9993e364706816aba3e25717850c26c9cd0d89d");
        assert_eq!(
            hs(&sha1(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
            "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
        );
        let mut s = Sha1::new();
        for _ in 0..1000 {
            s.update(&[b'a'; 1000]);
        }
        assert_eq!(hs(&s.finalize()), "34aa973cd4c4daa4f61eeb2bdbad27316534016f");
    }

    /// Split updates at every length around the block boundary = one-shot result.
    #[test]
    fn streaming_equals_oneshot() {
        let data: [u8; 200] = core::array::from_fn(|i| i as u8);
        for cut in 0..data.len() {
            let mut s = Sha256::new();
            s.update(&data[..cut]);
            s.update(&data[cut..]);
            assert_eq!(s.finalize(), sha256(&data), "sha256 cut {cut}");
            let mut t = Sha1::new();
            t.update(&data[..cut]);
            t.update(&data[cut..]);
            assert_eq!(t.finalize(), sha1(&data), "sha1 cut {cut}");
        }
        for n in 50..70 {
            let mut s = Sha256::new();
            for b in &data[..n] {
                s.update(core::slice::from_ref(b));
            }
            assert_eq!(s.finalize(), sha256(&data[..n]), "sha256 bytewise {n}");
        }
    }
}
