// Benchmark: n-body simulation of the Sun and four planets (floats, objects with float fields, sqrt). Takes n time steps
// of 0.01 and prints the total energy at the start and at the end, each times 1e9 and cut to a whole number.
class Body {
  constructor(x, y, z, vx, vy, vz, mass) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.vx = vx;
    this.vy = vy;
    this.vz = vz;
    this.mass = mass;
  }
}

function energy(bodies) {
  let e = 0.0;
  for (let i = 0; i < bodies.length; i++) {
    const b = bodies[i];
    e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
    for (let j = i + 1; j < bodies.length; j++) {
      const c = bodies[j];
      const dx = b.x - c.x;
      const dy = b.y - c.y;
      const dz = b.z - c.z;
      e -= b.mass * c.mass / Math.sqrt(dx * dx + dy * dy + dz * dz);
    }
  }
  return e;
}

function advance(bodies, dt) {
  for (let i = 0; i < bodies.length; i++) {
    const b = bodies[i];
    for (let j = i + 1; j < bodies.length; j++) {
      const c = bodies[j];
      const dx = b.x - c.x;
      const dy = b.y - c.y;
      const dz = b.z - c.z;
      const d2 = dx * dx + dy * dy + dz * dz;
      const mag = dt / (d2 * Math.sqrt(d2));
      b.vx -= dx * c.mass * mag;
      b.vy -= dy * c.mass * mag;
      b.vz -= dz * c.mass * mag;
      c.vx += dx * b.mass * mag;
      c.vy += dy * b.mass * mag;
      c.vz += dz * b.mass * mag;
    }
  }
  for (const b of bodies) {
    b.x += dt * b.vx;
    b.y += dt * b.vy;
    b.z += dt * b.vz;
  }
}

const n = Number(process.argv[2]);
const pi = 3.141592653589793;
const solarMass = 4.0 * pi * pi;
const dpy = 365.24;
const bodies = [
  new Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solarMass),
  new Body(4.84143144246472, -1.16032004402743, -1.03622044471123e-1, 1.66007664274404e-3 * dpy, 7.6990111841974e-3 * dpy, -6.90460016972063e-5 * dpy, 9.54791938424327e-4 * solarMass),
  new Body(8.34336671824458, 4.1247985641243, -4.03523417114321e-1, -2.76742510726862e-3 * dpy, 4.99852801234917e-3 * dpy, 2.30417297573764e-5 * dpy, 2.85885980666131e-4 * solarMass),
  new Body(1.28943695621391e1, -1.51111514016986e1, -2.23307578892656e-1, 2.96460137564762e-3 * dpy, 2.37847173959481e-3 * dpy, -2.96589568540238e-5 * dpy, 4.36624404335156e-5 * solarMass),
  new Body(1.53796971148509e1, -2.5919314609988e1, 1.79258772950371e-1, 2.68067772490389e-3 * dpy, 1.62824170038242e-3 * dpy, -9.51592254519716e-5 * dpy, 5.15138902046611e-5 * solarMass),
];
let px = 0.0;
let py = 0.0;
let pz = 0.0;
for (const b of bodies) {
  px += b.vx * b.mass;
  py += b.vy * b.mass;
  pz += b.vz * b.mass;
}
bodies[0].vx = -px / solarMass;
bodies[0].vy = -py / solarMass;
bodies[0].vz = -pz / solarMass;
console.log(String(Math.trunc(energy(bodies) * 1000000000.0)));
for (let step = 0; step < n; step++) advance(bodies, 0.01);
console.log(String(Math.trunc(energy(bodies) * 1000000000.0)));
