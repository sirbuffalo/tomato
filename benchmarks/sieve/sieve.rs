// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut composite = vec![false; n + 1];
    let mut count = 0;
    for i in 2..=n {
        if composite[i] {
            continue;
        }
        count += 1;
        let mut j = i * i;
        while j <= n {
            composite[j] = true;
            j += i;
        }
    }
    println!("{}", count);
}
