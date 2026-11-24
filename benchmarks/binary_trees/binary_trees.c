// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Node { struct Node *left, *right; } Node;

static Node *build(int64_t depth) {
    Node *node = malloc(sizeof *node);
    if (depth == 0) {
        node->left = node->right = NULL;
    } else {
        node->left = build(depth - 1);
        node->right = build(depth - 1);
    }
    return node;
}

static int64_t check(const Node *node) {
    if (!node->left || !node->right) return 1;
    return 1 + check(node->left) + check(node->right);
}

static void release(Node *node) {
    if (node->left) release(node->left);
    if (node->right) release(node->right);
    free(node);
}

int main(int argc, char **argv) {
    (void)argc;
    int64_t min_depth = 4, max_depth = atoll(argv[1]);
    if (max_depth < min_depth + 2) max_depth = min_depth + 2;
    Node *stretch = build(max_depth + 1);
    printf("stretch tree of depth %lld check: %lld\n", (long long)(max_depth + 1), (long long)check(stretch));
    release(stretch);
    Node *long_lived = build(max_depth);
    for (int64_t depth = min_depth; depth <= max_depth; depth += 2) {
        int64_t iterations = (int64_t)1 << (max_depth - depth + min_depth), total = 0;
        for (int64_t i = 0; i < iterations; i++) {
            Node *tree = build(depth);
            total += check(tree);
            release(tree);
        }
        printf("%lld trees of depth %lld check: %lld\n", (long long)iterations, (long long)depth, (long long)total);
    }
    printf("long lived tree of depth %lld check: %lld\n", (long long)max_depth, (long long)check(long_lived));
    release(long_lived);
}
