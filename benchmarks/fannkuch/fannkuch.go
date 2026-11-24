// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	perm1 := make([]int, n)
	for i := range perm1 {
		perm1[i] = i
	}
	perm := make([]int, n)
	count := make([]int, n)
	maxFlips, checksum, permCount := 0, 0, 0
	r := n
	done := false
	for !done {
		for r != 1 {
			count[r-1] = r
			r--
		}
		for i := 0; i < n; i++ {
			perm[i] = perm1[i]
		}
		flips := 0
		k := perm[0]
		for k != 0 {
			i, j := 0, k
			for i < j {
				perm[i], perm[j] = perm[j], perm[i]
				i++
				j--
			}
			flips++
			k = perm[0]
		}
		if flips > maxFlips {
			maxFlips = flips
		}
		if permCount%2 == 0 {
			checksum += flips
		} else {
			checksum -= flips
		}
		for {
			if r == n {
				done = true
				break
			}
			p0 := perm1[0]
			for i := 0; i < r; i++ {
				perm1[i] = perm1[i+1]
			}
			perm1[r] = p0
			count[r]--
			if count[r] > 0 {
				break
			}
			r++
		}
		permCount++
	}
	fmt.Println(checksum)
	fmt.Printf("Pfannkuchen(%d) = %d\n", n, maxFlips)
}
