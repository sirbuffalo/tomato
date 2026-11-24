// Benchmark: longest Collatz chain for a start below n, no caching. Prints the start and the chain length.
// The numbers pass 2^32 but stay far below 2^53, so plain JavaScript numbers hold them exactly; `/ 2` is exact on an even number.
function main(n: number): void {
  let bestStart = 1;
  let bestLength = 1;
  for (let start = 1; start < n; start++) {
    let x = start;
    let length = 1;
    while (x !== 1) {
      if (x % 2 === 0) x = x / 2;
      else x = 3 * x + 1;
      length++;
    }
    if (length > bestLength) {
      bestLength = length;
      bestStart = start;
    }
  }
  console.log(`${bestStart} ${bestLength}`);
}

main(Number(process.argv[2]));
