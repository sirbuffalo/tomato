// Benchmark: n-body simulation of the Sun and four planets (floats, objects with float fields, sqrt). Takes n time steps
// of 0.01 and prints the total energy at the start and at the end, each times 1e9 and cut to a whole number.
class nbody {
    static class Body {
        double x, y, z, vx, vy, vz, mass;
        Body(double x, double y, double z, double vx, double vy, double vz, double mass) {
            this.x = x; this.y = y; this.z = z; this.vx = vx; this.vy = vy; this.vz = vz; this.mass = mass;
        }
    }

    static double energy(Body[] bodies) {
        double e = 0.0;
        for (int i = 0; i < bodies.length; i++) {
            Body b = bodies[i];
            e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
            for (int j = i + 1; j < bodies.length; j++) {
                Body c = bodies[j];
                double dx = b.x - c.x;
                double dy = b.y - c.y;
                double dz = b.z - c.z;
                e -= b.mass * c.mass / Math.sqrt(dx * dx + dy * dy + dz * dz);
            }
        }
        return e;
    }

    static void advance(Body[] bodies, double dt) {
        for (int i = 0; i < bodies.length; i++) {
            Body b = bodies[i];
            for (int j = i + 1; j < bodies.length; j++) {
                Body c = bodies[j];
                double dx = b.x - c.x;
                double dy = b.y - c.y;
                double dz = b.z - c.z;
                double d2 = dx * dx + dy * dy + dz * dz;
                double mag = dt / (d2 * Math.sqrt(d2));
                b.vx -= dx * c.mass * mag;
                b.vy -= dy * c.mass * mag;
                b.vz -= dz * c.mass * mag;
                c.vx += dx * b.mass * mag;
                c.vy += dy * b.mass * mag;
                c.vz += dz * b.mass * mag;
            }
        }
        for (Body b : bodies) {
            b.x += dt * b.vx;
            b.y += dt * b.vy;
            b.z += dt * b.vz;
        }
    }

    public static void main(String[] args) {
        long n = Long.parseLong(args[0]);
        double pi = 3.141592653589793;
        double solarMass = 4.0 * pi * pi;
        double dpy = 365.24;
        Body[] bodies = {
            new Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solarMass),
            new Body(4.84143144246472, -1.16032004402743, -1.03622044471123e-1, 1.66007664274404e-3 * dpy, 7.6990111841974e-3 * dpy, -6.90460016972063e-5 * dpy, 9.54791938424327e-4 * solarMass),
            new Body(8.34336671824458, 4.1247985641243, -4.03523417114321e-1, -2.76742510726862e-3 * dpy, 4.99852801234917e-3 * dpy, 2.30417297573764e-5 * dpy, 2.85885980666131e-4 * solarMass),
            new Body(1.28943695621391e1, -1.51111514016986e1, -2.23307578892656e-1, 2.96460137564762e-3 * dpy, 2.37847173959481e-3 * dpy, -2.96589568540238e-5 * dpy, 4.36624404335156e-5 * solarMass),
            new Body(1.53796971148509e1, -2.5919314609988e1, 1.79258772950371e-1, 2.68067772490389e-3 * dpy, 1.62824170038242e-3 * dpy, -9.51592254519716e-5 * dpy, 5.15138902046611e-5 * solarMass)
        };
        double px = 0.0, py = 0.0, pz = 0.0;
        for (Body b : bodies) {
            px += b.vx * b.mass;
            py += b.vy * b.mass;
            pz += b.vz * b.mass;
        }
        bodies[0].vx = -px / solarMass;
        bodies[0].vy = -py / solarMass;
        bodies[0].vz = -pz / solarMass;
        System.out.println((long) (energy(bodies) * 1000000000.0));
        for (long step = 0; step < n; step++) advance(bodies, 0.01);
        System.out.println((long) (energy(bodies) * 1000000000.0));
    }
}
