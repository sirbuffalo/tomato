# The registry client: what is built

The sheet of the index client of `docs/package-registry-design.md` (stage 4; decision D141a in `docs/decisions.md`). The design says what the
registry is for and why; this sheet says what the code does today, and gives the **formats** that the registry's own tools (stage 5) must write.
Where the two differ this sheet is the code. Nothing here is promised stable in 1.x unless a decision says so (D126a): the index format has a
version (`format = 1` in the index's `config.toml`) so that a later one can change it, and a client that reads another format stops.

The client is `compiler/src/index.tom` (the files and their signatures), `compiler/src/regclient.tom` (settings, the local copy, names,
minimal version selection) and the lock and store half in `compiler/src/seeds.tom`. It needs `git` (as the git seeds do) and `ssh-keygen`
(OpenSSH 8.0 or newer) to check signatures. **`tomato run`, `build`, `compile` and `test` never read an index and never use the network** (D117a):
only `tomato seed add`, `install` and `registry add` and `update` do.

## Built in this slice, and what is not

| Built | Not built yet (the rest of stage 4) |
| --- | --- |
| the formats of `config.toml`, `policy.toml`, `owners/`, `seeds/`, `requests/`, `names.toml` and `yanks.toml`, and reading them | `tomato seed update` of a registry seed, `outdated`, `tree`, `why`, `search`, `info` |
| signatures through `ssh-keygen -Y verify`, key rotation and revocation, a handle's grant by the maintainers | the warning for a yanked version at `install`, `verify`, `outdated` and `tree` for a seed that is **already locked** (a yank is only seen where the index is read: `add`, and `install` of a manifest the lock does not cover, say so) |
| `tomato seed registry add`, `update`, `list`; `alias`, `unalias` | the owner's own server (`--from-owner`, `--index-only`, the automatic fallback) and the live check of a domain's `/.well-known/tomato-seeds.toml` on the first `add` of an owner |
| `tomato seed add NAME[@VERSION]` (an alias, a short name, `owner/name`, a handle), `--registry NAME`, `--allow-yanked`, `--test` | the "first seen under 30 days ago" line of `add` |
| minimal version selection, over the index or over the lock alone; `source = "registry"` entries in `tomato.lock` (`index`, `key`, `seeds`) | `tomato seed request-handle` and `request-name` (stage 5 writes requests), `only_listed`, the generated `listing.toml`, scores and endorsements (stages 5 and 5b) |
| `install` (with `--locked` and `--offline`), `verify`, `vendor` and every build for registry seeds | the registry itself, its acceptor `index-check` and `publish` (stage 5); the hosted form of `index` (stage 6) |
| owner yanks and the maintainers' emergency yanks: `add` skips a yanked version, a named one warns, `honor_maintainer_yanks` | |

## The user's settings (`${TOMATO_HOME:-$HOME/.tomato}/config.toml`)

```toml
[registry]
default = "tomato"                 # the registry `tomato seed add NAME` asks; `registry add` sets it when there is none

[registries.tomato]
index = "https://git.example.net/index.git"   # a git URL of the index: https, ssh, file:// or an absolute folder
maintainers = ["ssh-ed25519 AAAA... a maintainer"]   # the keys whose short names, handles and emergency yanks this registry is trusted with
only_listed = false                # read, not used yet
honor_maintainer_yanks = true      # false: a maintainer's yank is treated as absent (the owner's own yank always counts)

[aliases]
json5 = "acme.example/json5"       # your own short names: `tomato seed alias NAME OWNER/NAME`
```

These are the user's: a project's `tomato.toml` cannot set any of them (a seed cannot make a user's tool pick another seed). Other tables of the
file (`[limits]`, `[build]`) are read by other code and left alone; an unknown key *inside* these three tables is an error (E679). **The maintainer
keys come from here and never from the index being read**: a statement signed by a key that is not in `maintainers` is ignored, so a hostile
mirror can change nothing but what a bare name means. No default registry ships in this slice: the first `registry add` makes the registry the default.

## Commands

```
tomato seed registry add NAME URL [--maintainer KEY]... [--default]   write the settings, fetch the index, check it; a failed fetch or a repository
                                                                     that is not an index leaves the settings file exactly as it was
tomato seed registry update [NAME]       fetch the index again (all registries with no NAME); the new files replace the old only when they check out
tomato seed registry list                the registries, the commit each local copy is at, and how many maintainer keys
tomato seed alias [--list]               the aliases;  tomato seed alias NAME OWNER/NAME sets one;  tomato seed unalias NAME removes it
tomato seed add WORD [--registry NAME] [--allow-yanked] [--test] [--yes]
```

`WORD` is `NAME` or `NAME@VERSION` (`@1.2.0`: that exact version, yanked or not). A word with a slash is a full name, an owner (a domain or a
**handle**) and a seed. A word without one is, in this order: **your alias**, **the registry's short name** (granted by a maintainer's signed `[[name]]`),
else an error that lists the seeds of that name in the index (exit status 1, not the 2 the design says: every `tomato seed` error is 1) so you can
pick one by its full name. `add` prints what it is about to do before it writes anything, never asks except about foreign symbols (as for git seeds),
writes the **full name** and the chosen version as the minimum into `[seeds]` (`[test-seeds]` with `--test`; a lower version never lowers a
higher minimum on the same line), and locks. The summary is:

```
acme.example/json5 1.2.0  signed by domain acme.example (key SHA256:...), first seen 2026-11-01, 5 versions, similar to: none
imported as: from json5 import ...
status: listed (policy level 0: structural checks only), no endorsements or test results collected by this client
short name: json5 (granted 2026-12-03 by a maintainer of fixture)
note: the owner has changed its key 1 time; this version is signed by the key SHA256:...
```

A handle owner reads `signed by handle dave (granted 2026-11-20 by the registry NAME)`; an owner the index marks as looking like another one
(`similar = "other.example"` in its file) gets a warning line. **The registry's word is checked, not trusted**: nothing is believed that is not
signed (below), and the files fetched must hash to the signed content hash.

## The lock

`tomato.lock` gets a top-level `index = "NAME"` (the registry's name in your settings, not its URL; one lock never mixes registries) and entries like

```toml
[[seed]]
name = "acme.example/json5"
version = "1.2.0"
source = "registry"
git = "https://git.example.net/acme/json5.git"
commit = "9f2c1d...40 hex"
key = "SHA256:..."                  # the owner key that signed this version: the lock's pin
hash = "sha256:..."
modules = ["json5"]
seeds = ["other.example/strutil 0.4.1"]   # what it needs, as its signed entry says
```

`path` (a seed in a folder of its repository) is written when the entry has one, and makes the lock's `version` 2, as for a git seed. The lock holds
**everything a build needs**: `install --locked`, `install --offline`, `verify`, `vendor` and every build read the lock and the store only. A lock
records no yank. When the lock covers the manifest (the selection below, run over the lock's own `seeds` lists, gives exactly the locked seeds), `install`
does not read the index at all and fetches only what the store lacks; otherwise it reads the registry's local copy, selects again, and refuses an entry
that disagrees with the lock about a version it already holds (a published version never changes: E684).

## Resolution (design section 4)

The selection is minimal version selection: the highest minimum anyone asks for (the manifest, and the `seeds` of the selected versions' entries), repeated until
it stops changing, so a bump drops the requirements of the version it replaced. The version chosen must exist; two requirements on different compatible lines
of one seed (`1.x`; `0.y`) are E683 naming who asked for each; `add` chooses the newest version that is not yanked and not a pre-release; a pre-release is used
only when a requirement names it. `[test-seeds]` takes part in one selection with `[seeds]`, and a seed only the tests reach is `test_only`. A registered
seed's own `tomato.toml`, at the signed commit, must say what its signed entry says (its version, the seeds it needs, its modules): otherwise E684.

## The index format (version 1)

A folder of TOML files, in a git repository that the client fetches with the hardened fetch of the git seeds (no checkout, no symbolic link, no hook).
`registry add` and `update` accept up to 200,000 files. Unknown *files* are ignored; an unknown *field* of a statement makes that statement invalid (it
would not be covered by the signature), and a new field therefore needs a new `format`.

| File | Holds |
| --- | --- |
| `config.toml` | `format = 1` (required; another number stops the client) and `name`. The rest (rate limits, reserved names) is the acceptor's |
| `policy.toml` | `version`, `notice_days`, `[listing]`, `[short_name]`, `[demotion]`. The client reads which `[listing]` requirements are on (`level_zero`) for the summary line; it enforces nothing |
| `owners/OWNER.toml` | `[[key]]` statements in order; optionally `[owner] similar = "other.owner"` |
| `seeds/OWNER/NAME.toml` | `[[source]]`, `[[version]]`, `[[yank]]` and `[moved]` (or `[[moved]]`) statements |
| `requests/OWNER.toml` | `[[request]]`: the owner's signed ask for a short name or a handle (parsed by the logic tests; not needed to use a seed) |
| `names.toml` | the maintainers' `[[name]]`, `[[unname]]`, `[[handle]]`, `[[unhandle]]` |
| `yanks.toml` | the maintainers' emergency `[[yank]]` and `[[unyank]]` (listing only) |

### Signed statements

Every statement has the fields below, then `signed_by` (the fingerprint, `SHA256:...`, of the key that signed it), `signature` (an SSH signature,
`-----BEGIN SSH SIGNATURE-----` ...) and optionally `accepted` (the acceptor's stamp, `2026-12-01T10:15:00Z`, outside the signature). The text a signature covers:

```
tomato-seeds-v1 LF
KIND LF
SUBJECT LF
NAME=VALUE LF        for each field the statement has, in the order of the table below
```

`SUBJECT` binds the statement to what it is about, so it cannot be copied under another name: the owner for `key` and `request`, `owner/name` for
`source`, `version`, `yank` and `moved` (taken from the file's path), the short name for `name` and `unname`, the handle for `handle` and `unhandle`, the seed for
the maintainers' yanks. A text value is the string itself, with no control character; a list is its items joined by `,`; a table (`seeds`) is its `key:value` pairs
sorted and joined by `,`; a field the statement does not have is left out. The signature is made with `ssh-keygen -Y sign -n tomato-seeds-v1` and the client
checks it with `ssh-keygen -Y verify` against **one** key, the one `signed_by` names, written into a one-line allowed-signers file by the client from the key
alone. Only `ssh-ed25519` keys are used. `tests/registry/gen.sh` builds these texts in shell, independently of the Tomato code.

| Kind (table) | Fields, in signing order |
| --- | --- |
| `key` (`[[key]]`) | `kind` (`root`, `rotate` or `revoke`), `public`, `retires`, `revokes`, `signed_by` |
| `source` | `git`, `path`, `mirrors`, `signed_by` |
| `version` | `version`, `commit`, `hash`, `tomato`, `modules`, `seeds`, `published`, `signed_by` |
| `yank` | `version`, `kind` (`bug`, `security`, `malware`), `reason`, `signed_by` |
| `moved` | `to`, `signed_by` |
| `request` | `ask` (`name`, `handle`, `release`), `seed`, `handle`, `key`, `signed_by` |
| `name` | `name`, `seed`, `granted`, `signed_by` (a maintainer) |
| `unname` | `name`, `reason`, `signed_by` (a maintainer) |
| `handle` | `handle`, `key`, `granted`, `signed_by` (a maintainer) |
| `unhandle` | `handle`, `reason`, `signed_by` (a maintainer) |
| maintainer `yank` (`yanks.toml`, signed as kind `maint-yank`) | `seed`, `version`, `kind` (`security`, `malware`), `reason`, `signed_by` |
| maintainer `unyank` (signed as `maint-unyank`) | `seed`, `version`, `reason`, `signed_by` |

### Owners and keys

An owner is a **domain** (`acme.example`: lowercase letters, digits and hyphens in dotted labels, no `xn--`) or a **handle** (no dot, 2 to 32 characters, not reserved,
not `k-...`); there is no key-only owner (D117a). `owners/OWNER.toml` holds the owner's keys in order: the first statement is a `root` signed by its own key; a
`rotate` adds a key (`public`) and may retire an old one (`retires`); a `revoke` ends a key (`revokes`). A later statement is signed by a key that was valid when it was
written. **A key that was retired or revoked cannot sign what came after**: a statement signed by it is valid only if it carries an `accepted` stamp earlier than the
stamp of the statement that ended the key (a statement with no stamp, as a file served by the owner would have, is not trusted if its key was ended). The client takes the
*order* inside one file from the file; across files it relies on the stamps. A domain's well-known file is **not** re-checked by this slice (the acceptor checked it).
A handle owner's root key must be one a maintainer granted in `names.toml`; with no maintainer key in your settings no handle is granted and its seeds are not vouched for.

### Seeds

In `seeds/OWNER/NAME.toml`, the last valid `[[source]]` applies; a version number is published once (the first valid statement stands, a second one for the same number is
ignored); a `[[yank]]` of the owner hides a version from the listing. `mirrors` are read and not used yet. The statements of different tables are applied in the order of the
tables, then of the file (TOML keeps no order across tables), so a rule that needs the order between a version and a yank uses the stamps.

### Short names and the maintainers' yank

`names.toml` and `yanks.toml` are applied in the order of the acceptor's stamps (statements without one first, then the order of the file's tables): a name granted, released
and granted again works with stamps. A short name is the seed's own name (`json5`, `-` and `_` alike); a name granted to a seed does not resolve once released. A maintainer's yank
hides a version from `add`'s choice and warns when the version is named; it **never stops a build, a lock or an install** (D117a); an owner's `malware` yank makes `add` and the
fetch of that version refuse unless `--allow-yanked` is given (the one consequence of D117a that is only proposed, D123a).

## Errors

E679 the settings (`[registry]`, `[registries.NAME]`, `[aliases]`, a registry name or URL, the words of `registry`, `alias`, `unalias`); E680 the index (no `config.toml`,
another format, not TOML); E681 `ssh-keygen` is missing; E682 a name or version that the registry does not have or does not vouch for (the ignored statements are listed in
the message); E683 requirements that cannot all be met; E684 a seed that is not what its signed entry says, or a lock and an index that disagree about a published version; E685 an
owner's malware yank without `--allow-yanked`. E571 is also raised when a name needs a registry and none is set up. `docs/errors.md` has the one-line meanings.

## The fixture and the tests

`tests/registry/` is a signed index checked in as data: `index/` (made by `gen.sh` with the test-only keys of `keys/`, which are public test data), `seeds-src/` (the seeds' files),
`build-sources.sh` (one bare git repository for each seed, with deterministic commits, so the ids in the index are the ones the script makes on any machine) and `commits.txt`
and `fingerprints.txt`. The fixture holds a domain owner that rotated its key, a handle granted by a maintainer, versions yanked by an owner and by a maintainer, a statement signed after its key
was retired, one changed after it was signed, one signed by another owner's key, a short name that was granted and released, one granted by a key that is not a maintainer's, and seeds whose signed
entries do not match what is at their commit. `tests/run.sh` has `t_registry_logic` (`tests/registry_logic.tom`, the reader's rules) and `t_cli_registry` (three parts: setup, names and yanks and
mismatches and selection, install and offline). The sources are reached through a `git` shim that maps `https://git.fixture.example/OWNER/NAME.git` to the local repositories: there is no network.
