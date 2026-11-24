// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 42;
    const char letters[] = "abcd";
    char *s = malloc((size_t)n + 1), *t = malloc((size_t)n + 1);
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        s[i] = letters[seed / 65536 % 4];
        seed = (seed * 1103515245 + 12345) % 2147483648;
        t[i] = letters[seed / 65536 % 4];
    }
    int64_t *prev = malloc((size_t)(n + 1) * sizeof *prev), *cur = calloc((size_t)(n + 1), sizeof *cur);
    for (int64_t j = 0; j <= n; j++) prev[j] = j;
    for (int64_t i = 1; i <= n; i++) {
        cur[0] = i;
        char si = s[i - 1];
        for (int64_t j = 1; j <= n; j++) {
            int64_t cost = si == t[j - 1] ? 0 : 1;
            int64_t best = prev[j - 1] + cost;
            int64_t up = prev[j] + 1;
            if (up < best) best = up;
            int64_t left = cur[j - 1] + 1;
            if (left < best) best = left;
            cur[j] = best;
        }
        int64_t *swap = prev;
        prev = cur;
        cur = swap;
    }
    printf("%lld\n", (long long)prev[n]);
    free(s);
    free(t);
    free(prev);
    free(cur);
}
