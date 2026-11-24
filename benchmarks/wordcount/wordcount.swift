// Benchmark: word counting in a Dictionary. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
func run(_ n: Int) {
    var counts: [String: Int] = [:]
    for i in 0..<n { counts["w\(i * 7919 % 5003)", default: 0] += 1 }
    var checksum = 0
    for k in 0..<5003 { checksum += (k + 1) * counts["w\(k)", default: 0] }
    print(counts.count, checksum)
}

run(Int(CommandLine.arguments[1])!)
