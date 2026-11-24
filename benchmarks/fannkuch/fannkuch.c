// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    int64_t *perm1 = malloc((size_t)n * sizeof *perm1), *perm = calloc((size_t)n, sizeof *perm), *count = calloc((size_t)n, sizeof *count);
    for (int64_t i = 0; i < n; i++) perm1[i] = i;
    int64_t max_flips = 0, checksum = 0, perm_count = 0, r = n;
    int done = 0;
    while (!done) {
        while (r != 1) {
            count[r - 1] = r;
            r--;
        }
        for (int64_t i = 0; i < n; i++) perm[i] = perm1[i];
        int64_t flips = 0, k = perm[0];
        while (k != 0) {
            int64_t i = 0, j = k;
            while (i < j) {
                int64_t t = perm[i];
                perm[i] = perm[j];
                perm[j] = t;
                i++;
                j--;
            }
            flips++;
            k = perm[0];
        }
        if (flips > max_flips) max_flips = flips;
        if (perm_count % 2 == 0) checksum += flips;
        else checksum -= flips;
        while (1) {
            if (r == n) {
                done = 1;
                break;
            }
            int64_t p0 = perm1[0];
            for (int64_t i = 0; i < r; i++) perm1[i] = perm1[i + 1];
            perm1[r] = p0;
            count[r]--;
            if (count[r] > 0) break;
            r++;
        }
        perm_count++;
    }
    printf("%lld\n", (long long)checksum);
    printf("Pfannkuchen(%lld) = %lld\n", (long long)n, (long long)max_flips);
    free(perm1);
    free(perm);
    free(count);
}
