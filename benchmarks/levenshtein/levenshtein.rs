// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 42;
    let mut s: Vec<u8> = Vec::with_capacity(n);
    let mut t: Vec<u8> = Vec::with_capacity(n);
    for _ in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        s.push(b'a' + (seed / 65536 % 4) as u8);
        seed = (seed * 1103515245 + 12345) % 2147483648;
        t.push(b'a' + (seed / 65536 % 4) as u8);
    }
    let mut prev: Vec<u64> = (0..=n as u64).collect();
    let mut cur = vec![0u64; n + 1];
    for i in 1..=n {
        cur[0] = i as u64;
        let si = s[i - 1];
        for j in 1..=n {
            let cost = if si == t[j - 1] { 0 } else { 1 };
            let mut best = prev[j - 1] + cost;
            let up = prev[j] + 1;
            if up < best {
                best = up;
            }
            let left = cur[j - 1] + 1;
            if left < best {
                best = left;
            }
            cur[j] = best;
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    println!("{}", prev[n]);
}
