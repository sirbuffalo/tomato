// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted list.
fn insertion_sort(values: &mut [u64], low: i64, high: i64) {
    for i in low + 1..=high {
        let x = values[i as usize];
        let mut j = i - 1;
        while j >= low && values[j as usize] > x {
            values[(j + 1) as usize] = values[j as usize];
            j -= 1;
        }
        values[(j + 1) as usize] = x;
    }
}

fn quicksort(values: &mut [u64], mut low: i64, mut high: i64) {
    while high - low > 16 {
        let pivot = values[((low + high) / 2) as usize];
        let mut i = low;
        let mut j = high;
        while i <= j {
            while values[i as usize] < pivot {
                i += 1;
            }
            while values[j as usize] > pivot {
                j -= 1;
            }
            if i <= j {
                values.swap(i as usize, j as usize);
                i += 1;
                j -= 1;
            }
        }
        // recurse into the smaller part, loop on the larger one
        if j - low < high - i {
            quicksort(values, low, j);
            low = i;
        } else {
            quicksort(values, i, high);
            high = j;
        }
    }
    insertion_sort(values, low, high);
}

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 12345;
    let mut values = vec![0u64; n];
    for i in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    quicksort(&mut values, 0, n as i64 - 1);
    let mut checksum: u64 = 0;
    for i in 0..n {
        checksum = (checksum + (i as u64 % 1000 + 1) * values[i]) % 1000000007;
    }
    println!("{}", checksum);
}
