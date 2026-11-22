// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	bestStart, bestLength := 1, 1
	for start := 1; start < n; start++ {
		x := start
		length := 1
		for x != 1 {
			if x%2 == 0 {
				x /= 2
			} else {
				x = 3*x + 1
			}
			length++
		}
		if length > bestLength {
			bestLength = length
			bestStart = start
		}
	}
	fmt.Println(bestStart, bestLength)
}
