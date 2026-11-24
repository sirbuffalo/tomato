// Benchmark: Dijkstra's shortest paths on an n x n grid of pseudo-random step costs (1..9), from the top-left corner, with a
// hand-written binary min-heap of encoded (distance, cell) numbers. Prints the distance to the far corner and the sum
// of all distances.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func push(heap []int, size int, key int) ([]int, int) {
	if size == len(heap) {
		heap = append(heap, key)
	} else {
		heap[size] = key
	}
	i := size
	for i > 0 {
		parent := (i - 1) / 2
		if heap[parent] <= key {
			break
		}
		heap[i] = heap[parent]
		i = parent
	}
	heap[i] = key
	return heap, size + 1
}

func pop(heap []int, size int) int {
	// removes the smallest key (the caller has read heap[0]) and returns the new size
	size--
	key := heap[size]
	i := 0
	for {
		child := 2*i + 1
		if child >= size {
			break
		}
		if child+1 < size && heap[child+1] < heap[child] {
			child++
		}
		if heap[child] >= key {
			break
		}
		heap[i] = heap[child]
		i = child
	}
	heap[i] = key
	return size
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 2024
	cost := make([]int, n*n)
	for i := 0; i < n*n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		cost[i] = seed/65536%9 + 1
	}
	cells := n * n
	infinity := 1000000000
	dist := make([]int, cells)
	for i := range dist {
		dist[i] = infinity
	}
	heap := make([]int, 16)
	size := 0
	dist[0] = 0
	heap, size = push(heap, size, 0)
	for size > 0 {
		top := heap[0]
		size = pop(heap, size)
		d := top / cells
		cell := top % cells
		if d > dist[cell] {
			continue
		}
		y := cell / n
		x := cell % n
		if y > 0 && d+cost[cell-n] < dist[cell-n] {
			dist[cell-n] = d + cost[cell-n]
			heap, size = push(heap, size, dist[cell-n]*cells+cell-n)
		}
		if y < n-1 && d+cost[cell+n] < dist[cell+n] {
			dist[cell+n] = d + cost[cell+n]
			heap, size = push(heap, size, dist[cell+n]*cells+cell+n)
		}
		if x > 0 && d+cost[cell-1] < dist[cell-1] {
			dist[cell-1] = d + cost[cell-1]
			heap, size = push(heap, size, dist[cell-1]*cells+cell-1)
		}
		if x < n-1 && d+cost[cell+1] < dist[cell+1] {
			dist[cell+1] = d + cost[cell+1]
			heap, size = push(heap, size, dist[cell+1]*cells+cell+1)
		}
	}
	total := 0
	for _, d := range dist {
		total += d
	}
	fmt.Println(dist[cells-1], total)
}
