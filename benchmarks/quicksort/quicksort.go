// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted list.
package main

import (
	"fmt"
	"os"
	"strconv"
)

func insertionSort(values []int, low, high int) {
	for i := low + 1; i <= high; i++ {
		x := values[i]
		j := i - 1
		for j >= low && values[j] > x {
			values[j+1] = values[j]
			j--
		}
		values[j+1] = x
	}
}

func quicksort(values []int, low, high int) {
	for high-low > 16 {
		pivot := values[(low+high)/2]
		i, j := low, high
		for i <= j {
			for values[i] < pivot {
				i++
			}
			for values[j] > pivot {
				j--
			}
			if i <= j {
				values[i], values[j] = values[j], values[i]
				i++
				j--
			}
		}
		// recurse into the smaller part, loop on the larger one
		if j-low < high-i {
			quicksort(values, low, j)
			low = i
		} else {
			quicksort(values, i, high)
			high = j
		}
	}
	insertionSort(values, low, high)
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	seed := 12345
	values := make([]int, n)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) % 2147483648
		values[i] = seed
	}
	quicksort(values, 0, n-1)
	checksum := 0
	for i := 0; i < n; i++ {
		checksum = (checksum + (i%1000+1)*values[i]) % 1000000007
	}
	fmt.Println(checksum)
}
