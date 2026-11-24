// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
using System;

static class Program {
    class Node {
        public Node left, right;
        public Node(Node left, Node right) {
            this.left = left;
            this.right = right;
        }
    }

    static Node Build(int depth) {
        if (depth == 0) return new Node(null, null);
        return new Node(Build(depth - 1), Build(depth - 1));
    }

    static long Check(Node node) {
        if (node.left == null || node.right == null) return 1;
        return 1 + Check(node.left) + Check(node.right);
    }

    static void Main(string[] args) {
        int n = int.Parse(args[0]);
        int minDepth = 4;
        int maxDepth = n;
        if (maxDepth < minDepth + 2) maxDepth = minDepth + 2;
        Console.WriteLine($"stretch tree of depth {maxDepth + 1} check: {Check(Build(maxDepth + 1))}");
        Node longLived = Build(maxDepth);
        for (int depth = minDepth; depth <= maxDepth; depth += 2) {
            long iterations = 1L << (maxDepth - depth + minDepth);
            long total = 0;
            for (long i = 0; i < iterations; i++) total += Check(Build(depth));
            Console.WriteLine($"{iterations} trees of depth {depth} check: {total}");
        }
        Console.WriteLine($"long lived tree of depth {maxDepth} check: {Check(longLived)}");
    }
}
