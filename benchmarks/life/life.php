<?php
// Benchmark: Conway's Game of Life on an n x n torus, 100 generations, from a pseudo-random start (about 1 cell in 3
// alive). Nested lists, neighbour counting with wrap-around. Prints the live cells at the end and a position checksum.

function main(int $n): void {
    $seed = 99;
    $grid = [];
    $nextGrid = [];
    for ($y = 0; $y < $n; $y++) {
        $row = array_fill(0, $n, 0);
        for ($x = 0; $x < $n; $x++) {
            $seed = ($seed * 1103515245 + 12345) % 2147483648;
            if (intdiv($seed, 65536) % 3 == 0) $row[$x] = 1;
        }
        $grid[] = $row;
        $nextGrid[] = array_fill(0, $n, 0);
    }
    for ($gen = 0; $gen < 100; $gen++) {
        for ($y = 0; $y < $n; $y++) {
            $up = $grid[($y + $n - 1) % $n];
            $mid = $grid[$y];
            $down = $grid[($y + 1) % $n];
            $out = $nextGrid[$y];
            for ($x = 0; $x < $n; $x++) {
                $left = ($x + $n - 1) % $n;
                $right = ($x + 1) % $n;
                $around = $up[$left] + $up[$x] + $up[$right] + $mid[$left] + $mid[$right] + $down[$left] + $down[$x] + $down[$right];
                if ($around == 3 || ($around == 2 && $mid[$x] == 1)) {
                    $out[$x] = 1;
                } else {
                    $out[$x] = 0;
                }
            }
            $nextGrid[$y] = $out;
        }
        $swap = $grid;
        $grid = $nextGrid;
        $nextGrid = $swap;
    }
    $alive = 0;
    $checksum = 0;
    for ($y = 0; $y < $n; $y++) {
        for ($x = 0; $x < $n; $x++) {
            if ($grid[$y][$x] == 1) {
                $alive++;
                $checksum = ($checksum * 31 + $y * $n + $x) % 1000000007;
            }
        }
    }
    echo $alive, " ", $checksum, "\n";
}

main((int)$argv[1]);
