// Benchmark: naive recursive Fibonacci. Prints fib(n).
#include <cstdint>
#include <iostream>
#include <string>

static std::int64_t fib(std::int64_t n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(int, char **argv) {
    std::cout << fib(std::stoll(argv[1])) << '\n';
}
