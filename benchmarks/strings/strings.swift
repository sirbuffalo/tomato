// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
func run(_ n: Int) {
    let parts = (0..<n).map { String($0 * 7 % 1000) }
    let text = parts.joined(separator: ",")
    var total = 0
    for piece in text.split(separator: ",") { total += Int(piece)! }
    print(text.utf8.count, total)
}

run(Int(CommandLine.arguments[1])!)
