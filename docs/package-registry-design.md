# Seeds: packages and a registry for Tomato: design

Status: **proposal for Davis to review. Nothing is built, and no language rule changes until Davis answers the questions
at the end.** It records the decisions Davis has already made (the first section), settles what can be settled, and lists the
few real forks. The source facts about the compiler were read on `main` at `a58ae90b` (v0.51).

**Update, 2026-11-26 (stage 0, D89a in `docs/decisions.md`):** Davis gave his direction on the model: Homebrew-like (anyone
uses `owner/name` at once, no approval), a default index that **starts with no requirements beyond structural validity** and
whose requirements (passing tests, community recommendations, a score) are **raised over time** by a versioned policy file.
Section 18 records it and the ramp; sections 1.5, 1.7, 9, 11, 12, 13, 15 and 17 carry the small changes it needs. The five
older open questions stay open; questions 6 to 11 are new (section 19).

## The requirement

Davis wants to share Tomato code the way other languages share packages, with these decisions already taken:

- A package is called a **seed**. (`basket` was considered; it is kept for a bundle or workspace of seeds, section 16.)
  `tomato seed add owner/name`.
- Names are `owner/name` from day one. There are **no flat global names**, so nothing can be squatted the way names on
  PyPI and crates.io are.
- **Nothing depends on GitHub.** A seed's source and the registry are git repositories on any host: self-hosted, Gitea,
  GitLab, plain ssh or https. A host is storage, never an identity.
- **No curator, no human approval step anywhere in publishing.** An owner proves who they are, signs what they
  publish, and the registry accepts a change by an automatic rule check (valid signature, rules, rate limits).
- Users do not type long names every day: short names come from a local alias layer, and `tomato.lock` pins what was
  chosen. A direct git URL stays available as an escape hatch for an unregistered seed.
- The manifest is `tomato.toml` and the lockfile `tomato.lock`, with content hashes. Configuration in general is TOML
  (the huge-float limits, D77g, are its first user: `[limits]` in `tomato.toml` and `config.toml`; section 13).
- Written policies: no squatting, a way to reclaim abandoned work, yank instead of delete.
- The registry index is designed so a hosted service can replace the git repository later without changing any seed.
- **Homebrew-like use (added 2026-11-26):** any seed is usable as `owner/name` at once, with no approval and no registry
  needed; the default index's listing starts with **no requirements** beyond structural validity, and requirements are
  raised over time by a versioned policy file, never in a way that breaks a lock (section 18).

Candidate domains, **unregistered and unconfirmed when checked, and not contacted**: `tomatoseeds.dev` for the registry
and `tomatolang.dev` for the project. This document needs neither: the index location is a setting (section 13), so the
names below are only examples.

## Recommendation in short

1. **Owner identity is self-proving.** An owner is a **domain** (`acme.example`) whose web server publishes the owner's
   signing key at `/.well-known/tomato-seeds.toml`, or a **key** (`k-<fingerprint>`) for someone with no domain. There
   is no account system and no first-come name table, so there is nothing to squat at the owner level and nothing
   inside an owner's names that anyone else can take (section 1).
2. **The registry is untrusted storage of signed statements.** It is one git repository holding one TOML file per owner
   and per seed. Every statement in it (a key, a source URL, a version, a yank) is signed by the owner's key, and the
   client verifies the signatures itself. The registry's jobs are discovery, availability, an append-only history and
   rate limiting; it is never asked to be honest (sections 1 and 8).
3. **Changes to the registry are accepted by a program, not a person**: `tomato seed index-check` is a pure function of
   (the tree before, the tree after) and either accepts or rejects. Whether it runs as a push hook, a merge bot or a
   hosted service is a deployment choice (section 1.5).
4. **`owner/name` is what is stored; short names are local.** `tomato.toml` and `tomato.lock` always hold the full
   `owner/name`; an alias (`tomato seed alias json5 acme.example/json5`) is a typing shortcut in the user's own
   configuration and is never resolved by the registry (section 1.7).
5. **A seed is plain Tomato source, pinned by a content hash**, found by git URL plus commit in the owner's own
   repository. No install scripts, no build scripts, no native extensions (sections 6 and 8).
6. **Imports do not change.** A seed's module is imported with the existing `from name import x` or `import name`. The
   compiler learns one more place to look for a module file, after the project's own folder and before `std/`
   (section 5). Module names are made unique by a naming rule, not by new syntax.
7. **Versions resolve by minimal version selection (MVS), not semver ranges** (section 4). The reason is not taste: the
   compiler has one flat module namespace, so a program can hold only one copy of a seed, and that is the case MVS
   handles best.
8. **`tomato seed` is a shell front end plus a small helper program written in Tomato** (section 14), because the
   standard library cannot start a process today.
9. **Seven small stages**, each shippable alone; the first three need no registry at all (section 15).
10. **Use is open, listing is a ratchet.** `owner/name` always works. The default index's listing starts with structural
    checks only; tests, endorsements and a score are collected from the first day, and `policy.toml` raises the bar for **new**
    listings with a notice period, grandfathering what is already listed (section 18).

## What exists today

Read from the source (nothing here is new behavior):

- **Imports are by a single identifier.** The parser (`compiler/src/parser.tom:340-351`) reads `from NAME import a, b`
  and `import NAME` with `NAME` one token. There is no dotted name, no string path, no `as`, and no re-export
  (D24b and D24c in `docs/decisions.md` leave aliases and re-exports open). `import m` makes `m.x` a single `NAME`
  token through `qualify` (`parser.tom:227`).
- **Modules are found by name only, through two places.** `read_module(dir, std, name, line)`
  (`compiler/src/compiler.tom:12774`) opens `{dir}{name}.tom` (`dir` is the folder of the main program) and, if that
  fails, `std_path(std, name)`. A project's own file therefore **shadows** a standard module of the same name, with no
  warning. On failure the error lists the standard modules (`std_modules()`, line 12765).
- **One program holds one copy of each module.** `load_items` (line 12852) keeps a `loaded` list by module name, loads
  each module once, and places a module's declarations after those of the modules it imports. Declarations are keyed
  `module.name` (`key_of`, line 12296), the main program and `builtin` being plain. Two different files that are both
  called `json5` cannot coexist in one program.
- **`dir` is always the main program's folder**, not the importing module's: a module imported from the project folder
  finds its own imports there too. There is no subfolder lookup.
- **The compiler is a whole-program compiler of text**: `tomatoc FILE ENTRY STD MODE` prints LLVM IR; there is no
  separate compilation, no object or interface file, and warnings are collected per module (`collect_warnings`,
  line 12805), shown as the file name `{module}.tom` (`source_path`, line 12815).
