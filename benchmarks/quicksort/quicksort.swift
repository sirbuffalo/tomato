// Benchmark: a hand-written quicksort (recursive, Hoare partition, middle pivot, insertion sort for short ranges) on n
// pseudo-random integers from a linear congruential generator. Prints a position-weighted checksum of the sorted list.
func insertionSort(_ values: inout [Int], _ low: Int, _ high: Int) {
    var i = low + 1
    while i <= high {
        let x = values[i]
        var j = i - 1
        while j >= low && values[j] > x {
            values[j + 1] = values[j]
            j -= 1
        }
        values[j + 1] = x
        i += 1
    }
}

func quicksort(_ values: inout [Int], _ lowStart: Int, _ highStart: Int) {
    var low = lowStart
    var high = highStart
    while high - low > 16 {
        let pivot = values[(low + high) / 2]
        var i = low
        var j = high
        while i <= j {
            while values[i] < pivot { i += 1 }
            while values[j] > pivot { j -= 1 }
            if i <= j {
                let t = values[i]
                values[i] = values[j]
                values[j] = t
                i += 1
                j -= 1
            }
        }
        // recurse into the smaller part, loop on the larger one
        if j - low < high - i {
            quicksort(&values, low, j)
            low = i
        } else {
            quicksort(&values, i, high)
            high = j
        }
    }
    insertionSort(&values, low, high)
}

let n = Int(CommandLine.arguments[1])!
var seed = 12345
var values = [Int](repeating: 0, count: n)
for i in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    values[i] = seed
}
quicksort(&values, 0, n - 1)
var checksum = 0
for i in 0..<n {
    checksum = (checksum + (i % 1000 + 1) * values[i]) % 1000000007
}
print(checksum)
