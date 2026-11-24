// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, vectors of bools for the columns and the two diagonals).
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

static std::int64_t place(std::int64_t n, std::int64_t row, std::vector<bool> &cols, std::vector<bool> &diag1, std::vector<bool> &diag2) {
    if (row == n) return 1;
    std::int64_t count = 0;
    for (std::int64_t c = 0; c < n; c++) {
        std::int64_t d1 = row + c, d2 = row - c + n - 1;
        if (cols[c] || diag1[d1] || diag2[d2]) continue;
        cols[c] = diag1[d1] = diag2[d2] = true;
        count += place(n, row + 1, cols, diag1, diag2);
        cols[c] = diag1[d1] = diag2[d2] = false;
    }
    return count;
}

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    std::vector<bool> cols(n, false), diag1(2 * n, false), diag2(2 * n, false);
    std::cout << place(n, 0, cols, diag1, diag2) << '\n';
}
