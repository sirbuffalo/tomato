// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
// A matrix is an array of separately allocated rows, like the nested lists of the other versions.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    int64_t **a = malloc((size_t)n * sizeof *a), **b = malloc((size_t)n * sizeof *b);
    for (int64_t i = 0; i < n; i++) {
        a[i] = malloc((size_t)n * sizeof **a);
        b[i] = malloc((size_t)n * sizeof **b);
        for (int64_t j = 0; j < n; j++) {
            a[i][j] = (i * j + 1) % 10;
            b[i][j] = (i + j) % 10;
        }
    }
    int64_t total = 0;
    for (int64_t i = 0; i < n; i++) {
        const int64_t *row = a[i];
        for (int64_t j = 0; j < n; j++) {
            int64_t acc = 0;
            for (int64_t k = 0; k < n; k++) acc += row[k] * b[k][j];
            total += acc;
        }
    }
    printf("%lld\n", (long long)total);
    for (int64_t i = 0; i < n; i++) { free(a[i]); free(b[i]); }
    free(a); free(b);
}