- **`!name(...)` foreign declarations exist only in std modules** by convention (D27b; `docs/next-features.md` says "FFI
  exists as `!name(...)` declarations in std modules only"). I did not find a compiler check that forbids them in a
  user module, so sections 5 and 11 ask for one before seeds exist.
- **The `tomato` command is a POSIX shell script** (`native/tomato`) that calls `bin/tomatoc`, then clang. `tomato update`
  already downloads over https only, with a pinned sha256 (`curl_safe`, `native/tomato:52-55`), using `curl`, `tar` and
  `shasum`/`sha256sum`.
- **The standard library cannot start a process.** `std/os.tom` has files, folders, environment and `stat` (with a
  `mode`); `std/sys.tom` has argv and exit; there is no `system`, `popen` or `subprocess`. `std/toml.tom` (TOML v1.0.0),
  `std/hashlib.tom` (sha256 in Tomato) and `std/requests.tom` (libcurl through `dlopen`, native only) exist.
- **The browser** (`site/wasm/tomato.js`) has a fixed list of standard modules and no project folder; its `compile`
  takes an optional `extra` map of module files (the command-line repl uses it). Programs on the website cannot import
  their own modules today, and a seed would not change that until stage 7 of section 15.

## Vocabulary

| Word | Meaning |
| --- | --- |
| **seed** | a package: a folder of `.tom` files plus a `tomato.toml` with a `[seed]` table (the manifest's tables: section 2) |
| **owner** | the self-proving identity that signs for a set of seeds: a domain or a key |
| **index** | the registry's data: a git repository of signed TOML files |
| **version entry** | the signed statement "version V of owner/name is commit C of git URL U with hash H" |
| **store** | the user's local, content-addressed folder of fetched seeds (`~/.tomato/seeds/`) |
| **entry table** | `[seeds.ENTRY]` in `tomato.toml`: seeds used only when running that entry point (`[seeds.test]` for `tomato test`); `[seeds]` is for every build |
| **project** | a folder with a `tomato.toml` that has a `[project]` table (a program that uses seeds) |
| **basket** | reserved for a bundle or workspace of seeds in one repository; not designed here (section 16) |

## 1. Names and owners

### 1.1 Why the owner has to be self-proving

Davis's first sketch tied the owner to a GitHub user or organisation. That was replaced for two reasons: GitHub must
not be needed, and no person may have to approve an owner. What is left to answer is "who is allowed to publish under
`acme.example/`?" with nobody to ask. The answer has to be something a program can check and anybody can verify later.

| Owner kind | Spelled | Proof | Who can squat | Recovery if the key is lost | Human-readable |
| --- | --- | --- | --- | --- | --- |
| **Domain** (recommended) | `acme.example/json5` | a file on the domain's web server lists the signing key | nobody: only the domain's operator can prove it, and a lookalike is a different string | prove the domain again (section 1.6) | yes |
| **Key** | `k-5kq3x…/json5` | possession of the private key | nobody: the name is a hash of the key | none: the identity is the key | no, so aliases carry it |
| Host account (GitHub, GitLab, ...) | `acme/json5` | the host says so | the host's first-come table | the host's account recovery | yes |
| Git URL as identity (Go-like) | `git.example.net/acme/json5` | none: the URL is the name | nobody, but moving the repo renames the seed | none | long |
| Registry-granted handle | `acme/json5` | first merged claim | whoever is first | a human | yes |

The last three are rejected: the host account and the handle need an authority (an account system, or a curator);
the URL is a location, and a seed that moves host must keep its name. Domain and key owners need no authority at all:
the proof is public and any client can re-check it.

### 1.2 The owner string and the seed name

- A **domain owner** is a lowercase ASCII domain name with at least one dot: labels of `a-z0-9-`, no leading or
  trailing hyphen, no `xn--` label in version 1 (no internationalised names), at most 253 characters. Any domain or
  subdomain may be an owner; `git.acme.example` and `acme.example` are two owners and neither controls the other's
  names.
- A **key owner** is `k-` followed by 26 base32 characters (lowercase `a-z2-7`): the first 130 bits of the sha256 of the
  key's public blob. It has no dot, so it never collides with a domain.
- A **seed name** is `[a-z][a-z0-9_-]{0,63}`. Two names in one owner are the same name when `-` is replaced by `_`
  (`json-5` and `json_5` cannot both exist). The name with `-` turned into `_` is also the seed's **module name** stem
  (section 5), so it must be a valid Tomato identifier.
- A name that is also a standard module (`json`, `math`, ... : the list in `std_modules()`, copied into the index's
  `config.toml`) is refused for every owner, and so is anything beginning `std_` or `builtin`. This keeps today's
  imports from changing meaning when a seed appears (section 5).
- `owner/name` in text has exactly one slash: a domain has none and a name has none, so it splits unambiguously.

### 1.3 The owner's keys and the proof

An owner signs with one or more **ed25519 keys in OpenSSH format**. That is not decoration: `ssh-keygen -t ed25519`
exists on every machine that runs Tomato, `ssh-keygen -Y sign` and `-Y verify` produce and check detached signatures
(OpenSSH 8.0 or newer), and git itself already uses these keys for signed commits. Signatures use the namespace
`tomato-seeds-v1`.

- **Domain owner.** The proof is `https://DOMAIN/.well-known/tomato-seeds.toml`, a file only the domain's operator
  can place:

  ```toml
  # https://acme.example/.well-known/tomato-seeds.toml
  [[key]]
  public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... acme release key"
  ```

  A DNS TXT record (`_tomato-seeds.DOMAIN`) as an alternative for a domain with no web server is a later stage
  (section 15); it needs a DNS lookup that the shell front end does not have to hand.
- **Key owner.** The owner string is the proof: the first statement is signed by that key, and the checker confirms the
  string is the hash of the key. A key owner is shown everywhere as **unverified: no domain**.

### 1.4 The statements and where they live

Every fact the index holds is a **signed statement**, a small TOML table whose `signature` covers the table's other
fields in a fixed order, prefixed by the owner/name it belongs to (so a signed statement cannot be replayed under
another name). There are five kinds:

| Statement | In file | Says |
| --- | --- | --- |
| `[[key]]` | `owners/OWNER.toml` | this public key may sign for OWNER (the first is `root`, proved by the domain or by being the owner's own hash; later ones are `rotate`, signed by an earlier key) |
| `[[source]]` | `seeds/OWNER/NAME.toml` | the seed's git URL (and optional `path` and `mirrors`); repeatable, the **last** one in the file applies |
| `[[version]]` | the same | version V is commit C, content hash H, with these seeds and modules |
| `[[yank]]` | the same | version V is yanked, with a reason and a kind (`bug`, `security`, `malware`) |
| `[moved]` | the same | the seed continues as another `owner/name` (a notice, never an automatic redirect) |

Because each statement is self-contained and signed, **an index file can come from anywhere**: the registry repository,
a mirror, a hosted service, or the owner's own server at `https://DOMAIN/.well-known/tomato-seeds/NAME.toml`. A client
trusts the signature, not the place (section 8). That is what lets a hosted service replace the git repository later
without any seed noticing.

### 1.5 How an owner claims a name, and how the index accepts it

No one approves anything. `tomato seed claim DOMAIN` (or `claim --key`) writes `owners/OWNER.toml` with the root key and
signs it; the owner then sends the change to the index and a program runs the rules:

1. **Format and paths.** Only files under `owners/` and `seeds/` change, only for owners whose statements are present,
   and every file parses and matches the format version in the index's `config.toml`.
2. **Proof.** A new domain owner: the checker fetches the well-known file over https (certificate verified, no
   redirect to another host) and requires the signing key in it. A new key owner: the string equals the hash of the
   key, and the claim carries a small proof of work (a nonce so that sha256 of the claim has a stated number of zero
   bits, a few seconds of computing), because keys are free.
3. **Signatures.** Every added or changed statement verifies against a key that is valid for that owner **in the tree
   before the change** (a new owner's root key is the exception).
4. **Append only.** Existing bytes never change: a statement can be added, never edited or removed. (`yank`, `moved`
   and a key rotation are new statements.) So a version, once published, is immutable in the index.
5. **Source check** for each new `[[version]]`: the checker fetches the source (section 6) and recomputes the
   content hash; reads `tomato.toml` at that commit and requires the same name, version, top-level `[seeds]` (the entry tables are not in the index) and module
   list; and applies the seed checks of section 11 (size, file types, module names, no foreign declarations).
6. **Names.** The name rules above, and one deterministic look-alike rule (section 1.8).
7. **Rate limits.** At most a stated number of new versions per owner per day, a maximum size per seed, a maximum
   number of new key owners per day (a separate allowance from domain owners, so free keys cannot starve domains),
   and a maximum number of seeds per owner. The numbers live in the index's `config.toml`, so they can change without
   changing the checker.
8. **Order.** Where two changes conflict, the one the acceptor sees first wins; the other is rejected on the base
   it did not have, and its sender rebases. This is the only "first come" in the system, and it covers a version
   number inside one owner, which only that owner can publish.

The acceptor is the same program anywhere: a `pre-receive` or `update` hook on a git server that lets anyone push,
a bot that merges requests on a hosted forge, or a service. Pushing to a branch the rules do not accept simply fails.
(Time-based rules, section 1.6, need an acceptor with a trusted clock, which a bare shared repository does not have;
the hook or service stamps the time.)

**Which time counts.** The `published` date in a version entry and any date a signer writes are **display only**: a
thief holding a stolen key can write any date. What the rules and the clients rely on is **order**, which an append-only
file fixes: a statement is "before" another when it comes earlier in its file (and an owner's key statements in
`owners/OWNER.toml` are ordered the same way). A key revoked by statement N cannot validly sign anything placed after N.
The acceptor also stamps `accepted = <its clock>` on each statement it takes, for the delay rules (re-root), for
`outdated` and for audit; that stamp is authoritative where there is one. **A file served by the owner directly, or by a
mirror that does not run the acceptor, has no stamp and no assurance of order**: a thief could present a file in which
the revocation is missing. So a client takes the order and the revocations from the registry's log when it can reach
it, and `tomato seed add --from-owner` says plainly that the owner-direct form is verified for signatures but not for
history (the lock's key pin and the content hash still hold for anything already locked).

### 1.6 Rotation, loss, and abandoned owners

- **Rotation** (a planned key change): a new `[[key]]` signed by a current key. The old key is marked retired by a
  later statement; entries it signed stay valid.
- **Compromise or loss when the owner still has another key**: that key signs a `[[key]]` that revokes the other one.
  A revoked key's statements that come **before the revocation in the file's order** are still trusted, those after it
  are not; `yank` the bad versions. (Order, not a date: see "Which time counts" in section 1.5.)
- **Loss of every key, a domain owner**: the domain is the root of trust, so it is also the recovery path.
  The owner puts the new key in the well-known file and sends a `reroot` statement. The checker records a pending
  re-root and its own clock; if **no current key has signed anything or vetoed it within 30 days** (the delay is a
  setting), a second change completes it: the new key becomes the root, the old ones are retired. The delay lets a
  live owner stop a takeover by signing anything; the lock's key pin (section 3) tells every consumer that the owner's
  key changed. No person is involved.
- **Loss of every key, a key owner**: none. The identity is the key. The owner publishes under a new key and, if the
  old key still exists, signs a `[moved]` notice. This is the price of owners that need no domain; anything people
  depend on should have a domain owner (and the docs say so).
- **Abandoned owners and seeds.** A name inside an owner can only be used by that owner, so the squatting that
  worries other registries does not arise: nobody else *wants* `acme.example/json5`, they publish
  `theirs.example/json5`. The reclaim paths are therefore about owners: a domain that **expires and is bought by someone
  else** is the case that matters. The new registrant can prove the domain and re-root it after the delay, and
  every existing consumer is protected the way they are against any key change: their lock pins the old key and the
  old content hash, and `tomato seed update` stops with "the owner's key changed" until the user runs
  `tomato seed update --accept-owner-change acme.example`. New consumers see the owner's age and the re-root date
  in `tomato seed add` (section 1.8). Abandoned seeds under a live owner stay as they are; the usual answer is a fork
  under another owner, announced with a `[moved]` notice by whoever can sign one.
- **Hosts and moves.** The source URL is a `[[source]]` statement; the owner supersedes it at any time by appending a new one (the last applies, the older ones stay as history). A
  moved or dead repository never changes what a version *is*: the content hash does. A new URL is accepted only if
  the checker finds every published commit there with the same hash, so moving host cannot be used to swap content.

### 1.7 Short names: the alias layer

The user's configuration (section 13) has an `[aliases]` table:

```toml
# ~/.tomato/config.toml
[aliases]
json5 = "acme.example/json5"
```

- `tomato seed alias json5 acme.example/json5`, `tomato seed alias --list`, `tomato seed unalias json5` edit it.
- `tomato seed add json5` expands an alias, then proceeds as `add acme.example/json5`. The manifest records the **full
  name**, so a project means the same thing on every machine; aliases are not read from a project's `tomato.toml` and
  a project cannot give a user an alias.
- **A bare name that is not an alias is never resolved by the registry** (and a listing, section 18, does not change that;
  open question 7 asks whether it should). `tomato seed add json5` with no alias searches
  the index for seeds called `json5`, prints the candidates (owner, first-seen date, number of versions, signing
  domain or "unverified: no domain") and stops with exit status 2; the user picks one with the full name or sets an
  alias. There is no popularity ranking and no "default" owner for a name, because that would be a curator again.
- Direct add is the escape hatch: `tomato seed add --git URL [--rev COMMIT|--tag TAG] [--name NAME]` and
  `--path DIR` (section 12). It has no owner and no signature, so it is allowed only in a project, never in a seed that is
  published, and it prints that the seed is **unregistered**.

### 1.8 What remains without a curator, honestly

| Risk | Without a curator | What reduces it | What is left |
| --- | --- | --- | --- |
| **Squatting a name** | cannot happen inside an owner; cannot happen at the owner level either, since owners prove control | none needed | squatting *domains*, a domain-market problem, not ours |
| **Taking over a name** (hijack) | an attacker needs the owner's key, or the domain | signatures checked by every client; lock pins the key; immutable, hash-pinned versions; re-root delay and veto | an owner whose domain lapses (above): consumers are warned, **new** consumers are only informed |
| **Typosquatting**, `acme.exampel/json5`, `acme-example.com/json5` | **nothing stops it**: anyone can own a lookalike domain | owner and name shown at `add` (with age and signer); the full name is stored once and never retyped; a warn-only **skeleton** check on owners (below); first-seen date; a lookalike costs a domain | a user who types the wrong owner the first time and does not read the summary |
| **Flooding** the index | key owners are free | proof of work on key claims; separate daily allowances; per-owner and per-seed caps | an attacker who spends real money on domains |
| **Malware** in a seed | no one reviews code | none in the index; the language has no sandbox (section 8); hash pins keep a good version good | a malicious *owner* stays in the index until their key or domain is gone; section 8 and open question 1 |
| **Abandonment** | not detected | consumers see the last version date in `tomato seed outdated` | nobody is forced to fix anything |

The **skeleton rule** (automatic and deterministic) is **warn-only for owners and refusing only for names inside one
owner**:

- *Owners.* Two owners have "the same skeleton" when they are equal after lowercasing, mapping `0->o`, `1->l`, `rn->m`,
  `vv->w` and dropping a `www.` label. The checker **never refuses** an owner for this: a refusal would be first-come
  squatting (an attacker who proves `acrne.example` first would lock the real `acme.example` out of the index), which
  is exactly what this design removes. Instead each owner is marked `similar = "other.owner"` in the index when a
  skeleton or an edit distance of 1 matches an older owner, and `tomato seed add` shows "similar to X, older" or
  "similar to X, newer" with both first-seen dates. The cost is stated plainly: a lookalike owner is allowed to exist,
  and the protection is the warning and the lock, not a refusal.
- *Names.* Inside one owner, two names are the same name when they are equal after the rules of section 1.2
  (`-` and `_`) or have the same skeleton as above; the owner's second claim is refused. That is the owner's own
  namespace, so it is not a squat of anybody else's. Names are **never** compared across owners: `acme.example/json5` and
  `dave.example/json5` coexist (forks, section 5).

### 1.9 Comparing the curated model, briefly

The first design had maintainers who reviewed claims and approved changes. It is stronger in two ways and weaker in
four.

| | Curated (maintainers approve) | Automatic (this design) |
| --- | --- | --- |
| Lookalike owners and names | a person can refuse them | a deterministic lookalike check that **warns** (owners) and refuses only inside one owner's own names; the rest is shown, not stopped |
| Malicious seeds | can be removed | cannot be removed, only yanked by their owner |
| Scaling and delay | a queue of reviews | none: accepted in seconds |
| Who is trusted | the maintainers (a single point of trust and failure) | nobody but the owner's own key and domain |
| Subjectivity | "is this name too generic or hyped?" | rules are written down and apply to everyone |
| Cost to run | people's time, forever | a small program and a git host |

Davis chose automatic; this document designs that and says what it costs. The one real fork left is whether the
registry keeps a narrow, **yank-only** emergency power for named security keys (open question 1). Davis's later direction
(section 18) adds a second, deliberately weaker lever, a versioned `policy.toml` that raises the bar for **listing** over time; it
sets rules for everyone and cannot touch one seed.

## 2. The manifest: `tomato.toml`

One file for a seed and for a project (decisions D92a and D92b, 2026-11-26). A folder has **either** `[seed]` (a published
package) **or** `[project]` (a program that uses seeds), never both. Keys with a `/` are quoted, as TOML requires.

```toml
# a seed that is published
[seed]
name = "acme.example/json5"           # owner/name
version = "1.2.0"                      # MAJOR.MINOR.PATCH, optional -pre.N
tomato = "0.52"                        # the oldest compiler that builds it
description = "JSON5 reader and writer"   # optional
license = "MIT"                        # an SPDX id
modules = ["json5", "json5_pretty"]    # optional: all of src/*.tom otherwise (section 5)

[seeds]                                # a minimum version of each seed it imports from
"other.example/strutil" = "0.4.1"

[seeds.test]                           # only when running entry `test` (`tomato test`) in this seed
"other.example/fixtures" = "1.0.0"
```

```toml
# a project: a program that uses seeds
[project]
name = "todo-app"
version = "0.3.0"
tomato = "1.0"                         # the oldest compiler that builds it

[seeds]                                # packages and their minimum versions
"acme.example/json5" = "1.2.0"
"dave.example/scratch" = { git = "https://git.example.net/dave/scratch.git", rev = "9f2c...40hex" }   # unregistered
"local/thing" = { path = "../thing" }                                                                  # unregistered

[seeds.test]                           # only when running entry `test` (`tomato test`)
"other.example/fixtures" = "1.0.0"

[seeds.greet.loud]                     # only when running entry `greet.loud`
"x.example/colors" = "0.2.0"

[seed-store]
vendor = "vendor"                      # use ./vendor instead of the store (section 6)
```

Rules:

- `[seed]` has `name`, `version`, `tomato`, and optionally `description`, `license` and `modules`. (All three are optional;
  `description` and `license` are rewarded by the listing score of section 18.) `[project]` has `name`, `version` and `tomato`.
- `[seed]` makes the folder publishable and gives the files a layout: the seed's modules are the `.tom` files directly in
  `src/` (the compiler's lookup is flat, section 5). A file or folder named `tests/` is not part of a build.
- `[seeds]` lists the seeds used by every build. `[seeds.ENTRY]` (D92b) lists those used only when running that entry point
  (`[seeds.test]` for `tomato test`, `[seeds.greet.loud]` for the entry `greet.loud`); the entry names are the dotted
  names of the `@` markers. Seed names always contain `/` and are quoted keys, so they never clash with a sub-table
  name. A requirement
  `"acme.example/json5" = "1.2.0"` means **at least 1.2.0, and the same compatible line** (section 4). There is no range
  syntax, no `^`, no `<`.
- **Which tables a run reads.** Running entry `x` (which runs every `@x.*`) uses `[seeds]`, every table that is `x` or a
  prefix of it (`[seeds.test]` applies to a run of `test.parse` too), and (**proposed, not yet confirmed by Davis**) every table below `x` (a run of `test`
  runs `test.parse`, so it needs `[seeds.test.parse]`). `build`, `compile` and `run` of a plain program read `[seeds]` only.
- **The same seed in two tables** (say `[seeds]` and `[seeds.test]`): the higher minimum wins; if one table says
  `git` or `path` and the other a version, or the two forms differ, it is an error.
- **A published seed's `[seeds.ENTRY]` tables are read only by `tomato test` inside that seed**,
  never by a user of the seed and never in the index entry.
- The `git` and `path` forms are **unregistered**. They are accepted only in a project, and a seed's index check
  rejects them: a registered seed depends only on registered seeds, so the index is closed under its `[seeds]` and a
  seed's graph can always be resolved from signed statements.
- `tomato` is also a minimum (`tomato version` is compared; an older compiler stops with a clear message).
- Unknown top-level tables are an error, not ignored, so a typo in `[sedes]` is caught (a typo in an entry name, `[seeds.tset]`, is a valid table: `tomato seed check` warns when no `@tset` entry exists). `[limits]` and
  `[build]` are **reserved** for the configuration work (section 13), and `[seed-store]` holds the project's
  vendor folder (the former `[seeds] vendor`; `[seeds]` is now only the list of seeds).
- In a **seed that is used**, only its `[seed]` and its top-level `[seeds]` are read (not `[seeds.ENTRY]`). Its other tables (settings, `[limits]`) are
  ignored: a library cannot change how the program that uses it is built or limited.

## 3. The lockfile: `tomato.lock`

Written and rewritten only by `tomato seed`, sorted by name so diffs are small, and **committed** by projects. It holds
everything needed to rebuild and to check the sources, and nothing that is a preference.

```toml
# tomato.lock: generated by `tomato seed`, do not edit
version = 1
index = "tomato"                        # the registry's name in the user's config, not its URL

[[seed]]
name = "acme.example/json5"
version = "1.2.0"
source = "registry"
git = "https://git.example.net/acme/json5.git"
commit = "9f2c1d...40hex"
hash = "sha256:ab12...64hex"
key = "SHA256:Qn3...base64"             # the owner key that signed this version
modules = ["json5", "json5_pretty"]
seeds = ["other.example/strutil 0.4.1"]

[[seed]]
name = "other.example/strutil"
version = "0.4.1"
source = "registry"
git = "https://git.other.example/strutil.git"
commit = "..."
hash = "sha256:..."
key = "SHA256:..."
modules = ["strutil"]

[[seed]]
name = "other.example/fixtures"         # only in [seeds.test] of this manifest
version = "1.0.0"
source = "registry"
git = "https://git.other.example/fixtures.git"
commit = "..."
hash = "sha256:..."
key = "SHA256:..."
modules = ["fixtures"]
entries = ["test"]

[[seed]]
name = "dave.example/scratch"           # unregistered: no signature, no index
version = "0.0.0"
source = "git"
git = "https://git.example.net/dave/scratch.git"
commit = "9f2c...40hex"
hash = "sha256:..."
modules = ["scratch"]
```

- **The hash is the content hash of section 6**, not the commit's hash. A git commit id is sha1 and is no defence
  against a collision or a rewritten history; the content hash is sha256 over the files.
- `commit` and `git` are *where it came from*, kept so the source can be fetched again; the build trusts `hash`.
  If a host lost the repository, any copy that produces the same hash is the same seed.
- **`entries`** (D92b) appears only on a seed that not every build uses: the entry tables of the manifest that reach it
  (`["test"]`, `["greet.loud", "test"]`). A seed that some `[seeds]` requirement reaches, directly or through another
  seed, has no `entries` field. The lock holds all seeds, so `install`, `vendor` and `verify` cover every build.
- `key` pins who signed it. `tomato seed update` refuses a new version signed by a key that is not in the owner's
  chain from this key, unless told `--accept-owner-change` (section 1.6).
- A lock does **not** record the URL of the index, the compiler version, or any setting. It does record the registry's
  *name* so a mirror under a different URL is the same registry.
- `tomato seed install --locked` fails if the manifest would produce a different lock. This is the CI mode.

## 4. Version resolution

### What the compiler forces

A program can hold **one copy of a module**, keyed by its name (section "What exists today"), and the name is the
seed's name. Cargo and npm solve "A needs json5 1.x, B needs json5 2.x" by linking both; Tomato cannot without new
language rules (renaming a module per importer). So resolution has exactly one outcome per seed: one version, or an
error. That decides the comparison.

### Compared

| | Minimal version selection (Go) | Semver ranges (Cargo, npm) |
| --- | --- | --- |
| A requirement means | "at least V" in a compatible line | "any version matching the range" |
| The result is | the **highest minimum** anyone asked for | the **highest version** satisfying every range (a solver) |
| Without a lockfile | same answer every time | answer changes when a new version appears |
| Solver | a fixed-point loop, about 100 lines | backtracking, or PubGrub, 1,000 lines or more |
| New versions | never picked up by themselves | picked up at the next resolve |
| Upper bounds (`< 1.5`) | cannot be written | can be written (and over-used: they create conflicts) |
| Security fixes | need an explicit `update` | arrive silently, and so do new compromises |
| Two incompatible lines | error | error (here), with one copy allowed |
| Needs the whole graph's metadata | yes: each version entry lists its seeds | yes |
| Trust in `owner`'s semver discipline | needed only when bumping | needed on every resolve |

**Recommendation: MVS.** In a world with no curator and signed, immutable versions, a build that picks up code no one
asked for (ranges) is the wrong default; the lock then records *hashes*, not *choices*, which is a simpler job. It is
also the only one of the two whose solver is small enough to write, test and trust in Tomato.

### Rules

- **Compatible line.** Versions are semver 2.0.0. For major version 1 and up the line is the major number; for
  `0.y.z` the line is `0.y` (a minor bump in 0.x is a breaking change). Pre-release versions (`1.3.0-rc.1`) are never
  picked unless a requirement names one exactly.
- **Resolution.** Start from the project's requirements. Repeat: for each seed, take the highest version required
  anywhere; add the requirements of **that version's entry** (listed in the index entry, so no source is fetched to
  resolve); until nothing changes. Two requirements on different lines of one seed are an error that names the
  chain of requirers on each side. Nothing is downgraded and nothing is searched.
- **`add`** picks the newest non-yanked version of the seed in the index and writes it as the minimum. **`update`**
  raises the minimum of the seeds named (or all) to the newest in their line and re-locks. **`install`** never changes
  versions.
- **Yanked versions** (section 17) are skipped by `add` and `update`. A requirement that names a yanked version still
  resolves to it, with a warning, so existing locks keep building; a yank of kind `malware` is an error unless
  `--allow-yanked` is given.
- **Entry tables** (`[seeds.ENTRY]`, D92b) use the same rules. `tomato seed install`, `add` and `update` run MVS once, over
  the **union** of all the tables, and the lock holds that result: **one version per seed, the same for every build**.
  `tomato build`, `run` and `test` do not resolve again: the tables the run reads (section 2) only choose **which** locked
  seeds (and their dependencies) are compiled in, and the build checks that each has a locked version that meets the build's
  own minimum on the same line. So a test-only pin changes plain builds too: with `[seeds]` at 1.0.0 and `[seeds.test]` at
  1.2.0 the lock holds 1.2.0 and `tomato build` compiles 1.2.0. A seed in the lock only for another entry is not compiled
  in. Entry tables never enter a dependant's graph.

### Consequences to accept

- A requirement in an entry table on a **different line** of a seed (`[seeds]` at 1.0.0, `[seeds.test]` at 2.0.0) is the
  two-lines error of the union resolution, so it stops every `tomato build` and `run` of that manifest, not only `test`.

- You cannot say "not 1.4.2, it is broken". The answer is that 1.4.3 is published and you require it, or the owner
  yanks 1.4.2.
- Two dependencies on different major lines of a seed fail to build until one of them moves. In practice that
  pressure is on the seed authors, not on users, and it is cheap to explain in the error.
- Upgrades are explicit, so `tomato seed outdated` (newer versions, yanks, advisories, last-publish age) has to be good
  and is part of stage 4.
- If side-by-side majors are ever wanted, the Go answer (the major in the name: `acme.example/json5` for 1 and a new
  module name for 2) would work with this index without changes. Not designed now.

## 5. Imports in `.tom` files and the compiler

### What a seed's module is called

Seeds are imported exactly as today: `from json5 import parse` or `import json5` then `json5.parse(...)`. Nothing in the
parser changes. What makes that safe is a naming rule enforced by `tomato seed check` and by the index:

> A seed whose name is `owner/name` may contain only the module files `name.tom` and `name_*.tom` (with `-` in the
> name written `_`) in its `src/` folder.

So `acme.example/json5` provides `json5` and `json5_pretty`. Two seeds can collide in exactly two cases:

- **the same name under different owners** (`acme.example/json5` and `dave.example/json5`);
- **one name that extends another with `_`**: seed `foo` may ship `foo_bar.tom`, and a different seed `foo_bar` provides
  `foo_bar.tom` too. The same holds across owners for any such pair.

Both can be in the index, but **not in one program**: the resolver compares the module lists of every seed in the graph
and stops with "the seeds `A` and `B` both provide the module `M`" (the lock records each seed's `modules`, so this
needs no fetch). The index cannot refuse the second one, since refusing would let the first claimant block the second
(first-come again), so `index-check` only marks the overlap (`overlaps = "owner/name"` on the version entry) and
`tomato seed add` shows it. Seed authors avoid it by not shipping a `name_*` module that another registered seed is
called; `tomato seed check` warns when the local index has such a seed.

### How the compiler finds them

New lookup order in `read_module`, replacing today's two steps:

1. **The project's own file**: `{dir}{name}.tom`, as now, so a project can still shadow anything (as it can shadow
   `std` today). When a project file shadows a seed module, `tomato seed` prints a warning at install and check time.
2. **A seed module**, from a module map (below).
3. **The standard library**, as now.

A name present in both 2 and 3 (a std module added after a seed took the name) is a **compile error naming both**, not a
silent choice. The index prevents it ahead of time by reserving every std module name (section 1.2), and the project
that maintains `std/` checks a new module's name against the index before adding it.

The module map is a file of lines `module<TAB>path`, produced by `tomato seed` from `tomato.lock` and the store (or
`vendor/`) for the modules of the seeds in the lock. It is deliberately not TOML: the compiler is a Tomato program of
13,000 lines and should not grow a TOML reader. `tomatoc` gets one optional argument after `MODE`, the map's path
(`compile_module` gets the matching parameter; `compiler/src/ctool.tom` and the browser's `args` pass it or leave it
empty). No map means today's behavior exactly, so every existing program and test is untouched.

### What else the compiler must do for seeds

- **Name the seed in errors.** `source_path` (line 12815) shows `{module}.tom`; for a seed module it should show
  `acme.example/json5 1.2.0: src/json5.tom` so a user can tell their code from a dependency's.
- **Hide warnings from seeds.** `collect_warnings` runs for every module; lint warnings from code the user did not write
  and cannot change are noise. Show them only under a flag.
- **Reject `!name(...)` declarations in any module that is not `std`** if the compiler does not already (I did not find
  such a check): a seed must be Tomato source only (section 8).
- **Optional later: visibility.** `dir` is global, so a seed can import any module in the map, including a seed it did
  not declare. v1 only *checks* it, in `tomato seed check` by reading import lines; the compiler can enforce it once the
  map says which seed owns which module and which seeds a module may see (stage 7).

### What stays out

- **No new import syntax** in the first versions: no `from acme.example/json5 import x`, no `as`. Both would be language
  decisions about D24b and D24c (aliases, qualified names) and are open question 3.
- **No subfolders of modules.** The compiler's lookup is flat, so a seed is flat too.
- **The browser** supports no project folder today, so seeds do not run on the website at first. Because a seed is only
  Tomato source, `extra` files already carry one: the playground could ship the lock's modules in the same way later
  (section 15, stage 7), with no runtime change.

## 6. Fetching, the content hash, the store, vendoring and offline use

### The content hash

The hash must not depend on git's object format, on archive formats, or on line-ending and `.gitattributes` filters.
Definition (**seed hash v1**): take the files of the seed's tree at the commit, under `path` if the source names one
(for a repository that holds several seeds); the tree must contain only regular files and directories (no symlink,
no submodule); sort the file paths bytewise (`/` as separator, no leading `./`); for each file make the line

```
<sha256 of the file's raw bytes, lowercase hex>␠␠<mode>␠␠<path>\n
```

where `<mode>` is `755` for an executable file and `644` for any other; the seed hash is `sha256:` followed by the
lowercase hex of the sha256 of the lines concatenated. Raw bytes means the blob as git stores it, read with
`git cat-file`, never a checkout. The algorithm is small enough to cross-check in tests with `sha256sum`/`shasum` and a
loop, independent of the Tomato implementation.

### Fetching

The shell front end (section 14) does it, with `git` only, never a git library, and hardened: `GIT_ALLOW_PROTOCOL=https:ssh`
(`file` and the `ext::` helper protocol, which can run commands, are refused unless a user's own `--git file://...`
asks for it), no submodule update, no hooks, no checkout, no LFS; a URL that starts with `-` is refused; the fetch is
`git init` of a scratch repository, `git fetch --depth 1 URL COMMIT`, then `git ls-tree -r -z` and `git cat-file` of each
blob into a scratch folder with the mode from the tree. Fetching a commit by id works on hosts that allow it (most do);
a host that does not is reported with its error and `--rev` of a tag is the workaround. Paths with `..`, an absolute
path, a `.git` component, a name that collides with another when case is folded, or an entry over a size limit stop the
fetch.

Then `tomato-seed hash SCRATCH` computes the hash and compares it to the one in the lock (or the index entry). Only on
a match is the folder renamed to its place in the store. **Nothing that fails the hash is ever left where the compiler
can find it.**

### The store

`~/.tomato/seeds/` (`${TOMATO_HOME:-$HOME/.tomato}/seeds`; not under `native/`, which `install-native.sh` and
`tomato update` rebuild):

```
seeds/
  store/ab/12cd...64hex/      one folder per content hash: the seed's files, read-only by convention
  git/                        bare scratch clones, so an update fetches only new objects (a cache, safe to delete)
  index/<registry-name>/      a shallow clone of the index repository, refreshed by `tomato seed registry update`
```

A store folder is named by its hash and written once. Two projects using the same seed share it; nothing in it is ever
edited, so there is no "dirty store".

### Vendoring and offline

- **`tomato seed vendor`** copies every seed in the lock from the store into `./vendor/OWNER/NAME/` (the
  folder name is a setting, `[seed-store] vendor`) and writes nothing else; the lock is the same. With `[seed-store] vendor` set,
  the module map points into `vendor/`, `tomato seed verify` re-hashes it against the lock, and a project can be built
  on a machine with no network, no `git`, and no store. Vendored folders are meant to be committed.
- **`tomato run`, `build`, `compile` and `test` never use the network** and never fetch. They read the lock and the
  store (or `vendor/`), and if a seed is missing or the lock is out of step with `tomato.toml` they stop with one line:
  `run: tomato seed install`. Fetching and running third-party code in one command is the habit this design avoids
  (decision, open question 5).
- **`tomato seed install --offline`** fails rather than trying the network; with a complete store or vendor folder it
  is a no-op check.
- The **source host disappearing** is the real offline risk of "source in the author's own repo": the store, a vendor
  folder, a mirror URL in the `[[source]]` statement, or a hosted service that keeps the archive by hash (stage 6) all
  restore it, because the hash, not the place, identifies the content. Until stage 6 the index cannot guarantee
  availability, and the doc says so to users.

## 7. Build reproducibility

A build's inputs are: the program, the compiler and runtime (`tomato version`), the standard library, the seeds (all
pinned by the lock to content hashes), the mode and flags, and the configuration that is baked in (the float limits of
the other TODO, if they are set at compile time). The lock removes the seeds as a source of change:

- the module set and its load order follow from the imports, and `load_items` already places modules in import order;
- seeds are read from content-addressed folders that a later fetch cannot alter;
- `--locked` (CI) and a vendor folder turn a stale or missing lock into an error instead of a resolve.

What is *not* claimed: I did not measure whether two builds of one program produce byte-identical binaries, only that
the same module set is loaded in the same order. Stage 2 adds a test that compiles one seeded program twice and compares
the IR (`tomato compile`), which is the part Tomato controls; the final link is clang's. Settings that change the
output (the limits, `--mode`) belong in the printed inputs of `tomato seed verify --inputs` so a CI log shows them.

## 8. Security

### What a seed can do

A seed is Tomato code that runs with the program's full authority: the language has no sandbox, and a seed may open
files, sockets and processes through `std`. **Hash pinning and signatures say "this is what the owner published", not
"this is safe".** What the design does remove:

- **No code runs at install.** There are no install scripts, build scripts, macros or post-fetch hooks, and fetching only
  reads bytes. Code runs only when a program is run.
- **No foreign code.** A seed cannot declare `!name(...)` functions or ship C, so it cannot reach outside `std`'s
  reviewed runtime calls (section 5).
- **Dependencies are explicit.** Everything in a program comes from the lock, listed by hash.

### Threats

| Threat | Defence |
| --- | --- |
| A host serves different bytes than were published | the content hash in the lock; a mismatch is fatal and nothing is stored |
| A host rewrites history or deletes the repository | hash identifies content; store, vendor folder, mirrors; stage 6 archives |
| The index is altered (a bad clone, a hostile mirror) | statements are signed by the owner's key and verified by the client; a statement with no valid signature is ignored. A hostile index can still **hide** versions or replay an old state; the lock's pins and `outdated` are the defence |
| Someone publishes as an owner | needs the owner's private key or the domain; first `add` re-fetches the well-known file live and compares |
| A key is stolen | rotation and revocation statements; `yank`; the lock's `key` pin makes a surprise key visible |
| A domain lapses and is re-registered | re-root only after the delay and a veto window; consumers' locks pin the old key; `--accept-owner-change` |
| Typosquat | section 1.8: owner and age shown, skeleton rule, store the full name once; open |
| Dependency confusion (a public seed shadows an internal one) | project files shadow seeds; unregistered git/path dependencies are explicit; a seed can only be depended on by its full `owner/name` |
| Hostile git URL (a command-running transport, a file path, an option) | protocol allow-list, `--` before the URL, no hooks or filters, size and time limits (section 6); the acceptor runs the same fetch in a throwaway sandbox |
| Hostile tree (`..`, a symlink into the user's files, huge or case-colliding files) | the tree rules in sections 6 and 11 are checked before anything is written to the store |
| A poisoned lock in a pull request | `tomato seed verify` and `install --locked` recompute the hashes; the diff of a lock is small and readable |
| An old, broken seed that never changes | `outdated` shows the last-publish date |

### Signing: what is built when

The *index* has signatures from the first release of the registry (stage 5), because there is nobody else to vouch for
an entry. The client verifying them is stage 4, with `ssh-keygen -Y verify` called by the shell front end (so it needs
OpenSSH 8.0 or newer, present on macOS and on current Linux). A Tomato implementation of ed25519 verification (the
`int` type is unlimited, and the verification is a few modular exponentiations) would drop that dependency and make the
check work in the browser; it is a candidate later task, not a requirement. Signing the *seed's source tree* beyond the
version entry (signed git tags) is optional for authors and not checked.

### The release of the compiler is a separate trust root

`tomato update` trusts https plus one sha256 in `site/latest.json` and its archives are not signed (README, "Update
trust"). Seeds do not change that, and nothing in this design should make the seed registry's trust model look
stronger than the compiler's own.

## 9. Registry layout and the index format

A git repository, any host, any URL. The user's configuration names it (section 13); the default is a release-time
setting. The files are the whole interface, so a client needs only to read files by path (`git` for the repository, plain
HTTPS `GET`s for a hosted service).

```
config.toml                     index format version, the rule numbers (rate limits, delays, proof-of-work bits),
                                the reserved names (every std module, `std_*`, `builtin*`), the index's own name
owners/<owner>.toml             [owner]  and  [[key]] statements (section 1.4)
seeds/<owner>/<name>.toml       [[source]], [[version]], [[yank]] and [moved] statements, in the order they were accepted
policy.toml                     what listing requires, versioned, every requirement off at launch (section 18.3)
endorsements/<owner>.toml       [[endorse]] and [[unendorse]] statements by that owner (section 18.6)
results/<owner>/<name>.toml     [[result]] statements signed by a runner key (section 18.4)
listing.toml                    GENERATED: status, score, level and notices of each seed; verifiable, never hand-edited
```

```toml
# seeds/acme.example/json5.toml
[[source]]
git = "https://git.example.net/acme/json5.git"
mirrors = ["ssh://git@backup.example/acme/json5.git"]
signed_by = "SHA256:Qn3..."
signature = "-----BEGIN SSH SIGNATURE-----\n...\n-----END SSH SIGNATURE-----\n"

[[version]]
version = "1.2.0"
commit = "9f2c1d...40hex"
hash = "sha256:ab12...64hex"
tomato = "0.52"
modules = ["json5", "json5_pretty"]
seeds = { "other.example/strutil" = "0.4.1" }
published = 2026-12-01              # signer-declared, display only (section 1.5)
accepted = 2026-12-01T10:15:00Z        # stamped by the acceptor; absent in owner-direct or mirrored copies
signed_by = "SHA256:Qn3..."
signature = "..."

[[yank]]
version = "1.1.0"
kind = "bug"                # bug, security or malware
reason = "returns wrong numbers for 1e400"
signed_by = "SHA256:Qn3..."
signature = "..."
```

- **Why one file per seed, with every version in it.** A client resolving a seed reads one file (one `GET` on a hosted
  service) and an append-only rule is easy to check on a file. Different owners and seeds are different files, so changes
  by different people never conflict.
- **Search** is a client-side scan of the cloned index (`tomato seed search`, `info`): at this scale a clone is smaller
  than the one-time download of a language server, and nothing needs a service.
- **Seeds never mention the registry.** A seed's `tomato.toml` has an `owner/name` and requirements on other
  `owner/name`s; no URL of an index. The lock has the registry's *name*. Replacing the git repository with a hosted
  service, or mirroring it, is a change to one setting (`[registries.NAME] index`, where a `https://` URL means the
  hosted form and anything else is a git URL).
- **The same statement files can be served by the owner** at `https://DOMAIN/.well-known/tomato-seeds/NAME.toml`. A
  client uses them automatically when the registry has no entry for the seed or cannot be reached, and on request with
  `tomato seed add --from-owner acme.example/json5` (section 18.2), with exactly the same checks. This is the "decentralized" mode, costing no extra format.
- **Several registries** (a company's own, a mirror) are `[registries.NAME]` entries; a project's lock names which one
  each seed came from. Resolution never mixes registries behind the user's back.
- The checker, `tomato seed index-check BASE HEAD`, is part of the `tomato` distribution so that **anyone can run the
  rules** on a proposed change, and so the project's own index and a company's index use the same ones.

## 10. Publishing, in order

1. `tomato seed init acme.example/json5` makes `tomato.toml` and `src/`.
2. The author tags a release in their own repository, on any host.
3. `tomato seed check` lints the seed (section 11) and `tomato seed hash` prints its content hash.
4. `tomato seed claim acme.example` (once): prints the key to place in `/.well-known/tomato-seeds.toml` and writes the owner
   statement signed with it.
5. `tomato seed publish [--rev TAG]` writes the signed `[[source]]` and `[[version]]` statements into a clone of the index.
6. The author sends the change to the index however the index accepts changes (a push, a pull or merge request, a
   patch): the acceptor runs `index-check` and applies it or rejects it with the rule that failed.
7. A later version is steps 2, 3 and 5 only.

`tomato seed yank acme.example/json5 1.1.0 --kind security --reason "..."` writes a `[[yank]]` statement the same way.

## 11. Seed checks

`tomato seed check` is what the index also runs, so a seed that passes it locally is accepted:

- `tomato.toml` is valid; `[seed]` name, version and `tomato` are consistent with it and the tree;
- every file in `src/` is `name.tom` or `name_*.tom`; nothing else is a module;
- every module **parses** (the compiler's parser, not a regular expression) and uses no `!name(...)` declaration;
- the seed imports only its own modules, `std`, and the seeds in `[seeds]` or in any `[seeds.ENTRY]` of its own manifest (from the imports found while parsing; a module that imports an entry-only seed is reached only by a build that imports that module, so users who do not import it never need that seed);
- no symlink, submodule, file over 1 MB or tree over 5 MB (the numbers are settings in the index's `config.toml`);
- `[seeds]` and every `[seeds.ENTRY]` are registered seeds (no `git` or `path` form), and there is no `[project]` table;
- it compiles: `tomato compile` of a one-line program per module (this type-checks without running anything).

The index's checker **never runs a seed's tests or code**. Running arbitrary code from a publisher inside the acceptor
would turn the registry into a remote execution service. `tomato test` is for the owner, on their machine. The later
listing levels (section 18) do need test results; they come from a separate **sandboxed runner** that appends signed results
and gates nothing at launch (section 18.4), so this rule about the acceptor stays true.

## 12. The `tomato seed` commands

`tomato seed` is a subcommand of the existing command; the others keep working unchanged. `OWNER/NAME` is the full
name; an alias is also accepted wherever a name is added.

```
tomato seed init [OWNER/NAME]               start a seed (`[seed]`, src/), or with no name a project (`[project]`)
tomato seed add NAME[@VERSION]              add (or raise) a requirement, update tomato.toml and tomato.lock, fetch into the store
tomato seed add --git URL [--rev R|--tag T] [--name N]    unregistered source, by git URL (a project only)
tomato seed add --path DIR                  unregistered source, a local folder (a project only; for development)
tomato seed add NAME --from-owner | --index-only    use only the owner's server (domain owners), or never fall back to it (section 18.2)
tomato seed remove NAME                     drop a requirement and re-lock
tomato seed install [--locked] [--offline]  fetch every seed in the lock into the store and check each hash
tomato seed update [NAME...] [--accept-owner-change OWNER]   raise minimums to the newest in their line, re-lock
tomato seed outdated                        newer versions, yanks, last publish date
tomato seed tree                            the resolved graph;  tomato seed why NAME   who requires it
tomato seed verify [--inputs]               re-hash the store or vendor folder against the lock; list revoked keys; print build inputs
tomato seed vendor                          copy the locked seeds to ./vendor/
tomato seed search TEXT                     scan the index;  tomato seed info NAME   owner, signer, versions, first seen
tomato seed alias [NAME OWNER/NAME]         set an alias (no arguments lists them);  tomato seed unalias NAME
tomato seed registry update                 refresh the local clone of the index
tomato seed registry add NAME URL           add another index (the analogue of a Homebrew tap); `add --registry NAME` uses it
tomato seed endorse NAME | unendorse NAME   sign a recommendation ("star") of a seed (section 18.6)
tomato seed score NAME                      the listing status, policy level and the breakdown of the score (section 18.5)

# for a seed's author:
tomato seed check                           the seed checks (section 11);  tomato seed hash    print the content hash
tomato seed claim DOMAIN | --key            write the owner statement and the well-known file to place
tomato seed publish [--rev REV]             write the signed [[source]] and [[version]] statements into an index clone
tomato seed yank NAME VERSION --kind K --reason TEXT      write a signed [[yank]]
tomato seed index-check BASE HEAD           the registry's rules, for the acceptor and for anyone
tomato seed admit-check NAME [VERSION]      reproduce a test result locally (runs the seed's tests: use a sandbox)
tomato seed listing-verify                  recompute listing.toml from the index files; runs nothing
```

`add` prints one summary line before it changes anything and **never prompts** (so scripts behave like terminals):

```
acme.example/json5 1.2.0  signed by acme.example (key SHA256:Qn3...), first seen 2026-12-01, 4 versions, similar to: none
imported as: from json5 import ...
```

On the first `add` of an owner, `add` also fetches the domain's well-known file live (https only) and requires the signing
key in the index to be listed there; a key owner is unverified by definition. A first-time owner (first seen under 30 days ago), a re-rooted owner, a key-only owner and an unregistered source
each print a clearly worded extra line instead of a silent difference.

`tomato run FILE` looks for `tomato.toml` in the program's folder and each parent; with none (every existing program) it
behaves exactly as today.

## 13. Configuration in TOML

Davis wants configuration to be TOML throughout. The huge-float limits were the first user and are **built** (D77g in
`docs/decisions.md`): the compiler reads `[limits]` (`exp_bits`, `format_digits`) from the two files below and writes the
values into the program (so a native program reads no file when it runs; the browser has no files and uses the defaults),
and `tomato config` shows what is in effect. The files are found by `native/tomato` (a walk up from the program's folder,
then `${TOMATO_HOME:-$HOME/.tomato}/config.toml`), which only passes their paths on, as this section says. What D77g does
not do, so that the seed work decides it: it reads only `[limits]` and leaves every other table alone (it neither checks
nor rejects them, so `[seed]` and the rest are free for the manifest); there is no command-line override yet; and it
needs no `tomato-seed config get`, because the compiler (written in Tomato) already has `std/toml`. This design fixes the
*shape* so that later settings do not collide.

- **Two files, one format.** `tomato.toml` in a project folder (project settings and the manifest) and
  `~/.tomato/config.toml` (`${TOMATO_HOME:-$HOME/.tomato}/config.toml`, the user's). Both TOML 1.0, read by the same code.
- **Precedence**, highest first: the command line, the project's `tomato.toml`, the user's `config.toml`, the built-in
  default. A dependency's `tomato.toml` is **never** consulted for settings (section 2).
- **Tables** reserved now: `[registry]`/`[registries.NAME]` (default registry and index URLs; `only_listed`, user file only,
  section 18), `[aliases]` (user file
  only), `[seed-store]` (vendor folder, offline), `[limits]` (the float limits and the like) and `[build]` (mode and flags).
  Unknown tables and keys are errors, so a typo is not silently a default.
- **Who reads TOML.** The `tomato` front end is a shell script and must not parse TOML in shell. The helper program of
  section 14 prints a setting (`tomato-seed config get limits.exp_bits`), so the front end can pass limits to the compile
  or to the runtime build, and so the float task uses the one reader instead of writing another. If the limits end up
  read by native programs at run time (the other TODO's question), `std/toml.tom` is already available to them.
- **Example** user file:

  ```toml
  # ~/.tomato/config.toml
  [registry]
  default = "tomato"

  [registries.tomato]
  index = "https://tomatoseeds.dev/index.git"   # an example: a candidate domain, not registered

  [aliases]
  json5 = "acme.example/json5"
  ```

## 14. How `tomato seed` is built

The standard library cannot start a process (`std/os.tom` and `std/sys.tom` have no such function), and a Tomato program
cannot run `git` or `ssh-keygen`. Adding one to the runtime would be a C change that must also be built for WebAssembly
(`docs/next-features.md` item 9; the release gate compares `site/wasm/*.wasm` byte for byte). So the work is split:

- **The shell front end** (`native/tomato`, one new `seed)` case in the file that already holds `update` and `test`)
  does everything that needs a process or the network: `git` fetches into the scratch folder, `ssh-keygen -Y` for signing
  and verifying, `curl --proto '=https'` for the well-known files. It never parses TOML and never computes a hash.
- **A helper program in Tomato, `tomato-seed`** (`tools/seed/*.tom`, on `std/toml`, `std/hashlib`, `std/os`, `std/ospath`),
  does everything that is data: reads and writes `tomato.toml` and `tomato.lock`, runs MVS, computes the seed hash of a
  folder, checks a seed, runs `index-check`, prints the module map and settings. The two talk through argv, files and exit
  status; the helper prints *plans* ("fetch this URL at this commit into that folder, expecting this hash") that the front
  end executes, then the helper verifies the result.
- **It is compiled on first use** and cached, keyed by the hash of its source and of the compiler (the same idea as
  `native/rtcache.sh`), so `install-native.sh`, the release scripts and the Mac package do not change. Clang is already
  required to run any program. The compile time of a small tool is not measured here; stage 1 measures it, and if it is
  too slow the helper can ship precompiled by the release instead.
- **Rejected:** all in shell (TOML, semver, hashing and signatures in awk are the kind of code that cannot be tested well);
  a C helper in `runtime/` (a runtime change for tooling, rebuilt for WebAssembly, for no reason); a binary written in another
  language (the project is self-hosted and has no other implementation, `README.md`).
- **An `os.run` in `std`** (run a program with an argument list and no shell, return its status and output) would let the
  helper do all of it in Tomato. It is a standard library API and a runtime change, so it is open question 4.

## 15. Plan

Each stage is one reviewable change with the full test suite green and ships alone. The first three need no registry and
already give a useful local package workflow. Sizes are rough guesses of hand-written lines, not measured.

| stage | content | size (lines) | risk |
| --- | --- | ---: | --- |
| 0 | Davis's direction recorded (**done: D89a** and section 18); he still answers open questions 1 to 11; a short section in `docs/specification.md` when the first stage is built; reserve the `tomato seed` word | 0 | none |
| 1 | `tomato-seed` helper skeleton and `seed check` and `seed hash`: read and validate `tomato.toml`, the naming rule, the seed hash v1 with test vectors cross-checked in shell; no network, no compiler change; measure the helper's first-use compile time | 700 | low |
| 2 | **Compiler**: module map argument, the lookup order, seed names in errors, hidden warnings from seeds, the check against foreign declarations outside `std`; `tomato run` finds `tomato.toml`; works with `path` dependencies by hand-written lock; a test that compiles a seeded program twice and compares the IR | 350 + 300 test | medium: `tomatoc` is regenerated into `compiler/bootstrap/tomatoc.ll` and the wasm files |
| 3 | `tomato.lock`, the store, **`add --git`, `add --path`, `install`, `verify`, `vendor`, `--offline`/`--locked`**, the hardened fetch; no registry yet | 900 + 400 test | medium: git handling and hostile trees |
| 4 | **Index client**: `config.toml`, `policy.toml`, `owners/`, `seeds/` formats, parsing, signature verification through `ssh-keygen -Y`, MVS, `add NAME`, **`add` from the owner's own server (automatic fallback when the index has no entry or is unreachable, and the `--from-owner` and `--index-only` flags; moved up from stage 6: the tap-like path with no registry, section 18.2)**, `registry add`, `update`, `outdated`, `tree`, `why`, `search`, `info`, aliases; tested against a fixture index checked into `tests/` | 1,300 + 600 test | medium |
| 5 | **The registry and its checker, launched at policy level 0**: `index-check` with the rules (proof, signatures, append only, source check, names and skeleton, rate limits, the `policy.toml` notice rule), `claim`, `publish`, `yank`, `endorse`, the policy text as `POLICY.md` and `SECURITY.md` in the index, a `policy.toml` with every requirement off, the first index repository and its acceptor. Endorsements and the acceptor's age stamps are collected from the first day | 1,400 + 700 test | **high**: this is the security-critical program and runs on untrusted input from strangers |
| 5b | **Signals and the ramp machinery (section 18.3 to 18.6)**: the sandboxed runner and its signed `[[result]]` statements, the pure score function with test vectors, the generated `listing.toml` with the shadow score ("would pass level N"), `score`, `admit-check`, `listing-verify`, `only_listed`. **Still gates nothing**: every threshold stays at 0 until Davis raises one (open question 10) | 1,000 + 600 test | **high** for the runner (it runs strangers' code; the sandbox is the work), medium for the rest |
| 6 | Re-root with delay and veto, mirrors, DNS TXT proof; a hosted service that serves the same files, accepts the same signed statements and keeps archives by hash | separate design | medium |
| 7 | The compiler enforces which seeds a module may import; seeds in the playground and the repl through `extra`; in-Tomato ed25519 verification | separate design | medium |

Raising the listing bar (section 18.3) is not a stage: it is a commit to `policy.toml`, made when the signals say so, with its
notice period. Stage 5 ships with the launch policy and 5b makes the data for the first change.

The settings work (section 13) is independent of these stages and can start as soon as stage 1 exists; the float-limits
task is its first user.

Risks stated plainly: the acceptor's source check fetches URLs given by strangers and must run sandboxed with time,
size and network limits (the work of stage 5 is mostly there); the skeleton check's warnings will have false positives (they are only warnings, so nobody is locked out), and the one
refusing form, inside an owner's own names, cannot be appealed by a person, so it must be conservative; the helper depends on `git` and
`ssh-keygen` being present, which the commands check up front with a clear message.

## 16. Alternatives considered

- **Flat global names** (`json5`): rejected by Davis; they invite squatting and force a curator.
- **Host accounts or a registry-granted handle** (`acme/json5`): short and pleasant, but need an authority, which is the
  thing removed (section 1.1).
- **The URL as the name (Go style)**: no authority, but moving a repository renames the seed and names are long; Davis
  dislikes typing them. Domain owners keep Go's best property (the proof is public and re-checkable) with a short
  `owner/name` and a source URL that can move.
- **Semver ranges with a solver**: section 4.
- **Several versions of one seed side by side**: needs a module rename per importer, a language change (open question 3).
- **A central search service**: a clone of the index serves search at this size; a service is stage 6.
- **Seeds as git submodules, or a `vendor` folder only**: no discovery, no immutability check, no update path; vendoring is
  kept as the offline form of the same lock.
- **`basket` as the name of a package**: it fits a bundle better (a workspace of seeds in one repository). Reserved, not
  designed.
- **Native extensions, or seeds that declare `!` functions**: would let a seed run unreviewed C at build; out of scope, and
  the reason `check` rejects them.

## 17. Policies (to be published as `POLICY.md` in the index)

These are the written rules. Most are enforced by the checker, so they do not depend on someone's mood.

1. **No squatting.** Names are scoped by an owner who proved control, so there is no first-come name to take. Claiming an
   owner requires its proof (a domain's well-known file, or a key's own hash with proof of work). A lookalike owner is
   marked and warned about, never refused (a refusal would itself be a first-come squat); within one owner, a name that
   is the same skeleton as one of that owner's own is refused. Placeholder seeds with no
   modules are refused. Owners may not hold more than a stated number of seeds with no published version.
2. **Reclaim.** A seed under a live owner stays with that owner; anyone may fork under their own owner. An owner whose
   domain control moves is re-rooted by the rule in section 1.6 (a pending state, a delay, a veto by the old key), with
   no person involved and with the consumers' locks warning of the key change. A key owner's identity is the key and
   cannot be reclaimed.
3. **Yank, never delete.** A published version stays in the index for ever. An owner may add a `[[yank]]` with a kind and a
   reason; new resolutions skip a yanked version, existing locks keep building with a warning, and a `malware` yank
   stops a build unless told otherwise. The checker rejects any change that removes or edits an existing statement,
   including a yank's removal (an un-yank is a new statement).
4. **Immutable versions.** A version number is published once. Fixing it is a new version.
5. **Honest metadata.** The version entry must equal the seed's own `tomato.toml` at the commit; the checker verifies it.
6. **No secrets, no binaries.** A tree with a file that looks like a private key, or a file that is not text up to the size
   cap, is rejected (the exact rule is stage 5's).
7. **Naming.** Owners and names follow section 1.2: ASCII only, no std names, no confusable collisions.
8. **Changes of rules** are changes to `config.toml`, `policy.toml` and `POLICY.md` in the index, announced there and effective
   for later statements only, never retroactively; a tightening of what listing needs takes effect after a notice period
   and grandfathers what is already listed (section 18.3).
9. **No approval, ever.** No person decides whether a seed is accepted, usable, listed or delisted. A listing requirement is a
   written rule that a program applies to everyone, starts at "structurally valid" (level 0), and is raised only by a public
   `policy.toml` change with notice. Delisting never deletes a seed, never affects a lock, and never stops `owner/name` from
   being used.
10. **Security reports.** The index has a `SECURITY.md` and shows an owner's optional `security` contact; the registry's only
    automatic reaction to a report is the owner's own yank (and the named security keys', if open question 1 is answered that way).

## 18. Open use and the default index: launch open, tighten over time (Davis's direction of 2026-11-26, D89a)

### 18.1 What Davis said, and how it is read

His words, verbatim and typo included:

> I think we will do something like homebrew for seeds like a you can it username/whatever easy not paproval to get a
> full thing with just test you need star recommendations not relay reuirements becouse like fi you adj and your @74 you
> will probaly get acepted

Then, in a clarification: **there are no requirements for the default index to start with (no test requirement, no score
threshold, no star requirement), and requirements are increased over time.**

| Davis's words | Read as | Confidence |
| --- | --- | --- |
| "something like homebrew ... you can it username/whatever easy" | Anyone can use a seed as `owner/name`, at once, from their own git repository on any host, like a Homebrew tap (`brew install user/tap/formula`). | high |
| "not paproval" | **No approval step**, at launch or ever: nobody decides whether a seed may be used or listed. | high |
| "username" | The `owner` part. Owners are a domain or a key (section 1), not a free-text username, because a username table needs an authority; the alias layer (section 1.7) gives the short spelling. | medium: open question 8 |
| "to get a full thing with just test you need star recommendations" | A **later** level of the default index asks for passing tests and for recommendations ("stars") from other people. | high |
| "not relay reuirements" | Those signals are **soft**: they are not hard conditions on their own, and they are switched on later. At launch there is none. | high |
| "fi you adj and your @74 you will probaly get acepted" | I read it as an example: a project with roughly that many stars, or that score, would "probably" be accepted, which is why they are not hard requirements. **Unclear, and not needed now**: every number is a setting in a policy file (below), so none is decided here. It matters only when the first non-zero threshold is chosen (open question 10). | low |

So there are **two things**, and the design keeps them apart:

| | **Usable** (open) | **Listed** (the default index's listing) |
| --- | --- | --- |
| What it is | `tomato seed add owner/name` works | the seed appears in the default index's listing (search, `outdated` notes, the optional `only_listed` filter) |
| Approval | none, ever | none, ever: an automatic rule only |
| Condition at launch | the structural checks of section 1.5 (valid manifest, resolvable source, owner proof, name rules, no collisions, rate limits) | the same: **nothing more** |
| Condition later | unchanged | raised step by step by a policy file (section 18.3) |
| Who can use it | everyone, with no registry at all if the owner serves the statements (section 18.2) | everyone |

The line that matters for Davis's model: **raising the bar for listing never stops anyone from using `owner/name`.** A seed
that is not (or is no longer) listed is still usable, locks that contain it still build, and only discovery changes.

### 18.2 Using a seed with no approval (the tap-like path)

There is **no `tomato seed tap` command**: a tap exists in Homebrew because formulae live in separate repositories; a
seed's statements already name its own repository and are verified by the owner's key, so adding a source is not a
separate act. `tomato seed add owner/name` resolves in this order and says which one answered:

1. **The default index** (the user's `[registry] default`): the seed's file under `seeds/owner/`. This is "usable" by the
   structural rule of section 1.5, accepted within seconds of the owner sending the change, with no review.
2. **The owner's own server**, for a **domain** owner, **automatically only when** the default index has no entry for that
   exact `owner/name` or cannot be reached (an index that has the entry always wins, so the index's order and revocations
   are used when it has them). It is the same seed identity checked by the same owner key, not another registry, so it
   does not break "never mixes registries"; the summary line says it answered, and `--index-only` turns the fallback off.
   `--from-owner` (section 12) **forces** this path even when the index has an entry, for someone who does not want to use
   the index at all. The address:
   `https://DOMAIN/.well-known/tomato-seeds/NAME.toml` (section 9), with the same signature checks. This needs **no registry
   at all** and no submission step: put the signed file on your own website and `tomato seed add your.example/thing` works
   for everyone. It is verified for signatures but not for history (section 1.5, "Which time counts"), and the summary line
   says "from the owner directly, not in the index". It is moved up from stage 6 to stage 4 for this reason.
3. **Another index**, which is the real analogue of adding a tap: `tomato seed registry add NAME URL` puts a
   `[registries.NAME]` entry in the user's configuration (a company's index, a friend's, a mirror), and a seed is added
   from it with `--registry NAME`. Resolution never mixes registries behind the user's back (section 9).
4. **A git URL**, `--git`: the unregistered escape hatch (section 12), unchanged.

The summary line of `add` gains the status and the policy level:

```
acme.example/json5 1.2.0  signed by acme.example (key SHA256:Qn3...), first seen 2026-12-01, 4 versions, similar to: none
status: listed (policy level 0: structural checks only), 2 endorsements, no test result yet
```

### 18.3 The ramp: a versioned policy file, tightened over time

The index holds **`policy.toml`**, the one file that says what listing requires. It is data, not code, so raising the bar
is a change to numbers in a file, with no change to the checker or to any seed. At launch it is level 0:

```toml
# policy.toml (version 1: the launch policy, nothing required)
version = 1
notice_days = 60              # a tightening takes effect this long after it is committed (enforced by index-check)

[listing]                     # what a seed needs to be listed; every value here is "off"
require_tests_pass = false    # the newest stable version's tests pass in the sandbox runner (section 18.4)
min_tests_per_module = 0
min_age_days = 0              # days since the seed's first accepted version
min_score = 0                 # 0..100, section 18.5
require_license = false

[demotion]                    # re-checking seeds that are already listed
enabled = false
grace_days = 90

# A scheduled change is announced in the file before it applies:
# [[change]]
# effective = 2027-06-01
# set = { "listing.require_tests_pass" = true }
```

**Rules for changing it** (all checked by `index-check`, so nobody has to be trusted to remember them):

- A change that **tightens** anything (turns a requirement on, raises a number, enables demotion) must be committed at
  least `notice_days` before its `effective` date. A change that **loosens** takes effect at once.
- A tightening applies to **new listings** from the effective date. A seed already listed is **grandfathered** at the
  policy version it was listed under (`listed_under = N` in the generated listing) and is not re-examined.
- **Re-examining listed seeds is a separate switch** (`[demotion] enabled`), announced with its own notice and used last. When
  it is on, a seed below the current bar gets a visible **notice** (`below policy since DATE, delisted on DATE + grace_days
  unless it passes`), the owner can fix it in the meantime, and at the end it is **delisted**: flagged in the listing,
  never deleted. A seed that later meets the bar is listed again with no one's decision.
- **Nothing here touches a lock.** `tomato.lock` does not record the status (section 3), `install --locked` and
  `verify` do not look at it, and an `owner/name` requirement still resolves to every non-deleted version entry. The only
  people affected by a delisting are those who set `[registry] only_listed = true` (section 13), and `outdated` tells
  them.
- **Who may edit `policy.toml`** is open question 9. The honest statement: it is the one lever a person holds. It can change
  the rules **for everyone** and cannot approve, refuse, list or delist one named seed, and every change is a public commit
  with a notice period.

**The ramp** (a proposal; the numbers and the order are Davis's, open question 10). Each step is a new `policy.toml` version,
made only when the signals of section 18.4 say that the existing seeds would mostly pass it:

| Level | Listing asks for | Soft or hard | Raise it when |
| ---: | --- | --- | --- |
| 0 (launch) | the structural checks only | hard (they are the rules of section 1.5) | |
| 1 | a license, and the newest stable version's tests pass (at least one `@test` per module) | hard, for new listings | at least 80% of listed seeds already would pass |
| 2 | level 1 **and** a score of at least 40 (section 18.5): documentation, age, metadata and endorsements add to the tests, and no single part is required (a seed with no endorsement can reach 70) | hard conjunction of level 1 and a soft score; each level only adds conditions | the score distribution has been public for 60 days |
| 3 | level 1 **and** a score of at least 60; demotion enabled | soft for new, with notice for old | last, after a full cycle of notices |

Whether 74 is a score, a number of stars, or an example matters only at the step where a first non-zero threshold is
picked; until then every value is 0 or off.

### 18.4 Signals collected from day one

So that the later requirements are set from data and not guessed, these are recorded from the first release of the registry
(or, for tests, from stage 5b), **and none of them gates anything at level 0**:

| Signal | How it is collected | Available from |
| --- | --- | --- |
| **Age and history** | the acceptor's `accepted` stamp on each statement (section 1.5); number of versions; time between versions | stage 5 |
| **Endorsements ("stars")** | signed `[[endorse]]` statements (section 18.6), accepted and stored from the start | stage 5 |
| **Test results** | the **runner** (below) runs `tomato test` for the newest version of each seed and appends a signed `[[result]]` (status, number of tests, compiler version, platform, time taken); three runs, all must pass | stage 5b |
| **Shadow score** | the pure scoring function of section 18.5 is run over every seed and its value and "would pass level N" are written into the generated `listing.toml`, so the effect of a threshold is visible **before** it is set | stage 5b |
| **Yanks and reports** | the `[[yank]]` statements already in the index, by kind | stage 5 |
| **Not collected** | downloads, installs, who uses which seed, any telemetry: there is no central service to hold it, and the design should not grow one for this | |

**The runner** is a separate program run by anyone with the index clone and a sandbox, not part of the acceptor: it reads
the index, fetches each seed **by content hash** outside the sandbox, runs its tests **inside** one, and pushes `[[result]]`
statements signed by a runner key listed in `config.toml` (a key that can only append under `results/`). It may run in a
CI job on any git host, a cron job on any machine, or several of them. The sandbox is an operating-system one (a
container, `bwrap`, a throwaway virtual machine), because the language has none: no network, a read-only file system
except a temporary folder, no credentials in the environment, an unprivileged user, a time limit (five minutes), a memory
limit and a process limit. Tests that need the network fail, and the policy says tests must be hermetic. **The acceptor of
section 1.5 still never runs a seed's code** (section 11); the runner is the only place where stranger-written code runs,
and only for the signals above. Anyone can reproduce a result with `tomato seed admit-check owner/name VERSION` on their
own machine (it runs the seed's tests, which is code from the seed: use a sandbox), and `tomato seed listing-verify`
recomputes `listing.toml` from the index files without running anything.

### 18.5 The score (the later, soft tier)

A transparent score from 0 to 100, computed by a pure function over the index files (so it is reproducible and has test
vectors), shown by `tomato seed score owner/name` with every line of the breakdown. A proposal, to be tuned with the
signals of section 18.4:

| Part | Points | Measured by |
| --- | ---: | --- |
| Tests | 20 | a passing result; more points for more `@test` functions per module, up to 3 per module |
| Documentation | 20 | a `README.md` (10) whose fenced `tomato` examples compile (10, compiled, never run) |
| Age and stability | 20 | first version at least 30 days old (10), a version at 1.0.0 or later (5), at least 3 versions (5) |
| Endorsements | 30 | section 18.6; the points cannot pass the structural rules or the tests on their own |
| Metadata | 10 | license present, description present, `tomato` matching what the tests ran on |

Without a single endorsement the most a seed can reach is 70, so a threshold at or below 70 never *requires* a star; that is
"soft". Endorsements move a seed with weaker documentation or less age over the line (the tests stay a separate condition from level 1 on). A threshold above 70 (for example, if 74
meant a score) would make at least one endorsement necessary, which is a different, harder rule and should be chosen
knowingly.

### 18.6 Endorsements ("stars") without an account system

There is no account to star from. An endorsement is a **signed statement by an owner's key**, like everything else:

```toml
# endorsements/dave.example.toml  (the endorser's file; append only, like all index files)
[[endorse]]
seed = "acme.example/json5"
signed_by = "SHA256:..."
signature = "..."

[[unendorse]]          # a withdrawal is a new statement, never an edit
seed = "acme.example/json5"
signed_by = "SHA256:..."
signature = "..."
```

`tomato seed endorse owner/name` and `unendorse` write them; any key owner or domain owner can send one, so a person who
only wants to recommend a seed makes a key (`tomato seed claim --key`, a few seconds of proof of work) and does that.
The weight of an endorser is computed from the index files, never stated by anyone:

- Counted once per endorser per seed, only while it is not withdrawn, and only while the endorser's key is valid (a
  revoked key's earlier endorsements keep counting if they precede the revocation, as in section 1.6).
- **Eligible endorser:** at least 30 days old (by the acceptor's stamp); not the seed's own owner and not an owner whose
  domain is a subdomain of it or the other way round; not holding more than 25 active endorsements (so a farm of keys cannot
  endorse everything cheaply).
- **Weight:** a domain owner counts 1, a key owner 0.25 (keys are free, domains cost money). Two owners who endorse each other
  count half each. An owner with a `malware` yank against it counts zero.
- **Points:** `min(30, round(10 * log2(1 + total weight)))`: a total weight of 7 saturates, so the first few matter and the
  hundredth does not.

Abuse and Sybil resistance, honestly:

| Attack | Cost to the attacker | What it gains | Left over |
| --- | --- | --- | --- |
| Many keys endorse one seed | PoW per key, the daily cap on new key owners, a 30-day wait, weight 0.25 each | a few points | needs about 28 keys for a full 30 points |
| Many domains endorse one seed | about 7 real domains and a month | the full 30 points | a few tens of dollars a year: **this is the real hole** |
| A ring of mutual endorsements | the same | half weight | still possible, only less |
| Endorsement of a good seed by a bad actor | none | nothing: it is a vote for a seed | |
| Endorsements as a way to bury a seed | none: there is no negative vote | | |

The result: **endorsements are cheap to fake by someone who spends a little money, and the design assumes that.** They are
capped at 30 points, they can never replace the structural checks (or, once required, the tests), and the listing never
says a seed is safe, only "listed at level N, with this score and these signals". There is no way to make stars
trustworthy without an account system or a person; the cap is what bounds the harm.

### 18.7 What launching with no requirements costs

| Risk | At level 0 | What stays from day one | What is left |
| --- | --- | --- | --- |
| **Malware** | anyone can list a seed that does harm; "listed" means "structurally valid" and nothing more | no code runs at fetch or install (section 8); **hash pins**, so a bad version cannot replace a good one; signatures; **yank by the owner's key** (kind `malware` stops builds, section 4); immutable versions; a **security contact** (below); the language-level rule that a seed has no `!` functions (section 5) | a malicious owner who does not yank their own seed. **Without a human power (open question 1) the registry cannot remove one; only the owner can.** Say this to users |
| **Squatting and typosquatting** | no name can be squatted inside an owner; lookalike *owners* are allowed | the warn-only skeleton rule, first-seen date and age shown at `add`, the full name stored once (section 1.8); the daily caps and PoW for key owners | a user who types a lookalike owner and does not read the line. Unchanged from section 1.8, and a listing at level 0 gives no extra signal |
| **Abandoned and junk seeds** | nothing is removed or flagged; search fills with unmaintained work | rate limits and per-owner caps; `outdated` shows the last-publish date; the signals of section 18.4, so a later level can sort and filter on facts | search is poor at first. Mitigation without ranking power: default sort by endorsement weight, then by number of versions, shown with the numbers; `only_listed` becomes useful only at level 1 |
| **Flooding** | a script can fill the index with valid seeds | per-owner and per-day caps; key owners are limited separately; every statement is a small text file | an attacker who buys domains pays for it |
| **A weak "default" meaning** | users may take "listed" for "trusted" | the summary line says `policy level 0: structural checks only` | |

**Minimal safeguards that never wait for a later level:** hash pinning and the lock; signatures and the owner proof; no
code at install; the structural checks of section 11; yank by the owner's key (and, if Davis agrees, by named security keys,
open question 1); and a **security contact**: `SECURITY.md` in the index, plus an optional `security = "..."` (an email or
a URL) that an owner may put in `[seed]`, shown by `tomato seed info`. A report goes to that contact; the registry itself
has no staff queue to wait on, so the only action it can take automatically is the yank rule above.

### 18.8 Names under zero approval

- **Owner scoped names do not need it** (section 1): `acme.example/json5` is only ever claimable by the owner.
- **At level 0 nothing new:** listing is the same set as usable seeds, so no listing rule can refuse or reorder a name.
- **When listing has requirements (levels 1 and up), a contested name** needs one deterministic rule: two seeds with the same
  name under lookalike owners (equal skeleton or edit distance 1, section 1.8) and both eligible: the one with at least 10
  more points of endorsement is listed and the other stays usable but unlisted; with a smaller difference **neither**
  is listed. The rule can be griefed (register a lookalike and leave both unlisted) for the price of a domain, and
  that is accepted because the damaged party remains usable and the owner can win the contest with real endorsements.
  An owner can never be *blocked from use*, which is the property of section 1.8 that has to be kept.
- **No bare names.** A listing, like the index, never resolves a bare name (section 1.7). Whether it should (like
  homebrew-core's `brew install wget`) is open question 7.

### 18.9 What changes in the other sections

- Section 1.5's acceptor is exactly the level-0 admission; nothing in it is removed. Section 11's last paragraph is
  kept: the acceptor never runs seed code, and the runner of 18.4 is the only thing that does.
- `index-check` additionally checks `policy.toml` changes (the notice rule) and accepts `[[endorse]]`, `[[unendorse]]` and the
  runner's `[[result]]` statements under the same signed, append-only rules.
- New files in the index: `policy.toml`, `endorsements/<owner>.toml`, `results/<owner>/<name>.toml`, and the **generated**
  `listing.toml` (status, score, `listed_under`, notices; rebuilt by the program, never edited by hand, and verifiable with
  `tomato seed listing-verify`).
- New commands: `tomato seed endorse|unendorse`, `score`, `admit-check`, `listing-verify`, `registry add`; `add` shows the
  status line; `search` shows the listing and the numbers behind it (`--all` includes unlisted seeds).
- New setting in the user's configuration: `[registry] only_listed = false`. It is a user preference only: a project's
  `tomato.toml` cannot set it, so a seed cannot make a user's tool stricter or looser.

## 19. Open questions for Davis

1. **Does the registry keep any human power at all, even yank-only?** Everything routine is automatic, but nobody
   could remove a seed that is malware, illegal or leaking secrets from a registry I host, except by the owner's own
   yank. *Recommended: automatic for every routine step, plus a narrow emergency power held by a small set of named
   security keys listed in `config.toml`: they can add a `malware` or `legal` yank to any version (never delete, edit,
   or approve), the yank is public and signed, and a client can decline them with a setting.* It needs no approval of
   anything a publisher does.
2. **Are key-only owners (`k-...`) accepted into the shared registry**, or only domain owners, with key owners limited to
   direct `--git` adds? Domains cost money, which is a natural brake on flooding; keys are free and need a
   proof-of-work and a daily cap. *Recommended: accept both: some authors have no domain and the cost of the rules
   is small, and show every key owner as unverified.*
3. **How do `.tom` files name a seed?** *Recommended: no language change for now: import the module (`from json5 import
   parse`), made unique by the rule "a seed provides only `name` and `name_*`", with a clear error when two owners'
   same-named seeds meet.* The alternatives are new syntax (`from acme.example/json5 import parse`, `import ... as j`),
   which decides D24b and D24c, and per-importer module renaming, which allows two majors of a seed in one program.
   Choose them together later, not in this design.
4. **Does `std` get a way to run a program** (`os.run(args) -> (status, output)`, no shell), or does `tomato seed` stay a
   shell front end plus a Tomato helper? *Recommended: keep the split for the first stages (no runtime or WebAssembly
   change, ships soonest), and decide `os.run` on its own merits; it would make a version of the helper in pure Tomato
   possible later.*
5. **May `tomato run` ever fetch?** This design says no: `run` and `build` use only the lock and the store, and say
   `tomato seed install` when something is missing. *Recommended: keep it, because it keeps "download" and "run code" as
   two decisions; a `[seed-store] auto_install = true` setting can be added for people who want the other way.*
6. **Is the split "usable (`owner/name`, always, no approval) versus listed (the default index's listing, with a bar that
   rises over time)" what you meant?** It is how this document reconciles "easy, no approval" with "requirements increased over
   time". *Recommended: yes. Raising the bar then only ever changes discovery, never whether a seed can be used or a lock
   builds (section 18.1).*
7. **Should a listed seed get a bare name** (`tomato seed add json5`, like `brew install wget`)? It would make listing a
   first-come namespace again, the thing owner-scoped names avoid (section 1.7). *Recommended: no, not in this design. Keep
   `owner/name` plus aliases; if you want bare names later, give a bare name to the listed seed with the highest score, never
   by first come, and decide it with the squatting analysis in front of you.*
8. **Is "username" a domain or key owner, or do you want short handles** (`dave/thing`)? A handle table needs someone to hand
   them out (section 1.1). *Recommended: keep domain and key owners and the alias layer; short handles can be added later as
   an alias layer the index publishes, not as identity.*
9. **Who may edit `policy.toml`?** It sets the rules for everyone and can never touch one named seed (section 18.3).
   *Recommended: a small set of named policy keys in `config.toml` (yours first), a public commit for every change, and the
   checker's notice rule (60 days to tighten, none to loosen), so even those keys cannot surprise anyone.*
10. **The ramp: what is level 1, and when is it raised?** And does "@74" still matter, as a score or a count of stars?
    *Recommended: level 0 until the signals of section 18.4 have been collected for about six months and at least 80% of
    listed seeds would pass level 1; level 1 is "a license and passing tests"; stars enter as points at level 2, never as a
    condition; demotion last. Pick the first non-zero number only when the shadow score shows what it would do.*
11. **Do key owners' endorsements count** (weight 0.25 in section 18.6), or only domain owners'? Keys are free and
    make Sybil attacks cheaper; domains exclude ordinary users from recommending. *Recommended: count keys at 0.25 with
    the 25-endorsement cap, and revisit when the data shows abuse.*
