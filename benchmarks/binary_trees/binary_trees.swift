// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
final class Node {
    let left: Node?
    let right: Node?
    init(_ left: Node?, _ right: Node?) {
        self.left = left
        self.right = right
    }
}

func build(_ depth: Int) -> Node {
    if depth == 0 { return Node(nil, nil) }
    return Node(build(depth - 1), build(depth - 1))
}

func check(_ node: Node) -> Int {
    guard let left = node.left, let right = node.right else { return 1 }
    return 1 + check(left) + check(right)
}

let n = Int(CommandLine.arguments[1])!
let minDepth = 4
var maxDepth = n
if maxDepth < minDepth + 2 { maxDepth = minDepth + 2 }
print("stretch tree of depth \(maxDepth + 1) check: \(check(build(maxDepth + 1)))")
let longLived = build(maxDepth)
var depth = minDepth
while depth <= maxDepth {
    let iterations = 1 << (maxDepth - depth + minDepth)
    var total = 0
    var i = 0
    while i < iterations {
        total += check(build(depth))
        i += 1
    }
    print("\(iterations) trees of depth \(depth) check: \(total)")
    depth += 2
}
print("long lived tree of depth \(maxDepth) check: \(check(longLived))")
