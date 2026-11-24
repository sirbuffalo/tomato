// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
let n = Int(CommandLine.arguments[1])!
var perm1 = Array(0..<n)
var perm = [Int](repeating: 0, count: n)
var count = [Int](repeating: 0, count: n)
var maxFlips = 0
var checksum = 0
var permCount = 0
var r = n
var done = false
while !done {
    while r != 1 {
        count[r - 1] = r
        r -= 1
    }
    for i in 0..<n { perm[i] = perm1[i] }
    var flips = 0
    var k = perm[0]
    while k != 0 {
        var i = 0
        var j = k
        while i < j {
            let t = perm[i]
            perm[i] = perm[j]
            perm[j] = t
            i += 1
            j -= 1
        }
        flips += 1
        k = perm[0]
    }
    if flips > maxFlips { maxFlips = flips }
    if permCount % 2 == 0 { checksum += flips } else { checksum -= flips }
    while true {
        if r == n {
            done = true
            break
        }
        let p0 = perm1[0]
        for i in 0..<r { perm1[i] = perm1[i + 1] }
        perm1[r] = p0
        count[r] -= 1
        if count[r] > 0 { break }
        r += 1
    }
    permCount += 1
}
print(checksum)
print("Pfannkuchen(\(n)) = \(maxFlips)")
