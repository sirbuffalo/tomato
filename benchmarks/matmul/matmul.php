<?php
// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
function main(int $n): void {
    $a = [];
    $b = [];
    for ($i = 0; $i < $n; $i++) {
        $ra = [];
        $rb = [];
        for ($j = 0; $j < $n; $j++) {
            $ra[] = ($i * $j + 1) % 10;
            $rb[] = ($i + $j) % 10;
        }
        $a[] = $ra;
        $b[] = $rb;
    }
    $total = 0;
    for ($i = 0; $i < $n; $i++) {
        $row = $a[$i];
        for ($j = 0; $j < $n; $j++) {
            $acc = 0;
            for ($k = 0; $k < $n; $k++) $acc += $row[$k] * $b[$k][$j];
            $total += $acc;
        }
    }
    echo $total, "\n";
}

main((int)$argv[1]);
