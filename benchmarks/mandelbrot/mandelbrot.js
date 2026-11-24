// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
function main(n) {
  let total = 0;
  for (let py = 0; py < n; py++) {
    const ci = 2.0 * py / n - 1.0;
    for (let px = 0; px < n; px++) {
      const cr = 3.0 * px / n - 2.0;
      let zr = 0.0;
      let zi = 0.0;
      let i = 0;
      while (i < 100 && zr * zr + zi * zi <= 4.0) {
        const t = zr * zr - zi * zi + cr;
        zi = 2.0 * zr * zi + ci;
        zr = t;
        i++;
      }
      total += i;
    }
  }
  console.log(String(total));
}

main(Number(process.argv[2]));
