// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
let n = Int(CommandLine.arguments[1])!
var seed = 42
let letters: [UInt8] = [97, 98, 99, 100]
var s = [UInt8]()
var t = [UInt8]()
for _ in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    s.append(letters[seed / 65536 % 4])
    seed = (seed * 1103515245 + 12345) % 2147483648
    t.append(letters[seed / 65536 % 4])
}
var prev = Array(0...n)
var cur = [Int](repeating: 0, count: n + 1)
var i = 0
while i < n {
    i += 1
    cur[0] = i
    let si = s[i - 1]
    var j = 1
    while j <= n {
        var cost = 1
        if si == t[j - 1] { cost = 0 }
        var best = prev[j - 1] + cost
        let up = prev[j] + 1
        if up < best { best = up }
        let left = cur[j - 1] + 1
        if left < best { best = left }
        cur[j] = best
        j += 1
    }
    let swap = prev
    prev = cur
    cur = swap
}
print(prev[n])
