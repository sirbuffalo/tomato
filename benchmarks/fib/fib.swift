// Benchmark: naive recursive Fibonacci. Prints fib(n).
func fib(_ n: Int) -> Int {
    if n < 2 { return n }
    return fib(n - 1) + fib(n - 2)
}

print(fib(Int(CommandLine.arguments[1])!))
