// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::size_t n = std::stoull(argv[1]);
    std::vector<std::vector<std::int64_t>> a(n, std::vector<std::int64_t>(n)), b = a;
    for (std::size_t i = 0; i < n; i++) {
        for (std::size_t j = 0; j < n; j++) {
            a[i][j] = static_cast<std::int64_t>((i * j + 1) % 10);
            b[i][j] = static_cast<std::int64_t>((i + j) % 10);
        }
    }
    std::int64_t total = 0;
    for (std::size_t i = 0; i < n; i++) {
        const auto &row = a[i];
        for (std::size_t j = 0; j < n; j++) {
            std::int64_t acc = 0;
            for (std::size_t k = 0; k < n; k++) acc += row[k] * b[k][j];
            total += acc;
        }
    }
    std::cout << total << '\n';
}
