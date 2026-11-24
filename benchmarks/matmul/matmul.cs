// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
using System;

static class Program {
    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        long[][] a = new long[n][];
        long[][] b = new long[n][];
        for (int i = 0; i < n; i++) {
            a[i] = new long[n];
            b[i] = new long[n];
            for (int j = 0; j < n; j++) {
                a[i][j] = (i * j + 1) % 10;
                b[i][j] = (i + j) % 10;
            }
        }
        long total = 0;
        for (int i = 0; i < n; i++) {
            long[] row = a[i];
            for (int j = 0; j < n; j++) {
                long acc = 0;
                for (int k = 0; k < n; k++) acc += row[k] * b[k][j];
                total += acc;
            }
        }
        Console.WriteLine(total);
    }
}
