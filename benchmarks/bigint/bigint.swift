// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
// Swift's standard library has no big integers, so this multiplies an array of 64-bit words by hand (no package to install).
func run(_ n: UInt64) {
    var product: [UInt64] = [1]
    var i: UInt64 = 2
    while i <= n {
        var carry: UInt64 = 0
        for k in 0..<product.count {
            let (high, low) = product[k].multipliedFullWidth(by: i)
            let (sum, overflow) = low.addingReportingOverflow(carry)
            product[k] = sum
            carry = high &+ (overflow ? 1 : 0)
        }
        if carry > 0 { product.append(carry) }
        i += 1
    }
    let modulus: UInt64 = 1000000007
    var rest: UInt64 = 0
    for word in product.reversed() { rest = modulus.dividingFullWidth((rest, word)).remainder }
    print(rest)
}

run(UInt64(CommandLine.arguments[1])!)
