// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
class binary_trees {
    static class Node {
        Node left, right;
        Node(Node left, Node right) {
            this.left = left;
            this.right = right;
        }
    }

    static Node build(int depth) {
        if (depth == 0) return new Node(null, null);
        return new Node(build(depth - 1), build(depth - 1));
    }

    static long check(Node node) {
        if (node.left == null || node.right == null) return 1;
        return 1 + check(node.left) + check(node.right);
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        int minDepth = 4;
        int maxDepth = n;
        if (maxDepth < minDepth + 2) maxDepth = minDepth + 2;
        System.out.println("stretch tree of depth " + (maxDepth + 1) + " check: " + check(build(maxDepth + 1)));
        Node longLived = build(maxDepth);
        for (int depth = minDepth; depth <= maxDepth; depth += 2) {
            long iterations = 1L << (maxDepth - depth + minDepth);
            long total = 0;
            for (long i = 0; i < iterations; i++) total += check(build(depth));
            System.out.println(iterations + " trees of depth " + depth + " check: " + total);
        }
        System.out.println("long lived tree of depth " + maxDepth + " check: " + check(longLived));
    }
}
