// Benchmark: fannkuch-redux. Goes through all permutations of 0..n-1 and flips the prefix of each (as many cards as the
// first card says) until the first card is 0. Prints the alternating-sign checksum of the flip counts and the maximum.
const n: number = Number(process.argv[2]);
const perm1 = new Int32Array(n);
for (let i = 0; i < n; i++) perm1[i] = i;
const perm = new Int32Array(n);
const count = new Int32Array(n);
let maxFlips = 0;
let checksum = 0;
let permCount = 0;
let r = n;
let done: boolean = false;
while (!done) {
  while (r !== 1) {
    count[r - 1] = r;
    r -= 1;
  }
  for (let i = 0; i < n; i++) perm[i] = perm1[i];
  let flips = 0;
  let k = perm[0];
  while (k !== 0) {
    let i = 0;
    let j = k;
    while (i < j) {
      const t = perm[i];
      perm[i] = perm[j];
      perm[j] = t;
      i += 1;
      j -= 1;
    }
    flips += 1;
    k = perm[0];
  }
  if (flips > maxFlips) maxFlips = flips;
  if (permCount % 2 === 0) checksum += flips;
  else checksum -= flips;
  while (true) {
    if (r === n) {
      done = true;
      break;
    }
    const p0 = perm1[0];
    for (let i = 0; i < r; i++) perm1[i] = perm1[i + 1];
    perm1[r] = p0;
    count[r] -= 1;
    if (count[r] > 0) break;
    r += 1;
  }
  permCount += 1;
}
console.log(String(checksum));
console.log(`Pfannkuchen(${n}) = ${maxFlips}`);
