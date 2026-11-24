// Benchmark: function values. Calls one of four functions chosen from a list n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
package main

import (
	"fmt"
	"os"
	"sort"
	"strconv"
)

func f0(x int) int { return (x*3 + 1) % 1000003 }
func f1(x int) int { return (x + 7919) % 1000003 }
func f2(x int) int { return x * x % 1000003 }
func f3(x int) int { return (x ^ 12345) % 1000003 }

func applyTwice(f func(int) int, x int) int {
	return f(f(x))
}

func mapInts(f func(int) int, xs []int) []int {
	out := make([]int, len(xs))
	for i, v := range xs {
		out[i] = f(v)
	}
	return out
}

func filterInts(f func(int) bool, xs []int) []int {
	out := make([]int, 0)
	for _, v := range xs {
		if f(v) {
			out = append(out, v)
		}
	}
	return out
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	table := []func(int) int{f0, f1, f2, f3}
	x := 1
	for i := 0; i < n; i++ {
		x = table[i%4](x + i)
	}
	fmt.Println(x)
	y := 0
	for i := 0; i < n; i++ {
		y = (y + applyTwice(table[i%4], i)) % 1000000007
	}
	fmt.Println(y)
	m := n / 4
	xs := make([]int, m)
	for i := 0; i < m; i++ {
		xs[i] = i * 7919 % 100003
	}
	squares := mapInts(func(v int) int { return v * v % 1009 }, xs)
	odd := filterInts(func(v int) bool { return v%2 == 1 }, squares)
	key := func(v int) int { return v%997*1000 + v%1000 }
	sort.SliceStable(odd, func(a, b int) bool { return key(odd[a]) < key(odd[b]) })
	z := 0
	for _, v := range odd {
		z = (z*31 + v) % 1000000007
	}
	fmt.Println(len(odd), z)
}
