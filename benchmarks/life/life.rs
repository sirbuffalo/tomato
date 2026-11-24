// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Nested lists, neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 99;
    let mut grid: Vec<Vec<u8>> = Vec::new();
    let mut next_grid: Vec<Vec<u8>> = Vec::new();
    for _ in 0..n {
        let mut row = vec![0u8; n];
        for x in 0..n {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            if seed / 65536 % 3 == 0 {
                row[x] = 1;
            }
        }
        grid.push(row);
        next_grid.push(vec![0u8; n]);
    }
    for _ in 0..100 {
        for y in 0..n {
            let up = &grid[(y + n - 1) % n];
            let mid = &grid[y];
            let down = &grid[(y + 1) % n];
            let out = &mut next_grid[y];
            for x in 0..n {
                let left = (x + n - 1) % n;
                let right = (x + 1) % n;
                let around = up[left] + up[x] + up[right] + mid[left] + mid[right] + down[left] + down[x] + down[right];
                out[x] = if around == 3 || (around == 2 && mid[x] == 1) { 1 } else { 0 };
            }
        }
        std::mem::swap(&mut grid, &mut next_grid);
    }
    let mut alive = 0;
    let mut checksum: u64 = 0;
    for y in 0..n {
        for x in 0..n {
            if grid[y][x] == 1 {
                alive += 1;
                checksum = (checksum * 31 + (y * n + x) as u64) % 1000000007;
            }
        }
    }
    println!("{} {}", alive, checksum);
}
