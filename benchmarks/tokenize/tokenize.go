// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 555
	words := []string{"alpha", "beta", "gamma", "delta", "count", "total", "index", "value"}
	symbols := []string{"+", "-", "*", "/", "=", "(", ")", ";"}
	pieces := make([]string, 0)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		kind := seed / 65536 % 4
		seed = (seed*1103515245 + 12345) % 2147483648
		pick := seed / 65536
		if kind == 0 {
			pieces = append(pieces, words[pick%8]+" ")
		} else if kind == 1 {
			pieces = append(pieces, strconv.Itoa(pick%100000)+" ")
		} else if kind == 2 {
			pieces = append(pieces, symbols[pick%8])
		} else {
			pieces = append(pieces, words[pick%8]+strconv.Itoa(pick/8%100)+" ")
		}
	}
	text := strings.Join(pieces, "")
	names, numbers, syms := 0, 0, 0
	numberSum, nameLength := 0, 0
	inName, inNumber := false, false
	value := 0
	for i := 0; i < len(text); i++ {
		ch := text[i]
		isAlpha := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
		isDigit := ch >= '0' && ch <= '9'
		if isAlpha || (inName && isDigit) {
			if !inName {
				inName = true
				names++
			}
			nameLength++
		} else if isDigit {
			if !inNumber {
				inNumber = true
				numbers++
				value = 0
			}
			value = value*10 + int(ch) - 48
		} else {
			if inNumber {
				numberSum += value
			}
			inName = false
			inNumber = false
			if ch != ' ' {
				syms++
			}
		}
	}
	if inNumber {
		numberSum += value
	}
	fmt.Println(names, numbers, syms, numberSum, nameLength)
}
