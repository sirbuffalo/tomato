<?php
// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.

function a(int $i, int $j): float {
    return 1.0 / (intdiv(($i + $j) * ($i + $j + 1), 2) + $i + 1);
}

function times_a(int $n, array $v, array &$out): void {
    for ($i = 0; $i < $n; $i++) {
        $s = 0.0;
        for ($j = 0; $j < $n; $j++) $s += a($i, $j) * $v[$j];
        $out[$i] = $s;
    }
}

function times_a_transposed(int $n, array $v, array &$out): void {
    for ($i = 0; $i < $n; $i++) {
        $s = 0.0;
        for ($j = 0; $j < $n; $j++) $s += a($j, $i) * $v[$j];
        $out[$i] = $s;
    }
}

function times_at_a(int $n, array $v, array &$out, array &$tmp): void {
    times_a($n, $v, $tmp);
    times_a_transposed($n, $tmp, $out);
}

function main(int $n): void {
    $u = array_fill(0, $n, 1.0);
    $v = array_fill(0, $n, 0.0);
    $tmp = array_fill(0, $n, 0.0);
    for ($round = 0; $round < 10; $round++) {
        times_at_a($n, $u, $v, $tmp);
        times_at_a($n, $v, $u, $tmp);
    }
    $vbv = 0.0;
    $vv = 0.0;
    for ($i = 0; $i < $n; $i++) {
        $vbv += $u[$i] * $v[$i];
        $vv += $v[$i] * $v[$i];
    }
    echo (int)(sqrt($vbv / $vv) * 1000000000.0), "\n";
}

main((int)$argv[1]);
