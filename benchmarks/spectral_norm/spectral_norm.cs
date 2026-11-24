// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
using System;

static class Program {
    static double A(long i, long j) {
        return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);
    }

    static void TimesA(int n, double[] v, double[] output) {
        for (int i = 0; i < n; i++) {
            double s = 0.0;
            for (int j = 0; j < n; j++) s += A(i, j) * v[j];
            output[i] = s;
        }
    }

    static void TimesATransposed(int n, double[] v, double[] output) {
        for (int i = 0; i < n; i++) {
            double s = 0.0;
            for (int j = 0; j < n; j++) s += A(j, i) * v[j];
            output[i] = s;
        }
    }

    static void TimesAtA(int n, double[] v, double[] output, double[] tmp) {
        TimesA(n, v, tmp);
        TimesATransposed(n, tmp, output);
    }

    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        double[] u = new double[n];
        Array.Fill(u, 1.0);
        double[] v = new double[n];
        double[] tmp = new double[n];
        for (int round = 0; round < 10; round++) {
            TimesAtA(n, u, v, tmp);
            TimesAtA(n, v, u, tmp);
        }
        double vbv = 0.0, vv = 0.0;
        for (int i = 0; i < n; i++) {
            vbv += u[i] * v[i];
            vv += v[i] * v[i];
        }
        Console.WriteLine((long)(Math.Sqrt(vbv / vv) * 1000000000.0));
    }
}
