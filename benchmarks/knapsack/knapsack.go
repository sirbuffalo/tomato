// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 7
	weights := make([]int, n)
	values := make([]int, n)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		weights[i] = seed/65536%60 + 1
		seed = (seed*1103515245 + 12345) % 2147483648
		values[i] = seed/65536%1000 + 1
	}
	capacity := 5 * n
	best := make([]int, capacity+1)
	for i := 0; i < n; i++ {
		w := weights[i]
		v := values[i]
		for c := capacity; c >= w; c-- {
			candidate := best[c-w] + v
			if candidate > best[c] {
				best[c] = candidate
			}
		}
	}
	fmt.Println(best[capacity])
}
