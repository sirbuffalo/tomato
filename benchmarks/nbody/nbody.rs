// Benchmark: n-body simulation of the Sun and four planets (floats, objects with float fields, sqrt). Takes n time steps
// of 0.01 and prints the total energy at the start and at the end, each times 1e9 and cut to a whole number.
struct Body {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
}

fn energy(bodies: &[Body]) -> f64 {
    let mut e = 0.0;
    for i in 0..bodies.len() {
        let b = &bodies[i];
        e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
        for j in i + 1..bodies.len() {
            let c = &bodies[j];
            let dx = b.x - c.x;
            let dy = b.y - c.y;
            let dz = b.z - c.z;
            e -= b.mass * c.mass / (dx * dx + dy * dy + dz * dz).sqrt();
        }
    }
    e
}

fn advance(bodies: &mut Vec<Body>, dt: f64) {
    let n = bodies.len();
    for i in 0..n {
        for j in i + 1..n {
            let dx = bodies[i].x - bodies[j].x;
            let dy = bodies[i].y - bodies[j].y;
            let dz = bodies[i].z - bodies[j].z;
            let d2 = dx * dx + dy * dy + dz * dz;
            let mag = dt / (d2 * d2.sqrt());
            let mi = bodies[i].mass;
            let mj = bodies[j].mass;
            bodies[i].vx -= dx * mj * mag;
            bodies[i].vy -= dy * mj * mag;
            bodies[i].vz -= dz * mj * mag;
            bodies[j].vx += dx * mi * mag;
            bodies[j].vy += dy * mi * mag;
            bodies[j].vz += dz * mi * mag;
        }
    }
    for b in bodies.iter_mut() {
        b.x += dt * b.vx;
        b.y += dt * b.vy;
        b.z += dt * b.vz;
    }
}

fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let pi = 3.141592653589793_f64;
    let solar_mass = 4.0 * pi * pi;
    let dpy = 365.24_f64;
    let mut bodies = vec![
        Body { x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: solar_mass },
        Body { x: 4.84143144246472, y: -1.16032004402743, z: -1.03622044471123e-1, vx: 1.66007664274404e-3 * dpy, vy: 7.6990111841974e-3 * dpy, vz: -6.90460016972063e-5 * dpy, mass: 9.54791938424327e-4 * solar_mass },
        Body { x: 8.34336671824458, y: 4.1247985641243, z: -4.03523417114321e-1, vx: -2.76742510726862e-3 * dpy, vy: 4.99852801234917e-3 * dpy, vz: 2.30417297573764e-5 * dpy, mass: 2.85885980666131e-4 * solar_mass },
        Body { x: 1.28943695621391e1, y: -1.51111514016986e1, z: -2.23307578892656e-1, vx: 2.96460137564762e-3 * dpy, vy: 2.37847173959481e-3 * dpy, vz: -2.96589568540238e-5 * dpy, mass: 4.36624404335156e-5 * solar_mass },
        Body { x: 1.53796971148509e1, y: -2.5919314609988e1, z: 1.79258772950371e-1, vx: 2.68067772490389e-3 * dpy, vy: 1.62824170038242e-3 * dpy, vz: -9.51592254519716e-5 * dpy, mass: 5.15138902046611e-5 * solar_mass },
    ];
    let (mut px, mut py, mut pz) = (0.0, 0.0, 0.0);
    for b in &bodies {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    bodies[0].vx = -px / solar_mass;
    bodies[0].vy = -py / solar_mass;
    bodies[0].vz = -pz / solar_mass;
    println!("{}", (energy(&bodies) * 1000000000.0) as i64);
    for _ in 0..n {
        advance(&mut bodies, 0.01);
    }
    println!("{}", (energy(&bodies) * 1000000000.0) as i64);
}
