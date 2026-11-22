// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let fn_ = n as f64;
    let mut total: u64 = 0;
    for py in 0..n {
        let ci = 2.0 * py as f64 / fn_ - 1.0;
        for px in 0..n {
            let cr = 3.0 * px as f64 / fn_ - 2.0;
            let (mut zr, mut zi) = (0.0f64, 0.0f64);
            let mut i = 0;
            while i < 100 && zr * zr + zi * zi <= 4.0 {
                let t = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = t;
                i += 1;
            }
            total += i;
        }
    }
    println!("{}", total);
}
