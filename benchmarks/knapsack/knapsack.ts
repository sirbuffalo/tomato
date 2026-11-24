// Benchmark: 0/1 knapsack by dynamic programming over one row of capacities. n items with pseudo-random weights (1..60) and
// values (1..1000) from a linear congruential generator, capacity 5 * n. Prints the best total value.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
const n: number = Number(process.argv[2]);
let seed: number = 7;
const weights: Int32Array = new Int32Array(n);
const values: Int32Array = new Int32Array(n);
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  weights[i] = (seed >> 16) % 60 + 1;
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  values[i] = (seed >> 16) % 1000 + 1;
}
const capacity = 5 * n;
const best: Int32Array = new Int32Array(capacity + 1);
for (let i = 0; i < n; i++) {
  const w = weights[i];
  const v = values[i];
  let c = capacity;
  while (c >= w) {
    const candidate = best[c - w] + v;
    if (candidate > best[c]) best[c] = candidate;
    c -= 1;
  }
}
console.log(String(best[capacity]));
