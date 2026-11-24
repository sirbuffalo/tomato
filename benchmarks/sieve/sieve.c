// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), count = 0;
    bool *composite = calloc((size_t)n + 1, 1);
    for (int64_t i = 2; i <= n; i++) {
        if (composite[i]) continue;
        count++;
        for (int64_t j = i * i; j <= n; j += i) composite[j] = true;
    }
    printf("%lld\n", (long long)count);
    free(composite);
}
