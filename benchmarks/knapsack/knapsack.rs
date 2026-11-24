// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 7;
    let mut weights = vec![0usize; n];
    let mut values = vec![0u64; n];
    for i in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        weights[i] = (seed / 65536 % 60 + 1) as usize;
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed / 65536 % 1000 + 1;
    }
    let capacity = 5 * n;
    let mut best = vec![0u64; capacity + 1];
    for i in 0..n {
        let w = weights[i];
        let v = values[i];
        let mut c = capacity;
        while c >= w {
            let candidate = best[c - w] + v;
            if candidate > best[c] {
                best[c] = candidate;
            }
            c -= 1;
        }
    }
    println!("{}", best[capacity]);
}
