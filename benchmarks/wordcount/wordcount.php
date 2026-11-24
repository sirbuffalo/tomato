<?php
// Benchmark: word counting in an array. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
function main(int $n): void {
    $counts = [];
    for ($i = 0; $i < $n; $i++) {
        $word = 'w' . ($i * 7919 % 5003);
        $counts[$word] = ($counts[$word] ?? 0) + 1;
    }
    $checksum = 0;
    for ($k = 0; $k < 5003; $k++) $checksum += ($k + 1) * ($counts["w$k"] ?? 0);
    echo count($counts), ' ', $checksum, "\n";
}

main((int)$argv[1]);
