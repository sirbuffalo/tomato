<?php
// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.

function main(int $n): void {
    $perm1 = range(0, $n - 1);
    $perm = array_fill(0, $n, 0);
    $count = array_fill(0, $n, 0);
    $maxFlips = 0;
    $checksum = 0;
    $permCount = 0;
    $r = $n;
    $done = false;
    while (!$done) {
        while ($r != 1) {
            $count[$r - 1] = $r;
            $r--;
        }
        for ($i = 0; $i < $n; $i++) $perm[$i] = $perm1[$i];
        $flips = 0;
        $k = $perm[0];
        while ($k != 0) {
            $i = 0;
            $j = $k;
            while ($i < $j) {
                $t = $perm[$i];
                $perm[$i] = $perm[$j];
                $perm[$j] = $t;
                $i++;
                $j--;
            }
            $flips++;
            $k = $perm[0];
        }
        if ($flips > $maxFlips) $maxFlips = $flips;
        if ($permCount % 2 == 0) $checksum += $flips; else $checksum -= $flips;
        while (true) {
            if ($r == $n) {
                $done = true;
                break;
            }
            $p0 = $perm1[0];
            for ($i = 0; $i < $r; $i++) $perm1[$i] = $perm1[$i + 1];
            $perm1[$r] = $p0;
            $count[$r]--;
            if ($count[$r] > 0) break;
            $r++;
        }
        $permCount++;
    }
    echo $checksum, "\n";
    echo "Pfannkuchen($n) = $maxFlips\n";
}

main((int)$argv[1]);
