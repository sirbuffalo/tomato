// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	table := make([]int, 256)
	for i := 0; i < 256; i++ {
		c := i
		for k := 0; k < 8; k++ {
			if c&1 == 1 {
				c = 3988292384 ^ (c >> 1)
			} else {
				c = c >> 1
			}
		}
		table[i] = c
	}
	seed := 1
	data := make([]int, n)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		data[i] = seed / 65536 % 256
	}
	crc := 4294967295
	for rounds := 0; rounds < 4; rounds++ {
		for _, b := range data {
			crc = table[(crc^b)&255] ^ (crc >> 8)
		}
	}
	crc = crc ^ 4294967295
	a, b2 := 1, 0
	for _, b := range data {
		a = (a + b) % 65521
		b2 = (b2 + a) % 65521
	}
	fmt.Println(crc, b2*65536+a)
}
