# Messages between tasks: RisBoard

The rules are TAPE_SPEC 5.2 and 5.6. RisBoard copies Goose's typed
queues (doc/reference/goose/docs/goose_spec.md §11.2), a statically
typed cousin of Linda's tuple space: one shared board, one queue per
message type, owned by no task.

## Operations

| ris | Goose | Meaning |
|---|---|---|
| `RisBoard.post(v) : Bool` | `qput(v)` | copy in, never waits; false if full |
| `RisBoard.take(T) : T` | `qget<T>()` | take one; wait while empty |
| `RisBoard.take(T, ms)` | `qget<T>(ms)` | `{T?, Bool}`; ms <= 0 polls |
| `RisBoard.poll(T)` | `qpoll<T>()` | `{T?, Bool}`; never waits |
| `RisBoard.limit(T, n)` | `qlimit<T>(n)` | count limit, n >= 1 |

Each message goes to exactly one taker. Distinct roles are distinct
nominal types: `struct Job`, `struct Result`, `struct Quit`.

## Where ris differs from Goose

* Tasks are iyi fibers in groups, not detached native threads; parallel
  tasks use `g.spawn_parallel`. A cancelled take consumes nothing.
* Str is a tape view, not a flat value: its bytes are copied in at post
  and out to the taker's current tape.
* A miss answers nil in `{T?, Bool}`, since not every ris type has a
  zero value.
* Resources never cross tasks; IO stays in the task that opened it.

## Patterns

Workers and shutdown, as Goose does it:

```crystal
group do |g|
  4.times do
    g.spawn do
      loop do
        job = RisBoard.take(Job)
        break if job.quit?
        RisBoard.post(Result.new(run(job)))
      end
    end
  end
  jobs.each { |j| RisBoard.post(j) }
  4.times { RisBoard.post(Job.quit) }
end
```

A connection limit: post n `Permit` values, take one before accept and
post it back on every exit of the connection.

Many waiters on one result (Goose's `thread_wait`): start the work as a
task and let every waiter read its `value`.
