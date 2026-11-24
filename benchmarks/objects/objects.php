<?php
// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
ini_set('memory_limit', '-1');

class Particle {
    public function __construct(public int $x, public int $v) {}

    public function step(int $round): void {
        $this->x = ($this->x + $this->v * $round) % 1000003;
    }
}

function main(int $n): void {
    $particles = [];
    for ($i = 0; $i < $n; $i++) $particles[] = new Particle($i, $i % 13 + 1);
    for ($round = 1; $round <= 10; $round++) {
        foreach ($particles as $p) $p->step($round);
    }
    $total = 0;
    foreach ($particles as $p) $total += $p->x;
    echo $total, "\n";
}

main((int)$argv[1]);
