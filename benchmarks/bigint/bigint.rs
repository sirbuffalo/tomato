// Benchmark: big integers. Computes n! by multiplying one small number at a time. Prints n! mod 1000000007.
// Rust's standard library has no big integers, so this keeps the number as 32-bit limbs (least significant first).
fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut limbs: Vec<u32> = vec![1];
    for i in 2..=n {
        let mut carry: u64 = 0;
        for limb in limbs.iter_mut() {
            let v = *limb as u64 * i + carry;
            *limb = v as u32;
            carry = v >> 32;
        }
        if carry > 0 {
            limbs.push(carry as u32);
        }
    }
    let m: u64 = 1000000007;
    let mut rem: u64 = 0;
    for limb in limbs.iter().rev() {
        rem = ((rem << 32) | *limb as u64) % m;
    }
    println!("{}", rem);
}
