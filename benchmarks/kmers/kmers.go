// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a dict. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 31337
	letters := []string{"A", "C", "G", "T"}
	var sb strings.Builder
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		sb.WriteString(letters[seed/65536%4])
	}
	dna := sb.String()
	for _, k := range []int{1, 2, 4, 6, 12} {
		counts := map[string]int{}
		for i := 0; i < n-k+1; i++ {
			counts[dna[i:i+k]]++
		}
		most, squares := 0, 0
		for _, c := range counts {
			if c > most {
				most = c
			}
			squares += c * c
		}
		fmt.Println(k, len(counts), most, squares)
	}
}
