# The CLI contract tests

A black-box suite of the `tomato` command: every command and flag, the exit statuses, the text of the help and of the errors, what `init`
writes, the build tables, `config`, `version`, `explain`, and the paths of `update` that end before anything is downloaded. It is stage 0 of
`docs/shell-to-tomato-plan.md` (sections 6 and 12): the shell script `native/tomato` passes it today, and the compiled Tomato program that
replaces it must pass it **unchanged**. So a case may look only at what a user sees (standard output, standard error, the exit status, the
files left behind) and must not assume how the command is made: no sourcing of its files, no reading of its install folder, no shell
functions, no shell-specific wording (the `Terminated` line a shell prints about a dead child is not part of the contract).

```
sh tests/cli_contract/run.sh                  every case, against $TOMATO or the tomato on PATH
sh tests/cli_contract/run.sh init config      only these cases (files of cases/)
sh tests/cli_contract/run.sh --fast           skip the cases that link many programs
sh tests/cli_contract/run.sh -j 8             cases at a time (default 4)
sh tests/cli_contract/run.sh --update CASE    rewrite the golden files of a case from what the command prints now
TOMATO=/path/to/tomato sh tests/cli_contract/startup_times.sh   the startup numbers of plan section 2 (reports only)
```

`tests/run.sh` runs it as its own section ("CLI contract") against the installed command, one job per case; its fast tier skips the cases
whose second line is `# tier: full` (they build and run a program per check). The cases that look only at what `tomato` prints before it
compiles anything (`help`, `version`, `explain`, `config`, `init`, `args`, `update`) are in both tiers.

## How a case is written

`cases/NAME.sh` is a plain `sh` file: `. "$CONTRACT_DIR/lib.sh"` and then checks. It runs in a folder of its own (`$W`, also its current
folder), with `TOMATO_HOME` set to a folder inside it (so the user's own `~/.tomato/config.toml` is never read) and the colour, warning,
cache and update variables cleared. The helpers:

* `try NAME STATUS OUT ERR ARGS...` starts the command (standard input empty) and checks the exit status (a number, `-` for any, `!` for not
  0), the standard output and the standard error. OUT and ERR are the exact text (empty: nothing at all), `@FILE` (the golden file
  `golden/FILE`), `~TEXT` (the output contains this one line) or `-` (not checked). A path of the case's folder is written `$W` in the text
  and `@W` in a golden file; the version is `@VERSION@` and the manifest's `tomato = "..."` line `@MINV@`.
* `check NAME EXPECTED ACTUAL`, `within DIR COMMAND...`, `files_in DIR`, `fast` and `skip` do what they say.
* `$version` and `$minv` are this command's version and the MAJOR.MINOR that `init` writes.

A change to a golden file is a change to the contract: review its diff, and in a 1.0.x patch there is none (plan, section 6).

## What is covered, and where

| Case | What |
| --- | --- |
| `help` | the help text on standard output (status 0), the same text as a usage on standard error (status 2) for every misuse, an unknown command |
| `version` | the line, its three spellings, SemVer shape, nothing read from the folder |
| `explain` | the id forms, the class and message, the source line with a caret, a line past the end, what is not an id |
| `config` | no files, a project file found from a folder or a FILE, the user's file, the project over the user, the user's `[build] mode`, every error of the settings |
| `init` | the files and their golden text, names and quoting, `--seed`, each way of refusing, nothing written when refusing |
| `args` | which word is a FILE, an ENTRY, an option or an input for `run`, `build`, `compile` and `test`; every message; no program is linked |
| `update` | the flags, a manifest that is missing, not understood, not newer, without a checksum, or naming an unofficial URL (a file: manifest, no network) |
| `run_forms`, `run_programs` | `run FILE ENTRY INPUTS`, raw inputs, `--`, `File` inputs, the program's status and error text in both modes, standard input, environment, warnings |
| `build` | `-o`, the default `builds/NAME`, the built program's own entries and E591, `--entry`, `--mode`, `--llvm` |
| `project` | a project made by `init`: `run`, `build` and `test` with no FILE from a folder below it, program names, a seed's folder |
| `build_tables` | `[build]` and `[build.ENTRY]` for `run`, `build` and `test`, `output`, the flags winning, the user's file's mode |
| `seed` | `seed hash`, `check`, `install`, `install --locked`, the lock file, a path seed used by a program |
| `test_all`, `test_forms`, `test_messages` | `tomato test` over a folder of every kind of file, the forms of its words, `--filter`, `--timeout`, `--mode`, `-v`; what a failed file shows (the file and line of the check, the diffs, the class of an error, a long output cut, an all-skipped file) and the entry list of E228 |
| `color` | `--color`, `TOMATO_COLOR`, `NO_COLOR`, `--no-warnings`, `TOMATO_WARNINGS`, the painted error text |
| `env_status` | `TOMATO_CACHE_DIR` and `TOMATO_CACHE`, exit statuses for `sys.exit` and signals, how `test` says them |

Not covered here (the rest of the CLI section of `tests/run.sh`, which the plan keeps as it is): the repl, the runtime cache's internals,
the install and update swap (`t_atomic_*`), `release/release.sh`, and the LTO fallbacks.
