# `lineedit`: the API sheet as built (stage 2 of the repl editor)

`import lineedit` (`std/lineedit.tom`, D88a). An editor for one line or a block of lines on a terminal, with history, the usual keys of
Python's repl and readline, and hooks a program fills in. It is built on `terminal` (`docs/terminal-api.md`) and knows nothing about Tomato
the language or the repl: `tomato repl` uses it through `compiler/src/repledit.tom`, which adds the repl's rules. The design and the
reasons are in `docs/repl-editor-design.md` (section 8); this sheet says what was built, including where the design's sheet was made
precise.

```
import terminal
import lineedit

ed = lineedit.Editor()
ed.prompt = '> '
ed.history = lineedit.load_history('/tmp/my_history', '')     # one entry per line ('' : entries are single lines)
term = terminal.open()
result = ed.read(term)                                         # draws, reads keys, gives the terminal back as it found it
term.close()
if result.status == 'text':
    lineedit.append_history('/tmp/my_history', result.text, '')
    print(result.text)
```

Conventions as in `terminal`: explicit objects, no module state. Native only for the terminal itself (`terminal.open()` raises
`RuntimeError` in the browser playground); everything else is pure and works anywhere, which is how the tests run it.

## `Editor`

| Field | Default | Meaning |
| --- | --- | --- |
| `prompt` | `'>>> '` | before the first line |
| `continuation` | `'... '` | before every other line |
| `history` | `History([], 1000)` | Up and Down go through it; the program adds to it (and to its file) |
| `validator` | `AlwaysComplete()` | whether Enter on the last line submits (a one-line editor unless a paste brings more lines) |
| `indenter` | `KeepIndent()` | the indent of a line that Enter adds |
| `highlighter` | `Plain()` | the colors of the text; asked only when `colors` is above 0 |
| `tab` | `'    '` | what Tab inserts; its length is how much Shift-Tab, and Backspace in an indent, take away |
| `colors` | `0` | 0 for no colors, else as `Terminal.colors` (8, 16, 256, 16777216): the runs and the prompt styles are lowered to it |
| `prompt_style`, `continuation_style` | `Style()` | the prompts' styles, when `colors` is above 0 |
| `interrupt_text` | `'KeyboardInterrupt'` | written on its own line after Ctrl-C (`''` for nothing) |

`read(term: TermIO) -> Result` enters raw mode, turns bracketed paste on, draws the prompt and edits until the text is submitted, Ctrl-C or
Ctrl-D; then, in a `finally`, it turns bracketed paste off and leaves raw mode. The text stays on the screen as typed, with the cursor at
the start of the next line. It resets the history to the draft first, so each `read` starts after the newest entry.

`Result`: `status` is `'text'` (`text` is the submitted text without its trailing blank lines), `'eof'` (Ctrl-D on empty text, or the
input ended) or `'interrupt'` (Ctrl-C).

### Keys

| Key | Does |
| --- | --- |
| a character, a paste | inserts it; a paste is inserted as it is (tabs become `tab`, other control characters are dropped), with no indent added and no submit |
| Enter (Ctrl-J, Ctrl-M) | not on the last line: splits the line, the new line getting the indenter's indent. On the last line: submits when `validator.complete(text)` is True, else the same split |
| Left, Right, Ctrl-B, Ctrl-F | one character; they cross line ends |
| Up, Down, Ctrl-P, Ctrl-N | one line, keeping the column (or the end of a shorter line). Up on the first line recalls the previous history entry with the cursor at its end, so Up again walks up through its lines; Down on the last line recalls the next one with the cursor at the end of its first line; past the newest entry the draft (the text typed before the first Up) comes back |
| Home, End, Ctrl-A, Ctrl-E | the start and the end of the line |
| Ctrl-Left, Ctrl-Right, Alt-B, Alt-F | by word (words are split by spaces), crossing line ends |
| Backspace, Delete | one character; at a line's start or end they join two lines. Backspace with only spaces before the cursor goes back to the previous tab stop |
| Ctrl-D | Delete on text that is not empty; `'eof'` on empty text |
| Ctrl-K, Ctrl-U, Ctrl-W | cut to the end of the line, to its start, the word before the cursor (within the line); Ctrl-Y puts the last cut back |
| Tab, Shift-Tab | inserts `tab`; removes up to one `tab` of spaces from the line's start |
| Ctrl-L | clears the screen and draws the text at the top |
| Ctrl-C | `'interrupt'` |
| a resize | redraws at the new size |
| anything else (Ctrl-Z, Ctrl-\, Escape, F-keys, Page keys, Insert, unknown sequences, Alt with other letters) | nothing |

