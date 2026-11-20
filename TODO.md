# ris TODO

How to work (fewer tokens, faster to the goal):

* Demand first: take the largest gap to SPEC in an existing workload.
  For an uncovered language guarantee, add a small representative gate.
* One change, one relevant gate: check the promised behavior, including
  error paths.
* Replace, don't wrap: when a String API has a tape twin, grep the repo
  for callers. Few: move them and delete the String API in one commit.
* TODO holds open work only, one item per task; completed work lives in
  git log. Remove an item when its guarantee passes its gate.
* Linux x86_64 and aarch64, macOS arm64 (SPEC 7.1): no other targets.

## 0.2 blockers (decided 2026-11-10)

What CHANGELOG's 0.1.0 promises must work; the items stay in their
sections below and are listed here in order:

* Benches build (section 7), including `HTTP.tls_config=` callers.
* SPEC todos all proved (decided 2026-11-15,
  doc/drafts/release-0.1-todos/triage.md), in order: 2.3, 4.2, 6.6,
  6.4, capsule.8, 5.4, 6.2, then 6.1 Pool(T) after an EGM draft.

## 1. Programs first

* std on the tape, found porting the HTTP handlers (drift report in
  doc/drafts/server-answer-features.md): Router's `Pattern.parse` (SPEC
  1.9, router.ri:189), the HTTPS client (`records_handshake` returns
  an owner, http.ri:4847; blocks samples/ris/autocert.ri),
  `Zstd.decompress` (view check, zstd.ri:1410), `Cookie.parse_header`
  and `HTTP.cookie_pairs` (a Hash from a def). Then give `Incoming`
  back `form`, `multipart` and `cookies`, which `Request` had.

* The user's own ris programs: each obstacle becomes an item here.

* `Iterator#to_a` (iterator.ri:225) stores each round's item past its
  round, so samples/ris/std_iterator.ri does not build and is left out
  of the tarball with autocert.ri (Makefile, ris-tarball).

Breakage between steps is fine; no transition stages.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.
Fix a checker hole below only when a cluster hits it.

## 2. Checker holes (ordered: those programs hit first)

Unknown must be refused (SPEC 3.6).

* A one-call def's value moves down only when it is one fresh flat
  value: a tuple or two locals do not. Bzip2.decompress tags its String
  (a 0 or 1 byte first) to answer bytes or an error in one value.
  Found 2026-11-20: not a checker hole. SPEC 1.5 moves down only "a fresh
  flat value"; a Tuple(String, Array) made in a def is refused by
  check_leaving (SPEC 1.9) as written. Moving two values down needs a
  SPEC 1.5 change (EGM review) and codegen for a multi-value move.

* A struct whose constructor makes its own data is refused at a store
  past its round only with no owner argument: one given an Array or Hash
  it reads, or a builder, pool or class it does not allocate through, is
  still taken by the older rule. Follow where the constructor allocates.

