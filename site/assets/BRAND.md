# Tomato brand on the website

Logo and colors are by Davis; the artwork is fixed (never retyped or restyled). The wordmark is Quicksand Bold converted to paths.

| file | use |
|---|---|
| `tomato-logo-full.svg` (+ `-2400.png`, `-800.png`) | mark + wordmark, transparent: site header, README |
| `tomato-icon-square.svg` (+ `-1024.png`, `-256.png`, `-64.png`) | the mark alone: page titles (`h1 .mark`) |
| `../favicon.svg`, `../icon.svg` | copies of `tomato-icon-square.svg` |
| `../favicon.ico` (16/32/48), `../icon-192.png`, `../icon-512.png`, `../apple-touch-icon.png` (180, white background) | rendered from the square SVG with cairosvg |

Brand colors (screen source of truth; Pantone matches are approximate): red `#EB3C27` (Pantone 179 C), green `#009639` (Pantone 355 C). The two hexes are never changed, only paired with tints where the raw color is too light for text.

## Decisions

- Raw red on white is 4.03:1 and raw green on white is 3.87:1, so they fail AA (4.5) for small text. Text and links use a darker red tint `--accent` (`#C62E1A` light, `#FF6A52` dark) and a darker green tint `--accent-green` (`#00762E` light, `#5FD48A` dark); the raw hexes (`--red`, `--green`) are used for fills, the logo, the focus ring and the selected-tab underline (all need only 3:1).
- The primary button is brand red with near-black text (`--on-red` `#1A0805`, 4.82:1); white on `#EB3C27` is only 4.03:1.
- The red wordmark on the dark page background (`#1A1210`) is 4.58:1 (3:1 is the bar for a logo), and the green leaf is 4.76:1, so no light-on-dark variant of the full logo was made.
- Control borders (buttons, inputs, language pills) use `--ctl`, at least 3:1 on every surface; `--line` stays for dividers and card edges.
- Page titles and section headings (`h1`, `h2`) use Quicksand Bold (`fonts/quicksand-bold.woff2`, a Latin subset, SIL OFL), the wordmark's typeface.
- Benchmark chart: the Tomato bar is the brand red in both themes; "Tomato (debug)" is a dark maroon on light and a light pink on dark (the old light tint on white was under 3:1); every bar is at least 3:1 against the page.

## Contrast (WCAG 2.x; need 4.5 for text, 3 for large text and UI)

Computed from the token values in `style.css`; every pair passes. Surfaces: bg / card / code.
### Light
| pair | colors | ratio | need | |
|---|---|---|---|---|
| body text | text #2a1c19 on bg/card/code | 15.85 / 16.42 / 14.40 | 4.5 | pass |
| muted text | muted #6b5650 on bg/card/code | 6.60 / 6.84 / 5.99 | 4.5 | pass |
| links, nav hover, selected tab | accent #c62e1a on bg/card/code | 5.32 / 5.52 / 4.84 | 4.5 | pass |
| error text | danger #a82118 on bg/card/code | 7.00 / 7.25 / 6.36 | 4.5 | pass |
| ok / hint text | agreen #00762e on bg/card/code | 5.58 / 5.78 / 5.07 | 4.5 | pass |
| warning text | warn #8a5a00 on bg/card | 5.72 / 5.93 | 4.5 | pass |
| info text | info #2c5aa0 on bg/card | 6.59 / 6.82 | 4.5 | pass |
| location text | loc #0b6b73 on bg/card | 6.02 / 6.24 | 4.5 | pass |
| primary button/skip link text | onred #1a0805 on red | 4.82 | 4.5 | pass |
| brand red as UI (focus ring, tab underline, primary button edge) | red #eb3c27 on bg/card | 3.89 / 4.03 | 3 | pass |
| control borders | ctl #8f7b74 on bg/card/code | 3.86 / 4.00 / 3.50 | 3 | pass |

### Dark
| pair | colors | ratio | need | |
|---|---|---|---|---|
| body text | text #f6ece8 on bg/card/code | 15.89 / 14.64 / 13.25 | 4.5 | pass |
| muted text | muted #b8a69f on bg/card/code | 7.90 / 7.28 / 6.59 | 4.5 | pass |
| links, nav hover, selected tab | accent #ff6a52 on bg/card/code | 6.53 / 6.02 / 5.45 | 4.5 | pass |
| error text | danger #ff8a7a on bg/card/code | 8.06 / 7.42 / 6.72 | 4.5 | pass |
| ok / hint text | agreen #5fd48a on bg/card/code | 9.90 / 9.13 / 8.26 | 4.5 | pass |
| warning text | warn #f0c15a on bg/card | 10.97 / 10.10 | 4.5 | pass |
| info text | info #8fb4ee on bg/card | 8.73 / 8.04 | 4.5 | pass |
| location text | loc #6fd3dc on bg/card | 10.57 / 9.74 | 4.5 | pass |
| primary button/skip link text | onred #1a0805 on red | 4.82 | 4.5 | pass |
| brand red as UI (focus ring, tab underline, primary button edge) | red #eb3c27 on bg/card | 4.58 / 4.22 | 3 | pass |
| control borders | ctl #8c7870 on bg/card/code | 4.43 / 4.08 / 3.69 | 3 | pass |

