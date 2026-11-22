# Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
import sys

n = int(sys.argv[1])
total = 0
for py in range(n):
    ci = 2.0 * py / n - 1.0
    for px in range(n):
        cr = 3.0 * px / n - 2.0
        zr = 0.0
        zi = 0.0
        i = 0
        while i < 100 and zr * zr + zi * zi <= 4.0:
            t = zr * zr - zi * zi + cr
            zi = 2.0 * zr * zi + ci
            zr = t
            i += 1
        total += i
print(total)
