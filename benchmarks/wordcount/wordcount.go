// Benchmark: word counting in a dict. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	counts := map[string]int{}
	for i := 0; i < n; i++ {
		word := "w" + strconv.Itoa(i*7919%5003)
		counts[word]++
	}
	checksum := 0
	for k := 0; k < 5003; k++ {
		checksum += (k + 1) * counts["w"+strconv.Itoa(k)]
	}
	fmt.Println(len(counts), checksum)
}
