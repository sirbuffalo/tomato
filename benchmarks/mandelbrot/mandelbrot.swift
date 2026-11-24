// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
func run(_ n: Int) {
    var total = 0
    for py in 0..<n {
        let ci = 2.0 * Double(py) / Double(n) - 1.0
        for px in 0..<n {
            let cr = 3.0 * Double(px) / Double(n) - 2.0
            var zr = 0.0
            var zi = 0.0
            var i = 0
            while i < 100 && zr * zr + zi * zi <= 4.0 {
                let t = zr * zr - zi * zi + cr
                zi = 2.0 * zr * zi + ci
                zr = t
                i += 1
            }
            total += i
        }
    }
    print(total)
}

run(Int(CommandLine.arguments[1])!)
