// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
package main

import (
	"fmt"
	"os"
	"strconv"
)

type Node struct {
	left, right *Node
}

func build(depth int) *Node {
	if depth == 0 {
		return &Node{nil, nil}
	}
	return &Node{build(depth - 1), build(depth - 1)}
}

func check(node *Node) int {
	if node.left == nil || node.right == nil {
		return 1
	}
	return 1 + check(node.left) + check(node.right)
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	minDepth := 4
	maxDepth := n
	if maxDepth < minDepth+2 {
		maxDepth = minDepth + 2
	}
	fmt.Printf("stretch tree of depth %d check: %d\n", maxDepth+1, check(build(maxDepth+1)))
	longLived := build(maxDepth)
	for depth := minDepth; depth <= maxDepth; depth += 2 {
		iterations := 1 << uint(maxDepth-depth+minDepth)
		total := 0
		for i := 0; i < iterations; i++ {
			total += check(build(depth))
		}
		fmt.Printf("%d trees of depth %d check: %d\n", iterations, depth, total)
	}
	fmt.Printf("long lived tree of depth %d check: %d\n", maxDepth, check(longLived))
}
