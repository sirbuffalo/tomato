// Benchmark: binary trees. Builds and checks many complete binary trees of growing depth (millions of small objects made
// and freed), while one long-lived tree stays in memory. Prints the node counts the way the Benchmarks Game does.
class Node {
  constructor(left, right) {
    this.left = left;
    this.right = right;
  }
}

function build(depth) {
  if (depth === 0) return new Node(null, null);
  return new Node(build(depth - 1), build(depth - 1));
}

function check(node) {
  const left = node.left;
  const right = node.right;
  if (left === null || right === null) return 1;
  return 1 + check(left) + check(right);
}

const n = Number(process.argv[2]);
const minDepth = 4;
let maxDepth = n;
if (maxDepth < minDepth + 2) maxDepth = minDepth + 2;
console.log(`stretch tree of depth ${maxDepth + 1} check: ${check(build(maxDepth + 1))}`);
const longLived = build(maxDepth);
for (let depth = minDepth; depth <= maxDepth; depth += 2) {
  const iterations = 1 << (maxDepth - depth + minDepth);
  let total = 0;
  for (let i = 0; i < iterations; i++) total += check(build(depth));
  console.log(`${iterations} trees of depth ${depth} check: ${total}`);
}
console.log(`long lived tree of depth ${maxDepth} check: ${check(longLived)}`);
