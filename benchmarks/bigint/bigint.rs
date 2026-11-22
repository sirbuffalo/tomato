// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
// Rust's standard library has no big integers, so this uses the num-bigint crate (Cargo.toml pins the version), the
// usual library choice, as Go uses math/big and Python its built-in int. benchmarks/run.sh builds it with cargo --release.
use num_bigint::BigUint;

fn main() {
    let n: u32 = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut product = BigUint::from(1u32);
    for i in 2..=n {
        product *= i;
    }
    println!("{}", product % 1000000007u32);
}
