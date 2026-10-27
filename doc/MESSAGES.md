# Messages between tasks: RisBoard

The rules are TAPE_SPEC 5.1-5.3 and 5.6. RisBoard copies the typed-queue
transport in doc/reference/goose/docs/goose_spec.md §11.2, not Goose's
thread, global-copy or abort model. Main and all tasks use one board.

## Operations and identity

```crystal
RisBoard.post(v) : Bool
RisBoard.take(T) : T | Cancelled
RisBoard.take(T, ms : Int64) : {T?, Bool} | Cancelled
RisBoard.poll(T) : {T?, Bool} | Cancelled
RisBoard.limit(T, n : Int64) : Nil
```

Goose's counterparts are qput, qget, timed qget, qpoll and qlimit.
There is one process-wide queue per canonical specialized type, across
modules. Aliases share it; generic arguments distinguish it. post uses
its argument's exact static type, with no conversion or runtime-arm
routing. Bare union keys are refused: use a nominal struct containing
the union. Use distinct Job and Result types, never two Int32 protocols.
Distinct runtime instances of a library still share its protocol type;
a field holding an instance id does not provide selective take. Use a
single coordinator to route that protocol, or distinct nominal types.

post copies and publishes atomically, returning true, or false when
full with nothing queued. It ignores cancellation and never waits for
capacity; locking and copying still take time. Check false: handle the
refusal, retry with a cancellable yield, or fail and let the group cancel
its workers. A hot retry loop can starve same-thread consumers.

A take copies to the taker's tape before consuming one message. At one
commit the priority is cancellation, then data, then timeout. Cancelled
consumes nothing, even for poll or a task already cancelled. A failed
copy rolls back its destination and claim. Positive ms uses a saturating
monotonic deadline; ms <= 0 polls. Data present at commit can win after
a delayed deadline wake. Success is {value, true}; a miss is {nil, false}.
A queued Nil is {nil, true}, so test the Bool, not value.nil?. Top-level
Cancelled keys are refused: wrap that value in a nominal message.

limit sets a message-count bound, initially unlimited. n <= 0 follows
TAPE_SPEC 4.2. Lowering retains mail; posts fail while count >= n.
Admission and limit changes are linearized; unpublished copies do not
count. Physical exhaustion is 4.2, not false. FIFO is publication order
per type, a ris clarification; taker fairness and cross-type order are
not promised. Mail and limits survive task/group end, panic and cancel;
only mail is consumed. Process end discards remaining copies without
user callbacks. Group end neither closes nor drains the board.

## Copies and task boundaries

Messages are flat: numeric scalars, Bool, Char, Symbol, Nil, enums,
Str, Ary(T) and Tre(T) of flat T, and value structs recursively
containing these or unions of them. The compiler checks this at post
and take; no marker is needed. Generated copies preserve enum values
and concrete types, copy Str, Ary and Tre whole, split sharing as in 1.7
and run no user code. Owners, classes, pointers, resources, closures
and fields containing them are refused.
No receiver borrows sender bytes or a runtime pool view. GC and no-GC
storage must obey the same lifetime and transactional copy rules.

Unlike Goose, where arrays are values, Str, Ary and Tre are views on a
tape, so the board copies them whole; Tre links stay inside the copy. A
miss is nil rather than Goose's zero T. Tasks are grouped fibers, with
cancellable waits, Share checks and panic/defer cleanup. Every task,
local or parallel, captures only Share values or independent checked
copies on its own tape; no shared mutable borrows. This includes
receivers and reached program state. A copied closure must satisfy those
checks, not retain a hidden manager or resource.

## Workers and shutdown

Quit is a variant of Job, consumed by take(Job), never a separate Quit
queue. This sketch assumes Job.work/Job.quit and Result wrappers, a
finite jobs collection of work Jobs, and run(job) returning copied data:

```crystal
group do |g|
  4.times do
    g.spawn do
      loop do
        job = RisBoard.take(Job)
        break if job.is_a?(Cancelled)
        break if job.quit?
        unless RisBoard.post(Result.new(run(job)))
          raise "result queue full; result was not published"
        end
      end
      0
    end
  end
  jobs.each do |job|
    raise "job queue full; job was not published" unless RisBoard.post(job)
  end
  4.times do
    unless RisBoard.post(Job.quit)
      raise "job queue full; quit was not published"
    end
  end
  jobs.size.times do
    result = RisBoard.take(Result)
    break if result.is_a?(Cancelled)
    consume(result)
  end
  0
end
```

Normal completion posts one accepted quit per worker, collects all
results and joins. A refusal in this sketch panics and cancels the group;
it does not pretend shutdown succeeded. Cancellation does not discard
accepted jobs, quits or results. A protocol must account for leftovers
before reuse; never let an unrelated consumer drain them. Tests use
fresh nominal types, and fresh processes for initially unlimited state.

## HTTP and one-task IO

HTTP uses a prefork-style topology of N tasks, not N shared sockets or
necessarily N OS processes. Each task opens its own SO_REUSEPORT listening
socket on the same port, accepts a connection, serves it to completion,
closes it and accepts again. Each task owns all its connection resources;
N bounds concurrent connections. There are no permits or semaphore.
Construct a task's handler from its independently copied configuration;
keep its IdleConns and mutable handler state local. A configuration copy
is not a copy of an open listener, TLS connection or manager. Unsupported
SO_REUSEPORT targets need an explicit refusal, not shared-listener fallback.

Pipe and socket race IO stay within one task using OS facilities on the
poller. A pipe pump must interleave reads/writes, preserve partial IO and
handle EOF, EPIPE and cancel; filling it before reading can deadlock.
A socket race needs several pending connects and a wait for any readiness
or completion, the next launch time or deadline; close every loser in
that task. These need runtime poller work, not a global Chunk queue.
A socket or pipe end never crosses tasks: no owns:, task.take, resource
move, descriptor-as-message workaround or safety exception.

## Managers and completion broadcast

A manager such as autocert has independent state per task, or one task
owns its mutable state and serves copied board messages. That service
must coordinate reply routing; multiple waiters cannot selectively take
by an id field. Handler procs and IdleConns are not shared-manager
loopholes: construct independent handlers and connection state per task.

Many readers of one completion use a retained IyiTask result and value,
subject to task-handle Share checks. Results are copied to each reader's
tape; this is completion broadcast, not a consuming message or a timed
wait. Autocert needs timed nonconsuming task waits with separate handshake
deadlines: one waiter's timeout must not cancel the common order. value
alone does not provide this yet; TODO records that and manager wake/stop.
