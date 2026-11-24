<?php
// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
ini_set('memory_limit', '-1');

function main(int $n): void {
    $table = array_fill(0, 256, 0);
    for ($i = 0; $i < 256; $i++) {
        $c = $i;
        for ($k = 0; $k < 8; $k++) {
            if (($c & 1) == 1) {
                $c = 3988292384 ^ ($c >> 1);
            } else {
                $c = $c >> 1;
            }
        }
        $table[$i] = $c;
    }
    $seed = 1;
    $data = array_fill(0, $n, 0);
    for ($i = 0; $i < $n; $i++) {
        $seed = ($seed * 1103515245 + 12345) % 2147483648;
        $data[$i] = intdiv($seed, 65536) % 256;
    }
    $crc = 4294967295;
    for ($rounds = 0; $rounds < 4; $rounds++) {
        foreach ($data as $b) {
            $crc = $table[($crc ^ $b) & 255] ^ ($crc >> 8);
        }
    }
    $crc = $crc ^ 4294967295;
    $a = 1;
    $b2 = 0;
    foreach ($data as $b) {
        $a = ($a + $b) % 65521;
        $b2 = ($b2 + $a) % 65521;
    }
    echo $crc, " ", $b2 * 65536 + $a, "\n";
}

main((int)$argv[1]);
