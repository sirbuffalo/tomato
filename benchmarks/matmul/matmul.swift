// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
func run(_ n: Int) {
    var a: [[Int]] = []
    var b: [[Int]] = []
    for i in 0..<n {
        a.append((0..<n).map { (i * $0 + 1) % 10 })
        b.append((0..<n).map { (i + $0) % 10 })
    }
    var total = 0
    for i in 0..<n {
        let row = a[i]
        for j in 0..<n {
            var acc = 0
            for k in 0..<n { acc += row[k] * b[k][j] }
            total += acc
        }
    }
    print(total)
}

run(Int(CommandLine.arguments[1])!)
