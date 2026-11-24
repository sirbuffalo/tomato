<?php
// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.

function push(array &$heap, int $size, int $key): int {
    if ($size == count($heap)) {
        $heap[] = $key;
    } else {
        $heap[$size] = $key;
    }
    $i = $size;
    while ($i > 0) {
        $parent = ($i - 1) >> 1;
        if ($heap[$parent] <= $key) break;
        $heap[$i] = $heap[$parent];
        $i = $parent;
    }
    $heap[$i] = $key;
    return $size + 1;
}

function pop(array &$heap, int $size): int {
    // removes the smallest key (the caller has read heap[0]) and returns the new size
    $size--;
    $key = $heap[$size];
    $i = 0;
    while (true) {
        $child = 2 * $i + 1;
        if ($child >= $size) break;
        if ($child + 1 < $size && $heap[$child + 1] < $heap[$child]) $child++;
        if ($heap[$child] >= $key) break;
        $heap[$i] = $heap[$child];
        $i = $child;
    }
    $heap[$i] = $key;
    return $size;
}

function main(int $n): void {
    $seed = 2024;
    $cost = array_fill(0, $n * $n, 0);
    for ($i = 0; $i < $n * $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $cost[$i] = intdiv($seed, 65536) % 9 + 1;
    }
    $cells = $n * $n;
    $infinity = 1000000000;
    $dist = array_fill(0, $cells, $infinity);
    $heap = array_fill(0, 16, 0);
    $size = 0;
    $dist[0] = 0;
    $size = push($heap, $size, 0);
    while ($size > 0) {
        $top = $heap[0];
        $size = pop($heap, $size);
        $d = intdiv($top, $cells);
        $cell = $top % $cells;
        if ($d > $dist[$cell]) continue;
        $y = intdiv($cell, $n);
        $x = $cell % $n;
        if ($y > 0 && $d + $cost[$cell - $n] < $dist[$cell - $n]) {
            $dist[$cell - $n] = $d + $cost[$cell - $n];
            $size = push($heap, $size, $dist[$cell - $n] * $cells + $cell - $n);
        }
        if ($y < $n - 1 && $d + $cost[$cell + $n] < $dist[$cell + $n]) {
            $dist[$cell + $n] = $d + $cost[$cell + $n];
            $size = push($heap, $size, $dist[$cell + $n] * $cells + $cell + $n);
        }
        if ($x > 0 && $d + $cost[$cell - 1] < $dist[$cell - 1]) {
            $dist[$cell - 1] = $d + $cost[$cell - 1];
            $size = push($heap, $size, $dist[$cell - 1] * $cells + $cell - 1);
        }
        if ($x < $n - 1 && $d + $cost[$cell + 1] < $dist[$cell + 1]) {
            $dist[$cell + 1] = $d + $cost[$cell + 1];
            $size = push($heap, $size, $dist[$cell + 1] * $cells + $cell + 1);
        }
    }
    $total = 0;
    foreach ($dist as $d) $total += $d;
    echo $dist[$cells - 1], " ", $total, "\n";
}

main((int)$argv[1]);
