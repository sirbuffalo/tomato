<?php
// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted list.
ini_set('memory_limit', '-1');

function insertion_sort(array &$values, int $low, int $high): void {
    for ($i = $low + 1; $i <= $high; $i++) {
        $x = $values[$i];
        $j = $i - 1;
        while ($j >= $low && $values[$j] > $x) {
            $values[$j + 1] = $values[$j];
            $j--;
        }
        $values[$j + 1] = $x;
    }
}

function quicksort(array &$values, int $low, int $high): void {
    while ($high - $low > 16) {
        $pivot = $values[($low + $high) >> 1];
        $i = $low;
        $j = $high;
        while ($i <= $j) {
            while ($values[$i] < $pivot) $i++;
            while ($values[$j] > $pivot) $j--;
            if ($i <= $j) {
                $t = $values[$i];
                $values[$i] = $values[$j];
                $values[$j] = $t;
                $i++;
                $j--;
            }
        }
        // recurse into the smaller part, loop on the larger one
        if ($j - $low < $high - $i) {
            quicksort($values, $low, $j);
            $low = $i;
        } else {
            quicksort($values, $i, $high);
            $high = $j;
        }
    }
    insertion_sort($values, $low, $high);
}

function main(int $n): void {
    $seed = 12345;
    $values = array_fill(0, $n, 0);
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $values[$i] = $seed;
    }
    quicksort($values, 0, $n - 1);
    $checksum = 0;
    for ($i = 0; $i < $n; $i++) $checksum = ($checksum + ($i % 1000 + 1) * $values[$i]) % 1000000007;
    echo $checksum, "\n";
}

main((int)$argv[1]);
