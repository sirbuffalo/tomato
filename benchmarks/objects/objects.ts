// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
class Particle {
  x: number;
  v: number;

  constructor(x: number, v: number) {
    this.x = x;
    this.v = v;
  }

  step(round: number): void {
    this.x = (this.x + this.v * round) % 1000003;
  }
}

const n = Number(process.argv[2]);
const particles: Particle[] = [];
for (let i = 0; i < n; i++) particles.push(new Particle(i, i % 13 + 1));
for (let round = 1; round <= 10; round++) {
  for (const p of particles) p.step(round);
}
let total = 0;
for (const p of particles) total += p.x;
console.log(String(total));
