// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a dict. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
use std::collections::HashMap;

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 31337;
    let letters = ['A', 'C', 'G', 'T'];
    let mut dna = String::with_capacity(n);
    for _ in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        dna.push(letters[(seed / 65536 % 4) as usize]);
    }
    for k in [1usize, 2, 4, 6, 12] {
        let mut counts: HashMap<&str, u64> = HashMap::new();
        for i in 0..n + 1 - k {
            *counts.entry(&dna[i..i + k]).or_insert(0) += 1;
        }
        let mut most = 0;
        let mut squares = 0;
        for &c in counts.values() {
            if c > most {
                most = c;
            }
            squares += c * c;
        }
        println!("{} {} {} {}", k, counts.len(), most, squares);
    }
}
