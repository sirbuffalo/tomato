# `terminal`: the API sheet as built (stage 1 of the repl editor)

`import terminal` (`std/terminal.tom`, D86a). Raw keys, the size of the window, colors and styles, and the width of characters, for any
program that wants to draw on a terminal. The editor library `lineedit` (stage 2 of `docs/repl-editor-design.md`, D88a, its sheet
`docs/lineedit-api.md`) is built on it, and `terminal.Terminal` implements its `TermIO` interface. The design, the reasons and
the open stages are in `docs/repl-editor-design.md`; this sheet says what was built, including where the design's sheet (section 6) was
made precise.

Conventions as in the other std modules: explicit objects, no module state, errors are classes of `IOError`, names follow Python's where
Python has the thing. **Native only for the terminal itself**: in the browser playground `open()` raises `RuntimeError` (E514), `is_tty`
says `False`, and `color_depth`, `char_width`, `text_width`, `KeyDecoder`, `Style`, `sgr` and the escape helpers work.

```
import terminal

term = terminal.open()                   # /dev/tty: the keyboard and the screen, even when the standard streams are redirected
term.enter_raw()
try:
    term.write('press a key\r\n')        # raw mode turns the terminal's own output translation off: write '\r\n'
    key = term.read_key()                # blocks
    term.write(f'{key}\r\n')             # for example: char 'a' ctrl
finally:
    term.leave()                         # always: the terminal must not stay raw
    term.close()
```

## Functions

| Name | Does |
| --- | --- |
| `is_tty(fd: int) -> bool` | whether the descriptor is a terminal (0, 1 and 2 are the standard streams) |
| `open() -> Terminal` | opens `/dev/tty`; `TerminalError` (E532) when the process has no terminal; `RuntimeError` in the browser |
| `color_depth(mode: str = 'auto', fd: int = 2) -> int` | 0, 8, 16, 256 or 16777216 colors; rules below; a `mode` other than `auto`, `always`, `never` is a `ValueError` (E533) |
| `char_width(cp: int) -> int` | 0, 1 or 2 cells of a code point |
| `text_width(text: str) -> int` | the sum over the characters |
| `rgb(r, g, b) -> int` | a 24-bit color value (each part 0 to 255, else `ValueError` E534): `16777216 + (r << 16) + (g << 8) + b` |
| `ansi(n: int) -> int` | one of the terminal's own 16 colors, 0 to 15 (else `ValueError` E535): 0 to 7 black, red, green, yellow, blue, magenta, cyan, white; 8 to 15 the bright ones |
| `sgr(style: Style, colors: int) -> str` | the escape text that starts the style, lowered to `colors`; `''` when `colors` is below 8 or the style is plain |
| `reset() -> str` | `ESC[0m` |
| `styled(text, style, colors) -> str` | the text with `sgr` before and `reset` after; the text alone when `sgr` is `''` |
| `cursor_up(n)`, `cursor_down(n)` | `ESC[nA`, `ESC[nB`; `''` when `n` is 0 or less |
| `cursor_column(c)` | `ESC[(c+1)G`: column 0 is the left edge |
| `clear_to_end()`, `clear_line()`, `clear_screen()` | `ESC[J` (cursor to the end of the screen), `ESC[2K` (the whole line), `ESC[2J ESC[H` |
| `hide_cursor()`, `show_cursor()`, `bracketed_paste(on)` | `ESC[?25l`, `ESC[?25h`, `ESC[?2004h` or `l` |

All of these return strings and write nothing: the program decides when to write them (one `Terminal.write` per frame).

## Classes

`TerminalError(IOError)`: the terminal cannot be opened or used. The message is the system's, as in `os`: `could not open the terminal: No such device or address`.

`Terminal` (from `open()`): `fd`, `colors` (from `color_depth('auto', fd)`; a program may set another value, 0 for none), and

