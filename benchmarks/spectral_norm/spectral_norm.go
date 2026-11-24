// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
)

func a(i, j int) float64 {
	return 1.0 / float64((i+j)*(i+j+1)/2+i+1)
}

func timesA(n int, v, out []float64) {
	for i := 0; i < n; i++ {
		s := 0.0
		for j := 0; j < n; j++ {
			s += a(i, j) * v[j]
		}
		out[i] = s
	}
}

func timesATransposed(n int, v, out []float64) {
	for i := 0; i < n; i++ {
		s := 0.0
		for j := 0; j < n; j++ {
			s += a(j, i) * v[j]
		}
		out[i] = s
	}
}

func timesAtA(n int, v, out, tmp []float64) {
	timesA(n, v, tmp)
	timesATransposed(n, tmp, out)
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	u := make([]float64, n)
	for i := range u {
		u[i] = 1.0
	}
	v := make([]float64, n)
	tmp := make([]float64, n)
	for round := 0; round < 10; round++ {
		timesAtA(n, u, v, tmp)
		timesAtA(n, v, u, tmp)
	}
	vbv, vv := 0.0, 0.0
	for i := 0; i < n; i++ {
		vbv += u[i] * v[i]
		vv += v[i] * v[i]
	}
	fmt.Println(int64(math.Sqrt(vbv/vv) * 1000000000.0))
}
