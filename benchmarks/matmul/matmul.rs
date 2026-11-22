// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut a = vec![vec![0i64; n]; n];
    let mut b = vec![vec![0i64; n]; n];
    for i in 0..n {
        for j in 0..n {
            a[i][j] = ((i * j + 1) % 10) as i64;
            b[i][j] = ((i + j) % 10) as i64;
        }
    }
    let mut total: i64 = 0;
    for i in 0..n {
        let row = &a[i];
        for j in 0..n {
            let mut acc: i64 = 0;
            for k in 0..n {
                acc += row[k] * b[k][j];
            }
            total += acc;
        }
    }
    println!("{}", total);
}
