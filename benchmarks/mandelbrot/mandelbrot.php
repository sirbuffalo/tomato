<?php
// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
function main(int $n): void {
    $total = 0;
    for ($py = 0; $py < $n; $py++) {
        $ci = 2.0 * $py / $n - 1.0;
        for ($px = 0; $px < $n; $px++) {
            $cr = 3.0 * $px / $n - 2.0;
            $zr = 0.0;
            $zi = 0.0;
            $i = 0;
            while ($i < 100 && $zr * $zr + $zi * $zi <= 4.0) {
                $t = $zr * $zr - $zi * $zi + $cr;
                $zi = 2.0 * $zr * $zi + $ci;
                $zr = $t;
                $i++;
            }
            $total += $i;
        }
    }
    echo $total, "\n";
}

main((int)$argv[1]);