An edit to a recalled entry is kept while the person stays on it and dropped when Up or Down leaves it (Python 3.13's behavior; readline
would keep it). An entry that is edited and submitted is a new entry for the program to add.

## Hooks

```
export interface Highlighter:  def highlight(self, lines: list[str]) -> list[list[Run]]
export interface Validator:    def complete(self, text: str) -> bool
export interface Indenter:     def indent_after(self, line: str, before: str) -> str
export class Run:              start: int; end: int; style: Style       # characters start to end (not included) of a line
```

`highlight` gives, per line, runs that are sorted and do not overlap; what they leave out is drawn plain. The editor wraps the lines and
places the cursor from the plain text, so a highlighter cannot change the text or the cursor. `indent_after` gets the current line up to
the cursor and all of the text up to the cursor. The defaults are `Plain`, `AlwaysComplete` and `KeepIndent` (the line's own leading
spaces). A hook is a class with state if it needs one (a theme, a cache).

*Precise where the design was a proposal:* the hooks are never `None`: an interface type cannot be optional (`Validator | None` is not a
type the compiler takes), so each field has a default object instead of `None`. `TermIO` is an interface of methods only (an interface has
no fields), so the colors are `Editor.colors` rather than a field of the terminal.

## `TermIO`

```
export interface TermIO:
    def read_key(self, timeout: float = -1.0) -> Key
    def write(self, text: str)
    def size(self) -> tuple[int, int]
    def enter_raw(self)
    def leave(self)
```

`terminal.Terminal` implements it (`lineedit` declares `Terminal implements TermIO`). A test makes its own: `tests/lineedit_logic.tom`
has a `FakeTerminal` whose keys are a list and whose writes are recorded, and runs whole sessions on it.

## `Buffer`

The text and the cursor, and the editing operations; pure. `lines: list[str]`, `row`, `col` (the line and the character in it, from 0).
`text()`, `set_text(text)` (cursor at the end), `is_empty()`, `line()`, `on_last_line()`, `insert(text)` (a `'\n'` splits the line),
`newline(indent)` (splits at the cursor; the spaces after the cursor give way to the indent), `backspace()` and `delete()` (True when
something was deleted; they join lines), `dedent_back(n)` (Backspace in an indent), `dedent(n)` (Shift-Tab), `left()`, `right()`, `up()`,
`down()` (False when there is nowhere to go), `home()`, `end()`, `word_left()`, `word_right()`, `kill_to_end()`, `kill_to_start()`,
`kill_word_back()` (they give the text they cut).

## `History` and the history file

`History(entries, limit=1000)`: the newest `limit` entries (oldest first; a negative limit keeps all). `previous(current) -> str | None`
(the entry before the one shown; `current` is kept as the draft when it is left; `None` at the oldest), `next() -> str | None` (the entry
after the one shown, **the draft** after the newest, `None` when the draft is shown already: the design's sheet had `None` past the
newest and the editor putting the draft back), `recalled()` (an entry, not the draft, is shown), `add(text)` (appends, trims to `limit`,
back to an empty draft), `reset()`.

The file: plain text, UTF-8, one entry per line, the line breaks of an entry written as a `joiner` the program chooses (the repl's is
`⏎`, U+23CE; with `''` entries are single lines and a line break becomes a space).

| Function | Does |
| --- | --- |
| `read_history(path, joiner) -> list[str]` | the entries, oldest first; empty lines skipped, tabs become four spaces, other control characters (a CR of a CRLF file too) dropped; no file gives `[]`; an unreadable one raises the `os` module's error |
| `load_history(path, joiner, limit=1000) -> History` | `History(read_history(path, joiner), limit)` |
| `append_history(path, entry, joiner, limit=1000)` | appends one line (making the folders when missing); when the file then holds more than `limit` entries it is rewritten with the newest `limit`, to a temporary name and renamed over it, so a reader never sees half a file |
| `history_line(entry, joiner) -> str` | the line of one entry |
| `clean_text(text, tab='    ', keep_lines=True) -> str` | tabs become `tab`, control characters (C0, DEL, C1) are dropped, `'\n'` is kept when `keep_lines` |

