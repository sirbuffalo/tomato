// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Nested vectors, neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), seed = 99;
    std::vector<std::vector<std::int64_t>> grid, next_grid;
    for (std::int64_t y = 0; y < n; y++) {
        std::vector<std::int64_t> row(n, 0);
        for (std::int64_t x = 0; x < n; x++) {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            if (seed / 65536 % 3 == 0) row[x] = 1;
        }
        grid.push_back(std::move(row));
        next_grid.emplace_back(n, 0);
    }
    for (int gen = 0; gen < 100; gen++) {
        for (std::int64_t y = 0; y < n; y++) {
            const auto &up = grid[(y + n - 1) % n], &mid = grid[y], &down = grid[(y + 1) % n];
            auto &out = next_grid[y];
            for (std::int64_t x = 0; x < n; x++) {
                std::int64_t left = (x + n - 1) % n, right = (x + 1) % n;
                std::int64_t around = up[left] + up[x] + up[right] + mid[left] + mid[right] + down[left] + down[x] + down[right];
                out[x] = (around == 3 || (around == 2 && mid[x] == 1)) ? 1 : 0;
            }
        }
        std::swap(grid, next_grid);
    }
    std::int64_t alive = 0, checksum = 0;
    for (std::int64_t y = 0; y < n; y++)
        for (std::int64_t x = 0; x < n; x++)
            if (grid[y][x] == 1) {
                alive++;
                checksum = (checksum * 31 + y * n + x) % 1000000007;
            }
    std::cout << alive << ' ' << checksum << '\n';
}
