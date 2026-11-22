// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
package main

import (
	"fmt"
	"math/big"
	"os"
	"strconv"
)

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	product := big.NewInt(1)
	for i := 2; i <= n; i++ {
		product.Mul(product, big.NewInt(int64(i)))
	}
	product.Mod(product, big.NewInt(1000000007))
	fmt.Println(product.String())
}