| Method | Does |
| --- | --- |
| `enter_raw()` | raw mode: no echo, no line editing, no signals from the keyboard (Ctrl-C, Ctrl-Z and Ctrl-\ are keys), no translation of CR and NL in or out, 8 bits, one byte is enough to read. Idempotent |
| `leave()` | writes `ESC[0m ESC[?25h`, then restores the saved settings. Idempotent, never raises, a no-op when not raw: it belongs in a `finally` |
| `close()` | `leave()`, then closes the descriptor if `open()` made it (a `Terminal(fd)` a program makes itself leaves `fd` to the program); closing twice is fine |
| `size() -> tuple[int, int]` | (rows, columns); when the terminal does not say, from `LINES` and `COLUMNS`, else (24, 80) |
| `read_key(timeout: float = -1.0) -> Key` | blocks for the next key; with a timeout of 0 or more seconds returns kind `'timeout'` when it ran out (0 only looks). The window being resized gives `'resize'`; the end of the input or a terminal that went away gives `'eof'`, and keeps giving it. A lone Escape is told from the start of a sequence by waiting about 100 ms for more bytes, counted from when they were first seen, so a loop that polls with a short timeout still gets the Escape key |
| `write(text: str)` | one unbuffered write of all the bytes; `TerminalError` when it fails |

`Key`: `kind`, `text`, `name`, `ctrl`, `alt`, `shift`. `str(key)` shows it for people (`char 'a' ctrl`, `key up shift`, `paste 'a\nb'`, `timeout`) and `==` compares all fields.

| kind | fields |
| --- | --- |
| `'char'` | `text` is the character. A control key is the letter with `ctrl`: Ctrl-A is `'a'`, Ctrl-Space `' '`, Ctrl-\ ] ^ _ those characters. Tab, Enter, Backspace are never `'char'`. `alt` for `ESC x` |
| `'key'` | `name`: `enter tab backtab backspace delete escape up down left right home end pageup pagedown insert f1`..`f12`. `backtab` (Shift-Tab) has `shift` True. Ctrl-Left is `name 'left'`, `ctrl` True |
| `'paste'` | `text` is the pasted text, every line break as `\n` (after `bracketed_paste(True)`) |
| `'resize'`, `'timeout'`, `'eof'` | no fields |

`KeyDecoder`: pure, no terminal needed: `feed(bytes: list[int]) -> list[Key]`, `pending() -> bool` (an unfinished sequence is waiting: wait about 100 ms, then `flush()`), `flush() -> list[Key]`.
It understands CSI and SS3 sequences of xterm, VT100, the Linux console, macOS Terminal, iTerm2, GNOME Terminal and tmux: arrows, every
spelling of Home and End, Insert, Delete, the page keys, F1 to F12, the modifier parameter (`ESC[1;5C` is Ctrl-Right: 1 + shift + 2 alt + 4 ctrl + 8 meta), `ESC x` as Alt-x, the `ESC[code;mod u` form, and bracketed paste. `0x7f` and
`0x08` are Backspace; CR and LF are Enter, and CR LF in one piece is one Enter (split across two reads it cannot be told from Enter then Ctrl-J, and is two). UTF-8: a half character at the end of a read waits for the next one (`flush` drops it); an invalid byte is dropped. Unknown sequences (answers to queries, focus events, mouse reports) are dropped, and a control byte inside a sequence ends it. Inside a bracketed paste there is no wait: `pending()` is False and `flush()` does not end it. A paste whose end marker never comes would swallow every later key, so `Terminal.read_key` closes it itself: after 2 seconds with no byte, or at the end of the input, the text so far is the `'paste'` key (a program that drives a `KeyDecoder` itself does this with `in_paste()` and `abort_paste()`). `ESC[row;columnR`, the answer to a cursor position query, is not F3 (F3 is `ESC[R` or `ESC[1;modR`) and is dropped.

