// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
let n = Int(CommandLine.arguments[1])!
var seed = 2718
let letters: [UInt8] = [65, 67, 71, 84]
var dna = [UInt8]()
dna.reserveCapacity(n)
for _ in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    dna.append(letters[seed / 65536 % 4])
}
var lines = [[UInt8]]()
var start = 0
while start < n {
    lines.append(Array(dna[start..<min(start + 60, n)]))
    start += 60
}
var text = [UInt8]()
text.reserveCapacity(n)
for line in lines { text.append(contentsOf: line) }
var complement = [UInt8](repeating: 0, count: 256)
complement[65] = 84
complement[67] = 71
complement[71] = 67
complement[84] = 65
var rc = [UInt8]()
rc.reserveCapacity(text.count)
var i = text.count - 1
while i >= 0 {
    rc.append(complement[Int(text[i])])
    i -= 1
}
var wrapped = [[UInt8]]()
start = 0
while start < rc.count {
    wrapped.append(Array(rc[start..<min(start + 60, rc.count)]))
    start += 60
}
var checksum = 0
for line in wrapped {
    var k = 0
    while k < line.count {
        checksum = (checksum * 131 + Int(line[k])) % 1000000007
        k += 7
    }
}
print(wrapped.count, checksum)
