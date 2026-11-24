// Benchmark: function values. Calls one of four functions chosen from a list n times (each result feeds the next), then
// runs map and filter with lambdas and sorts with a key function over a list of n / 4 numbers. Prints three checksums.
func f0(_ x: Int) -> Int { return (x * 3 + 1) % 1000003 }
func f1(_ x: Int) -> Int { return (x + 7919) % 1000003 }
func f2(_ x: Int) -> Int { return x * x % 1000003 }
func f3(_ x: Int) -> Int { return (x ^ 12345) % 1000003 }

func applyTwice(_ f: (Int) -> Int, _ x: Int) -> Int {
    return f(f(x))
}

let n = Int(CommandLine.arguments[1])!
let table: [(Int) -> Int] = [f0, f1, f2, f3]
var x = 1
for i in 0..<n {
    x = table[i % 4](x + i)
}
print(x)
var y = 0
for i in 0..<n {
    y = (y + applyTwice(table[i % 4], i)) % 1000000007
}
print(y)
let m = n / 4
var xs = [Int]()
for i in 0..<m { xs.append(i * 7919 % 100003) }
let mapper: (Int) -> Int = { v in v * v % 1009 }
let pred: (Int) -> Bool = { v in v % 2 == 1 }
let keyFn: (Int) -> Int = { v in v % 997 * 1000 + v % 1000 }
var odd = [Int]()
for v in xs {
    let s = mapper(v)
    if pred(s) { odd.append(s) }
}
// sorted by key, ties kept in their original order (a stable sort)
var keyed = [(key: Int, index: Int, value: Int)]()
for i in 0..<odd.count { keyed.append((keyFn(odd[i]), i, odd[i])) }
keyed.sort { $0.key != $1.key ? $0.key < $1.key : $0.index < $1.index }
var z = 0
for i in 0..<keyed.count {
    z = (z * 31 + keyed[i].value) % 1000000007
}
print(keyed.count, z)
