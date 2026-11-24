// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Nested arrays, neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long seed = 99;
        long[][] grid = new long[n][];
        long[][] nextGrid = new long[n][];
        for (int y = 0; y < n; y++) {
            long[] row = new long[n];
            for (int x = 0; x < n; x++) {
                seed = (seed * 1103515245L + 12345) % 2147483648L;
                if (seed / 65536 % 3 == 0) row[x] = 1;
            }
            grid[y] = row;
            nextGrid[y] = new long[n];
        }
        for (int gen = 0; gen < 100; gen++) {
            for (int y = 0; y < n; y++) {
                long[] up = grid[(y + n - 1) % n];
                long[] mid = grid[y];
                long[] down = grid[(y + 1) % n];
                long[] output = nextGrid[y];
                for (int x = 0; x < n; x++) {
                    int left = (x + n - 1) % n;
                    int right = (x + 1) % n;
                    long around = up[left] + up[x] + up[right] + mid[left] + mid[right] + down[left] + down[x] + down[right];
                    if (around == 3 || (around == 2 && mid[x] == 1)) output[x] = 1;
                    else output[x] = 0;
                }
            }
            long[][] swap = grid;
            grid = nextGrid;
            nextGrid = swap;
        }
        long alive = 0;
        long checksum = 0;
        for (int y = 0; y < n; y++) {
            for (int x = 0; x < n; x++) {
                if (grid[y][x] == 1) {
                    alive++;
                    checksum = (checksum * 31 + (long)y * n + x) % 1000000007L;
                }
            }
        }
        Console.WriteLine($"{alive} {checksum}");
    }
}
