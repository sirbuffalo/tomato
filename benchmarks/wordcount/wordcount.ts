// Benchmark: word counting in a Map. Counts n generated words ("w0".."w5002"), then prints a weighted checksum.
const n: number = Number(process.argv[2]);
const counts: Map<string, number> = new Map();
for (let i = 0; i < n; i++) {
  const word = `w${i * 7919 % 5003}`;
  counts.set(word, (counts.get(word) || 0) + 1);
}
let checksum = 0;
for (let k = 0; k < 5003; k++) checksum += (k + 1) * (counts.get(`w${k}`) || 0);
console.log(`${counts.size} ${checksum}`);
