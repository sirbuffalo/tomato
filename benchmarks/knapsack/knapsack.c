// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 7;
    int64_t *weights = malloc((size_t)n * sizeof *weights), *values = malloc((size_t)n * sizeof *values);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        weights[i] = seed / 65536 % 60 + 1;
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed / 65536 % 1000 + 1;
    }
    int64_t capacity = 5 * n;
    int64_t *best = calloc((size_t)(capacity + 1), sizeof *best);
    for (int64_t i = 0; i < n; i++) {
        int64_t w = weights[i], v = values[i];
        for (int64_t c = capacity; c >= w; c--) {
            int64_t candidate = best[c - w] + v;
            if (candidate > best[c]) best[c] = candidate;
        }
    }
    printf("%lld\n", (long long)best[capacity]);
    free(weights);
    free(values);
    free(best);
}
