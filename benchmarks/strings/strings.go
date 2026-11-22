// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	parts := make([]string, n)
	for i := 0; i < n; i++ {
		parts[i] = strconv.Itoa(i * 7 % 1000)
	}
	text := strings.Join(parts, ",")
	total := 0
	for _, piece := range strings.Split(text, ",") {
		v, _ := strconv.Atoi(piece)
		total += v
	}
	fmt.Println(len(text), total)
}
