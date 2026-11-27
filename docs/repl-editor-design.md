# The repl line editor, written in Tomato: design

Status: **approved by Davis (all seven recommendations of section 14, 26 November 2026); stages 1, 2, 3 and 4 are built** (D86a,
`docs/terminal-api.md`, D88a, `docs/lineedit-api.md`, D90a, the decision entry that says where section 7 became different as built, and
D91a, which says where section 8's hooks and keys became different with the completion, the single-line mode and the kill ring); stage 5 is
not planned. The questions are at the end (section 14), each with a
recommendation and Davis's answer. The marks are the ones of `docs/wave2-api-sheets.md`: **[V]** I read it in this repository, **[M]** I ran it (on
Linux, or on Davis's MacBook Pro, macOS 27 arm64), **[I]** inferred, not checked.

## 1. The requirement

Davis wants `tomato repl` to behave like the Python 3.13 repl for multi-line blocks, and chose to write the editor **in Tomato, as a
whole library** (not as a one-off C program, and not as one repl-only program). On top of the behaviour the first brief asked for, he
added two requirements: **syntax highlighting** that reuses the compiler's real lexer, and the editor as a **reusable std library**
that other Tomato programs can use to build interactive tools.

### Problem statement: what the repl does today

`native/tomato-repl` is a bash script **[V]**. It reads each line with `read -r -e` (readline), so the arrow keys and the history are
readline's. Readline has one history entry per line, so a multi-line block is stored as one entry with its lines joined by `⏎`
(`BLK`, line 233), and the history file `~/.tomato/repl_history_v2` (or `$TOMATO_HISTORY`) is plain text, one entry per line.

On macOS, bash is 3.2: no `bind -x`, no `READLINE_LINE`, no `read -i` **[V]** (D59a, `docs/decisions.md`). Up-arrow therefore shows a
recalled block as **one line with `⏎` markers**. Enter then prints the block as real lines (`>>> ` and `... `) and asks
`[Enter] run  [e] edit:` (line 249); `e` walks through the lines one at a time. D59a records why a true multi-line editor was rejected:
"not possible without writing a terminal program; rejected as too large". This design is that terminal program.

What must not change **[V]**: the "each line re-runs the whole session" model (the banner says so; each piece is added to the session
and the whole program is compiled and run again, `try_run` and `try_once`), the error format (`docs/errors.md`), `--color=auto|always|never`
and `NO_COLOR` (`repl_color`, and the same rule in `native/tomato` and in the runtime's `use_color`), `:help`, `:quit`, `:load`, `:save`,
`:reset`, `:program`, `:compile`, Ctrl-D leaving, `await input()` asking for answers one at a time, and plain line reading when
standard input is not a terminal (the checks of `tests/run.sh` pipe their input).

### The behaviour to build

1. **Up and Down** at the prompt recall the previous and next history entry as the real block (`>>> ` then `... ` lines, indentation
   kept), ready to edit in place. Left, Right, Home, End and Up/Down also move between the lines of the block being edited; Up on its
   first line goes to the previous history entry, Down on its last line to the next. Insert, Backspace and Delete edit in place.
2. **Enter** on the last line runs the block when it is complete (the rule the repl uses today to decide whether to show `...`: the
   first line ends with `:` or starts with `@`, and the block ends at an empty line), otherwise adds a line. Auto-indent follows a
   line that ends with `:` and keeps the indent otherwise. Tab inserts four spaces.
3. Ctrl-A, Ctrl-E, Ctrl-K, Ctrl-U and Ctrl-W. **Ctrl-C** cancels the current input without leaving; **Ctrl-D** on an empty prompt
   leaves.
4. **Paste** of multi-line text works (bracketed paste). UTF-8 text must not corrupt the display; terminal resize and long (wrapping)
   lines are handled.
5. **History**: same plain-text file and location, the old format (entries joined with `⏎`) still read, same limit (1000) and no
   duplicate-handling changes.
6. **Syntax highlighting** (Davis, later): color the code as it is typed and in recalled blocks; keywords, strings, numbers,
   comments, function names, decorators such as `@main`, operators; the brand colors (red `#EB3C27`, green `#009639`) as accents,
   readable on dark and light terminals; `--color`, `NO_COLOR`, and 8, 16, 256 and truecolor fallbacks; reuse the compiler's lexer;
   survive unfinished input (an unterminated string, an open block) without an error.
7. The **same on macOS (arm64 and x86-64, bash 3.2, universal `.pkg`) and Linux**; no readline, ncurses or rlwrap; a machine with only
   clang can build everything from the checked-in files; `tomato update` and the `.pkg` and `.tar.gz` layouts ship it.

## 2. Recommendation in short

1. **Three layers, two of them generic std modules.** A small C layer in the runtime (about 300 lines: raw mode, size, one read with a
   timeout, a write, the display width of a character). `std/terminal.tom`: terminals, keys, styles and colors. `std/lineedit.tom`:
   the editor (a text buffer of lines, history, key bindings, drawing, hooks for highlighting, completeness and indentation). Neither
   knows about Tomato the language or about the repl.
2. **Everything Tomato-specific is outside std**, in `compiler/src/`, next to the lexer it uses: a **tolerant mode of the real lexer**
   (`lex_spans`, which never raises and keeps comments and spans), the highlighter built on it, and the program `repledit.tom` that
   wires the library to the history file and the repl's rules. The repl calls it once per prompt.
3. **The repl stays a bash driver.** The session model (compile and run the whole session per piece) is unchanged. Only the question
   "what did the person type?" moves from `read -e` to a compiled Tomato helper, `tomato-repl-edit`, whose standard output is the block.
   Interactive and tty-capable: use it. Not a tty, no helper, `TERM=dumb`: today's plain path.
4. **Built at install time from shipped Tomato sources** with the `tomatoc` that the installer has just built (so a machine with only
   clang is enough), and for the `.pkg` once per architecture and joined with `lipo`, exactly like `tomatoc`. No new generated file in
   git.
5. **Stages** (section 12): the runtime and `terminal` first, then the editor with the repl on it, then highlighting, then the
   library polish. Each stage ships on its own and each has tests that run without a terminal as well as pty tests.

## 3. What exists today (the gaps)

All of it **[V]** unless marked.

| Need | Today | Gap |
| --- | --- | --- |
| Raw mode (no echo, no line buffering, no signals) | none: no `termios`, `tcsetattr` or `isatty` in std; the runtime calls `isatty(2)` only to decide error colors | new runtime functions, and a restore that survives errors, `exit` and fatal signals |
| Read one key | `input(prompt)` reads a line with `getc(stdin)` (`tomato_input`); `socket` reads from sockets with `await _fd_wait(fd, 1)`; nothing reads bytes from a terminal | read with a timeout and a way to see "the window was resized" |
| Escape sequences (arrows, Home, End, Delete, Ctrl-arrows, bracketed paste) | none | decode in Tomato from bytes |
| Terminal size, resize | none; no signal handling except the fault handler for stack overflow | `TIOCGWINSZ`, `SIGWINCH` |
| Write to the terminal | `sys.write_stderr` and `sys.write_stdout`, through stdio (`tomato_write_fd` accepts only fd 1 and 2) | one unbuffered write of a whole frame to the terminal device |
| Escape characters in source | the lexer knows `\n \t \r \0 \\ \' \"` (`escape_char`): no `\e` and no `\x1b` | build with `chr(27)` (no language change) |
| Display width (wide CJK and emoji = 2 cells, combining marks = 0) | none; `len(s)` counts characters | `char_width`, own tables (not libc's `wcwidth`: it differs between macOS and glibc and needs `setlocale`) |
| History file | `os.read_text`, `os.write_text(path, text, append=True)`, `os.rename`, `os.makedirs` exist | nothing; the format is kept (section 9) |
| Color policy | `TOMATO_COLOR`, `NO_COLOR`, `TERM=dumb`, then `isatty(2)` in three places (`native/tomato`, `native/tomato-repl`, `runtime use_color`) | the same rule in `terminal`; depth (8, 16, 256, truecolor) from `COLORTERM` and `TERM` is new |
| Lexing for colors | `compiler/src/lexer.tom` is the real lexer, but it **raises** `LexError` (unterminated string, a tab in indentation, an unknown character, an unclosed bracket), **drops comments**, **decodes** string text (no source span), turns an f-string into synthetic tokens with fake columns, and has no end column | a tolerant, lossless mode (section 7) |
| Module resolution | `read_module`: a module next to the program, else `std/NAME.tom` | the editor program must sit next to `lexer.tom`, or `lexer.tom` must be copied beside it at build time |
| Module state | none at module level (D49b: `const name = literal` only) and no `with`, no destructors | explicit objects; `try`/`finally` for restoring the terminal |
| Function values | plain code pointers: named, non-capturing, not methods (D63a) | hooks are **interfaces** (a class with state implements them) rather than function values |
| Tests | `@test` functions and `tomato test`; `tests/run.sh` pty tests with `expect` (skipped when `expect` is missing) | a fake terminal for the whole-editor tests (section 11) |
| Browser | `site/wasm/runtime.wasm` is built from `tomato_rt.c` with the WASI SDK and compared byte for byte on release; native-only std calls raise `RuntimeError` there (`os`, `requests` precedent) | stubs for the new runtime functions, a rebuilt `runtime.wasm` |

Two macOS facts that shaped the design:

- **`poll()` does not work on a terminal device on macOS.** **[M]** On Davis's MacBook (macOS 27, arm64), `poll()` on a descriptor
  opened from `/dev/tty` returned immediately with `revents = 0x20` (`POLLNVAL`), while `select()` on the same descriptor behaved.
  The runtime's own waits use `poll` and `kqueue`/`epoll` for sockets; none of that can wait for a keypress. The new read uses
  `select()` (one descriptor, no `FD_SETSIZE` problem).
- Bash 3.2 and a plain `/dev/tty` read are no obstacle for a compiled helper: the helper does not use bash at all.

## 4. Layers and modules

```
 tomato-repl (bash)                         the session: compile + run the whole session per piece (unchanged)
   |  once per prompt: block=$(tomato-repl-edit --history FILE ...)      stdout = the block; the screen is /dev/tty
   v
 compiler/src/repledit.tom   REPL-SPECIFIC  the program: history file, completeness rule, indent rule, banner-free
 compiler/src/hltomato.tom   TOMATO-SPECIFIC the highlighter (an implementation of lineedit.Highlighter)
 compiler/src/lexer.tom      TOMATO-SPECIFIC lex_spans: the tolerant lossless mode next to the compiler's own lex
   |  uses
   v
 std/lineedit.tom            GENERIC        Buffer, History, KeyMap, Screen (layout + drawing), Editor, hook interfaces
 std/terminal.tom            GENERIC        Terminal, Key, KeyDecoder, Style, colors, escape helpers, char_width
   |  extern !tomato_tty_*
   v
 runtime/tomato_rt.c         C              open /dev/tty, termios raw + restore, size, resize flag, read with timeout, write
```

**Generic** (usable by any Tomato program): `terminal`, `lineedit`. **Repl-specific**: `repledit.tom` and the history rules in it
(the `⏎` format, skipping `:commands`, the completeness rule). **Tomato-specific, not repl-specific**: `lex_spans` and the
highlighter (a formatter or a playground in the terminal could use them).

### Why two std modules and not one, or five

`terminal` is useful without an editor (a progress display, a menu, a game: raw keys, size, colors). `lineedit` is the editor
widget. The pieces inside `lineedit` (`Buffer`, `History`, `Screen`) are exported classes but not separate modules: they are small
and nobody needs one without the others, and each extra module is a name in `std_modules()` (a compiler change, section 10).
`ansi` styling lives in `terminal` for the same reason. Flat names, no packages (the Wave 1 convention).

## 5. The runtime layer (C)

*(As built: eight `tomato_tty_*` functions, since `Terminal.close` needs a `tomato_tty_close`, and no `tomato_tty_resized`: `tomato_tty_read` clears the
resize flag itself. The exact contracts are in `docs/terminal-api.md`.)*

Seven functions in a new block of `tomato_rt.c`, all `#if`ed out under WebAssembly, where stubs say "no terminal". They return `int`
codes and fill `list[int]` outputs, like `os` and `socket`; `terminal.tom` raises the Tomato errors.

| Function | Does |
| --- | --- |
| `tomato_tty_open(path: str) -> int` | `open(path, O_RDWR \| O_NOCTTY \| O_CLOEXEC)` (the module passes `/dev/tty`); returns the descriptor or `-errno` |
| `tomato_tty_is(fd: int) -> int` | `isatty(fd)` |
| `tomato_tty_raw(fd: int) -> int` | saves the termios of `fd` once, then sets: no `ICANON`, `ECHO`, `ISIG`, `IEXTEN`, `IXON`, `ICRNL`, `INLCR`, `OPOST`; `VMIN=1`, `VTIME=0`; `tcsetattr(TCSADRAIN)`. Registers the restore (below) and installs the `SIGWINCH` handler. Calling it again is a no-op |
| `tomato_tty_restore(fd: int) -> int` | `tcsetattr(TCSADRAIN)` with the saved termios; idempotent |
| `tomato_tty_size(fd: int, out: list[int]) -> int` | `TIOCGWINSZ` → `[rows, cols]` (macOS and Linux have the same ioctl); when it fails or says 0, `LINES` and `COLUMNS`, then 24 x 80 |
| `tomato_tty_read(fd: int, out: list[int], max: int, ms: int) -> int` | waits with `select()` on `fd` and on the read end of the resize pipe for up to `ms` (negative: forever), then reads what is there (at most `max` bytes, no more waiting): returns the count; `0` when the time ran out; `-1` at end of file; `-2` when the window was resized (the flag is cleared by `tomato_tty_resized`); a signal other than `SIGWINCH` (`EINTR`) just retries |
| `tomato_tty_write(fd: int, text: str) -> int` | writes all bytes with a loop (`EINTR`, partial writes), unbuffered: a frame is one call |
| `tomato_char_width(cp: int) -> int` | 0, 1 or 2 from range tables checked into the runtime (Unicode East Asian Width W/F, emoji presentation, and the combining and format ranges for 0). It does not use libc, so macOS, Linux and the browser agree |

**Restoring the terminal is guaranteed in four ways, because there is no `with` and no destructor** (`socket`'s header says the same):
(1) `terminal` code uses `try`/`finally`; (2) the runtime registers `atexit(restore)` when raw mode is entered, which covers
`sys.exit`, a normal end and an uncaught error (they all end with `exit()`: `tomato_exit` **[V]**); (3) the fault handler and handlers
for `SIGTERM` and `SIGHUP` restore and then re-raise with the default action (the stack-overflow handler already calls `_exit(1)`,
line 163 **[V]**); (4) the editor program is a short-lived child of the repl, so even if all of that failed the person would only have to run `stty sane`;
the bash driver does **not** guess at that. A `kill -9` cannot be covered by any program. `ISIG` is off in raw mode, so Ctrl-Z and
Ctrl-\ arrive as bytes and the editor ignores them.

`SIGWINCH`: the handler writes one byte to a self-pipe (created on the first `raw`) and sets a flag. The pipe is what lets `select`
wake up without the race that `EINTR` alone has (the signal arriving between the flag test and the `read`), and without relying on
which thread gets the signal (the runtime has helper threads for name lookups **[V]**).

## 6. `std/terminal.tom`: the terminal

The API sheet. *(As built, with the points where the code made it precise: `docs/terminal-api.md`: `Style` takes its fields positionally because a class
cannot take keyword arguments; `cursor_column` counts from 0; `char_width` is 0 for control characters; Ctrl-Space is `char ' '` with `ctrl`; `backtab`
has `shift` True; `leave()` also writes the reset and `show_cursor`; `Terminal` is a class and the `TermIO` interface comes with `lineedit` in stage 2;
`color_depth` reads `TOMATO_COLOR` when `mode` is `'auto'`.)* Conventions as in Wave 1 and 2: explicit objects, no module state, errors are classes of `IOError`, native only (in the
browser `open()` raises `RuntimeError` like `os.putenv`), and names match Python's where Python has the thing (`shutil.get_terminal_size`,
`termios`, `curses`) and are otherwise plain words.

```
export class TerminalError(IOError)                       # new error id; the terminal cannot be opened or used

export def is_tty(fd: int) -> bool                         # 0, 1 and 2 are the standard streams
export def open() -> Terminal                              # /dev/tty; TerminalError when the process has no terminal
export def color_depth(mode: str = 'auto', fd: int = 2) -> int
export def char_width(cp: int) -> int                      # 0, 1 or 2 terminal cells
export def text_width(text: str) -> int                    # the sum over its characters (not grapheme clusters, see below)

export class Terminal:
    fd: int
    colors: int                                            # 0, 8, 16, 256 or 16777216, from color_depth()
    def enter_raw(self)                                    # idempotent; call leave() in a finally
    def leave(self)                                        # idempotent; restores the settings and the cursor
    def close(self)
    def size(self) -> tuple[int, int]                      # (rows, columns)
    def read_key(self, timeout: float = -1.0) -> Key       # blocks; kind 'timeout' when timeout seconds passed
    def write(self, text: str)                             # one unbuffered write

export class Key:
    kind: str       # 'char' | 'key' | 'paste' | 'resize' | 'timeout' | 'eof'
    text: str       # the character ('char'), or the pasted text ('paste', newlines as \n)
    name: str       # for 'key': 'enter' 'tab' 'backtab' 'backspace' 'delete' 'escape' 'up' 'down' 'left' 'right' 'home' 'end'
                    #   'pageup' 'pagedown' 'insert' 'f1'..'f12'
    ctrl: bool      # Ctrl-A is kind 'char', text 'a', ctrl True;  Ctrl-Left is kind 'key', name 'left', ctrl True
    alt: bool
    shift: bool

export class KeyDecoder:                                   # pure: bytes in, keys out; no terminal needed (tests, and a pty-free editor test)
    def feed(self, data: list[int]) -> list[Key]           # keeps an unfinished sequence or UTF-8 character until more bytes arrive
    def pending(self) -> bool                              # an unfinished sequence is waiting (so read_key waits ~100 ms for the rest)
    def flush(self) -> list[Key]                           # the wait is over: a lone ESC is the Escape key

export class Style:                                        # a value; no escape bytes in user code
    fg: int; bg: int; bold: bool; dim: bool; italic: bool; underline: bool; reverse: bool
export def rgb(r: int, g: int, b: int) -> int              # a color value (24 bits, with a marker bit)
export def ansi(n: int) -> int                             # one of the 16 terminal colors: 0 to 15 (a theme's own colors adapt to the terminal)
export def sgr(style: Style, colors: int) -> str           # the escape text that starts the style, with the color lowered to `colors`
export def reset() -> str                                  # chr(27) + '[0m'
export def styled(text: str, style: Style, colors: int) -> str   # '' prefix and suffix when colors == 0
export def cursor_up(n: int) -> str  # cursor_down, cursor_column(c), clear_to_end(), clear_line(), clear_screen(), hide_cursor(), show_cursor(),
                                     # bracketed_paste(on: bool) -> str: only strings; the caller decides when to write them
```

Notes:

- **Key decoding is pure Tomato** over a byte list. It reads CSI (`ESC [ ... final`), SS3 (`ESC O x`), `ESC x` as Alt-x, the modifier
  parameter (`1;5C` is Ctrl-Right; the xterm `1 + shift + 2 alt + 4 ctrl + 8 meta` encoding), the many Home/End/Delete spellings
  (`ESC [ H`, `ESC [ 1 ~`, `ESC O H`, ...) of xterm, VT100, macOS Terminal, iTerm2, GNOME Terminal and tmux, bracketed paste
  (`ESC [ 200 ~` text `ESC [ 201 ~` becomes one `'paste'` key, CR and CRLF turned into `\n`), and UTF-8 (a partial character at the
  end of a read waits for the next one; an invalid byte is dropped). `0x7f` and `0x08` are both Backspace; `\r` and `\n` both Enter.
- **A lone ESC** is told from the start of a sequence by waiting about 100 ms for more bytes (`pending()`); on a slow link a split
  sequence still works because the decoder keeps what it has.
- **Colors.** `color_depth(mode, fd)` follows the rule the repl already has: `always` and `never` decide; else `NO_COLOR` (non-empty)
  → 0, `TERM=dumb` → 0, a descriptor that is not a terminal → 0 (`TOMATO_COLOR` is read as the default of `mode`). Depth: `COLORTERM`
  `truecolor` or `24bit` → 16777216; `TERM` ending in `-direct` → 16777216; `TERM_PROGRAM=Apple_Terminal` → 256 (it has no
  truecolor); `TERM` containing `256color` → 256; `TERM=linux` → 8; `TERM` starting with `xterm`, `screen`, `tmux`, `vt100` and the
  rest → 16. `sgr` lowers a truecolor value to the nearest of the 256 (the 6x6x6 cube and the 24 greys), the nearest of the 16 (by
  distance in RGB), or the 8 (the 16 without the bright ones); 8-color terminals show bold for the bright ones. It writes `38;2;r;g;b`,
  `38;5;n`, `30..37`/`90..97`.
- **Widths.** A cell count is a property of the terminal's own tables; no program can know it exactly. `char_width` covers what
  matters for source code and prompts: combining marks and zero-width characters (0), CJK and full-width forms, Hangul, and emoji with
  emoji presentation (2), the rest (1); control characters are drawn by the editor as `^X` (2) or replaced. **Limit:** grapheme
  clusters (a flag, a family emoji, a letter plus variation selector) are summed per code point, so they can be drawn one or two
  cells off; the editor repaints the whole block on every key, so a wrong width cannot accumulate, it only misplaces the cursor on
  that line. Python's own repl has the same limit.
- **No async.** `read_key` blocks. The editor is a single-task program and a blocking read is the simplest correct thing; a program
  that wants keys beside other tasks would need `_fd_wait`-style readiness and a way to put the tty in that set, which is a larger
  change to the scheduler (open question 4).

## 7. Syntax highlighting and the tolerant lexer

### The lexer's gaps, and the shape of the change

`lex` in `compiler/src/lexer.tom` **[V]** is the language's definition of a token, and the highlighter must not disagree with it
(`tests/highlighter_lists.sh` already keeps the website and the VS Code grammar in step with its keyword table). But `lex` cannot be
called as it is: it raises at the first problem, so every half-typed line would lose all its color; it discards comments and
whitespace; it **decodes** strings (`'a\nb'` becomes a two-line text with no source position); it **rewrites f-strings** into
synthetic `+ str( ... ) +` tokens with fake columns; and it records only a start column.

The change is one new entry point in the same file, **`lex_spans(src: str) -> list[Span]`**, which shares the lexer's scanners
instead of copying them:

- The character classes, `is_keyword`, the operator tables and the number rule are already helpers. The **scanning** half of
  `lex_number`, the string loop in `lex_line` and `field_end` is moved into `scan_*` functions that return the end index, and both
  `lex_line` (which builds tokens, as before, raising as before) and `lex_spans` (which builds spans, never raising) call them. A
  test lexes every file of the repository both ways and checks that the token kinds and the order agree.
- `Span` is `{ kind, line, col, end_col }` in characters, **lossless**: spans cover the whole text between them as `'space'` gaps, so
  the concatenation of the spans' source slices is the input (a test checks it). Kinds: `keyword`, `name`, `number`, `string`,
  `fstring-brace` (the `{` and `}` of a replacement field, whose inside is lexed again as code, recursively), `comment`, `op`,
  `error`.
- **Never raises, and says where it gave up.** An unterminated string becomes a `string` span to the end of the line followed by an
  empty `error` marker at that point (the lexer's own message and column are kept, so the editor can show them if it wants). An
  unknown character is a one-character `error`. A tab in indentation is an `error` span. A closing bracket with nothing open, and an
  opening bracket never closed (reported by `lex` at the end of the input), are `error` spans on the bracket. A format spec that does
  not parse is still a `number`-colored span. The depth and the open indentation levels are returned beside the spans
  (`LexState`), which is also what the completeness rule can use (section 8).
- **Strings are one line, so unfinished input is local.** Tomato has no triple-quoted or multi-line strings, so a damaged line never
  changes the meaning of the lines after it. Brackets are the only state that crosses lines; the highlighter lexes the whole block
  each time (blocks are a few lines; at 5,000 characters per key the lexer's cost is far below a keystroke). A per-line cache keyed on
  the line text and the bracket depth is the optimization if it is ever needed.

*(As built, D90a: `lex_spans` returns `tuple[list[Span], LexState]`, with `LexState` = `depth`, `indents`, where the first open bracket is,
`message` (what `lex` raises, with its place) and `rejected`; columns are from 0 and `end_col` is after the last character; an open bracket
is not marked as an `error` span, since it is the normal state while typing, only `LexState.depth` says so, and a closing bracket with
nothing open is. The scanners are `scan_number`, `scan_string`, `scan_fstring`, `name_end` and `op_len`. The equivalence test is
`tests/lexer_spans.tom`. The repl's validator reads the spans and the state instead of the lexer's error message.)*

### The highlighter

`compiler/src/hltomato.tom` turns spans into styled runs, with the context the lexer does not give: the name after `def`, `class`,
`interface` (and `async def`) is a **function or class name**; `@name` at the start of a line is a **decorator** (the whole
`@main`); a `NAME` that is in the built-in list (the list `tests/highlighter_lists.sh` already reads from `lint.tom`) is a
**builtin**; `True`, `False`, `None` are constants. It implements `lineedit.Highlighter`:

```
export interface Highlighter:
    def highlight(self, lines: list[str]) -> list[list[Run]]      # per line: runs of (start, end, Style); gaps are unstyled
```

The editor draws the runs, and wraps and positions the cursor from the plain text, so a highlighter can never change what the text
means or where the cursor is.

### Palette

*(As built: the 256-color red is `196` as suggested; the builtins are bright blue (`ansi(12)`), not the plain blue, which is dark on a dark
background; `True`, `False` and `None` are magenta, the braces of an f-string field bold green; below truecolor the red and green are
`ansi(1)` and `ansi(2)`. `Palette` in `hltomato.tom` is the table.)*

Colors are a table of `Style`s in `hltomato.tom` with truecolor values and 256/16/8 equivalents; `terminal.sgr` does the lowering,
so the table is written once. Principles:

- **Brand accents, sparingly:** red `#EB3C27` for **keywords** and green `#009639` for **strings**, because those two are what the eye
  parses first; the same two as `tomato paint` already uses for errors (red) and `help:` (green), so the repl looks like the rest of
  the tool. At 256 colors the nearest entries are `166` (`#d75f00`) and `29` (`#00875f`); the red looks orange there, so the 256 table may use `196` (`#ff0000`)
  instead, a choice for the palette review in stage 3. At 16 and 8 colors they become the terminal's own red (`31`) and
  green (`32`), which every theme keeps readable. *(Stage 1 note: `terminal.sgr` lowers `#EB3C27` to the nearest of the 16, which is the bright red `91`, not `31`; the green does become `32`. The palette in
  stage 3 should therefore pick `ansi(1)` itself when `colors` is 16 or less.)*
- **Readable on both** light and dark: no white, black or bright-black text. Mid-tone accents (by the usual relative-luminance formula, the red `#EB3C27` has contrast 4.0:1 on white and 5.2:1 on
  black, the green `#009639` 3.9:1 on white and 5.4:1 on black: both above 3:1, the usual floor for large or bold text) and the terminal's own 16 colors for the rest, because those are chosen by the
  theme. Comments use *dim* (`SGR 2`) rather than a grey, which follows the foreground on any theme. No background colors in the
  default palette. The editor does **not** try to detect a light or dark background (the OSC 11 query is not answered by every
  terminal and needs a read with a timeout before the first prompt).
- Numbers cyan; decorators and function and class names bold in the default color (a definition reads as a heading, with no third
  accent); operators plain; builtins in the terminal's blue; `error` spans underlined red
  (an unterminated string, a stray bracket: the "error-prone spots", at no extra cost).
- The prompts are colored too: `>>> ` in the brand green, `... ` dim.
- **Off** when `color_depth` is 0: `--color=never`, `NO_COLOR`, `TERM=dumb`, or not a terminal; the text is then exactly what it
  is today. `--color=always` wins over `NO_COLOR`, as in D61a. The bash driver passes `--color=` on to the helper.

## 8. The editor library: `std/lineedit.tom`

The API sheet. The editor owns **a region of the screen** from the line where the prompt starts down, and redraws it after every key
(there is no incremental diff: a block is small, and one write per key avoids flicker).

```
export class Buffer:                       # the text: lines of characters, a cursor (line, column), and the editing operations (pure)
    lines: list[str]; row: int; col: int   # column counts characters
    def insert(self, text: str)            # a '\n' in text splits the line
    def newline(self, indent: str)         # a new line below the cursor's, starting with indent
    def backspace(self); def delete(self)  # at a line start/end they join lines
    def left(self); def right(self); def up(self) -> bool; def down(self) -> bool   # up/down return False at the first/last line
    def home(self); def end(self)
    def kill_to_end(self) -> str; def kill_to_start(self) -> str; def kill_word_back(self) -> str   # return the removed text (the kill ring)
    def text(self) -> str                  # lines joined with '\n'
    def set_text(self, text: str)          # cursor at the end

export class History:
    @init
    def make(self, entries: list[str], limit: int = 1000)
    def previous(self, current: str) -> str | None     # remembers `current` (the draft) the first time
    def next(self) -> str | None                       # None past the newest: the editor puts the draft back
    def add(self, text: str)                           # appends (the caller decides whether the entry is worth keeping)
    def reset(self)
export def load_history(path: str) -> History          # the repl's format is in repledit.tom, not here; this one reads one entry per
export def save_history(...)                           #   line with a caller-given separator (open question 3)

export interface Highlighter: def highlight(self, lines: list[str]) -> list[list[Run]]
export interface Validator:   def complete(self, text: str) -> bool           # may Enter submit? (False: add a line)
export interface Indenter:    def indent_after(self, line: str, text_before: str) -> str   # the indent a new line gets

export class Editor:
    prompt: str = '>>> '
    continuation: str = '... '
    history: History
    highlighter: Highlighter | None
    validator: Validator | None            # None: Enter always submits (a single-line editor)
    indenter: Indenter | None              # None: keep the current line's indent
    tab: str = '    '                      # what Tab inserts
    def read(self, term: Terminal) -> Result              # draws, loops on keys, restores, returns
export class Result:
    status: str     # 'text' | 'eof' | 'interrupt'
    text: str       # the block, without trailing empty lines, for 'text'
```

`Editor.read` takes a `Terminal`, enters raw mode, turns bracketed paste on, and in a `finally` turns it off and leaves raw mode. To
test it without a terminal, `terminal.Terminal` is an **interface in practice**: `Editor.read` accepts anything with `read_key`,
`write`, `size` and `colors` (`interface TermIO`), and the tests pass a `FakeTerminal` (a list of scripted keys; every write is
recorded).

*(As built in stage 4, D91a: `Editor` also has `completer: Completer` (a hook like the others, `complete(line, before) -> Completion(start,
candidates, after)`, with `NoCompletion` as the default), `single_line`, `kill_ring` (how many cuts Ctrl-Y can bring back, 1 by default; more joins cuts in
a row and gives Alt-Y) and `menu_rows`; `KillRing`, `common_prefix`, `candidate_rows` and `read_line(prompt, history_file)` are exported. Tab asks
the completer: one candidate is put in, several give their common start, and when that adds nothing they are listed under the text (a menu that
the next key takes away); with no candidate Tab indents only in an indent. `tomato repl` has a completer for Tomato names (`ReplCompleter`).
The sheet is `docs/lineedit-api.md`, the worked example `examples/todo_shell.tom`.)*

### The editing rules (from the brief)

- **Enter**: if the cursor is not on the last line, it splits the line (like Python). On the last line: if the validator says the block
  is complete, the editor submits; else it adds a line with the indenter's indent. The repl's validator is today's rule: a block is
  *open* when its first line ends with `:` or starts with `@`, and it is *complete* once the last line is empty or whitespace only; a
  single line that opens nothing is complete at once. It can use the lexer's bracket depth as well, so `x = (1,` continues instead of
  failing to compile; that is a **behavior change** for Davis (open question 5).
- **Indenter**: after a line whose last non-comment text ends with `:` the new line gets the line's indent plus four spaces; otherwise
  the same indent. An empty indented last line plus Enter submits and strips trailing empty lines (as when typing today).
- **Keys** (Python 3.13 and readline): Left/Right cross line ends; Up/Down move by line keeping the column; Home/End and Ctrl-A/Ctrl-E
  go to the line's start and end; Backspace, Delete, Ctrl-D (when the text is not empty, Delete); Ctrl-K and Ctrl-U within the line,
  Ctrl-W the word before the cursor (whitespace-delimited), Ctrl-Y puts back the last kill; Alt-B/Alt-F and Ctrl-Left/Right by word;
  Ctrl-L clears the screen and redraws; Ctrl-B/F/P/N as the arrows; Tab inserts the `tab` text; Shift-Tab removes up to four leading
  spaces; Ctrl-C returns `'interrupt'` after printing `KeyboardInterrupt` as Python 3.13 does; Ctrl-D on empty text returns `'eof'`; Ctrl-Z, Ctrl-\
  and unknown sequences are ignored. A `'paste'` key inserts its text as is (tabs become four spaces, other control characters are
  dropped), with **no** auto-indent and no submit; the person presses Enter afterwards.
- **History**: Up on the first line of the block recalls the previous entry **as a block with the cursor at its end**, so Up again walks
  up through its lines before reaching the entry before it (as Python does); Down on the last line recalls the next, and past the
  newest the draft returns. Edits to a recalled entry are kept as the draft until the person moves on, then dropped (readline would
  keep them; open question 6). An entry the person edits and submits is a new entry.

### Drawing

- **Layout** is a pure function: from the lines, the prompts, the width, the cursor, it returns the rows (each a range of one
  logical line) and the cursor's (row, column) **in cells** (`text_width`). A line wraps at the width, a wide character never splits
  across the edge, and a line that exactly fills the row does not leave the terminal in its "pending wrap" state (the next row is
  started with an explicit `\r\n`). Pure, so it is unit-tested.
- **Frame**: move up by the cursor's row from the previous draw (`cursor_up`), `\r`, clear to the end of the screen, write the rows
  (each logical line prefixed by `>>> ` or `... `, styled by the highlighter) joined by `\r\n`, then place the cursor with `cursor_up`
  and `cursor_column`. All in one `write`. **Tall blocks:** when the rows do not fit the screen, only a window of `rows - 1` rows
  around the cursor is drawn (otherwise the redraw moves up past the top of the screen and leaves copies).
- **Resize**: `read_key` returns `'resize'`; the editor reads the new size and redraws. Terminals differ in how they re-wrap old
  text; the editor assumes the old text re-wrapped at the new width (macOS Terminal, iTerm2 and most Linux terminals do) and moves up by the
  cursor's row at the new width. A terminal that does not re-wrap leaves some stale lines above the prompt; the next Ctrl-L cleans it.
- **On finish** the editor redraws once with the cursor at the end of the block and no highlight of the cursor, then writes `\r\n`;
  the block stays on screen as typed, as in Python.

## 9. The repl program, history and the non-tty path

`compiler/src/repledit.tom` (about 150 lines) is the **repl-specific** part:

```
tomato-repl-edit [--history FILE] [--color=auto|always|never]
   exit 0:  the block is on standard output
   exit 10: end of input (Ctrl-D on an empty prompt)       exit 11: Ctrl-C (a new prompt)
   any other status: the helper failed (no usable terminal, a crash, an uncaught error): the driver falls back to the plain path
```

The codes 10 and 11 are deliberate: an uncaught Tomato error or a runtime failure ends a program with status 1 (`tomato_exit` and the
error path of the runtime), 2 can come from a usage error, and a signal gives 128 plus the signal number. A bug in the editor must
**never** look like Ctrl-D, because the repl would then quit silently and lose the session. Only 0, 10 and 11 mean something; every
other status is a failure, and the driver then falls back for the rest of the session (it does not retry the helper at every prompt).

- **History format (kept, documented):** a plain text file, one entry per line, the lines of a block joined by `⏎` (U+23CE), UTF-8,
  a newline after each entry. The old file reads as it is. Writing is the same format, so an older `tomato` can still read a file the
  new one wrote and the reverse. **Known limit, unchanged from today:** a block with a literal `⏎` inside a string comes back with
  that character as a line break. Reading also drops other control characters (and turns tabs into four spaces).
  Location: `$TOMATO_HISTORY`, else `~/.tomato/repl_history_v2` (the directory is created as now).
- **What is recorded:** an entry per accepted block, **not** the `:commands` and not `leave()`, `exit()`, `quit()` (today these never
  reach `remember`; unchanged), not an empty block. Kept: the last 1000; no duplicate removal (today's `HISTCONTROL`-free default).
  The helper appends the new entry with `os.write_text(path, line, append=True)` and rewrites the trimmed file (to a temporary name,
  then `os.rename`) only when the file has grown past the limit. (Today bash rewrites the whole file at exit; two sessions at once
  still interleave harmlessly.)
- **The driver** (`native/tomato-repl`) loses `recall_block`, `show_block`, `BLK`, the private `inputrc` and `history -r/-s/-a/-w`
  (about 60 of its 330 lines) and gains: find the helper (`TOMATO_REPL_EDIT`, set by `native/tomato` from `$home/bin`); use it when
  standard input is a terminal, `TERM` is not `dumb` and `[ -x helper ]`; call it as `text=$("$edit" ...)`, read the exit code, and go
  on with the same `case` over the text (a single-line text still goes through the `:quit`, `:help`, ... commands). The answers to
  `await input()` are read with plain `read -r` (cooked mode: the program's own prompt was already printed at column 0 by the
  driver, and the editor would erase it by redrawing from column 0).
- **Not a terminal:** exactly today's path (`IFS= read -r`, the typed-block loop reading `...` lines until an empty one, no prompts printed). Same
  output; every existing `tests/run.sh` check goes through it. If the helper is missing or fails (any status but 0, 10, 11), a terminal session falls back to
  `read -r -e` without history (a degraded but working repl). The driver prints **one line** on standard error once ("the line editor is
  not available; using plain input"), so a broken editor is never silent; with the helper simply absent (a bare checkout without an
  install) it prints the same line.
- **How the screen and the answer share one process:** the helper opens `/dev/tty` itself for both reading and drawing, so
  `block=$(...)` (which captures standard output) shows the editor normally, and a redirect of standard error does not hide it.
- **Where the editor fits the "re-run the whole session" model:** it does not touch it. The session is the bash driver's concern
  (`stmts`, the `d/` declarations, `shown`, `inputs`); the editor's input is the history file and the terminal, its output one block
  of text. A later, separate step could move the driver itself into Tomato; it needs a way to run a program and capture its output
  (no `subprocess` yet: Wave 3), so it is **not** part of this design.

## 10. Build, ship, bootstrap and the browser

### Build and ship

- **Sources** live in the repository: `std/terminal.tom`, `std/lineedit.tom` (the generic library), and
  `compiler/src/lexer.tom`, `hltomato.tom`, `repledit.tom`. `repledit.tom` needs `lexer` and `hltomato` **next to it** (the module
  rule of `read_module`). To keep one copy of the lexer, `install-native.sh` copies those three files into a temporary build folder.
- **`install-native.sh`** (installed case, also the tarball and `tomato update`): the installer builds the whole new install in a
  staging folder beside the old one (`$TOMATO_HOME/.native.new.PID`) and swaps it in with one rename at the end (docs/releasing.md,
  How an update installs), so this step works on the **staging folder, not on `$home`**. After the compiler, runtime, std and scripts
  are copied into it, the step copies the three files into a temporary folder inside the staging folder and builds the helper **with the
  staged `tomato`** (it finds its own folder, so it works before the swap):
  `run "$stage/bin/tomato" build "$tmp/repledit.tom" -o "$stage/bin/tomato-repl-edit" --mode release`, where `run` is the installer's
  wrapper that runs a command as a background job and waits for it (so Ctrl-C or SIGTERM stops the build and removes the staging folder
  at once). It goes after those copies and before the installer's check that the staged install runs, which precedes the swap. The old
  temporary-name-then-`mv` pattern is not needed: nothing in the live install is written, so a running `tomato update` is never
  overwritten in place.
  **Why `tomato build` and not a hand-written `tomatoc` and `clang` line:** it already owns everything that line would have to repeat
  and keep in step: the runtime cache (`rtcache.sh`: the runtime is compiled once per mode and clang), `-ldl` on Linux (the runtime loads libcurl with
  `dlopen`), the LTO link with its bitcode-merge and no-LTO fallbacks, and the build warnings. A copy in the installer would drift.
  **The mode is release on purpose:** the default debug mode prints a leak report and call traces on standard error, which would be drawn
  over the editor's screen, while a release program prints a short error code; a crash of the helper then shows as the driver's
  one-line fallback note (above). The cost is the release runtime object (LTO bitcode) compiled once into the cache **[I]**: some seconds
  on the first install, then a cache hit; it must be measured in stage 2, and if it is too slow the helper may use the debug-mode link
  with the leak report silenced instead.
  **The step is optional and must not stop the install**, which runs under `set -e`: it is written as
  `build_helper || echo "warning: the repl line editor could not be built: $reason; the repl will use plain input" >&2`, with clang's or
  tomato's message kept and shown, not a silent skip. `tests/run.sh` checks that `$home/bin/tomato-repl-edit` exists and is executable
  after the install, so a helper that stops building fails the suite. Estimated 1 to 2 s plus the runtime object **[I]**.
- **The tarball** (`release/build.sh`) adds `compiler/src/lexer.tom`, `hltomato.tom` and `repledit.tom` (a few hundred KB of
  text in all, no generated file) under `compiler/src/`; `std/*.tom` is already copied by wildcard. `tomato update` runs the new
  installer from the unpacked archive, so an update builds the helper too; no change to `native/tomato` except exporting
  `TOMATO_REPL_EDIT`.
- **The `.pkg`** (`release/pkg.sh`) needs one **universal** helper, and `tomato build` makes a native one only, so `pkg.sh` builds
  it the way it builds `tomatoc`. It runs the installer into the payload with `>/dev/null` and then **deletes the payload's `tomatoc`**
  (line 16), and the installer's temporary folder is gone, so `pkg.sh` regenerates what it needs itself: before that `rm`, or from the
  `$work/tomatoc.$arch` it builds a few lines later (the one for the build machine's architecture can run), it copies the three `.tom`
  files into `$work/repledit/`, runs `tomatoc repledit.tom main std/ release > $work/repledit.ll` **once** (the IR carries no target
  triple **[V]**, so one `.ll` serves both architectures), and then, per `-arch arm64` and `-arch x86_64`, `clang -arch A -O1
  -DTOMATO_RELEASE -Wno-override-module -o repledit.A repledit.ll tomato_rt.c -pthread -lm` (the runtime source is compiled in the same
  line, as `pkg.sh` does for `tomatoc`) and `lipo -create` into the payload's `native/bin/tomato-repl-edit`.
  **For the `.pkg` this step is fatal**, not a warning: `pkg.sh` has `set -e`, the helper step has no fallback, and the installer's
  optional-helper rule above applies only to the installed case. The release has a check that fails unless
  `lipo -archs` of the payload's helper says `x86_64 arm64` (in either order), so a `.pkg` can never ship with no helper or one built only
  for the build machine. The change is about ten lines in `pkg.sh` and a few in `install-native.sh` and `build.sh`; the pre-release
  audit also edits those files, so it goes in its own commit to ease merging.
- **A machine with only clang** has everything: `tomatoc` from `compiler/bootstrap/tomatoc.ll`, then the helper from the shipped
  `.tom` files. The rest of the tests (`tests/run.sh`) build the installed `tomato` already, so the helper is built by the same step
  and the pty test uses it.

### Bootstrap

The compiler is self-hosted and `compiler/bootstrap/tomatoc.ll` is its own IR **[V]**.

- The plan changes the compiler **twice, both small**: in stage 1 `std_modules()` gains `terminal` (and in stage 2 `lineedit`; a test
  checks that list against the folder, so it cannot be skipped), and in stage 3 `lexer.tom` gains `lex_spans`. Each is followed by
  `compiler/bootstrap/refresh.sh`, which the repository already treats as routine (the fixed point is checked by the suite).
- **The editor and the highlighter are not part of the compiler.** `repledit.tom` and `hltomato.tom` import `lexer` but are not
  imported by `compiler.tom` or `ctool.tom`, so they cannot break the bootstrap; and `lex_spans` is new code beside `lex`, with the
  shared scanners refactored under a test that lexes every file both ways, which also protects the compiler's own lexing.
- **No new generated file in git** (the alternative, a checked-in `repledit.ll` like `tomatoc.ll`, would need `refresh` scripts and
  stale-file tests; see section 13).

### Browser and the website

- `runtime.wasm` gets stubs of the new functions (`is` returns 0, `open` returns an error), so a program that imports `terminal`
  still links; `terminal.open()` raises `RuntimeError` (E514 style, like `os.putenv`). `std/` is copied to `site/wasm/std` by
  `site/wasm/build.sh`; the new modules go with it. A program that only uses `terminal.color_depth` or `char_width` works there.
- **Cost:** the compiler and the runtime change, so `site/wasm/build.sh` must be run with WASI SDK 24 and the committed
  `tomatoc.wasm`, `runtime.wasm` and `SOURCE.sha256` updated (the release's `test` step compares them byte for byte). That is the
  routine described in `docs/releasing.md`, not new work, but it needs the SDK, which this machine does not have **[I]**: the stage that changes the
  runtime and compiler should be done where `WASI_SDK` is set (the Mac), or the wasm refresh left to the release host.
- The website playground and its highlighter (`site/site.js`, the VS Code grammar) are unchanged; `tests/highlighter_lists.sh` keeps
  its job.

## 11. Testing

1. **Pure logic, as `@test` functions** (`tests/programs/`, run by the suite on every machine, with expected output): `KeyDecoder`
   (every sequence of section 6, split at every byte boundary, a lone ESC, a truncated UTF-8 character, bracketed paste with CRLF),
   `Buffer` (every operation at line ends, with wide and combining characters), `History` (the draft, the limit, the old `⏎` format
   and a file with a trailing blank line), the layout function (wrapping, wide characters at the edge, exactly full rows, the cursor
   after a full row), `color_depth` over an environment table, `sgr` lowering (truecolor → 256 → 16 → 8, checked against hand-computed
   values), `char_width` against a list of known characters, `lex_spans` (never raises over the repository's `.tom` files and a
   corpus of truncated ones: every prefix of every line of a few programs; the spans cover the input; the kinds agree with `lex`), the
   highlighter on a table of lines, and the repl's validator (today's cases, as examples).
2. **The whole editor without a terminal**: `FakeTerminal` scripts keys and records the frames, so the flows of the brief run
   everywhere: recall a block, edit its middle line, add lines, delete, Ctrl-C, Ctrl-D, paste, Up through a block into the previous
   entry, a resize between keys. Frames are compared as text, with the escape codes spelled out.
3. **pty tests with `expect`** (`tests/repl_history.exp` rewritten, and one more file for `terminal` itself), following the existing
   style (a key is sent only after the prompt it answers is drawn; no fixed sleeps; the whole test is skipped when `expect` is missing, as today, but **fails, never skips, when `expect` is there and the helper is
   missing**, so it cannot pass while the editor is not exercised). They run the **real**
   `native/tomato-repl` with the **built helper**: recall (Up, Up) shows `>>> for ...` and `... ` lines, edit the middle line and
   run it, add lines, delete, Ctrl-C, Ctrl-D, paste (the bracketed-paste bytes), `TERM=dumb` falling back, a UTF-8 line, a resize
   (`stty cols`), and **the terminal's settings are the same before and after** (`stty -g`), including after a kill with SIGTERM
   and after an error in the program, and a **helper that raises** (`TOMATO_REPL_EDIT` pointing at a program that exits 1, and one that is killed): the repl
   must not quit, must print the one-line fallback note and go on with plain input; only exit 10 leaves. The old test's assertions about `[Enter] run  [e] edit` are replaced.
4. **The non-tty fallback** is already covered by the pipe-based `t_cli_repl_*` checks, unchanged. A new check runs the repl with
   input piped **and** `TOMATO_REPL_EDIT` set to a helper that fails, to prove the helper is never used off a terminal.
5. **The Mac**: the same pty tests run on Davis's MacBook (arm64) and, under Rosetta or on the Intel build, x86-64, before the stage
   ships; `poll` vs `select`, Terminal.app's keys (Option as Alt sends `ESC x` only when "Use Option as Meta" is on; documented, not
   fixed) and iTerm2 are checked by hand and by recording a transcript.
6. A short **recorded session** (the `expect` log) of recall-and-edit is kept as evidence in each stage's review.

## 12. Plan: small shippable stages

Each stage is its own task and merge, leaves the repl working, and does not depend on a later one.

| # | Stage | Contents | Ships | Size |
| --- | --- | --- | --- | --- |
| 0 | Design | this document, Davis's answers | docs | - |
| 1 | Runtime and `terminal` **(built, D86a)** | the seven C functions + wasm stubs; `std/terminal.tom` (keys, decoder, raw mode, size, colors, widths, styles); `std_modules()` + bootstrap refresh + wasm rebuild; `@test`s and one pty test program; the doc sheet in `docs/` and a decision entry | a usable terminal module; the repl unchanged | M |
| 2 | Editor library and the repl on it **(built, D88a)** | `std/lineedit.tom` (buffer, history, keymap, layout, frame, hooks); `repledit.tom` with the repl's validator and history; the installer, tarball and pkg steps; the driver change; `tests/repl_history.exp` rewritten; decision entry D-new superseding D59a | the multi-line repl, no colors yet | L |
| 3 | The tolerant lexer and highlighting **(built, D90a)** | `lex_spans` + shared scanners + the equivalence tests; `hltomato.tom`; palette; `--color` and `NO_COLOR`; bootstrap refresh + wasm rebuild | colors in the repl | M |
| 4 | Library polish **(built, D91a)** | what other programs need and the repl did not: a single-line mode with completion hook, a `Completer` interface, a kill ring option, docs and a worked example under `examples/` (a small interactive program), site docs copy | the library is documented and exampled | S |
| 5 | (not planned) | the driver in Tomato; needs `subprocess` | - | - |

Stages 1, 2 and 3 each touch the compiler's sources (`std_modules()` gains `terminal` in stage 1 and `lineedit` in stage 2; `lexer.tom` gains
`lex_spans` in stage 3) and stage 1 touches the runtime, so each needs `compiler/bootstrap/refresh.sh` and a `site/wasm/build.sh` run with WASI SDK 24
(the Mac has it; this Linux box does not **[I]**). To save two wasm rebuilds, stage 1 may add both names to `std_modules()` (with a `lineedit.tom`
holding only its header comment) at the price of a placeholder module for one release. Stage 4 touched neither, as planned: no bootstrap refresh and no wasm rebuild (the website's copy of `std/lineedit.tom` is a plain copy). Stages 1 and 2 could also be one
task, but then the library API gets its first real use only after review, so a stage 1 merged alone may need a small API change later: the
sheets in sections 6 and 8 are meant to be reviewed before stage 1 starts.

## 13. Alternatives considered

- **A C editor** (the first plan, a `native/*.c` program built by `install-native.sh`): smaller (about 700 lines, no compiler change) and
  quick, but it is a second implementation language for a tool of a language that is meant to write its own tools, it cannot be the
  library other Tomato programs use, and its highlighting could not reuse the lexer. Davis rejected it.
- **A checked-in `repledit.ll`** (the editor compiled once and kept in git like `tomatoc.ll`): install needs no `tomatoc` run, and the
  `.pkg` could use it directly. Costs: a generated file in every diff, a `refresh` script, a test that fails when the compiler, the
  runtime or a used std module changes, and 1 to 3 MB of IR churn. Recommended against; reconsider only if build time at install
  becomes a problem.
- **`rlwrap` or `readline` bindings:** a dependency the brief rules out, and neither gives a multi-line buffer.
- **Hand-written tokenizer for colors** (the website's and the VS Code grammar's approach, a regex per class): quick, but it is the
  second copy of the language's token rules that Davis asked to avoid, and it cannot know what the real lexer will reject.
- **Making the lexer a std module** (`std/tokenize.tom`, as Python has `tokenize`) so any program can lex Tomato: attractive, but the
  compiler would then import its lexer from `std/` (its own build depends on the folder it is compiling), and the std API of a
  language's tokens is a public promise. Left as open question 2.
- **An async `read_key`** that cooperates with tasks: see the note in section 6.

## 14. Questions for Davis

Each has a recommendation; the first four are the ones that change the shape of the work.

**Davis approved all seven recommendations (26 November 2026).**

1. **Where does the editor library live, and how generic is its API?** *Recommend: two std modules, `terminal` and `lineedit`, with
   hooks as `interface`s (`Highlighter`, `Validator`, `Indenter`) rather than function values.* Interfaces carry state (a theme, the
   lexer's results), and function values cannot (D63a: no closures). The cost is that a user writes a class with one method for a hook.
   The alternative is one module `readline` (Python's name) with named-function hooks.
2. **Is the Tomato lexer public?** *Recommend: no. Keep `lexer.tom` in `compiler/src/` with the new `lex_spans`; the highlighter and
   the editor program live beside it and the installer copies the three files into a build folder.* The alternative, `std/tokenize.tom`
   imported by the compiler and by tools, gives other programs a lexer but makes the token set a public API and makes the compiler's
   build depend on `std/`.
3. **Which history format?** *Recommend: keep `⏎`-joined entries* (section 9), because both old and new `tomato` read the file and
   nothing has to be migrated; its only flaw (a literal `⏎` inside a string comes back as a newline) is the one today's repl already
   has. The alternative is an escaped format (`\n` and `\\`), which fixes that but breaks the old reader on new files.
4. **Blocking or async keys?** *Recommend: blocking `read_key`* for stages 1 to 4. An async one means putting a terminal in the
   scheduler's descriptor set (the runtime's `kqueue` and `epoll` back-ends are not known to watch a terminal device on macOS; `poll` does not, **[M]** section 3), which is a larger
   runtime change with no user yet.
5. **Should Enter also continue on an open bracket?** *Recommend: yes, `x = (1,` and `f(` continue on the next line, as in Python*,
   using the lexer's bracket depth. It differs from the repl's rule today (those lines are submitted and fail to compile), so it is
   your call; with "no" the validator is exactly the current one.
6. **Do edits to a recalled entry survive moving on?** *Recommend: no* (drop them when Up or Down leaves the entry; the draft the
   person was typing before is kept). Readline keeps them; Python 3.13 does not.
7. **Colors:** *Recommend: keywords red, strings green (the brand colors), everything else from the terminal's own palette, comments
   dim, no light/dark detection.* The alternative is a second palette chosen by an `OSC 11` query or a `TOMATO_THEME` variable.

Not asked, decided in this design (change them by saying so): prompts are `>>> ` and `... `; Tab inserts four spaces; the helper
reads and draws on `/dev/tty`; `:commands` and quit words are not recorded; the history limit is 1000; terminal restore uses
`try`/`finally` plus `atexit` and signal handlers; widths come from our own tables.
