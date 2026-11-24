<?php
// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $seed = 12345;
    $values = [];
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $values[] = $seed;
    }
    sort($values, SORT_NUMERIC);
    $checksum = 0;
    for ($i = 0; $i < $n; $i++) $checksum = ($checksum + ($i % 1000 + 1) * $values[$i]) % 1000000007;
    echo $checksum, "\n";
}

main((int)$argv[1]);
