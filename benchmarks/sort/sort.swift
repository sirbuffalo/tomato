// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
func run(_ n: Int) {
    var seed = 12345
    var values = [Int](repeating: 0, count: n)
    for i in 0..<n {
        seed = (seed * 1103515245 + 12345) % 2147483648
        values[i] = seed
    }
    let ordered = values.sorted()
    var checksum = 0
    for i in 0..<n { checksum = (checksum + (i % 1000 + 1) * ordered[i]) % 1000000007 }
    print(checksum)
}

run(Int(CommandLine.arguments[1])!)