`Style(fg=-1, bg=-1, bold=False, dim=False, italic=False, underline=False, reverse=False)`: positional arguments in this order (a class cannot take
keyword arguments); the fields can be changed after. A color value is `-1` (the terminal's own), 0 to 15 (`ansi(n)`), 16 to 255 (the fixed 256 palette, as it is), or `rgb(...)`; any other value (256 up to 16777215) has no color and `sgr` ignores it.

## Colors

`color_depth(mode, fd)`: `'never'` is 0. `'always'` is the depth the environment says, whatever `fd` is and whatever `NO_COLOR` or `TERM=dumb` say.
`'auto'` first reads `TOMATO_COLOR` (`always` and `never` decide, another value changes nothing), then is 0 when `NO_COLOR` is not empty, `TERM` is `dumb`, or `fd` is not a terminal.
The depth: `COLORTERM` `truecolor` or `24bit`, or a `TERM` ending in `-direct`: 16777216; `TERM_PROGRAM=Apple_Terminal` (no truecolor): 256; a `TERM` containing `256color`: 256; `TERM=linux`: 8; anything else: 16.

`sgr` lowers each color to what the terminal has:

| colors | an `rgb` value | a palette value 16..255 | an `ansi` value |
| --- | --- | --- | --- |
| 16777216 | `38;2;r;g;b` | `38;5;n` | `30..37`, `90..97` |
| 256 | `38;5;n`, n the nearest of the 6x6x6 cube (levels 0, 95, 135, 175, 215, 255; a tie goes to the lower level) and the 24 greys (8 + 10 i), the cube wins a tie | `38;5;n` | `30..37`, `90..97` |
| 16 | the nearest of the 16 by the distance in RGB over xterm's values (0,0,0 205,0,0 0,205,0 205,205,0 0,0,238 205,0,205 0,205,205 229,229,229, then 127,127,127 255,0,0 0,255,0 255,255,0 92,92,255 255,0,255 0,255,255 255,255,255), the lower number winning a tie | the same, from the palette's RGB | `30..37`, `90..97` |
| 8 | as for 16, then the bright ones are the plain ones, and a bright foreground adds bold (`1`) | the same | the same |

For a background the numbers are 40 and 100 and 48 instead of 30, 90 and 38; a bright background at 8 colors stays plain. The codes come in the order bold, dim, italic, underline, reverse, foreground, background.
Examples (checked in `tests/terminal_logic.tom`): `rgb(235, 60, 39)` is `38;2;235;60;39`, `38;5;166` (a tie between 215 and 255 in red goes to 215), `91` at 16 colors and `1;31` at 8; `rgb(0, 150, 57)` is `38;5;29`, `32`, `32`.
Note for the palette (done in stage 3, D90a): the brand red `#EB3C27` lowers to the *bright* red (`91`, 255,0,0 is nearer than 205,0,0), not the plain red `31` that section 7 of the design hopes for, so the repl's palette (`compiler/src/hltomato.tom`) picks `ansi(1)` and `ansi(2)` itself when `colors` is 16 or less, and `196` for the red at 256.

## Widths

`char_width` is 0 for control characters, combining marks, zero-width and format characters (including U+200B to U+200F, variation selectors, the Hangul medial and final jamo), 2 for East Asian Wide and Full-width characters and emoji with emoji presentation, else 1.
The tables are in the runtime (`tomato_char_width`, Unicode 16.0, generated by `tools/gen_width_table.py` from Python 3.14's `unicodedata`; an unassigned code point is one cell) and give the same answer on every system and in the browser. Grapheme clusters (a flag, a family emoji, a letter plus a variation selector) are summed per code point.

## Giving the terminal back

`enter_raw()` saves the settings once and `leave()` restores them. They are also restored at the end of the process however it ends, with no `leave()` at all: `atexit` covers a normal end, `sys.exit` and an uncaught error; the handlers of `SIGTERM`, `SIGHUP`, `SIGINT` and `SIGQUIT` (installed when the default action is in place) and of a fault (including a stack overflow) restore and then take the default action; the signal handlers use `TCSANOW`, so an output that is stuck (a terminal that is not reading) cannot hold the process up, while `leave()` and `atexit` use `TCSADRAIN`. A `SIGKILL` cannot be covered by any program (`stty sane` does it by hand).
`tests/terminal_pty.exp` checks `stty -g` before and after for each of these ways, on Linux and macOS. The one bit of the settings that it ignores is macOS's `PENDIN`, which the kernel sets whenever `ICANON` changes and clears when the pending input is retyped.

## The runtime layer

`runtime/tomato_rt.c`, after `tomato_stat`; stubs under WebAssembly (except `tomato_char_width`, which is the same code). A call gives a count or 0, or `-errno` (and the reason is kept for `tomato_os_error`, as in the `os` calls).

| Function | Does |
| --- | --- |
| `tomato_tty_open(path: str) -> int` | `open(path, O_RDWR \| O_NOCTTY \| O_CLOEXEC)`: the descriptor |
| `tomato_tty_close(fd: int) -> int` | restores a raw terminal, then `close` (not in the design's list: `Terminal.close` needs it) |
| `tomato_tty_is(fd: int) -> int` | `isatty` |
| `tomato_tty_raw(fd: int) -> int` | saves the termios once (up to 4 terminals), clears `ICANON ECHO ECHONL ISIG IEXTEN IXON ICRNL INLCR IGNCR BRKINT IGNBRK PARMRK ISTRIP OPOST PARENB`, 8 bits, `VMIN=1 VTIME=0`, `TCSADRAIN`; installs `atexit`, the signal handlers and the `SIGWINCH` self-pipe on the first call; again on a raw terminal is a no-op |
| `tomato_tty_restore(fd: int) -> int` | the saved termios, `TCSADRAIN`; idempotent. A slot is tied to the file its descriptor named when raw mode was entered (device and inode): if the descriptor was closed by other means and its number reused, `tomato_tty_raw` on it makes the new file raw, and neither it nor the restore at the end of the process touches that file with the old settings |
| `tomato_tty_size(fd: int, out: list[int]) -> int` | pushes rows and columns: 0 when the terminal said (`TIOCGWINSZ`), 1 when they come from `LINES` and `COLUMNS` or are 24 and 80 |
| `tomato_tty_read(fd: int, out: list[int], max: int, ms: int) -> int` | `select()` on the descriptor and the resize pipe, up to `ms` (negative: for ever), then one `read` of at most `max` (4096) bytes onto `out`: the count; 0 when the time ran out; -1 at the end of the input (or `EIO`, a terminal that went away); -2 when the window was resized (the flag is cleared by this call); `-1000 - errno` for a failure. Another signal just waits again |
| `tomato_tty_write(fd: int, text: str) -> int` | writes every byte (loops over partial writes, `EINTR` and `EAGAIN`) |
| `tomato_char_width(cp: int) -> int` | the width above |

`select()` and not `poll()`: on macOS 27 `poll()` on a terminal device answers `POLLNVAL` at once (design, section 3).

## Tests

- `tests/terminal_logic.tom`: 22 `@test` functions run by the suite (`tomato test`, debug and release mode): the key decoder at every byte split (whole, in two pieces at every place, one byte at a time), a lone Escape, Alt, half sequences, bad UTF-8, bracketed paste (also in small pieces and with escape sequences inside), widths, `rgb`/`ansi`, SGR lowering to 256, 16 and 8 colors with hand-computed values, the escape helpers and `color_depth` over a table of environments.
- `tests/terminal_pty.tom` and `tests/terminal_pty.exp`: a program on a real pty, driven by `expect` (skipped, with a message, when `expect` is missing): raw mode, every kind of key, the timeout, the size and two resizes, the color depth in several environments, `TerminalError` without a controlling terminal (needs `perl`), and the restore after a normal end, `leave()` in a `finally`, an uncaught error, `sys.exit`, no `leave()`, a stack overflow, `SIGTERM` and `SIGHUP`.
- `tests/programs/terminal_browser.tom`: the browser path (WebAssembly only).

## Limits

`read_key` blocks (no async version; design question 4). Key names that a terminal does not send cannot be seen (Option as Alt in macOS Terminal sends `ESC x` only when "Use Option as Meta" is on). No mouse, no focus events, no `OSC 11` background query. One terminal at a time is the normal use; a program can have up to four in raw mode.
