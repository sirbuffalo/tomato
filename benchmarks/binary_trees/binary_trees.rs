// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

fn build(depth: u32) -> Box<Node> {
    if depth == 0 {
        return Box::new(Node { left: None, right: None });
    }
    Box::new(Node { left: Some(build(depth - 1)), right: Some(build(depth - 1)) })
}

fn check(node: &Node) -> u64 {
    match (&node.left, &node.right) {
        (Some(l), Some(r)) => 1 + check(l) + check(r),
        _ => 1,
    }
}

fn main() {
    let n: u32 = std::env::args().nth(1).unwrap().parse().unwrap();
    let min_depth = 4;
    let mut max_depth = n;
    if max_depth < min_depth + 2 {
        max_depth = min_depth + 2;
    }
    println!("stretch tree of depth {} check: {}", max_depth + 1, check(&build(max_depth + 1)));
    let long_lived = build(max_depth);
    let mut depth = min_depth;
    while depth <= max_depth {
        let iterations: u64 = 1 << (max_depth - depth + min_depth);
        let mut total = 0;
        for _ in 0..iterations {
            total += check(&build(depth));
        }
        println!("{} trees of depth {} check: {}", iterations, depth, total);
        depth += 2;
    }
    println!("long lived tree of depth {} check: {}", max_depth, check(&long_lived));
}
