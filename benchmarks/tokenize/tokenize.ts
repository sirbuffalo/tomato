// Benchmark: a hand-written tokenizer (no regular expressions). Makes n pseudo-random tokens of source-like text (names,
// whole numbers and punctuation), joins them, then scans the text one character at a time and classifies the tokens.
// Prints the number of names, numbers and symbols, the sum of the numbers and the total length of the names.
// The LCG product needs 61 bits, more than a JavaScript number holds exactly, so Math.imul keeps its low 32 bits, which is
// all that the mod 2^31 (the & 0x7fffffff) looks at.
const n: number = Number(process.argv[2]);
let seed: number = 555;
const words: string[] = ["alpha", "beta", "gamma", "delta", "count", "total", "index", "value"];
const symbols: string[] = ["+", "-", "*", "/", "=", "(", ")", ";"];
const pieces: string[] = [];
for (let i = 0; i < n; i++) {
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  const kind = (seed >> 16) % 4;
  seed = (Math.imul(seed, 1103515245) + 12345) & 0x7fffffff;
  const pick = seed >> 16;
  if (kind === 0) pieces.push(words[pick % 8] + " ");
  else if (kind === 1) pieces.push(String(pick % 100000) + " ");
  else if (kind === 2) pieces.push(symbols[pick % 8]);
  else pieces.push(words[pick % 8] + String(Math.floor(pick / 8) % 100) + " ");
}
const text: string = pieces.join("");
let names = 0;
let numbers = 0;
let syms = 0;
let numberSum = 0;
let nameLength = 0;
let inName: boolean = false;
let inNumber: boolean = false;
let value = 0;
for (let p = 0; p < text.length; p++) {
  const ch = text.charCodeAt(p);
  const alpha = (ch >= 97 && ch <= 122) || (ch >= 65 && ch <= 90);
  const digit = ch >= 48 && ch <= 57;
  if (alpha || (inName && digit)) {
    if (!inName) {
      inName = true;
      names += 1;
    }
    nameLength += 1;
  } else if (digit) {
    if (!inNumber) {
      inNumber = true;
      numbers += 1;
      value = 0;
    }
    value = value * 10 + ch - 48;
  } else {
    if (inNumber) numberSum += value;
    inName = false;
    inNumber = false;
    if (ch !== 32) syms += 1;
  }
}
if (inNumber) numberSum += value;
console.log(names + " " + numbers + " " + syms + " " + numberSum + " " + nameLength);
