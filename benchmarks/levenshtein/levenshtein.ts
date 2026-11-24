// Benchmark: edit distance (Levenshtein) by dynamic programming. Makes two pseudo-random strings of n letters (a..d) with a
// linear congruential generator and fills the table row by row (two rows kept). Prints the distance.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
const n: number = Number(process.argv[2]);
let seed: number = 42;
const s: Uint8Array = new Uint8Array(n);
const t: Uint8Array = new Uint8Array(n);
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  s[i] = 97 + (seed >> 16) % 4;
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  t[i] = 97 + (seed >> 16) % 4;
}
let prev: Int32Array = new Int32Array(n + 1);
let cur: Int32Array = new Int32Array(n + 1);
for (let j = 0; j <= n; j++) prev[j] = j;
for (let i = 1; i <= n; i++) {
  cur[0] = i;
  const si = s[i - 1];
  for (let j = 1; j <= n; j++) {
    let cost = 1;
    if (si === t[j - 1]) cost = 0;
    let best = prev[j - 1] + cost;
    const up = prev[j] + 1;
    if (up < best) best = up;
    const left = cur[j - 1] + 1;
    if (left < best) best = left;
    cur[j] = best;
  }
  const swap = prev;
  prev = cur;
  cur = swap;
}
console.log(String(prev[n]));
