<?php
// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $seed = 555;
    $words = ['alpha', 'beta', 'gamma', 'delta', 'count', 'total', 'index', 'value'];
    $symbols = ['+', '-', '*', '/', '=', '(', ')', ';'];
    $pieces = [];
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $kind = intdiv($seed, 65536) % 4;
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $pick = intdiv($seed, 65536);
        if ($kind == 0) {
            $pieces[] = $words[$pick % 8] . ' ';
        } elseif ($kind == 1) {
            $pieces[] = ($pick % 100000) . ' ';
        } elseif ($kind == 2) {
            $pieces[] = $symbols[$pick % 8];
        } else {
            $pieces[] = $words[$pick % 8] . (intdiv($pick, 8) % 100) . ' ';
        }
    }
    $text = implode('', $pieces);
    $names = 0;
    $numbers = 0;
    $syms = 0;
    $numberSum = 0;
    $nameLength = 0;
    $inName = false;
    $inNumber = false;
    $value = 0;
    $len = strlen($text);
    for ($p = 0; $p < $len; $p++) {
        $ch = ord($text[$p]);
        $isAlpha = ($ch >= 65 && $ch <= 90) || ($ch >= 97 && $ch <= 122);
        $isDigit = $ch >= 48 && $ch <= 57;
        if ($isAlpha || ($inName && $isDigit)) {
            if (!$inName) {
                $inName = true;
                $names++;
            }
            $nameLength++;
        } elseif ($isDigit) {
            if (!$inNumber) {
                $inNumber = true;
                $numbers++;
                $value = 0;
            }
            $value = $value * 10 + $ch - 48;
        } else {
            if ($inNumber) $numberSum += $value;
            $inName = false;
            $inNumber = false;
            if ($ch != 32) $syms++;
        }
    }
    if ($inNumber) $numberSum += $value;
    echo "$names $numbers $syms $numberSum $nameLength\n";
}

main((int)$argv[1]);
