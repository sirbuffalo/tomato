<?php
// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
function main(int $n): void {
    $best_start = 1;
    $best_length = 1;
    for ($start = 1; $start < $n; $start++) {
        $x = $start;
        $length = 1;
        while ($x !== 1) {
            if ($x % 2 === 0) $x = intdiv($x, 2);
            else $x = 3 * $x + 1;
            $length++;
        }
        if ($length > $best_length) {
            $best_length = $length;
            $best_start = $start;
        }
    }
    echo "$best_start $best_length\n";
}

main((int)$argv[1]);
