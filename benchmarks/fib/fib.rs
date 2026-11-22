// Benchmark: naive recursive Fibonacci. Prints fib(n).
fn fib(n: u64) -> u64 {
    if n < 2 {
        return n;
    }
    fib(n - 1) + fib(n - 2)
}

fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    println!("{}", fib(n));
}
