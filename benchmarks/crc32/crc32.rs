// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut table = [0u64; 256];
    for i in 0..256 {
        let mut c = i as u64;
        for _ in 0..8 {
            if c & 1 == 1 {
                c = 3988292384 ^ (c >> 1);
            } else {
                c >>= 1;
            }
        }
        table[i] = c;
    }
    let mut seed: u64 = 1;
    let mut data = vec![0u64; n];
    for i in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        data[i] = seed / 65536 % 256;
    }
    let mut crc: u64 = 4294967295;
    for _ in 0..4 {
        for &b in &data {
            crc = table[((crc ^ b) & 255) as usize] ^ (crc >> 8);
        }
    }
    crc ^= 4294967295;
    let mut a: u64 = 1;
    let mut b2: u64 = 0;
    for &b in &data {
        a = (a + b) % 65521;
        b2 = (b2 + a) % 65521;
    }
    println!("{} {}", crc, b2 * 65536 + a);
}
