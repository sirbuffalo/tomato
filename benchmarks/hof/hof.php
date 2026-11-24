<?php
// Benchmark: function values. Calls one of four functions chosen from a list n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
ini_set('memory_limit', '-1');

function f0(int $x): int { return ($x * 3 + 1) % 1000003; }
function f1(int $x): int { return ($x + 7919) % 1000003; }
function f2(int $x): int { return $x * $x % 1000003; }
function f3(int $x): int { return ($x ^ 12345) % 1000003; }

function apply_twice(callable $f, int $x): int {
    return $f($f($x));
}

function main(int $n): void {
    $table = [f0(...), f1(...), f2(...), f3(...)];
    $x = 1;
    for ($i = 0; $i < $n; $i++) {
        $x = $table[$i % 4]($x + $i);
    }
    echo $x, "\n";
    $y = 0;
    for ($i = 0; $i < $n; $i++) {
        $y = ($y + apply_twice($table[$i % 4], $i)) % 1000000007;
    }
    echo $y, "\n";
    $m = intdiv($n, 4);
    $xs = [];
    for ($i = 0; $i < $m; $i++) $xs[] = $i * 7919 % 100003;
    $squares = array_map(fn($v) => $v * $v % 1009, $xs);
    $odd = array_values(array_filter($squares, fn($v) => $v % 2 == 1));
    // sorted by key, ties kept in their original order (PHP's sort is stable)
    $keyFn = fn($v) => $v % 997 * 1000 + $v % 1000;
    $keys = array_map($keyFn, $odd);
    $idx = array_keys($odd);
    usort($idx, fn($a, $b) => $keys[$a] <=> $keys[$b]);
    $z = 0;
    foreach ($idx as $i) $z = ($z * 31 + $odd[$i]) % 1000000007;
    echo count($odd), " ", $z, "\n";
}

main((int)$argv[1]);
