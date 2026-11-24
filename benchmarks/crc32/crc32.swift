// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
let n = Int(CommandLine.arguments[1])!
var table = [Int](repeating: 0, count: 256)
for i in 0..<256 {
    var c = i
    for _ in 0..<8 {
        if c & 1 == 1 {
            c = 3988292384 ^ (c >> 1)
        } else {
            c = c >> 1
        }
    }
    table[i] = c
}
var seed = 1
var data = [Int](repeating: 0, count: n)
for i in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    data[i] = seed / 65536 % 256
}
var crc = 4294967295
for _ in 0..<4 {
    for b in data {
        crc = table[(crc ^ b) & 255] ^ (crc >> 8)
    }
}
crc = crc ^ 4294967295
var a = 1
var b2 = 0
for b in data {
    a = (a + b) % 65521
    b2 = (b2 + a) % 65521
}
print(crc, b2 * 65536 + a)
