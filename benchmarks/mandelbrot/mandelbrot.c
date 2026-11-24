// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    (void)argc;
    int64_t n = atoll(argv[1]), total = 0;
    for (int64_t py = 0; py < n; py++) {
        double ci = 2.0 * (double)py / (double)n - 1.0;
        for (int64_t px = 0; px < n; px++) {
            double cr = 3.0 * (double)px / (double)n - 2.0, zr = 0.0, zi = 0.0;
            int64_t i = 0;
            while (i < 100 && zr * zr + zi * zi <= 4.0) {
                double t = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = t;
                i++;
            }
            total += i;
        }
    }
    printf("%lld\n", (long long)total);
}
