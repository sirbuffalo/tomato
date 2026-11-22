// Benchmark: Mandelbrot set on an n x n grid (floats), at most 100 iterations per point. Prints the total iterations.
// The float64(...) conversions stop Go fusing multiply-adds, so every language rounds the same way.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	fn := float64(n)
	total := 0
	for py := 0; py < n; py++ {
		ci := float64(2.0*float64(py))/fn - 1.0
		for px := 0; px < n; px++ {
			cr := float64(3.0*float64(px))/fn - 2.0
			zr, zi := 0.0, 0.0
			i := 0
			for i < 100 && float64(zr*zr)+float64(zi*zi) <= 4.0 {
				t := float64(zr*zr) - float64(zi*zi) + cr
				zi = float64(float64(2.0*zr)*zi) + ci
				zr = t
				i++
			}
			total += i
		}
	}
	fmt.Println(total)
}
