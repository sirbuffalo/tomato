<?php
// Benchmark: naive recursive Fibonacci. Prints fib(n).
function fib(int $n): int {
    if ($n < 2) return $n;
    return fib($n - 1) + fib($n - 2);
}

echo fib((int)$argv[1]), "\n";
