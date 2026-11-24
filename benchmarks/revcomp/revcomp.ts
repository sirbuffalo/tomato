// Benchmark: reverse complement of DNA text. Makes a pseudo-random sequence of n letters (A, C, G, T) with a linear
// congruential generator, writes it as FASTA lines of 60 letters, reads the lines back, joins them, builds the reverse
// complement, and wraps it again. Prints the number of lines and a checksum over every 7th letter of the result.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
const n: number = Number(process.argv[2]);
let seed: number = 2718;
const letters: string[] = ["A", "C", "G", "T"];
const parts: string[] = [];
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  parts.push(letters[(seed >> 16) % 4]);
}
const dna: string = parts.join("");
const lines: string[] = [];
for (let start = 0; start < n; start += 60) lines.push(dna.substring(start, start + 60));
const text = lines.join("");
const complement: Record<string, string> = { A: "T", C: "G", G: "C", T: "A" };
const out: string[] = [];
for (let i = text.length - 1; i >= 0; i--) out.push(complement[text[i]]);
const rc = out.join("");
const wrapped: string[] = [];
for (let start = 0; start < rc.length; start += 60) wrapped.push(rc.substring(start, start + 60));
let checksum = 0;
for (const line of wrapped) {
  for (let k = 0; k < line.length; k += 7) checksum = (checksum * 131 + line.charCodeAt(k)) % 1000000007;
}
console.log(wrapped.length + " " + checksum);
