<?php
// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $seed = 2718;
    $letters = ['A', 'C', 'G', 'T'];
    $parts = [];
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $parts[] = $letters[intdiv($seed, 65536) % 4];
    }
    $dna = implode('', $parts);
    $lines = [];
    for ($start = 0; $start < $n; $start += 60) $lines[] = substr($dna, $start, 60);
    $text = implode('', $lines);
    $complement = ['A' => 'T', 'C' => 'G', 'G' => 'C', 'T' => 'A'];
    $out = [];
    for ($i = strlen($text) - 1; $i >= 0; $i--) $out[] = $complement[$text[$i]];
    $rc = implode('', $out);
    $wrapped = [];
    $len = strlen($rc);
    for ($start = 0; $start < $len; $start += 60) $wrapped[] = substr($rc, $start, 60);
    $checksum = 0;
    foreach ($wrapped as $line) {
        $m = strlen($line);
        for ($k = 0; $k < $m; $k += 7) $checksum = ($checksum * 131 + ord($line[$k])) % 1000000007;
    }
    echo count($wrapped), " ", $checksum, "\n";
}

main((int)$argv[1]);
