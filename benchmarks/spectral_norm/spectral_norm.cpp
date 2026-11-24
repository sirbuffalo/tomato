// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

static double a(std::int64_t i, std::int64_t j) { return 1.0 / static_cast<double>((i + j) * (i + j + 1) / 2 + i + 1); }

static void times_a(std::int64_t n, const std::vector<double> &v, std::vector<double> &out) {
    for (std::int64_t i = 0; i < n; i++) {
        double s = 0.0;
        for (std::int64_t j = 0; j < n; j++) s += a(i, j) * v[j];
        out[i] = s;
    }
}

static void times_a_transposed(std::int64_t n, const std::vector<double> &v, std::vector<double> &out) {
    for (std::int64_t i = 0; i < n; i++) {
        double s = 0.0;
        for (std::int64_t j = 0; j < n; j++) s += a(j, i) * v[j];
        out[i] = s;
    }
}

static void times_at_a(std::int64_t n, const std::vector<double> &v, std::vector<double> &out, std::vector<double> &tmp) {
    times_a(n, v, tmp);
    times_a_transposed(n, tmp, out);
}

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::vector<double> u(n, 1.0), v(n, 0.0), tmp(n, 0.0);
    for (int round = 0; round < 10; round++) {
        times_at_a(n, u, v, tmp);
        times_at_a(n, v, u, tmp);
    }
    double vbv = 0.0, vv = 0.0;
    for (std::int64_t i = 0; i < n; i++) {
        vbv += u[i] * v[i];
        vv += v[i] * v[i];
    }
    std::cout << static_cast<std::int64_t>(std::sqrt(vbv / vv) * 1000000000.0) << '\n';
}
