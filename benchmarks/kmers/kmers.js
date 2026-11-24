// Benchmark: k-nucleotide counting. Makes a pseudo-random DNA string of n letters (A, C, G, T) with a linear congruential
// generator, then counts every substring of length 1, 2, 4, 6 and 12 in a Map. For each length prints the number of
// different substrings, the highest count and the sum of the squares of the counts.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
const n = Number(process.argv[2]);
let seed = 31337;
const letters = ["A", "C", "G", "T"];
const parts = [];
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  parts.push(letters[(seed >> 16) % 4]);
}
const dna = parts.join("");
for (const k of [1, 2, 4, 6, 12]) {
  const counts = new Map();
  for (let i = 0; i < n - k + 1; i++) {
    const key = dna.substring(i, i + k);
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  let most = 0;
  let squares = 0;
  for (const c of counts.values()) {
    if (c > most) most = c;
    squares += c * c;
  }
  console.log(k + " " + counts.size + " " + most + " " + squares);
}
