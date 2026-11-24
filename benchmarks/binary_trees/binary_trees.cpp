// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>

struct Node {
    std::unique_ptr<Node> left, right;
};

static std::unique_ptr<Node> build(std::int64_t depth) {
    auto node = std::make_unique<Node>();
    if (depth > 0) {
        node->left = build(depth - 1);
        node->right = build(depth - 1);
    }
    return node;
}

static std::int64_t check(const Node &node) {
    if (!node.left || !node.right) return 1;
    return 1 + check(*node.left) + check(*node.right);
}

int main(int, char **argv) {
    std::int64_t min_depth = 4, max_depth = std::stoll(argv[1]);
    if (max_depth < min_depth + 2) max_depth = min_depth + 2;
    std::cout << "stretch tree of depth " << max_depth + 1 << " check: " << check(*build(max_depth + 1)) << '\n';
    auto long_lived = build(max_depth);
    for (std::int64_t depth = min_depth; depth <= max_depth; depth += 2) {
        std::int64_t iterations = std::int64_t{1} << (max_depth - depth + min_depth), total = 0;
        for (std::int64_t i = 0; i < iterations; i++) total += check(*build(depth));
        std::cout << iterations << " trees of depth " << depth << " check: " << total << '\n';
    }
    std::cout << "long lived tree of depth " << max_depth << " check: " << check(*long_lived) << '\n';
}
