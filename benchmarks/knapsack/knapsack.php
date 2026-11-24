<?php
// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.

function main(int $n): void {
    $seed = 7;
    $weights = array_fill(0, $n, 0);
    $values = array_fill(0, $n, 0);
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $weights[$i] = intdiv($seed, 65536) % 60 + 1;
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $values[$i] = intdiv($seed, 65536) % 1000 + 1;
    }
    $capacity = 5 * $n;
    $best = array_fill(0, $capacity + 1, 0);
    for ($i = 0; $i < $n; $i++) {
        $w = $weights[$i];
        $v = $values[$i];
        for ($c = $capacity; $c >= $w; $c--) {
            $candidate = $best[$c - $w] + $v;
            if ($candidate > $best[$c]) $best[$c] = $candidate;
        }
    }
    echo $best[$capacity], "\n";
}

main((int)$argv[1]);
