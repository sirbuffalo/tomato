// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
class mandelbrot {
    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        long total = 0;
        for (int py = 0; py < n; py++) {
            double ci = 2.0 * py / n - 1.0;
            for (int px = 0; px < n; px++) {
                double cr = 3.0 * px / n - 2.0;
                double zr = 0.0;
                double zi = 0.0;
                int i = 0;
                while (i < 100 && zr * zr + zi * zi <= 4.0) {
                    double t = zr * zr - zi * zi + cr;
                    zi = 2.0 * zr * zi + ci;
                    zr = t;
                    i++;
                }
                total += i;
            }
        }
        System.out.println(total);
    }
}
