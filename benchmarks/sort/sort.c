// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
// The C library's sort is qsort, which calls a compare function.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int compare(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return (x > y) - (x < y);
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 12345;
    int64_t *values = malloc((size_t)n * sizeof *values);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        values[i] = seed;
    }
    qsort(values, (size_t)n, sizeof *values, compare);
    int64_t checksum = 0;
    for (int64_t i = 0; i < n; i++) checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007;
    printf("%lld\n", (long long)checksum);
    free(values);
}
