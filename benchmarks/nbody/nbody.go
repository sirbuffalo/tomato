// Benchmark: n-body simulation of the Sun and four planets (floats, objects with float fields, sqrt). Takes n time steps
// of 0.01 and prints the total energy at the start and at the end, each times 1e9 and cut to a whole number.
package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
)

type Body struct {
	x, y, z, vx, vy, vz, mass float64
}

func energy(bodies []*Body) float64 {
	e := 0.0
	for i := 0; i < len(bodies); i++ {
		b := bodies[i]
		e += 0.5 * b.mass * (b.vx*b.vx + b.vy*b.vy + b.vz*b.vz)
		for j := i + 1; j < len(bodies); j++ {
			c := bodies[j]
			dx := b.x - c.x
			dy := b.y - c.y
			dz := b.z - c.z
			e -= b.mass * c.mass / math.Sqrt(dx*dx+dy*dy+dz*dz)
		}
	}
	return e
}

func advance(bodies []*Body, dt float64) {
	for i := 0; i < len(bodies); i++ {
		b := bodies[i]
		for j := i + 1; j < len(bodies); j++ {
			c := bodies[j]
			dx := b.x - c.x
			dy := b.y - c.y
			dz := b.z - c.z
			d2 := dx*dx + dy*dy + dz*dz
			mag := dt / (d2 * math.Sqrt(d2))
			b.vx -= dx * c.mass * mag
			b.vy -= dy * c.mass * mag
			b.vz -= dz * c.mass * mag
			c.vx += dx * b.mass * mag
			c.vy += dy * b.mass * mag
			c.vz += dz * b.mass * mag
		}
	}
	for _, b := range bodies {
		b.x += dt * b.vx
		b.y += dt * b.vy
		b.z += dt * b.vz
	}
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	pi := 3.141592653589793
	solarMass := 4.0 * pi * pi
	dpy := 365.24
	init := []Body{
		{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solarMass},
		{4.84143144246472, -1.16032004402743, -1.03622044471123e-1, 1.66007664274404e-3 * dpy, 7.6990111841974e-3 * dpy, -6.90460016972063e-5 * dpy, 9.54791938424327e-4 * solarMass},
		{8.34336671824458, 4.1247985641243, -4.03523417114321e-1, -2.76742510726862e-3 * dpy, 4.99852801234917e-3 * dpy, 2.30417297573764e-5 * dpy, 2.85885980666131e-4 * solarMass},
		{1.28943695621391e1, -1.51111514016986e1, -2.23307578892656e-1, 2.96460137564762e-3 * dpy, 2.37847173959481e-3 * dpy, -2.96589568540238e-5 * dpy, 4.36624404335156e-5 * solarMass},
		{1.53796971148509e1, -2.5919314609988e1, 1.79258772950371e-1, 2.68067772490389e-3 * dpy, 1.62824170038242e-3 * dpy, -9.51592254519716e-5 * dpy, 5.15138902046611e-5 * solarMass},
	}
	bodies := make([]*Body, len(init))
	for i := range init {
		bodies[i] = &init[i]
	}
	px, py, pz := 0.0, 0.0, 0.0
	for _, b := range bodies {
		px += b.vx * b.mass
		py += b.vy * b.mass
		pz += b.vz * b.mass
	}
	bodies[0].vx = -px / solarMass
	bodies[0].vy = -py / solarMass
	bodies[0].vz = -pz / solarMass
	fmt.Println(int64(energy(bodies) * 1000000000.0))
	for step := 0; step < n; step++ {
		advance(bodies, 0.01)
	}
	fmt.Println(int64(energy(bodies) * 1000000000.0))
}
