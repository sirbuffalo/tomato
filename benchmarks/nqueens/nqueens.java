// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, arrays of booleans for the columns and the two diagonals).
class nqueens {
    static long place(int n, int row, boolean[] cols, boolean[] diag1, boolean[] diag2) {
        if (row == n) return 1;
        long count = 0;
        for (int c = 0; c < n; c++) {
            int d1 = row + c;
            int d2 = row - c + n - 1;
            if (cols[c] || diag1[d1] || diag2[d2]) continue;
            cols[c] = true;
            diag1[d1] = true;
            diag2[d2] = true;
            count += place(n, row + 1, cols, diag1, diag2);
            cols[c] = false;
            diag1[d1] = false;
            diag2[d2] = false;
        }
        return count;
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        System.out.println(place(n, 0, new boolean[n], new boolean[2 * n], new boolean[2 * n]));
    }
}
