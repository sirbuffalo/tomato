<?php
// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
// PHP has no big integers without an extension (gmp or bcmath), so this multiplies an array of 40-bit words by hand: a word
// times a number below 2 ** 22 still fits in PHP's 64-bit int.
function main(int $n): void {
    $mask = (1 << 40) - 1;
    $product = [1];
    for ($i = 2; $i <= $n; $i++) {
        $carry = 0;
        foreach ($product as $k => $word) {
            $carry += $word * $i;
            $product[$k] = $carry & $mask;
            $carry >>= 40;
        }
        if ($carry > 0) $product[] = $carry;
    }
    $rest = 0;
    for ($k = count($product) - 1; $k >= 0; $k--) {
        // two steps of 20 bits: rest is below 2 ** 30, so neither passes 2 ** 63
        $rest = (($rest << 20) | ($product[$k] >> 20)) % 1000000007;
        $rest = (($rest << 20) | ($product[$k] & 0xfffff)) % 1000000007;
    }
    echo $rest, "\n";
}

main((int)$argv[1]);
