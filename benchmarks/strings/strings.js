// Benchmark: text building and parsing. Joins n numbers into one comma-separated string, splits it and adds them up.
// Prints the text length and the sum.
const n = Number(process.argv[2]);
const parts = [];
for (let i = 0; i < n; i++) parts.push(String(i * 7 % 1000));
const text = parts.join(',');
let total = 0;
for (const piece of text.split(',')) total += parseInt(piece, 10);
console.log(`${text.length} ${total}`);
