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

A message is Copyable: it has a finite, self-contained packed form
(Goose calls this flat). Copyable types are numeric scalars, Bool, Char,
Symbol, Nil, enums, Str, Ary(T) and Tre(T) of Copyable T, and value
structs or unions of these. The compiler infers this at post, take, poll
and limit; no marker is needed. Copyable differs from @[Tape::Flat],
which marks raw-byte images: Str, Ary and Tre are handles, and the board
packs their live data, never their pointers. A type that contains itself
through fields, unions, Ary or Tre is refused; keep recursive data in a
Tre or a node array with checked indices. User link fields stay refused;
only Tre's own stop boundaries cross, relative to the copied entries. A
post packs counts, fixed fields, union tags and live elements into one
owned image, sized before publication, while the source stays unchanged;
each handle occurrence gets its own copy, and an empty value still
counts once under the limit. take unpacks fresh containers with capacity
equal to size. Copies keep concrete types and enum values and run no
user code. Owners, classes, pointers, resources, closures and fields
containing them are refused. No receiver borrows sender bytes or a
runtime pool view. GC and no-GC storage obey the same lifetime and
transactional copy rules.

The core has these physical bounds, independent of limit(T, n):

* At most 4,096 distinct canonical specialized queue types per process.
  Registry slots and their limits last until process end.
* At most 65,536 live message images across all queues. A private image
  being packed also occupies one slot until publication or rollback.
* At most 16,777,216 packed bytes per message, including counts, union
  tags and fixed fields. No pointer or spare container capacity is packed.
* At most 1,048,576 value occurrences per message. The root, every struct
  field, every container element and each live union arm count. Container
  lengths and Tre stop metadata occupy bytes but add no occurrences.

An empty message still occupies one queue place and one image slot.
Exceeding a physical bound follows TAPE_SPEC 4.2, rather than returning
false. Byte slabs are reused; images above the slab classes use private
mappings released after consumption. Total mapping capacity is subject to
OS exhaustion. A take's destination remains subject to the tape limits.
Wait records live on their suspended takers' stacks, bounded by the
runtime's task and stack limits. The scheduler roots those stacks and
fibers in GC builds; packed images and registry slots hold no GC objects.
No-GC builds use typed runtime mappings and no general heap allocation.

Board packing is private; it is not the to_bytes/from_bytes image. To
send a linked structure, encode it to Str or Ary(UInt8), post that and
validate it before decoding. Static Str uses the same copy rule; sharing
static program data between tasks does not admit other views or pointers
as messages.

Unlike Goose, where arrays are values, Str, Ary and Tre are views on a
tape, so the board packs their data. A miss is nil rather than Goose's
zero T. Tasks are grouped fibers, with cancellable waits, Share checks
and panic/defer cleanup. Every task, local or parallel, captures only
Share values or independent checked copies on its own tape; no shared
mutable borrows. This includes receivers and reached program state. A
copied closure must satisfy those checks, not retain a hidden manager or
resource.

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

The server entry points take an address and a factory type:

```text
Server.answer(host, port, config, Handler, max_connections: n)
Server.serve(host, port, config, Handler, max_connections: n)
```

`Handler.new(config)` runs on each serving task with an independent
checked packed copy of `config`. `answer` calls `Handler#call(Incoming,
Outgoing)`; `serve` calls `Handler#call(Request)` and uses its Response.
A factory type replaces a captured callback: construct mutable routers,
TLS configuration and managers there, using copied values or file paths.
An open socket, a proc, a class or a resource-containing config is refused.
An optional `Handler#tls_config` supplies that task's TLS configuration to
`serve`; it replaces the old `tls:` argument. An optional
`Handler#listening(port)` runs after that worker's listener has opened.
It may post a nominal readiness message to the caller.

The old open-listener/block overloads are refused with the replacement
form. A caller chooses one port in 1..65535 before starting the pool;
port zero is refused. `max_connections` is the positive number of serving
tasks, including connections idle between keep-alive requests. The old
zero-for-unlimited mode is refused. The kernel distributes new connections
among listeners; it promises neither equal queues nor global FIFO order.

A supervisor for each serving task observes its completion in an inner
group. A handler panic unwinds and closes that task's client and listener;
the supervisor consumes Panicked and starts a fresh worker, rebuilding
state from the original config. A worker cancelled independently of the
pool is replaced too. Other workers keep serving. Supervisors
hold packed configuration only, never sockets, handlers or IdleConns.
Listener setup errors fail the pool rather than retrying or falling back
to a shared listener. The pool's joining caller retains the immutable
packed image until all supervisors and readers have stopped.

Shutdown is cancellation of the enclosing group. It stops pending accepts
and cancels in-flight reads, writes and TLS handshakes. Client and listener
defers run before the group joins; an application callback must cooperate
with cancellation just as any other grouped task must. This API does not
promise a graceful response drain. A signal waiter can cancel the server's
group; there is no foreign task closing a listener or traversing IdleConns.

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

IyiTask#value is not Goose's thread_wait: it answers the task's result
or Panicked, not a status Bool, and a task handle is not a message. In
Goose results flow back through queues; do the same with a Result type,
and keep value for completion inside the group that made the task. To
let one failed worker end without failing its siblings, run it in an
inner group of a supervisor task and handle Panicked there; ordinary
groups fail fast (iyi III.4.3). Goose's hardware_threads sizes workers
by its stack budget; ris has no counterpart yet, and task count is not
the native worker count (IyiWorkers).
