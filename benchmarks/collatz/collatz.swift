// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
func run(_ n: Int) {
    var bestStart = 1
    var bestLength = 1
    var start = 1
    while start < n {
        var x = start
        var length = 1
        while x != 1 {
            if x % 2 == 0 { x /= 2 } else { x = 3 * x + 1 }
            length += 1
        }
        if length > bestLength {
            bestLength = length
            bestStart = start
        }
        start += 1
    }
    print(bestStart, bestLength)
}

run(Int(CommandLine.arguments[1])!)
