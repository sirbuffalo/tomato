// Benchmark: naive recursive Fibonacci. Prints fib(n).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int64_t fib(int64_t n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(int argc, char **argv) {
    (void)argc;
    printf("%lld\n", (long long)fib(atoll(argv[1])));
}
