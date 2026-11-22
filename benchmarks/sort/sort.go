// Benchmark: sort n pseudo-random integers (a linear congruential generator). Prints a position-weighted checksum.
package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 12345
	values := make([]int, n)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		values[i] = seed
	}
	sort.Ints(values)
	checksum := 0
	for i := 0; i < n; i++ {
		checksum = (checksum + (i%1000+1)*values[i]) % 1000000007
	}
	fmt.Println(checksum)
}
