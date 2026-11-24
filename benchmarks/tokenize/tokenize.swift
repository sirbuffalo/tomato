// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
let n = Int(CommandLine.arguments[1])!
var seed = 555
let words: [[UInt8]] = ["alpha", "beta", "gamma", "delta", "count", "total", "index", "value"].map { Array($0.utf8) }
let symbols: [UInt8] = Array("+-*/=();".utf8)
var text = [UInt8]()
for _ in 0..<n {
    seed = (seed * 1103515245 + 12345) % 2147483648
    let kind = seed / 65536 % 4
    seed = (seed * 1103515245 + 12345) % 2147483648
    let pick = seed / 65536
    if kind == 0 {
        text.append(contentsOf: words[pick % 8])
        text.append(32)
    } else if kind == 1 {
        text.append(contentsOf: Array(String(pick % 100000).utf8))
        text.append(32)
    } else if kind == 2 {
        text.append(symbols[pick % 8])
    } else {
        text.append(contentsOf: words[pick % 8])
        text.append(contentsOf: Array(String(pick / 8 % 100).utf8))
        text.append(32)
    }
}
var names = 0
var numbers = 0
var syms = 0
var numberSum = 0
var nameLength = 0
var inName = false
var inNumber = false
var value = 0
for ch in text {
    let isAlpha = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
    let isDigit = ch >= 48 && ch <= 57
    if isAlpha || (inName && isDigit) {
        if !inName {
            inName = true
            names += 1
        }
        nameLength += 1
    } else if isDigit {
        if !inNumber {
            inNumber = true
            numbers += 1
            value = 0
        }
        value = value * 10 + Int(ch) - 48
    } else {
        if inNumber { numberSum += value }
        inName = false
        inNumber = false
        if ch != 32 { syms += 1 }
    }
}
if inNumber { numberSum += value }
print(names, numbers, syms, numberSum, nameLength)
