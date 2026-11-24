# Locks for Tomato: a design for Davis to review

Status: **proposal, nothing decided, nothing implemented.** Davis decides every API and language rule; each numbered decision in section 9 needs his answer before a builder starts. Written against `main` at `3b1ea879`. Evidence marks: `[V]` I read it in this repo (file and line given where it matters); `[I]` inferred. I ran nothing (no program, test or build); every `[V]` is about source text.

Coordination: the *Async toolkit and sockets* task (`tskgHjcVrXs7re`) is building `Queue[T]`, `gather` and `wait_for` (Davis approved those three only). Its plan: a FIFO `Queue` that parks the task in a scheduler wait, cancellation unlinking the frame before queuing it to resume, no shielding, no `t.cancelled()`, a timeout cancels and joins the target and raises `asyncio.TimeoutError`; its exact waiter data structure is still open. This design reuses that parking mechanism and does not change anything it chose. `Lock` and friends are **not yet approved**; they should land after, and on top of, the Queue's wait.

---

## 1. What a lock means in Tomato (and when you need one)

Tasks are cooperative on one thread and switch only at an `await` that is not ready or a `yield` `[V]` (D51b, `docs/decisions.md:1333`). So there are no data races, and **a stretch of code with no `await` in it needs no lock** (this is already how `std/cache.tom` documents itself: "no cache method awaits, so a cache can be shared by async tasks without a lock" `[V]`).

A lock is needed only when a critical section **contains an `await`**, because another task can then run in the middle and see half-updated state:

```
# without a lock, two tasks both pass the check and both write
async def deposit(acct: Account, n: int):
    balance = acct.balance
    await sleep(0.1)            # another task runs here
    acct.balance = balance + n  # lost update
```

Typical uses: serialising writes to one socket or file (a half-sent message must not interleave with another), a connection pool, "only one refresh of this cache entry at a time", rate limiting (semaphore). So the lock's job is to **make one task wait while another is suspended inside a section**, which is exactly a scheduler wait, not a CPU concern. The same thing is why a pure-Tomato version built on `await sleep(0)` polling is the wrong foundation (section 6).

Threads are deferred (D31a/D31b `[V]`). Everything here is for tasks. I name the module accordingly so a future thread library can have its own `Lock` without a clash (section 9, decision 1).

## 2. API (proposal)

Module `asyncio` (the name Davis's `wait_for` task already uses for `asyncio.TimeoutError` `[V from the async task's message]`; decision 1 below). All of it is ordinary Tomato in `std/asyncio.tom`, written on one runtime primitive (section 6).

```
from asyncio import Lock

class Lock:
    @init def make(self)
    def locked(self) -> bool                  # True while some task holds it
    def waiting(self) -> int                  # how many tasks are queued for it
    async def acquire(self)                   # wait (FIFO) until it is ours
    def try_acquire(self) -> bool             # take it now if free and nobody queued; never waits
    def release(self)                         # give it up; raises LockError if not held
```

`release` is a plain `def`, not `async`: it never waits, and a `finally` block must be able to call it with no ceremony. `acquire` is `async def`, so forgetting `await` is the existing compile error with its fix hint (D51a `[V]`).

The only v1 idiom, since Tomato has no `with` and no closures `[V]` (`docs/next-features.md:17`):

```
await lock.acquire()
try:
    ...                      # may await; other tasks that want the lock queue behind us
finally:
    lock.release()
```

`LockError(RuntimeError)` is the new error (id `lock-error`, following P88's id scheme `[V]` `docs/provisional.md:96`). It is raised by `release()` on a lock that is not held, and by nothing else.

### Companions (same wait primitive, same rules)

```
class Semaphore:
    @init def make(self, value: int = 1)      # value < 0 -> ValueError
    def locked(self) -> bool                  # True when value == 0
    async def acquire(self)
    def try_acquire(self) -> bool
    def release(self)                         # more releases than acquires -> LockError ("bounded", like Python's BoundedSemaphore)

class Event:
    @init def make(self)
    def is_set(self) -> bool
    def set(self)                             # wakes every waiter, FIFO; later waits return at once
    def clear(self)
    async def wait(self)
