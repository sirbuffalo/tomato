// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
class matmul {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long[][] a = new long[n][n];
        long[][] b = new long[n][n];
        for (int i = 0; i < n; i++) {
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
        System.out.println(total);
    }
}
