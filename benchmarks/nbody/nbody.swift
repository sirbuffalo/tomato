// Benchmark: n-body simulation of the Sun and four planets (floats, objects with float fields, sqrt). Takes n time steps
// of 0.01 and prints the total energy at the start and at the end, each times 1e9 and cut to a whole number.
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class Body {
    var x: Double, y: Double, z: Double, vx: Double, vy: Double, vz: Double, mass: Double
    init(_ x: Double, _ y: Double, _ z: Double, _ vx: Double, _ vy: Double, _ vz: Double, _ mass: Double) {
        self.x = x; self.y = y; self.z = z; self.vx = vx; self.vy = vy; self.vz = vz; self.mass = mass
    }
}

func energy(_ bodies: [Body]) -> Double {
    var e = 0.0
    for i in 0..<bodies.count {
        let b = bodies[i]
        e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
        var j = i + 1
        while j < bodies.count {
            let c = bodies[j]
            let dx = b.x - c.x
            let dy = b.y - c.y
            let dz = b.z - c.z
            e -= b.mass * c.mass / (dx * dx + dy * dy + dz * dz).squareRoot()
            j += 1
        }
    }
    return e
}

func advance(_ bodies: [Body], _ dt: Double) {
    for i in 0..<bodies.count {
        let b = bodies[i]
        var j = i + 1
        while j < bodies.count {
            let c = bodies[j]
            let dx = b.x - c.x
            let dy = b.y - c.y
            let dz = b.z - c.z
            let d2 = dx * dx + dy * dy + dz * dz
            let mag = dt / (d2 * d2.squareRoot())
            b.vx -= dx * c.mass * mag
            b.vy -= dy * c.mass * mag
            b.vz -= dz * c.mass * mag
            c.vx += dx * b.mass * mag
            c.vy += dy * b.mass * mag
            c.vz += dz * b.mass * mag
            j += 1
        }
    }
    for b in bodies {
        b.x += dt * b.vx
        b.y += dt * b.vy
        b.z += dt * b.vz
    }
}

let n = Int(CommandLine.arguments[1])!
let pi = 3.141592653589793
let solarMass = 4.0 * pi * pi
let dpy = 365.24
let bodies = [
    Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solarMass),
    Body(4.84143144246472, -1.16032004402743, -1.03622044471123e-1, 1.66007664274404e-3 * dpy, 7.6990111841974e-3 * dpy, -6.90460016972063e-5 * dpy, 9.54791938424327e-4 * solarMass),
    Body(8.34336671824458, 4.1247985641243, -4.03523417114321e-1, -2.76742510726862e-3 * dpy, 4.99852801234917e-3 * dpy, 2.30417297573764e-5 * dpy, 2.85885980666131e-4 * solarMass),
    Body(1.28943695621391e1, -1.51111514016986e1, -2.23307578892656e-1, 2.96460137564762e-3 * dpy, 2.37847173959481e-3 * dpy, -2.96589568540238e-5 * dpy, 4.36624404335156e-5 * solarMass),
    Body(1.53796971148509e1, -2.5919314609988e1, 1.79258772950371e-1, 2.68067772490389e-3 * dpy, 1.62824170038242e-3 * dpy, -9.51592254519716e-5 * dpy, 5.15138902046611e-5 * solarMass),
]
var px = 0.0, py = 0.0, pz = 0.0
for b in bodies {
    px += b.vx * b.mass
    py += b.vy * b.mass
    pz += b.vz * b.mass
}
bodies[0].vx = -px / solarMass
bodies[0].vy = -py / solarMass
bodies[0].vz = -pz / solarMass
print(Int(energy(bodies) * 1000000000.0))
var step = 0
while step < n {
    advance(bodies, 0.01)
    step += 1
}
print(Int(energy(bodies) * 1000000000.0))
