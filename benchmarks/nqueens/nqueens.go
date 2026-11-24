// Benchmark: n queens. Counts the ways to place n queens on an n x n board so that none attacks another (backtracking,
// recursion, lists of bools for the columns and the two diagonals).
package main

import (
	"fmt"
	"os"
	"strconv"
)

func place(n, row int, cols, diag1, diag2 []bool) int {
	if row == n {
		return 1
	}
	count := 0
	for c := 0; c < n; c++ {
		d1 := row + c
		d2 := row - c + n - 1
		if cols[c] || diag1[d1] || diag2[d2] {
			continue
		}
		cols[c] = true
		diag1[d1] = true
		diag2[d2] = true
		count += place(n, row+1, cols, diag1, diag2)
		cols[c] = false
		diag1[d1] = false
		diag2[d2] = false
	}
	return count
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	fmt.Println(place(n, 0, make([]bool, n), make([]bool, 2*n), make([]bool, 2*n)))
}