* The call graph's `fresh?` takes a call's String-or-error union as
  fresh when any path allocates (an error sentence's interpolation),
  though every String it answers views the parser (toml's
  basic_string now writes into the parser's @texts): scalar's
  `TapeAny.new(basic_string!)` is refused. Narrow by summary.

* text_grow: `field.take_event(Program.tape)` returns
  `GrowingTextEvent.new(@text).copy_to(owner)`, yet the caller sees the
  event as a live view of `field`'s text, so the later rebind is refused
  as a shrink. A callee's copy_to result is not a view of its input.

* A spawn block's non-flat value (a Tuple or Hash, task_tape_result)
  is refused: the block frees its scratch before the task copy takes
  the value. Copy the value at the boundary before the reset.

* OptionParser.parse given an `args` shorter-lived than `found` is
  refused at the append inside std/option_parser, with a generic message:
  the refusal belongs at the caller's `parse` line
  (doc/drafts/option-parser/probes/p14d.ri).

## 3. SPEC 3.3 alias clear (EGM decision)

* SPEC 3.3: `v = w.rows`, `w.rows.clear`, `puts v.size` passes, as
  does the same with a local `v = a`. v aliases the Array handle (SPEC
  1.4) and reads size 0: nothing dangles. A view through the getter
  (`w.rows[0]`, `w.buf.finish`) is refused. Whether an alias is a 3.3
  "holder" a clear must refuse is a SPEC question: decide it (EGM),
  then refuse both forms or drop this item.

## 4. SSE stable storage, then HTTPClient pooling

* test/ris/sse.ri needs stable storage, then inclusion
  in check.sh: EventParser replaces
  `@line` and `@data` with a new builder in a round, and keeps `@type` and
  `@id_buffer` from `SSE.clean`'s scratch. Give them stable storage.

* HTTPClient pooling: HTTPClient owns one exchange per pooled
  connection with `@idle` as indexes into them, not `{String, Conn}`
  made per request; SSE.open keeps one exchange beside its parser; gate:
  two requests over one connection, `reused` 1. Today `client.open` is
  refused at open_by: the exchange it makes is its own, and give_back
  would keep its Conn in the client. A try (exchanges made in
  initialize, `lend`/`release` by index, `take` given the exchange)
  got past these, in order:
  - `connect_by_records` made and answered a TlsClient and a tuple: it
    takes the exchange, moves the socket into it (an `adopt` beside
    `take_connection`), handshakes on its `tls` slot and answers the
    socket; the caller reads the config back with `https_current`.
  - Exchanges made under `if i <= idle` in initialize (macro-unrolled)
    and pushed into `@exchanges` are refused ("cannot store a view
    beyond its owner scope"). Taking branches out of the checker's
    scopes passes them but breaks refused/root_branch_escape and
    root_store_join: SPEC 3.2 says branch-local storage cannot escape,
    while 1.1 frees only per def, round and block. Decide with EGM, or
    make all MAX_POOLED exchanges (16 resolvers and buffers a client).
  - The resolver refill: read once a request before the loop (done).
  - SvcbStore kept views of the DNS message (done).
  Next: `HTTP.https_endpoints` stores `ech` bytes and the `ordered`
  alpn made in its block into the endpoints, and passes Arrays where
  HttpsEndpoint takes views: build them into caller-owned storage.
  Unknown what follows; the HTTPS-records path never compiled behind a
  client before.

## 5. Tighten heap_trap

* None open: heap_trap checks each case's outcome (ris2).

## 6. Checker `evaluate` stack use

* None open: call_value keeps `evaluate`'s frame small (ris2).

## 7. Benches

* 36 check scripts nothing runs (not CI, not test/ris/check.sh, not another
  script; gates_reachable.py lists them): wire each into CI or delete it.
  test/cli: bounded_gate.sh, collections_exercise.sh, collector_free_floor.sh,
  daemon_agrees.py, debug_info.py, enum_exercise.sh, float_text.sh,
  format_exercise.sh, gates_reachable.py, generic_boundary.py, io_exercise.sh,
  language_is_named.py, lsp_artifacts.py, lsp_positions.py,
  lsp_token_boundaries.py, mod_context.sh, mod_diff.sh, number_exercise.sh,
  packages_get.sh, parallel_exercise.sh, runtime_exercise.sh,
  sandbox_story.sh, server_load.sh, socket_exercise.sh, tarball_std.sh,
  test_verb.sh, value_exercise.sh, verbs_exercise.sh,
  wasm_concurrency_probe.sh, windows_exercise.sh. test/speed: defer_cost.sh,
  definition_typing_scale.py, measured_numbers.py, metric_port.sh,
  rebuild_speed.py, tls_speed.sh.

* Build each test/cli program, group refusals by message, fix per group.
  2026-11-14 (fifth round): 114 of 130 programs pass
  `RIS_SCOPE_ERRORS=all bin/ris build --no-codegen FILE`; 16 fail (114
  after the fourth round, 112 after the third, 107 after the second,
  100 before the first). http joined; big (std_big_exercise.ri:989, a
  BigDecimal kept from a times block) and websocket (:1606, a loop
  round's store) fail since the main merge of 2026-11-14, before this
  round's changes.
  Names omit std_ and _exercise where present; each failure appears once.

  Fifth round (checker questions): http builds. The String to Builder
  lowering covers std under an RIS_PATH entry's std/ (test/ris/
  patched_std_lowering.sh). `server_reads` is a socket round trip to a
  server whose handler describes the request; the 2 GB chunk is now a
  413 (the server refuses it before it arrives). The test's
  IyiThread servers became group tasks (program tape writes need one
  thread), `x = x + piece` loops became `<<` in defs (gather, drain,
  body_pieces: growth in a task block is not lowered, a compiler bug
  left open). std fixes: MultipartBuilder's chosen boundary was a def's
  scratch kept in a field (now made again from the parts each time);
  a response head's field error lacked "HTTP: ". Checker: a holder used
  whole no longer counts as a live view of storage it reaches through
  an object field (test/ris/owner_reference.ri; refused/
  owner_reference_view.ri keeps a real view refused), and such storage
  is not the holder's scope or tape (test/ris/client_open_block.ri:
  HTTPClient#open with a block). SPEC 5.1: a joined task may borrow one
  value of its spawner (doc/drafts/joined-task-borrow/), UdpSocket may
  be handed off. A compiler built from the same commit reuses
  ~/.cache/ris check results: set RIS_CACHE_DIR to a fresh dir when
  testing a checker change.
  Left, with their cause:
  - acme: past the read-after-shrink; now ~15 retained-def-data sites in
    acme.ri (from, new_order, finalize_order, post, take_nonce, object,
    problem), x509.ri:1716 from_pem and the test's request_fields: a
    port, as big's was.
  - autocert: tls.ri:6626 and :7005 (`identity_for` returns an owner)
    and the test at line 40.
  - tls: the group tasks borrow their config and answer through
    `value`; left: `crafted`'s `Array({Int32, Array(UInt8)})` is a
    runtime-sized collection of growing values (SPEC 2.2).
  - http_https_records: the UdpSocket is handed off; left: `zone` is
    shared mutable state between the DNS task and the checks (the
    spawner sets `zone.https` while the task answers): RisBoard messages.
  - fuzz: no parse_request left; TLS API drift as before, plus
    `Server.handle` private and `String#compare`.
  - The checker questions toml/yaml, zip, router, file, log/ocsp/x509
    and iterator: design draft doc/drafts/checker-open-questions/
    (EGM-reviewed, not implemented).

  Fourth round (the TLS-owner group): benchmark and websocket build.
  benchmark: bm and ips answer Nil, Tms and Entry are `@[OnTape]`
  structs a job writes back by index. websocket: Raw reads into an
  append-only String::Builder; `handshake` is a macro, so the request
  and its fields are the caller's. RsaPrivateKey drops its @n and @e
  copies (the TLS store's copy of an RSA key was refused at
  tls.ri:4616 while they were fields). AutocertIssuer opens its
  AcmeClient into @client (`open_client`) instead of returning it; its
  dead `session.is_a?(AcmeError)` check now reads `session.error`, and
  an order is copied before the next request reuses the answer it views.
  websocket's program passes (its 101 no longer carries Connection in
  the Outgoing: the expectations dropped it); its .sh still fails "runs
  the same from its artifacts" (`utf8_scan` is exported and does not
  say what `src` is) and `iyi doc src/std/websocket.ri`. rsa.sh: three
  stale patch sites (a signature past the modulus, of any length,
  rsaEncryption's parameters) and its artifacts build (a task captures
  a Dir), as before this round.
  Left, with their cause:
  - tls: from_pem, TlsServer.over, TlsClient.over, TlsRecordCipher and
    HpkeSuite#sender callers rewritten; left: a `group` task captures a
    TlsServerConfig parameter (ech_pair, captured, crafted). Only
    Strings and handed-off sockets cross into a joined task, and
    copy_to(Program.tape) is no way in either: a checker question.
  - acme, autocert: an AcmeClient that holds the caller's HTTPClient
    counts as a live view of its resolver text
    (`@http.@system.@own_text`), so its next use after a request is
    refused as a read after a shrink: a checker question. autocert also
    hits tls.ri:6626 and :7005, `TlsIdentitySource#identity_for`
    returning an owner (an API question).
  - http: HTTP.upgrade callers declare an Upgraded; left: 30
    `server_reads` checks need `Server.parse_request` (see below).
  - http_https_records: a task captures a UdpSocket; only IyiSocket and
    pipes are exempt when handed off (checker).

  Third round: tar, compress, big, p256 and hpke build. Found on the
  way: `-7 >> 1` was -7 (BigInt's negative right shift dropped its
  value; test/ris/big_shift_right.ri); BigDecimal `+ - * // %`,
  BigRational `+ - *` and BigFloat's rounded results ended with a
  constructor over a scratch BigInt and read freed limbs (the checker
  accepts it); each now ends `.copy_to(RisCurrentTape.new)`. A def's
  copy is accepted only as its last expression, never in `return X
  if`, so guarded returns became one `result = if ...` (big, hpke).
  Loop-carried BigInts refill a limbs Array (BigInt.refill). Benches
  keep a block's values with `.copy_to(Program.tape)`. A top-level
  local named like a block's local (z, feed, x, key) makes the block's
  store refused at a line that does not say so: renamed.
  The String to Builder lowering now applies to std under any RIS_PATH
  entry's std/ (fifth round), so tar.sh's mutation copies sit under
  patched/std as the other .sh files' do; the "read after the reader
  moved on" refusal is now a build refusal.
  The p256 and big tests' hex helpers appended `"0123456789abcdef"[i]`,
  a byte, as its decimal number: now `[i, 1]`.
  Built but failing at run time: hpke passes its plain build; its
  --release build segfaults in HpkeContext#configure (hpke.ri:784)
  from the first vector's `sender.setup`, so the release, no-argument,
  every-vector and Python oracle steps of its .sh fail. tar.sh passes
  every step it reaches but its 31 mutation builds outlast a 25-minute
  run.
  p256.sh passes but for two stale patch sites ("SEC 1's public key
  unchecked", "SEC 1's curve unchecked").
  big.sh passes its plain, release and oracle steps; six mutations
  (negate, abs, exponentiation, decimal division, exact division,
  decimal zero) report "the patch changed nothing".
  Left from this round's list, with their cause:
  - user: `User.parse_line` ends with `User.new(..., uid.to_s, ...)`;
    the class views its def's scratch and the checker accepts it
    (ids read back as garbage); `.copy_to(RisCurrentTape.new)` there
    is accepted too and still dangles when called in a block round. A
    checker hole and an owner question: not applied.
  - compress: builds and passes; its .sh fails only "runs the same from
    its artifacts": with --use-rimod, Inflater#read is an opaque
    contract and the reader `z` itself counts as a live view at the
    next read (checker question).
  Second round: csv builds and its program passes (the header is asked
  after the rows; a tape-bytes drop no longer underflows); its .sh
  oracle and refusal programs still need owner declarations. toml and
  yaml refuse `Array(Array(T))` reads as json does, and toml's `dig?`
  ends with a call. ZipEntryReader#read answers its kept error copy.
  Left with their cause:
  - toml, yaml: a derived struct read in an Array (`Array(Inner)`) is
    made in the block's scratch through RisDecoded. Ending with
    `T.new(value)` passed the checker but lost the Array fields of an
    `@[OnTape]` struct at run time (spec 8.1: tags read back []): a
    checker hole, not applied.
  - zip: a ZipEntryReader still "views" its decoder's message after a
    read; the shrink checker blames the reader (used at `r.finished?`)
    even with the read in a def of its own: a checker question.
  - router: tables are top-level locals (a constant of tuples is
    refused as request tape data: checker), handlers capture no
    String; left: `Pattern.parse` returns an owner (section 1) and the
    handler call is an opaque callback (router.ri:594).
  - file: tasks open their own files; left: `File.read_lines` returns
    views of its own read (std file.7 needs a caller's text).
  - fuzz: `Server.parse_head` replaces `parse_request`; left: TLS API
    drift (TlsRecordCipher.new, TlsServerConfig.from_der, from_der
    owners, Array::View pending bytes).

  Built this round: http2, http_latency, http_resume, http_stop, zstd
  and number. TLS callers declare TlsIdentity, TlsServerConfig,
  TlsClient and Upgraded as owners; roots are read into the store
  before a config views them (a def taking the store and config is
  refused, a macro is not). Zstd.decompress copies into one tagged
  String (as Bzip2's); MathInterpreter folds a constant through its
  `__ris_program_init` block. Built but failing at run time: http2 and
  http_stop (HTTP/2 PROTOCOL_ERROR reset on the first GET), http_resume
  ("new roots" resumes) and number (panic: not a number "\u20281e-3").

  - TLS owners, 3: tls (2000 lines, ~25 sites: from_pem, TlsClient.over,
    TlsServer.over), autocert (std/autocert's AutocertIssuer#client
    returns an AcmeClient owner it makes lazily) and http
    (Server.parse_request is gone, see below; HTTP.upgrade callers).
  - Block/round storage, 2: user and websocket (third round above).
  - Procs outliving their tape, 4: file, router, http_https_records and
    benchmark (Job#report keeps a block's proc in an Entry; bm and ips
    return their owner job).
  - Program-owned retained data, 3: log, ocsp and x509. A Time constant
    (`NOW = Time.utc(...)`, even with copy_to(Program.tape)) and a
    constant of certificates are refused at time.ri's Zone#initialize;
    the same Time made in a def builds. x509's `cert(hex)` returns a
    Certificate viewing its def's bytes.
  - Scratch results, 2: toml and yaml (see above).
  - Reset/growth views, 1: zip (see above).
  - Retained def data, 1: acme.
  - API drift, 1: fuzz.
  - Opaque callback, 1: iterator's to_a (a loop without the block trades
    it for a live-view refusal: a checker question).

  Earlier round (2026-11-12): bzip2, eiy, file_utils, rsa, slice, sse,
  xz and tls_probe built and ran; each bug has a regression in
  test/ris/check.sh. No checker, SPEC.md or CHANGELOG.md changes.

  Known outside this round: format fails on main; text panics at
  "string: chomp cr".
* Most of std_http_exercise.sh's mutation patterns no longer match
  http.ri. Its program builds (fifth round) and fails at run time at "a
  HEAD names the coding its GET would have, and writes no body".

## 8. Speed

Speed work stays out of minitest. The jq check at jqg.ri:424 is the
maintainer's.

At the end of each Now step, run ris-bench's `goose-evals.sh medium`
(the goose-evaluations ports jq, json, ninja and yaml against Goose)
and put one line per port in the step's commit body.
x = ris time / Goose time, median of 5 runs; lower is faster. A
timing is a baseline and never fails a gate; nothing is timed per
change. Gates stay structural.

## 9. Language and runtime

* RisScopeMove keeps a def's scratch when its fresh result does not fit
  on the marked mapping or its Array payload is on a mapping the scope
  grew onto; a loop's `break` with a value and a block's `break` skip
  their scope's reset. Free those too (SPEC 1.1).
* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
  A spawn reached through a proc call is not followed by the capture
  check yet.
* Typed pool validation (SPEC 6.1-6.4): audit remaining bounds,
  overflow, membership, stale views, reset lifetimes and external images.
* FFI paths in use: enforce borrow lifetimes, retained-storage owners,
  foreign-thread attachment and no unwind across foreign frames.
* Runtime pools (test/ris/task_reuse.ri): a long-lived group (a
  server's) or `IyiGroup.new` keeps each task's slot until it ends;
  parallel task fibers are not pooled; a spawned block's captured
  closure data takes program storage per spawn.
* std's long-lived state (HPACK tables, autocert cache, HTTPClient ticket
  origins, log sinks) into typed Pool/SlicePool with explicit free and
  index links (Goose
  doc/reference/goose/docs/design/owning_dynamic_data.md).
* Stats: RIS_TAPE_STATS owner paths and pool waste (SPEC 6.6).
* A tape hash map laid out as Ruby's Hash (st_table): entries in an
  Array in insertion order, bins an Array(Int32) of indices, String keys
  as views; Copyable like RisTree. Replace the linear-scan TapeMap copies
  in std/yaml, toml, xml and mail. Gate: O(1) lookup on a large map,
  insertion order.

## 10. std

* HTTP answer's slow request path still uses String-based read_head and
  body readers. Recheck prefork, TLS and samples/ris/web after it.
* TlsConfig system roots: check whether SystemRoots (00130b97e) already
  keeps them. If still read per handshake, make Certificate copyable to
  Program.tape to keep them once.
* Autocert part B: test/cli/std_autocert_exercise.ri and its driver, with
  real TLS deadline and parallel-server cases, Pebble, restarts and
  mutation checks (part A's gates: test/ris/autocert.ri, autocert_wire.ri).
* std_process: the `handlers` mutation proof (child keeps this program's
  TERM handler) is not caught.
* Add 128-bit formatting, IDNA and URI resolution.
* src/ris/float.ri's parser has a copy in src/ris/tape.ri: merge them.

## 11. macOS arm64

SPEC 7.1 lists it; these are what Linux has and it lacks yet.

* Measure pages returned to the OS: scope_frees.ri and fibers/spares.ri read
  /proc, and `MADV_FREE` is lazy, so resident size may not fall. Decide
  between `task_info` with `MADV_FREE_REUSABLE`, or `mmap` over the range.
* Port the other checks in `ris-macos.yml`'s `RIS_CHECK_SKIP`: file_copy_to.ri
  and tls_session_tickets.ri.
* Short frame names in a backtrace, then drop check.sh's `frame_edge`.
* A tarball, its release job and `install_ris.sh`: static LLVM fails there.
* Run a reservation-heavy program on a small Mac: `MAP_NORESERVE` is a no-op.

## 12. Known failures

* compiler_test's "Codegen: const" crashed once (signal 11) when all
  describes ran 30 at a time on minitest (2026-11-11); alone it passes
  three times of three. Find the race or the load-dependent fault.

* Every growing tape value reserves 128 MiB of address space, even a
  128-byte builder (SIDE_RESERVE, region.ri:529). Under
  `vm.overcommit_memory=2` each is charged: a FileServer answer holds
  up to eight (doc/drafts/fileserver-outgoing.md, Memory).
* A constant's initializer runs on the program tape only in a .ri
  file; a compiler_test example (source "spec") still needs
  `.copy_to(Program.tape)` for a constant or class variable (SPEC 7.5).
* A branch that cannot be typed (`raise "#{f}"` with `f` untyped) does
  not narrow a variable as a NoReturn branch does (if_test.cr).
* A local receiver of `<<` in a program without the prelude reads as
  growing text and names `::RisTextGrowth` (iyi_test.cr, std/int case).
* test/cli/concurrency_exercise.sh needs `ulimit -n 8192` and is not in
  check.sh; recheck on minitest.
* test/cli/parallel_exercise.ri:124 (a task value's Panicked arm) and
  test/speed/metric/metric.ri (Array of the tape type Planet) do not
  typecheck; recheck on minitest.
* test/cli/std_websocket_exercise.ri appends to an `io` builder and reads
  it back: move it to a String local, then recheck the artifact
  comparison on minitest.
* test/compiler/iyimod_test.cr's getter/defer case cannot resolve
  `Pointer(RisArrayPool(String))` from boot/shelf's type ids.
* test/cli/socket_exercise.sh: several mutations are not caught; a
  unix-socket mutation fails with "the address is in use". Recheck on
  minitest.
* The mutation phases of std_acme, cookie, router, sse and websocket .sh
  run past 20 minutes; recheck on minitest whether they finish.
* base64's timing ratio fails under load; recheck on minitest.

* Found while porting rispacks (2026-11-13), reproducers not yet in
  test/cli; the first three are reported by the port, not rechecked:
  * A native worker's tape trap stops a spec module; the runner's
    summary leaves out the blocks not run and says 0 broken (sha2).
  * `a == b` with both `UInt8 | Char` is refused as a String index
    comparison (sqlite).
  * An optional path given to `Process.run` fails LLVM module
    validation: `(String | Nil)` passed where String is expected (pg).
  * `ris check types --fix` reports db's program-owned driver registry
    as request storage; a plain build passes (ricord).
  * The formatter fails on `x.each(&.destroy.or_panic)`; macro
    declarations are dropped in a spec build (ricord).
  * `ris check unused` skips a package with no root module.
  * `ris check format` reads files git ignores (web's tmp/).
