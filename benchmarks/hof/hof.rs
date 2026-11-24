// Benchmark: function values. Calls one of four functions chosen from a list n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
fn f0(x: u64) -> u64 {
    (x * 3 + 1) % 1000003
}

fn f1(x: u64) -> u64 {
    (x + 7919) % 1000003
}

fn f2(x: u64) -> u64 {
    x * x % 1000003
}

fn f3(x: u64) -> u64 {
    (x ^ 12345) % 1000003
}

fn apply_twice(f: fn(u64) -> u64, x: u64) -> u64 {
    f(f(x))
}

fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let table: Vec<fn(u64) -> u64> = vec![f0, f1, f2, f3];
    let mut x: u64 = 1;
    for i in 0..n {
        x = table[(i % 4) as usize](x + i);
    }
    println!("{}", x);
    let mut y: u64 = 0;
    for i in 0..n {
        y = (y + apply_twice(table[(i % 4) as usize], i)) % 1000000007;
    }
    println!("{}", y);
    let m = n / 4;
    let xs: Vec<u64> = (0..m).map(|i| i * 7919 % 100003).collect();
    let squares: Vec<u64> = xs.iter().map(|&v| v * v % 1009).collect();
    let mut odd: Vec<u64> = squares.into_iter().filter(|&v| v % 2 == 1).collect();
    odd.sort_by_key(|&v| v % 997 * 1000 + v % 1000);
    let mut z: u64 = 0;
    for &v in &odd {
        z = (z * 31 + v) % 1000000007;
    }
    println!("{} {}", odd.len(), z);
}
