// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a dict. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
let n = Int(CommandLine.arguments[1])!
var seed = 31337
let letters: [UInt8] = [65, 67, 71, 84]
var dna = [UInt8]()
dna.reserveCapacity(n)
for _ in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    dna.append(letters[seed / 65536 % 4])
}
for k in [1, 2, 4, 6, 12] {
    var counts = [String: Int]()
    var i = 0
    while i < n - k + 1 {
        let key = String(decoding: dna[i..<(i + k)], as: UTF8.self)
        counts[key, default: 0] += 1
        i += 1
    }
    var most = 0
    var squares = 0
    for c in counts.values {
        if c > most { most = c }
        squares += c * c
    }
    print(k, counts.count, most, squares)
}
