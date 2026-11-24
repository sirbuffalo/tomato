// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
func run(_ n: Int) {
    var composite = [Bool](repeating: false, count: n + 1)
    var count = 0
    var i = 2
    while i <= n {
        if !composite[i] {
            count += 1
            var j = i * i
            while j <= n {
                composite[j] = true
                j += i
            }
        }
        i += 1
    }
    print(count)
}

run(Int(CommandLine.arguments[1])!)
