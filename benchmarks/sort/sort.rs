// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 12345;
    let mut values = vec![0u64; n];
    for i in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    values.sort();
    let mut checksum: u64 = 0;
    for i in 0..n {
        checksum = (checksum + (i as u64 % 1000 + 1) * values[i]) % 1000000007;
    }
    println!("{}", checksum);
}
