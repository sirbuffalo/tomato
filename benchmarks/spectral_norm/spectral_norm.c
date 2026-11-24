// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static double a(int64_t i, int64_t j) { return 1.0 / (double)((i + j) * (i + j + 1) / 2 + i + 1); }

static void times_a(int64_t n, const double *v, double *out) {
    for (int64_t i = 0; i < n; i++) {
        double s = 0.0;
        for (int64_t j = 0; j < n; j++) s += a(i, j) * v[j];
        out[i] = s;
    }
}

static void times_a_transposed(int64_t n, const double *v, double *out) {
    for (int64_t i = 0; i < n; i++) {
        double s = 0.0;
        for (int64_t j = 0; j < n; j++) s += a(j, i) * v[j];
        out[i] = s;
    }
}

static void times_at_a(int64_t n, const double *v, double *out, double *tmp) {
    times_a(n, v, tmp);
    times_a_transposed(n, tmp, out);
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]);
    double *u = malloc((size_t)n * sizeof *u), *v = calloc((size_t)n, sizeof *v), *tmp = calloc((size_t)n, sizeof *tmp);
    for (int64_t i = 0; i < n; i++) u[i] = 1.0;
    for (int round = 0; round < 10; round++) {
        times_at_a(n, u, v, tmp);
        times_at_a(n, v, u, tmp);
    }
    double vbv = 0.0, vv = 0.0;
    for (int64_t i = 0; i < n; i++) {
        vbv += u[i] * v[i];
        vv += v[i] * v[i];
    }
    printf("%lld\n", (long long)(sqrt(vbv / vv) * 1000000000.0));
    free(u);
    free(v);
    free(tmp);
}
