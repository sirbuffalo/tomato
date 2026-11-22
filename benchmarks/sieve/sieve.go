// Benchmark: sieve of Eratosthenes. Prints how many primes are <= n.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	composite := make([]bool, n+1)
	count := 0
	for i := 2; i <= n; i++ {
		if composite[i] {
			continue
		}
		count++
		for j := i * i; j <= n; j += i {
			composite[j] = true
		}
	}
	fmt.Println(count)
}
