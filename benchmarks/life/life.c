// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), seed = 99;
    int64_t **grid = malloc((size_t)n * sizeof *grid), **next_grid = malloc((size_t)n * sizeof *next_grid);
    for (int64_t y = 0; y < n; y++) {
        grid[y] = calloc((size_t)n, sizeof **grid);
        next_grid[y] = calloc((size_t)n, sizeof **next_grid);
        for (int64_t x = 0; x < n; x++) {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            if (seed / 65536 % 3 == 0) grid[y][x] = 1;
        }
    }
    for (int gen = 0; gen < 100; gen++) {
        for (int64_t y = 0; y < n; y++) {
            int64_t *up = grid[(y + n - 1) % n], *mid = grid[y], *down = grid[(y + 1) % n], *out = next_grid[y];
            for (int64_t x = 0; x < n; x++) {
                int64_t left = (x + n - 1) % n, right = (x + 1) % n;
                int64_t around = up[left] + up[x] + up[right] + mid[left] + mid[right] + down[left] + down[x] + down[right];
                out[x] = (around == 3 || (around == 2 && mid[x] == 1)) ? 1 : 0;
            }
        }
        int64_t **swap = grid;
        grid = next_grid;
        next_grid = swap;
    }
    int64_t alive = 0, checksum = 0;
    for (int64_t y = 0; y < n; y++)
        for (int64_t x = 0; x < n; x++)
            if (grid[y][x] == 1) {
                alive++;
                checksum = (checksum * 31 + y * n + x) % 1000000007;
            }
    printf("%lld %lld\n", (long long)alive, (long long)checksum);
    for (int64_t y = 0; y < n; y++) {
        free(grid[y]);
        free(next_grid[y]);
    }
    free(grid);
    free(next_grid);
}
