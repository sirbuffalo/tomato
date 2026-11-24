// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, arrays of flags for the columns and the two diagonals).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int64_t place(int64_t n, int64_t row, char *cols, char *diag1, char *diag2) {
    if (row == n) return 1;
    int64_t count = 0;
    for (int64_t c = 0; c < n; c++) {
        int64_t d1 = row + c, d2 = row - c + n - 1;
        if (cols[c] || diag1[d1] || diag2[d2]) continue;
        cols[c] = diag1[d1] = diag2[d2] = 1;
        count += place(n, row + 1, cols, diag1, diag2);
        cols[c] = diag1[d1] = diag2[d2] = 0;
    }
    return count;
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    char *cols = calloc((size_t)n, 1), *diag1 = calloc((size_t)(2 * n), 1), *diag2 = calloc((size_t)(2 * n), 1);
    printf("%lld\n", (long long)place(n, 0, cols, diag1, diag2));
    free(cols);
    free(diag1);
    free(diag2);
}
