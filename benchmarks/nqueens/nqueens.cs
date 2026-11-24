// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, arrays of booleans for the columns and the two diagonals).
using System;

static class Program {
    static long Place(int n, int row, bool[] cols, bool[] diag1, bool[] diag2) {
        if (row == n) return 1;
        long count = 0;
        for (int c = 0; c < n; c++) {
            int d1 = row + c;
            int d2 = row - c + n - 1;
            if (cols[c] || diag1[d1] || diag2[d2]) continue;
            cols[c] = true;
            diag1[d1] = true;
            diag2[d2] = true;
            count += Place(n, row + 1, cols, diag1, diag2);
            cols[c] = false;
            diag1[d1] = false;
            diag2[d2] = false;
        }
        return count;
    }

    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        Console.WriteLine(Place(n, 0, new bool[n], new bool[2 * n], new bool[2 * n]));
    }
}
