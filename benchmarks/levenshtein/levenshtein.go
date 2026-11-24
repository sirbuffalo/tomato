// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 42
	s := make([]byte, n)
	t := make([]byte, n)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		s[i] = byte('a' + seed/65536%4)
		seed = (seed*1103515245 + 12345) % 2147483648
		t[i] = byte('a' + seed/65536%4)
	}
	prev := make([]int, n+1)
	for i := range prev {
		prev[i] = i
	}
	cur := make([]int, n+1)
	for i := 1; i <= n; i++ {
		cur[0] = i
		si := s[i-1]
		for j := 1; j <= n; j++ {
			cost := 1
			if si == t[j-1] {
				cost = 0
			}
			best := prev[j-1] + cost
			up := prev[j] + 1
			if up < best {
				best = up
			}
			left := cur[j-1] + 1
			if left < best {
				best = left
			}
			cur[j] = best
		}
		prev, cur = cur, prev
	}
	fmt.Println(prev[n])
}
