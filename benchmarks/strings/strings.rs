// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let parts: Vec<String> = (0..n).map(|i| (i * 7 % 1000).to_string()).collect();
    let text = parts.join(",");
    let mut total: u64 = 0;
    for piece in text.split(',') {
        total += piece.parse::<u64>().unwrap();
    }
    println!("{} {}", text.len(), total);
}
