// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), best_start = 1, best_length = 1;
    for (int64_t start = 1; start < n; start++) {
        int64_t x = start, length = 1;
        while (x != 1) {
            if (x % 2 == 0) x /= 2;
            else x = 3 * x + 1;
            length++;
        }
        if (length > best_length) {
            best_length = length;
            best_start = start;
        }
    }
    printf("%lld %lld\n", (long long)best_start, (long long)best_length);
}
