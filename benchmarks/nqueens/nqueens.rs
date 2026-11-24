// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, lists of bools for the columns and the two diagonals).
fn place(n: usize, row: usize, cols: &mut [bool], diag1: &mut [bool], diag2: &mut [bool]) -> u64 {
    if row == n {
        return 1;
    }
    let mut count = 0;
    for c in 0..n {
        let d1 = row + c;
        let d2 = row + n - 1 - c;
        if cols[c] || diag1[d1] || diag2[d2] {
            continue;
        }
        cols[c] = true;
        diag1[d1] = true;
        diag2[d2] = true;
        count += place(n, row + 1, cols, diag1, diag2);
        cols[c] = false;
        diag1[d1] = false;
        diag2[d2] = false;
    }
    count
}

fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut cols = vec![false; n];
    let mut diag1 = vec![false; 2 * n];
    let mut diag2 = vec![false; 2 * n];
    println!("{}", place(n, 0, &mut cols, &mut diag1, &mut diag2));
}
