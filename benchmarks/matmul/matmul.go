// Benchmark: integer matrix multiply, n x n, nested loops. Prints the sum of all entries of C = A * B.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	a := make([][]int, n)
	b := make([][]int, n)
	for i := 0; i < n; i++ {
		a[i] = make([]int, n)
		b[i] = make([]int, n)
		for j := 0; j < n; j++ {
			a[i][j] = (i*j + 1) % 10
			b[i][j] = (i + j) % 10
		}
	}
	total := 0
	for i := 0; i < n; i++ {
		row := a[i]
		for j := 0; j < n; j++ {
			acc := 0
			for k := 0; k < n; k++ {
				acc += row[k] * b[k][j]
			}
			total += acc
		}
	}
	fmt.Println(total)
}
