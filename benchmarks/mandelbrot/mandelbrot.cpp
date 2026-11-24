// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
#include <cstdint>
#include <iostream>
#include <string>

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]), total = 0;
    for (std::int64_t py = 0; py < n; py++) {
        double ci = 2.0 * static_cast<double>(py) / static_cast<double>(n) - 1.0;
        for (std::int64_t px = 0; px < n; px++) {
            double cr = 3.0 * static_cast<double>(px) / static_cast<double>(n) - 2.0, zr = 0.0, zi = 0.0;
            std::int64_t i = 0;
            while (i < 100 && zr * zr + zi * zi <= 4.0) {
                double t = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = t;
                i++;
            }
            total += i;
        }
    }
    std::cout << total << '\n';
}
