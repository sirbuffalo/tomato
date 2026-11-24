<?php
// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
ini_set('memory_limit', '-1');

class Node {
    public function __construct(public ?Node $left, public ?Node $right) {}
}

function build(int $depth): Node {
    if ($depth == 0) return new Node(null, null);
    return new Node(build($depth - 1), build($depth - 1));
}

function check(Node $node): int {
    $left = $node->left;
    $right = $node->right;
    if ($left === null || $right === null) return 1;
    return 1 + check($left) + check($right);
}

function main(int $n): void {
    $minDepth = 4;
    $maxDepth = $n;
    if ($maxDepth < $minDepth + 2) $maxDepth = $minDepth + 2;
    echo "stretch tree of depth ", $maxDepth + 1, " check: ", check(build($maxDepth + 1)), "\n";
    $longLived = build($maxDepth);
    $depth = $minDepth;
    while ($depth <= $maxDepth) {
        $iterations = 1 << ($maxDepth - $depth + $minDepth);
        $total = 0;
        for ($i = 0; $i < $iterations; $i++) $total += check(build($depth));
        echo "$iterations trees of depth $depth check: $total\n";
        $depth += 2;
    }
    echo "long lived tree of depth $maxDepth check: ", check($longLived), "\n";
}

main((int)$argv[1]);
