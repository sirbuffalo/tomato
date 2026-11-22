// The sort benchmark with a radix sort instead of the standard library's comparison sort, shown beside it as headroom:
// Tomato's sorted() is an introsort (so it can take compare functions), not a radix sort. Same input and checksum as sort.rs.
fn radix_sort(values: &mut Vec<u64>) {
    // least significant digit first, 8 bits per pass; the values are below 2**31, so four passes
    let mut buf = vec![0u64; values.len()];
    for pass in 0..4 {
        let shift = pass * 8;
        let mut count = [0usize; 257];
        for &v in values.iter() {
            count[((v >> shift) & 255) as usize + 1] += 1;
        }
        for d in 0..256 {
            count[d + 1] += count[d];
        }
        for &v in values.iter() {
            let d = ((v >> shift) & 255) as usize;
            buf[count[d]] = v;
            count[d] += 1;
        }
        std::mem::swap(values, &mut buf);
    }
}

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 12345;
    let mut values = vec![0u64; n];
    for i in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    radix_sort(&mut values);
    let mut checksum: u64 = 0;
    for i in 0..n {
        checksum = (checksum + (i as u64 % 1000 + 1) * values[i]) % 1000000007;
    }
    println!("{}", checksum);
}
