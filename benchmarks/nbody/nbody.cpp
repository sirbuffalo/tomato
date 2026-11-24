// Benchmark: n-body simulation of the Sun and four planets (floats, structs with float fields, sqrt). Takes n time steps
// of 0.01 and prints the total energy at the start and at the end, each times 1e9 and cut to a whole number.
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

struct Body { double x, y, z, vx, vy, vz, mass; };

static double energy(const std::vector<Body> &bodies) {
    double e = 0.0;
    for (std::size_t i = 0; i < bodies.size(); i++) {
        const Body &b = bodies[i];
        e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
        for (std::size_t j = i + 1; j < bodies.size(); j++) {
            const Body &c = bodies[j];
            double dx = b.x - c.x, dy = b.y - c.y, dz = b.z - c.z;
            e -= b.mass * c.mass / std::sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

static void advance(std::vector<Body> &bodies, double dt) {
    for (std::size_t i = 0; i < bodies.size(); i++) {
        Body &b = bodies[i];
        for (std::size_t j = i + 1; j < bodies.size(); j++) {
            Body &c = bodies[j];
            double dx = b.x - c.x, dy = b.y - c.y, dz = b.z - c.z;
            double d2 = dx * dx + dy * dy + dz * dz;
            double mag = dt / (d2 * std::sqrt(d2));
            b.vx -= dx * c.mass * mag;
            b.vy -= dy * c.mass * mag;
            b.vz -= dz * c.mass * mag;
            c.vx += dx * b.mass * mag;
            c.vy += dy * b.mass * mag;
            c.vz += dz * b.mass * mag;
        }
    }
    for (Body &b : bodies) {
        b.x += dt * b.vx;
        b.y += dt * b.vy;
        b.z += dt * b.vz;
    }
}

int main(int, char **argv) {
    std::int64_t n = std::stoll(argv[1]);
    double pi = 3.141592653589793;
    double solar_mass = 4.0 * pi * pi;
    double dpy = 365.24;
    std::vector<Body> bodies = {
        {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solar_mass},
        {4.84143144246472, -1.16032004402743, -1.03622044471123e-1, 1.66007664274404e-3 * dpy, 7.6990111841974e-3 * dpy, -6.90460016972063e-5 * dpy, 9.54791938424327e-4 * solar_mass},
        {8.34336671824458, 4.1247985641243, -4.03523417114321e-1, -2.76742510726862e-3 * dpy, 4.99852801234917e-3 * dpy, 2.30417297573764e-5 * dpy, 2.85885980666131e-4 * solar_mass},
        {1.28943695621391e1, -1.51111514016986e1, -2.23307578892656e-1, 2.96460137564762e-3 * dpy, 2.37847173959481e-3 * dpy, -2.96589568540238e-5 * dpy, 4.36624404335156e-5 * solar_mass},
        {1.53796971148509e1, -2.5919314609988e1, 1.79258772950371e-1, 2.68067772490389e-3 * dpy, 1.62824170038242e-3 * dpy, -9.51592254519716e-5 * dpy, 5.15138902046611e-5 * solar_mass},
    };
    double px = 0.0, py = 0.0, pz = 0.0;
    for (const Body &b : bodies) {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    bodies[0].vx = -px / solar_mass;
    bodies[0].vy = -py / solar_mass;
    bodies[0].vz = -pz / solar_mass;
    std::cout << static_cast<std::int64_t>(energy(bodies) * 1000000000.0) << '\n';
    for (std::int64_t step = 0; step < n; step++) advance(bodies, 0.01);
    std::cout << static_cast<std::int64_t>(energy(bodies) * 1000000000.0) << '\n';
}
