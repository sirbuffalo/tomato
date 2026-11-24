// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
fn main() {
    let n: usize = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut seed: u64 = 555;
    let words = ["alpha", "beta", "gamma", "delta", "count", "total", "index", "value"];
    let symbols = ["+", "-", "*", "/", "=", "(", ")", ";"];
    let mut pieces: Vec<String> = Vec::new();
    for _ in 0..n {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        let kind = seed / 65536 % 4;
        seed = (seed * 1103515245 + 12345) % 2147483648;
        let pick = (seed / 65536) as usize;
        if kind == 0 {
            pieces.push(format!("{} ", words[pick % 8]));
        } else if kind == 1 {
            pieces.push(format!("{} ", pick % 100000));
        } else if kind == 2 {
            pieces.push(symbols[pick % 8].to_string());
        } else {
            pieces.push(format!("{}{} ", words[pick % 8], pick / 8 % 100));
        }
    }
    let text = pieces.join("");
    let (mut names, mut numbers, mut syms) = (0u64, 0u64, 0u64);
    let mut number_sum: u64 = 0;
    let mut name_length: u64 = 0;
    let mut in_name = false;
    let mut in_number = false;
    let mut value: u64 = 0;
    for ch in text.chars() {
        if ch.is_ascii_alphabetic() || (in_name && ch.is_ascii_digit()) {
            if !in_name {
                in_name = true;
                names += 1;
            }
            name_length += 1;
        } else if ch.is_ascii_digit() {
            if !in_number {
                in_number = true;
                numbers += 1;
                value = 0;
            }
            value = value * 10 + ch as u64 - 48;
        } else {
            if in_number {
                number_sum += value;
            }
            in_name = false;
            in_number = false;
            if ch != ' ' {
                syms += 1;
            }
        }
    }
    if in_number {
        number_sum += value;
    }
    println!("{} {} {} {} {}", names, numbers, syms, number_sum, name_length);
}
