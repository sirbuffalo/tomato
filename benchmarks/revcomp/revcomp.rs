// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
use std::collections::HashMap;

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 2718;
    let letters = ['A', 'C', 'G', 'T'];
    let mut parts: Vec<String> = Vec::new();
    for _ in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        parts.push(letters[(seed / 65536 % 4) as usize].to_string());
    }
    let dna = parts.join("");
    let mut lines: Vec<String> = Vec::new();
    let mut start = 0;
    while start < n {
        lines.push(dna[start..(start + 60).min(n)].to_string());
        start += 60;
    }
    let text = lines.join("");
    let complement: HashMap<char, &str> = HashMap::from([('A', "T"), ('C', "G"), ('G', "C"), ('T', "A")]);
    let mut out: Vec<&str> = Vec::new();
    for ch in text.chars().rev() {
        out.push(complement[&ch]);
    }
    let rc = out.join("");
    let mut wrapped: Vec<String> = Vec::new();
    let mut start = 0;
    while start < rc.len() {
        wrapped.push(rc[start..(start + 60).min(rc.len())].to_string());
        start += 60;
    }
    let mut checksum: u64 = 0;
    for line in &wrapped {
        let bytes = line.as_bytes();
        let mut k = 0;
        while k < bytes.len() {
            checksum = (checksum * 131 + bytes[k] as u64) % 1000000007;
            k += 7;
        }
    }
    println!("{} {}", wrapped.len(), checksum);
}
