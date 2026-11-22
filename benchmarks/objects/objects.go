// Benchmark: objects and method calls. Makes n particles, steps each one 10 times, prints the sum of their positions.
// The particles are separate heap objects (pointers), like Tomato and Python objects.
package main

import (
	"fmt"
	"os"
	"strconv"
)

type Particle struct {
	x, v int
}

func (p *Particle) step(round int) {
	p.x = (p.x + p.v*round) % 1000003
}

func main() {
	n, _ := strconv.Atoi(os.Args[1])
	particles := make([]*Particle, 0)
	for i := 0; i < n; i++ {
		particles = append(particles, &Particle{i, i%13 + 1})
	}
	for round := 1; round <= 10; round++ {
		for _, p := range particles {
			p.step(round)
		}
	}
	total := 0
	for _, p := range particles {
		total += p.x
	}
	fmt.Println(total)
}
