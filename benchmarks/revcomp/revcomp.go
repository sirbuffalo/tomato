// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 2718
	letters := []string{"A", "C", "G", "T"}
	parts := make([]string, 0)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		parts = append(parts, letters[seed/65536%4])
	}
	dna := strings.Join(parts, "")
	lines := make([]string, 0)
	for start := 0; start < n; start += 60 {
		end := start + 60
		if end > n {
			end = n
		}
		lines = append(lines, dna[start:end])
	}
	text := strings.Join(lines, "")
	complement := map[byte]string{'A': "T", 'C': "G", 'G': "C", 'T': "A"}
	out := make([]string, 0)
	for i := len(text) - 1; i >= 0; i-- {
		out = append(out, complement[text[i]])
	}
	rc := strings.Join(out, "")
	wrapped := make([]string, 0)
	for start := 0; start < len(rc); start += 60 {
		end := start + 60
		if end > len(rc) {
			end = len(rc)
		}
		wrapped = append(wrapped, rc[start:end])
	}
	checksum := 0
	for _, line := range wrapped {
		for k := 0; k < len(line); k += 7 {
			checksum = (checksum*131 + int(line[k])) % 1000000007
		}
	}
	fmt.Println(len(wrapped), checksum)
}