```

`Condition(lock)` (`wait`, `notify`, `notify_all`) is deferred to a later wave: it needs the cancellation-while-reacquiring rule in section 5 and no concrete user exists yet. A read-write lock is **not proposed**.

`Semaphore` is bounded by default (unlike Python's plain `Semaphore`, like its `BoundedSemaphore`) because an extra `release` is almost always a bug, and `Lock` = `Semaphore(1)` plus the same bounded check, so one shared implementation can serve both (decision 3).

## 3. Semantics

1. **Non-reentrant, no owner.** A task that holds the lock and acquires again waits for itself forever. `Lock` does **not** record who holds it, and `release()` may be called from any task (this is Python's `asyncio.Lock`). Why not track the owner and raise `LockError("already held by this task")`: an `await helper()` runs `helper` as its own task (its own frame) at once `[V]` (D51a), so the caller and the code it awaits are different tasks, and a lock taken before the call and released inside it (or the reverse) is a normal, legal pattern. Frame identity is not the programmer's idea of "who". Owner tracking would raise false errors. Cost: a self-deadlock is not diagnosed specially; it is reported by the existing "every task is waiting for something that can no longer happen" stop (D51b `[V]`), which section 8 proposes naming the lock in.
2. **FIFO, with direct hand-off, no barging.** Waiters are served in the order they asked, matching D51b ("served in the order they asked") and D58c (ties in the order they went to sleep) `[V]`, so output order never depends on timing. When `release()` is called and someone is queued, the lock **stays locked** and ownership passes straight to the first waiter, which is made ready (it runs when the releaser next waits, in ready order, D51b). A task that calls `acquire()` after that, before the waiter has run, **queues behind** it; `try_acquire()` returns `False` (a lock with waiters is never "free"). This is deterministic and starvation-free; it costs one extra task switch per contended release compared to a "wake and race" lock.
3. **`acquire()` on a free, unqueued lock does not yield.** It takes the lock and returns without switching tasks, exactly as `await f()` runs `f` at once. So an uncontended `acquire`/`release` pair is cheap and **does not give a cancellation a place to land** (cancel is observed "at its next wait", D58d `[V]`, `docs/decisions.md:1366`).
4. **`release()` never switches tasks.** The woken waiter runs when the releaser next awaits, yields, or finishes.
5. **`waiting()` and `locked()` are snapshots**, for diagnostics and tests, not for deciding to skip the lock (a check-then-acquire across an `await` is the race the lock exists to prevent; within no-await code it is fine).

### Example with its output order (deterministic)

```
lock = Lock()

async def worker(name: str):
    await lock.acquire()
    try:
        print(name, 'in')
        await sleep(1)
        print(name, 'out')
    finally:
        lock.release()

@main
async def main():
    a = start worker('a')
    b = start worker('b')
    c = start worker('c')
    await a; await b; await c
