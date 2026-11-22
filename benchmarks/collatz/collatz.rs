// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let (mut best_start, mut best_length) = (1u64, 1u64);
    for start in 1..n {
        let mut x = start;
        let mut length = 1u64;
        while x != 1 {
            if x % 2 == 0 {
                x /= 2;
            } else {
                x = 3 * x + 1;
            }
            length += 1;
        }
        if length > best_length {
            best_length = length;
            best_start = start;
        }
    }
    println!("{} {}", best_start, best_length);
}
