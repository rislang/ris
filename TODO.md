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

## 1. Programs first

* std on the tape, found porting the HTTP handlers (drift report in
  doc/drafts/server-answer-features.md). Done 2026-11-20: Pattern views
  its text (no growing field, SPEC 2.1) and `match` writes into the
  caller's pieces, builder and Captures; `Zstd.decompress` decodes in
  answer_compress; `HTTP.cookie_pairs` fills a caller's Hash; `Incoming`
  has `form` (a Query), `cookies(found)` and `multipart { |parts| }`.
  Left: `Router#call` hands `Incoming` to an opaque handler Proc,
  refused ("cannot prove opaque callback retain/escape effects",
  router.ri `@handlers[found].call`; doc/drafts/checker-open-questions),
  so std_router_exercise does not build. The HTTPS client: done
  2026-11-20, `records_handshake` builds (std_http_resume.ri does);
  AutocertIssuer keeps no HTTPClient or AcmeClient in fields: `issue`
  makes them on its own tape and hands them down. The acme/x509 port:
  done 2026-11-20, std_acme_exercise builds (results end in a call or
  `copy_to(RisCurrentTape.new)`, the test's script server writes into
  the Outgoing). autocert.ri and std_autocert_exercise still stop at
  tls.ri `@identity = chosen` and `identity12`: an identity a
  TlsIdentitySource makes per handshake is kept by the connection (an
  API question: copy it into a connection-owned TlsIdentity with
  `read_identity`, or have the source yield it); the exercise also at
  lines 40, 208-229.

* The user's own ris programs: each obstacle becomes an item here.

* samples/ris/std_iterator.ri does not build and is left out of the
  tarball with autocert.ri (Makefile, ris-tarball). 2026-11-20:
  `Iterator#to_a` loops on `next` itself (no opaque `each` block). Left,
  both shrink-checker false positives in to_a's `result << item`
  (checker-open-questions Q6): `map` over `Iterator.of_entries(hash)` is
  refused as if the proc shrank the entries' @keys
  (std_iterator_exercise.ri:292, :313), and the sample's `cycle(n)` as
  growing a pool run with a live view of CycleNIterator's @cache.

Breakage between steps is fine; no transition stages.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.
Fix a checker hole below only when a cluster hits it.

## 2. Checker holes (ordered: those programs hit first)

Unknown must be refused (SPEC 3.6).