```

Prints `a in`, `a out`, `b in`, `b out`, `c in`, `c out`, on every machine, natively and in the browser (the logical clock of D58c `[V]` makes the sleeps order-stable).

## 4. Interaction with cancellation (the heart of it)

Facts from the runtime `[V]` (`runtime/tomato_rt.c:2527-2573`): `t.cancel()` sets a bit in the frame header and, if the task is parked, **unlinks it from whatever it waits in** (the sleeper queue, the input queue, curl, or the waiter list of the task it awaits, found through the field at frame offset 80) and makes it ready; the task then raises `CancelledError` at the first check after resuming. `finally` blocks run; the task may catch the error and carry on. Cancelling a finished task does nothing.

Rules for locks, each with the reason:

| Situation | Behaviour | Why |
|---|---|---|
| Task cancelled **while queued in `acquire`** | It is removed from the lock's wait queue, raises `CancelledError` out of `acquire`, and **does not hold the lock**. Nobody else is affected. | The lock must never be held by a task that thinks it failed to get it. |
| Task cancelled **after the lock was handed to it but before it ran** (the hand-off race) | When the task resumes inside `acquire` and sees the cancellation, `acquire` **passes the lock on** (`self.release()`) and then re-raises `CancelledError`. | Hand-off (rule 2) made it the owner while it was only *ready*, not running. Without this rule the lock would stay locked forever. This is the one subtle rule; it needs a test. |
| Holder cancelled **while inside the section** (awaiting something) | `CancelledError` is raised at its wait, the `finally` runs `release()`, the next waiter is woken. | The documented idiom handles it; no special lock code. |
| Holder cancelled **without a `finally`** (idiom not followed) | The lock stays held. | No owner is recorded (rule 1), so the lock cannot know. It is a bug in the program, the same as in Python. Section 8 offers a debugging aid. |
| `t.cancel()` on a task waiting in `acquire` that is awaited by another (`await t`) | Cancels only `t` (D58d: "cancelling a task that waits for another task cancels only the waiter") `[V]`. `await t` then raises `CancelledError`. | Unchanged. |
| `wait_for(t, secs)` where `t` is blocked in `acquire` | On timeout the toolkit cancels and joins `t`, then raises `TimeoutError` (the async task's plan). `t` leaves the queue by the first row. | Gives lock timeouts for free with no `timeout=` argument on `acquire` (decision 4). |
| `acquire()` called by a task whose cancel flag is already set but that has not yet reached a wait | The lock is taken (rule 3, no yield) and the error is raised at the task's next wait; the `finally` releases it. | Consistent with D58d's "at its next wait". |

Why not "shielding" or making `acquire` uncancellable: the async task explicitly excluded shielding, and an uncancellable wait would make a stuck lock immortal (the task could never be cancelled out of it).

## 5. The lock-in-a-cancelled-condition problem (Condition, deferred)

`Condition.wait()` releases its lock, waits for a notify, then reacquires. If cancelled while *reacquiring*, Python still reacquires before raising, so the caller's `finally` can release a lock it really holds. If that is wanted here, `wait` must catch the cancellation, finish reacquiring, and re-raise. That is one more thing the same re-raise capability (section 6) has to support, which is why `Condition` waits until `Lock`, `Semaphore` and `Event` have shipped and been used.

## 6. Implementation outline (not for building until approved)

**One runtime primitive, everything else in Tomato.** The shared dependency with the Queue work is "park the current task on a list of waiters, and let the scheduler wake one or all in FIFO order, with cancellation unlinking the frame":

- the runtime already has a waiter list on task frames: a `PtrVec` at frame offset 40, a frame added with `tomato_task_wait`, woken by `tomato_wake_waiters`, and cancellation removing a parked frame from it using the "what it waits for" field at offset 80 `[V]` (`runtime/tomato_rt.c:2125-2146, 2539-2565`). The Queue plans a scheduler wait with the same unlink-before-resume behaviour.
- I propose the primitive be exposed to Tomato library code as one small built-in object, a **one-shot signal** (`Signal`): `await sig.wait()` parks the task; `sig.fire()` wakes every parked task (FIFO) and stays fired; a cancelled waiter is removed from the signal's list. A signal can reuse a task frame's existing waiter-list layout, so `tomato_task_cancel`'s unlink loop works unchanged (the same loop already handles "waiters of another task").
- `Lock` keeps a FIFO list of `Signal`s, one per queued task, plus a held flag. `release()` fires the first signal and leaves `held = True`; the cancellation rule in section 4 is a `try`/`catch CancelledError` inside `acquire` that calls `release()` if its own signal had fired, then re-raises. `Semaphore` holds a counter plus the same list; `Event` is one signal plus a flag.
- This needs one language capability: **re-raise the caught error** from a `catch`. The error docs list `raise` (`docs/errors.md`); whether a bare re-raise of the caught `CancelledError` works must be checked by the builder before relying on it (`[I]`, not verified here). If it does not, `finally`-with-a-flag expresses the same thing.

**Why not poll with `await sleep(0)`** (the cheap Sonnet-only option in `docs/next-features.md` item 8 `[V]`): a loop of ready-again tasks (1) busy-spins forever instead of reaching the "every task is waiting" stop, so a deadlock is a hang not an error; (2) prevents the logical clock of D58c from advancing while a lock waiter spins (the clock moves only when nothing is ready), so a `sleep` inside the holder never finishes and the program deadlocks; (3) has no FIFO fairness. It is therefore not an acceptable lock, not just a slower one.

**Performance** `[I]`: uncontended `acquire`/`release` are two Tomato method calls and a flag, no scheduler involvement and no allocation; a contended acquire allocates one `Signal` and one queue entry. Reference counts: a queued `Signal` is held by the lock's list and by the waiting frame; both drop on wake or cancellation (the leak the existing task-waiter fix addressed `[V]` `TODO.md`), so the builder adds the cancel-while-queued and hand-off-then-cancel cases to the leak tests.

**wasm**: the scheduler is shared, so locks work in the browser playground and under the logical clock (decided by the existing scheduler design `[I]`).

## 7. Alternatives considered

| Option | Decision | Reason |
|---|---|---|
| **A. `Lock` class + `acquire/try/finally/release` (proposed)** | recommended | Needs no new syntax, matches Python's `asyncio.Lock`, and the idiom is explicit. |
| B. `async with lock:` (a `with` statement) | not proposed here, but see decision 5 | Removes the one real way to misuse a lock (forgetting the `finally`). It is a language feature (open question about `with` and resource cleanup `[V]` `docs/next-features.md:17,202`); it would give classes `@enter`/`@exit` hooks, and it would also help files and sockets. If Davis wants `with` for those, `Lock` should use it too; adding it later does not break this API. |
| C. Owner-tracked, reentrant lock | rejected | An `await helper()` is a different task from its caller (D51a), so ownership by frame is not what a programmer means; false errors. |
| D. Lock built on `sleep(0)` polling | rejected | Section 6. |
| E. A callback style `lock.run(fn)` | impossible | No closures; bound methods and generic functions cannot be values `[V]` (`docs/decisions.md:1518`). |
| F. Lock auto-released when the holder task finishes | rejected for v1 | Needs an owner (C), and hides bugs; a debugging report (section 8) gets most of the value. |

## 8. Diagnostics (cheap, optional)

- When the program stops with "every task is waiting for something that can no longer happen" and any of those tasks is queued on a lock, add a line per lock: "task N is waiting for a lock held since line L" (the lock may record the line of the last acquire; one `int`). Self-deadlock and forgotten `release()` are the two commonest lock bugs, and this turns both from a silent stop into a pointer.
- A lock still held when the program ends could be reported the same way the end-of-program unread-error rule works (D58a `[V]`): a note on stderr, exit code unchanged. Marked optional; Davis may find it noisy.

## 9. Decisions for Davis (what blocks building)

Each has my recommendation first.

1. **Module and names.** Put `Lock`, `Semaphore`, `Event`, `LockError` in `asyncio` next to `Queue`/`gather`/`wait_for`. Alternative: a `sync` module. I recommend `asyncio` (one import for everything async, a future thread `Lock` lives in `threading`).
2. **Scope of v1.** `Lock`, `Semaphore`, `Event` now; `Condition` later; read-write lock not proposed. (Or `Lock` only.)
3. **Semantics:** non-reentrant, no owner, FIFO with direct hand-off, uncontended acquire does not yield, `Semaphore` bounded. Alternative: owner-tracked (section 7 C) or wake-and-race.
4. **Timeouts.** No `timeout=` parameter on `acquire`; use `wait_for(start lock.acquire(), secs)` (section 4). Alternative: add `acquire(timeout=...)` as sugar later.
5. **`with` statement.** Should Tomato get `async with lock:` (a separate language decision that also covers files and sockets), or stay with `try/finally` for now? I recommend `try/finally` now and asking about `with` separately, because it is a bigger design and does not block locks.
6. **Re-raise in `catch`.** Confirm bare re-raise works (builder check, no decision needed unless it does not).
7. **Diagnostics (section 8).** Include the "waiting for a lock" line in the deadlock stop? Include the held-at-exit note? I recommend yes for the first, no for the second.
8. **Ordering with the async task.** Lock/Semaphore/Event should be built **after** the Queue, reusing its waiter primitive and its cancellation unlink. I recommend a single owner for the scheduler change so `Queue` and `Signal` do not diverge.

## 10. Test plan (for the builder)

Each as a `tests/programs/*.tom` with expected output, plus the leak check:

1. FIFO order of three workers (the example in section 3).
2. A task cancelled while queued: the lock goes to the next waiter; the cancelled task does not hold it.
3. The hand-off race: A holds; B queued; A releases (B is ready, owner); B cancelled before running; C queued behind; C must get the lock.
4. Holder cancelled mid-section with `finally`: next waiter runs.
5. `release()` on an unheld lock raises `LockError`; `try_acquire` on a lock with waiters is `False`.
6. `wait_for(start lock.acquire(), 0.5)` on a held lock times out with `TimeoutError`, the lock still held by its owner, no waiter left.
7. Self-deadlock produces the "every task is waiting" stop (and the section 8 line if adopted).
8. `Semaphore(2)` admits two, queues the third, a third `release` above the initial count raises `LockError`; `Event.set` wakes all waiters FIFO.
9. The same programs in the browser (wasm) interpreter.
10. The leak check on every cancelled-while-queued and hand-off-then-cancel path.
