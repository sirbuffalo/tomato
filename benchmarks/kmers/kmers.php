<?php
// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a dict. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $seed = 31337;
    $letters = ['A', 'C', 'G', 'T'];
    $parts = [];
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $parts[] = $letters[intdiv($seed, 65536) % 4];
    }
    $dna = implode('', $parts);
    foreach ([1, 2, 4, 6, 12] as $k) {
        $counts = [];
        for ($i = 0; $i < $n - $k + 1; $i++) {
            $key = substr($dna, $i, $k);
            $counts[$key] = ($counts[$key] ?? 0) + 1;
        }
        $most = 0;
        $squares = 0;
        foreach ($counts as $c) {
            if ($c > $most) $most = $c;
            $squares += $c * $c;
        }
        echo $k, " ", count($counts), " ", $most, " ", $squares, "\n";
    }
}

main((int)$argv[1]);