**Limit:** an entry with the joiner inside its text (a `⏎` in a string) comes back with a line break there; the old repl had the same.

## Drawing

`layout(lines, prompt, continuation, width, row, col) -> Layout`: pure. `Layout.rows` is a list of `Row` (`line`, `start`, `end`: the
characters of that line on the row; `prefix`: the prompt on a line's first row, `''` on the rows it wraps onto), and `cursor_row`,
`cursor_col` (in cells, `terminal.text_width`). A line wraps at the width; a wide character never splits across the edge; a cursor after a
line that fills its last row exactly gets a row of its own below (the editor never leaves the terminal at the edge, waiting to wrap).

`Screen` keeps the region: `cursor_row` (where the last frame left the cursor, from the region's top), `height`, `width`, `colors` and the
prompt styles. `frame(lines, runs, prompt, continuation, row, col, all_rows) -> str` is one write: `cursor_up` to the region's top, `\r`,
`clear_to_end`, the rows joined by `\r\n`, then `cursor_up` and `cursor_column` to the cursor. A layout taller than the window shows only
`height` rows around the cursor, unless `all_rows` (the last frame, when the text is submitted, shows every row and lets the terminal
scroll). `resized(rows, cols, ...)` finds the cursor's row again at the new width, assuming the terminal re-wrapped the old text (most do;
Ctrl-L cleans up after one that does not). `strip_trailing_lines(text)` and `leading_spaces(line)` are the small helpers the editor uses.

## The repl on it (`compiler/src/repledit.tom`, `tomato-repl-edit`)

The helper is a Tomato program next to the compiler's lexer, built by `install-native.sh` with the installed `tomato build ... --mode
release` (optional: a warning when it cannot be built, and the repl uses plain input), shipped in the tarball as source, and in the
`.pkg` as a universal binary (`release/pkg.sh`, fatal there, checked with `lipo -archs`). `native/tomato-repl` runs it once per prompt
when standard input is a terminal and `TERM` is not `dumb`:

```
tomato-repl-edit [--history FILE] [--color=auto|always|never]
  exit 0: the piece is on standard output    exit 10: Ctrl-D (leave)    exit 11: Ctrl-C (a new prompt)
  any other status: it failed; the repl says "the line editor is not available; using plain input" once and goes on with read -e
```

Its rules: **Validator** (`ReplValidator`): a piece is complete when no bracket is left open (the compiler's own `lex` says so) and, if it
starts a block (a line outside brackets ends with `:`, or a line starts with `@`), once its last line is blank; a piece the lexer rejects
for another reason is complete unless it is a block still being typed, so the compiler reports the error. **Indenter**: the line's
indent, four more spaces after a line whose code ends with `:`. **History**: `$TOMATO_HISTORY`, else `~/.tomato/repl_history_v2`, joiner
`⏎`, 1000 entries; not recorded: empty pieces, `:commands`, `leave()`, `exit()`, `quit()`, and a piece equal to the newest entry (one recalled and run again unchanged). The colors (`--color`) come with stage 3.

## Tests

- `tests/lineedit_logic.tom`: 32 `@test` functions (debug and release): `Buffer` at line ends and with wide and combining characters,
  `History` (the draft, dropped edits, the limit, the old `⏎` file with a blank line, a tab, a CR and a control character, appending and
  trimming), `layout` (wrapping, wide characters at the edge, exactly full rows), frames (spelled out, a tall block's window, runs split
  where a line wraps) and whole sessions on a `FakeTerminal` (recall a block and edit its middle line, Up through a block into the entry
  before, Down back to the draft, add and delete lines, Enter inside a block, Ctrl-C, Ctrl-D, paste, kills, Tab and Shift-Tab, a resize,
  Ctrl-L, word moves, UTF-8).
- `tests/repledit_logic.tom`: the repl's validator, indenter and history rules (copied beside `repledit.tom` and `lexer.tom` to run).
- `tests/repl_history.exp`: the real repl with the built helper on a pty (see its header); it fails, never skips, when the helper is
  missing.
