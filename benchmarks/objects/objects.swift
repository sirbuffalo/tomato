// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
final class Particle {
    var x: Int
    let v: Int

    init(x: Int, v: Int) {
        self.x = x
        self.v = v
    }

    func step(_ round: Int) {
        x = (x + v * round) % 1000003
    }
}

func run(_ n: Int) {
    var particles: [Particle] = []
    for i in 0..<n { particles.append(Particle(x: i, v: i % 13 + 1)) }
    for round in 1...10 {
        for p in particles { p.step(round) }
    }
    var total = 0
    for p in particles { total += p.x }
    print(total)
}

run(Int(CommandLine.arguments[1])!)