* Unsound, first: five shapes built but read freed memory at run time
  (found porting acme, 2026-11-20; section 7 "acme:" lists them): a
  struct a constructor keeps viewing the constructor's answer; a
  callee's KEEP copy returned or stored from a def that is not one
  call; a key made in a loop round; a def returning strings viewing
  JSON it parsed; String::Builder views kept across its growth. Each
  gets a refused/ fixture that runs under ASan or reads poison, then
  the checker refuses it.
  2026-11-20, RIS_TAPE_POISON=1: the acme exercise from before the port
  no longer builds (SPEC 1.9); the current one crashed poisoned. Found
  and fixed: (a) a struct holding more than texts (an Array, a view)
  made by a call, a callee's copy_to(RisCurrentTape.new) included,
  returned from a def that is not one call: RESULT moves only texts
  (refused/kept_struct_returned; acme's error paths, x509.read_pem and
  time's Location.load now end in copy_to(RisCurrentTape.new)); (b)
  std/http's supervise spawned a task whose @[TaskClosureUnsafe]
  closure lived on supervise's tape (now in
  prefork); (c) an error with a view field made in a loop round and
  passed on by a caller that is not one call (acme's poll): RESULT
  moved only structs of texts, so the detail read poison. Now
  __iyi_text_move moves a struct's texts whatever else it holds
  (test/ris/struct_view_round_error.ri, plain and poisoned). The
  other shapes (a constructor's view, a loop round's key,
  JSON-viewing strings, builder growth) do not reproduce poisoned.

* A def's result that holds a value an earlier call of the def made is
  taken, and freed with the def: `key = P256PrivateKey.from_bytes(..)`
  then `SigningKey.new(key)` returned a key whose point was gone
  (X509.self_signed wrote a 0-byte public key; fixed in std by drawing
  in SigningKey's constructor, test/ris/signing_key_made.ri). SPEC 1.5
  moves down only the last call's own value: refuse the rest (1.9).

* A view kept past its round through a block's return value is taken:
  `(1..32).map { Certificate.parse(..).serial }` kept 32 views of
  certificates each round freed (std_x509_exercise.ri, now written out
  in its round).

* A field written through a `Pointer` escapes the checker: toml's
  `@path.value = parts` kept a header def's own Array, freed with the
  def, and a refusal naming the path segfaulted (fixed: @path is a plain
  Array refilled, test/ris/toml_header_path.ri). Pointer in std is
  unsafe by design; `ris unsafe` should list such field writes.

* `--use-rimod` checks differently from a source build: toml's exercise
  builds from source, yet from its artifacts is refused in std/json's
  Builder ("live view of Std::Json::Builder ... (opaque contract)",
  serializable:498). std_toml_exercise.sh's artifacts step fails on it.

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

* A constant made through a def that stores, as `NOW = Time.utc(...)`
  through Time::Location::Zone#initialize, is refused as request data
  on the program tape, copy_to(Program.tape) or not: TapeProgramChecker
  has no constant-initializer context (`initializer`,
  tape_program_checker.cr:108). SPEC 1.8. Until then a def makes the
  value (test/ris/time_in_def.ri; refused/time_constant.ri moves to a
  passing test when it lands). checker-open-questions Q5.

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

## 4. SSE stable storage and HTTPS records

* test/ris/sse.ri needs stable storage, then inclusion
  in check.sh: EventParser replaces
  `@line` and `@data` with a new builder in a round, and keeps `@type` and
  `@id_buffer` from `SSE.clean`'s scratch. Give them stable storage.

* HTTPClient HTTPS-records path: `HTTP.https_endpoints` stores `ech`
  bytes and the `ordered` alpn made in its block into the endpoints,
  and passes Arrays where HttpsEndpoint takes views: build them into
  caller-owned storage. Unknown what follows; this path never compiled
  behind a client before. Ordinary pooling now keeps its transport on
  the client's tape; test/ris/client_pool_tls.ri gates two HTTPS
  requests, one connection made and one reused.

* HTTPClient retires a closed HTTP/2 transport slot: its HPACK tables,
  stream IDs and flow windows belong to that connection. Add an in-place
  reset before recycling those slots; overflow safely closes on return.

## 5. Tighten heap_trap

* None open: heap_trap checks each case's outcome (ris2).

## 6. Checker `evaluate` stack use

* None open: call_value keeps `evaluate`'s frame small (ris2).

## 7. Benches

* Unrun check scripts sorted (2026-11-20): windows, wasm and sandbox
  scripts deleted, bounded_gate and 3 timings are TOOLS. The gates below
  fail and sit in gates_reachable.py's BROKEN; each moves to a CI step
  and off BROKEN when it passes.
* collector_free_floor.sh: "a collector is still linked"; samples/ris/
  autocert.ri fails "cannot store a view beyond its owner scope"; "the
  default build broke".
* debug_info.py: no sample builds with --debug (autocert, basics, calc…).
* parallel_exercise.sh: shares_array is refused for the tape-proc reason,
  not the one the script expects.
* runtime_exercise.sh: dependency floor: the runtime puts undefined
  symbols back on the link line (__gmon_start__, _ITM_*…).
* mod_context.sh: imports left ungrounded (autocert calc logline webapp);
  tool dependencies fail on webapp.
* lsp_artifacts.py: the workspace does not build (with source and
  artifact-only); no interface hash.
* lsp_positions.py: hangs (killed after 15 min, no output).
* generic_boundary.py: reads samples/ris now; samples/ris/calc does not
  build: String indexes are UInt8 (calc.ri:37, calc/parser.ri:92 passes
  a byte as Binary's Char op).
* test/speed/metric_port.sh: std/gc dropped from the port and
  `Array.new(n) { }` fixed; the port still needs String indexes as bytes
  (`.ord` on UInt8, Hash(Char) keys) and Coordinates.from_json refers to
  a private constant.

* Build each test/cli program, group refusals by message, fix per group.
  2026-11-20 (seventh round): 123 of 131 build; left acme, autocert,
  fuzz, http_https_records, iterator, router, tls, zip.
  2026-11-20 (sixth round): 117 of 131 programs pass
  `RIS_SCOPE_ERRORS=all bin/ris build --no-codegen FILE`; 14 fail (116
  before this round, 114 after the fifth, 112 after the third, 107
  after the second, 100 before the first). big and websocket build
  again; eiy had broken since the fifth round.
  Names omit std_ and _exercise where present; each failure appears once.

  Sixth round: eiy's `render` returned a Buffer's text from a def's
  scratch (SPEC 1.9); it now writes through an `Eiy::Printer` into a
  local String::Builder grown in place. fuzz: its `class Pool` clashed
  with the prelude's Pool(T) (now CertPool); it still fails on the TLS
  API drift below. The other failures are as the fifth round left them.

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
  - acme: ported 2026-11-20 (see section 1). Checker questions found on
    the way: `String::Builder#append_span(name)` counts as a view of
    *name* (Outgoing#header now counts the span on its own text); a
    `copy_to(RisCurrentTape.new)` result is refused unless it is the
    def's last expression; and these built but read freed memory at
    run time (a checker that passes them is unsound): a struct a
    constructor keeps that views the constructor's answer
    (AcmeClient's directory), a callee's KEEP copy returned or stored
    from a def that is not one call (poll's object, finalize's order,
    a challenge's problem), a key made in a loop round
    (`SigningKey.p256`), a def returning JSON strings it parsed
    (the test's `jws_parts`), and `String::Builder` views kept across
    its growth (AcmeClient keeps its texts in a builder sized up front).
  - The HTTPClient pool: a second request on a pooled HTTPS connection
    segfaults (std_acme_exercise's clients use `idle: 0` until fixed).
  - std_acme_exercise.sh "the artifacts did not build": x509.ri's
    `module Storage` assigns its fields in the module body (lines
    128-135), which `--use-rimod` reads as type-body code to run.
  - autocert: tls.ri:6636 and :7015 (`identity_for` returns an owner)
    and the test at lines 40, 208-229.
  - tls: the group tasks borrow their config and answer through
    `value`; left: `crafted`'s `Array({Int32, Array(UInt8)})` is a
    runtime-sized collection of growing values (SPEC 2.2).
  - http_https_records: the UdpSocket is handed off; left: `zone` is
    shared mutable state between the DNS task and the checks (the
    spawner sets `zone.https` while the task answers): RisBoard messages.
  - fuzz: no parse_request left; TLS API drift as before, plus
    `Server.handle` private and `String#compare`.
  - The checker questions toml/yaml, zip, router, file, log/ocsp/x509
    and iterator (doc/drafts/checker-open-questions/), 2026-11-20:
    file (Q4: read_lines gone), ocsp and x509 (Q5: values made in a
    def, DER appended to the caller's Array), toml and yaml (Q1:
    from_toml/from_yaml are macros as from_json; read_into; RisDecoded
    gone; the round store is refused by 2.2) build. Router's patterns
    live in the router (Q3); router is left on the opaque handler call
    (router.ri:717). Found on the way: `Array == Array::View` was always
    false (test/ris/array_equals_view.ri; ocsp's responder by key hash),
    each_line kept every line on the tape to the end, ocsp's hex wrote
    decimal bytes. Left:
    - log: done 2026-11-20. `bind` answers a `BoundLogger`, a type of
      its own whose `for` makes the child under the program logger
      (test/ris/bound_logger.ri); `Log.context(found)` fills a caller's
      Hash. std_log_exercise.sh holds.
    - zip (Q2 probe): the test's first_error writes the sentence into
      the caller's builder; the first refusal is now the Q2 blame
      itself, in `ZipReader#extract` (zip.ri:513, "a view beyond its
      owner scope", reported at the def's first line).
    - iterator (Q6 probe): see section 1.
    - Run time, 2026-11-20: x509's 0-byte key (a def's result holding
      an earlier call's value, section 2), its 7 stale patch sites and
      the test's kept serial views are fixed; x509.sh is left failing
      only --release: "a P-256 chain checked inside a task, 100 frames
      down" overflows the task's stack. toml's segfault (a header path
      kept through a Pointer, section 2) is fixed; toml.sh is left on
      the --use-rimod refusal (section 2). yaml's sequence hash mixes
      through a Tuple (test/ris/yaml_seq_hash.ri) and its refusal
      programs mark Spot @[OnTape]. file.sh and ocsp.sh pass.

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
  - Program-owned retained data: log (see the checker questions above;
    ocsp and x509 build).
  - Scratch results: toml and yaml build (checker questions above).
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

* TlsConfig system roots: check whether SystemRoots (00130b97e) already
  keeps them. If still read per handshake, make Certificate copyable to
  Program.tape to keep them once.
* Autocert part B: test/cli/std_autocert_exercise.ri and its driver, with
  real TLS deadline and parallel-server cases, Pebble, restarts and
  mutation checks (part A's gates: test/ris/autocert.ri, autocert_wire.ri).
* std_process: the `handlers` mutation proof (child keeps this program's
  TERM handler) is not caught.

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
