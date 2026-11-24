<?php
// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.

function main(int $n): void {
    $seed = 42;
    $letters = ['a', 'b', 'c', 'd'];
    $first = [];
    $second = [];
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $first[] = $letters[intdiv($seed, 65536) % 4];
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $second[] = $letters[intdiv($seed, 65536) % 4];
    }
    $s = implode('', $first);
    $t = implode('', $second);
    $prev = range(0, $n);
    $cur = array_fill(0, $n + 1, 0);
    for ($i = 1; $i <= $n; $i++) {
        $cur[0] = $i;
        $si = $s[$i - 1];
        for ($j = 1; $j <= $n; $j++) {
            $cost = 1;
            if ($si === $t[$j - 1]) $cost = 0;
            $best = $prev[$j - 1] + $cost;
            $up = $prev[$j] + 1;
            if ($up < $best) $best = $up;
            $left = $cur[$j - 1] + 1;
            if ($left < $best) $best = $left;
            $cur[$j] = $best;
        }
        $swap = $prev;
        $prev = $cur;
        $cur = $swap;
    }
    echo $prev[$n], "\n";
}

main((int)$argv[1]);
