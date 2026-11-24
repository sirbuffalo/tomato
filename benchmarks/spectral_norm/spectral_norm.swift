// Benchmark: spectral norm of an infinite matrix, cut to n x n (float arithmetic in nested loops, function calls).
// Ten rounds of the power method; prints the norm times 1e9, cut to a whole number.
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
func a(_ i: Int, _ j: Int) -> Double {
    return 1.0 / Double((i + j) * (i + j + 1) / 2 + i + 1)
}

func timesA(_ n: Int, _ v: [Double], _ out: inout [Double]) {
    for i in 0..<n {
        var s = 0.0
        for j in 0..<n { s += a(i, j) * v[j] }
        out[i] = s
    }
}

func timesATransposed(_ n: Int, _ v: [Double], _ out: inout [Double]) {
    for i in 0..<n {
        var s = 0.0
        for j in 0..<n { s += a(j, i) * v[j] }
        out[i] = s
    }
}

func timesAtA(_ n: Int, _ v: [Double], _ out: inout [Double], _ tmp: inout [Double]) {
    timesA(n, v, &tmp)
    timesATransposed(n, tmp, &out)
}

let n = Int(CommandLine.arguments[1])!
var u = [Double](repeating: 1.0, count: n)
var v = [Double](repeating: 0.0, count: n)
var tmp = [Double](repeating: 0.0, count: n)
for _ in 0..<10 {
    timesAtA(n, u, &v, &tmp)
    timesAtA(n, v, &u, &tmp)
}
var vbv = 0.0
var vv = 0.0
for i in 0..<n {
    vbv += u[i] * v[i]
    vv += v[i] * v[i]
}
print(Int((vbv / vv).squareRoot() * 1000000000.0))
