// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
// The particles are separate heap objects (Box), like Tomato and Python objects.
struct Particle {
    x: u64,
    v: u64,
}

impl Particle {
    fn step(&mut self, round: u64) {
        self.x = (self.x + self.v * round) % 1000003;
    }
}

fn main() {
    let n: u64 = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut particles: Vec<Box<Particle>> = Vec::new();
    for i in 0..n {
        particles.push(Box::new(Particle { x: i, v: i % 13 + 1 }));
    }
    for round in 1..=10 {
        for p in particles.iter_mut() {
            p.step(round);
        }
    }
    let mut total: u64 = 0;
    for p in &particles {
        total += p.x;
    }
    println!("{}", total);
}
