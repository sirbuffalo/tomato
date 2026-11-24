// Benchmark: checksums over bytes. Makes n pseudo-random bytes with a linear congruential generator, then computes the
// table-driven CRC-32 (polynomial 0xEDB88320) over them four times (each pass starts from the previous result) and the
// Adler-32 once. Prints both. Bitwise operators and lookups in a 256-entry table.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
// JavaScript's bitwise operators work on signed 32-bit numbers, so >>> 0 turns the results back into unsigned ones.
const n = Number(process.argv[2]);
const table = new Uint32Array(256);
for (let i = 0; i < 256; i++) {
  let c = i;
  for (let k = 0; k < 8; k++) {
    if ((c & 1) === 1) c = (3988292384 ^ (c >>> 1)) >>> 0;
    else c = c >>> 1;
  }
  table[i] = c;
}
let seed = 1;
const data = new Uint8Array(n);
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  data[i] = (seed >> 16) % 256;
}
let crc = 4294967295;
for (let rounds = 0; rounds < 4; rounds++) {
  for (let i = 0; i < n; i++) crc = (table[(crc ^ data[i]) & 255] ^ (crc >>> 8)) >>> 0;
}
crc = (crc ^ 4294967295) >>> 0;
let a = 1;
let b2 = 0;
for (let i = 0; i < n; i++) {
  a = (a + data[i]) % 65521;
  b2 = (b2 + a) % 65521;
}
console.log(crc + " " + (b2 * 65536 + a));
