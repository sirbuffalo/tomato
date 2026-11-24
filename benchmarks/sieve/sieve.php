<?php
// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $composite = array_fill(0, $n + 1, false);
    $count = 0;
    for ($i = 2; $i <= $n; $i++) {
        if ($composite[$i]) continue;
        $count++;
        for ($j = $i * $i; $j <= $n; $j += $i) $composite[$j] = true;
    }
    echo $count, "\n";
}

main((int)$argv[1]);
