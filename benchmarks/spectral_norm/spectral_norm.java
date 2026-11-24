// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
class spectral_norm {
    static double a(long i, long j) {
        return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);
    }

    static void timesA(int n, double[] v, double[] out) {
        for (int i = 0; i < n; i++) {
            double s = 0.0;
            for (int j = 0; j < n; j++) s += a(i, j) * v[j];
            out[i] = s;
        }
    }

    static void timesATransposed(int n, double[] v, double[] out) {
        for (int i = 0; i < n; i++) {
            double s = 0.0;
            for (int j = 0; j < n; j++) s += a(j, i) * v[j];
            out[i] = s;
        }
    }

    static void timesAtA(int n, double[] v, double[] out, double[] tmp) {
        timesA(n, v, tmp);
        timesATransposed(n, tmp, out);
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        double[] u = new double[n];
        java.util.Arrays.fill(u, 1.0);
        double[] v = new double[n];
        double[] tmp = new double[n];
        for (int round = 0; round < 10; round++) {
            timesAtA(n, u, v, tmp);
            timesAtA(n, v, u, tmp);
        }
        double vbv = 0.0, vv = 0.0;
        for (int i = 0; i < n; i++) {
            vbv += u[i] * v[i];
            vv += v[i] * v[i];
        }
        System.out.println((long) (Math.sqrt(vbv / vv) * 1000000000.0));
    }
}
