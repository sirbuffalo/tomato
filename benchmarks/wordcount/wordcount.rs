// Benchmark: word counting in a dict. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
use std::collections::HashMap;

fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut counts: HashMap<String, u64> = HashMap::new();
    for i in 0..n {
        let word = format!("w{}", i * 7919 % 5003);
        *counts.entry(word).or_insert(0) += 1;
    }
    let mut checksum: u64 = 0;
    for k in 0..5003u64 {
        checksum += (k + 1) * counts.get(&format!("w{}", k)).copied().unwrap_or(0);
    }
    println!("{} {}", counts.len(), checksum);
}
