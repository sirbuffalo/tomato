<?php
// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $parts = [];
    for ($i = 0; $i < $n; $i++) $parts[] = (string)($i * 7 % 1000);
    $text = implode(',', $parts);
    $total = 0;
    foreach (explode(',', $text) as $piece) $total += (int)$piece;
    echo strlen($text), ' ', $total, "\n";
}

main((int)$argv[1]);
