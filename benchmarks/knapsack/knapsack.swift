// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
let n = Int(CommandLine.arguments[1])!
var seed = 7
var weights = [Int](repeating: 0, count: n)
var values = [Int](repeating: 0, count: n)
for i in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    weights[i] = seed / 65536 % 60 + 1
    seed = (seed * 1103515245 + 12345) % 2147483648
    values[i] = seed / 65536 % 1000 + 1
}
let capacity = 5 * n
var best = [Int](repeating: 0, count: capacity + 1)
for i in 0..<n {
    let w = weights[i]
    let v = values[i]
    var c = capacity
    while c >= w {
        let candidate = best[c - w] + v
        if candidate > best[c] { best[c] = candidate }
        c -= 1
    }
}
print(best[capacity])
