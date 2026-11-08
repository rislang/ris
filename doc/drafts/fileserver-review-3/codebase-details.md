# Codebase-details review (third review)

Target: doc/drafts/fileserver-outgoing.md

One Major, six Nits, no Blockers. MA1-MA7 fixes hold against code.

## Major

1. Cap memory reasoning (337-344, Risks 543-544).
   src/iyi/region.iyi:523-526: on Linux each growing payload reserves
   128 MiB (SIDE_RESERVE, :529) or its initial capacity if larger,
   never relocating. If `res.body` is one, 1024 answers reserve about
   128 GiB of address space whatever *max* is; "16 GiB at worst" is
   wrong, and a smaller *max* does not lower commit charge under
   `vm.overcommit_memory=2`. Check how Builder bodies reserve.

## Nits

1. Line 135 "check.sh:43-50" is `expect()`, not a list; cite the
   `expect <name>` calls.
2. Line 253: the bodiless branch is http.iyi:2434-2438, not 2433
   (also noted in review 2).
3. Line 336 "io.iyi:165": give src/iyi/io.iyi; src/std/io.iyi:165 is
   `pipe_of`.
4. Line 330: fileserver.iyi:53 is the 405, 104 the 416, 120 the 404;
   reorder.
5. `to_unix(year : Int64?, ..., day : Int64?)` feeds
   `Time.days_from_civil(Int64, Int32, Int32)` (time.iyi:1784): nil
   and Int64-to-Int32 handling unsaid.
6. http.iyi:2479 and :2486 are duplicate `check_line` overloads.

## Claims checked, correct

* http.iyi: Outgoing doc 2213-2217, LINES 2220, new/block 2219;
  `header` 2246-2256, raise 2249-2251, views stored 2254;
  `each_line` sole caller `format_head` 2428; `format_head`
  2419-2442; `format_response` 2444-2447; `answered_on_tape?`
  2451-2461 (calls 2455; called 2376, 2412); MAX_CONNECTIONS
  2515-2517; panic note 2582-2584; Response `format_head` 3296;
  other `format_response` callers (2985, 3024) take Response.
* tape.iyi: `as_tape` identity 214; `String#[](span)` 524;
  `reserve` 895-898 (to_i32); `grow`/`owned_resize` 902-917;
  `append_span` 919-924; `truncate` 881.
* src/iyi/io.iyi:165 `read_str`; src/iyi/file.iyi:28, 32-38;
  src/std/file.iyi:2141 `IyiIO`, `seek` 2150; http_head.iyi:195, 206.
* mime.iyi:28; dir.iyi 464, 590; log.iyi :20, 1041, 1045;
  time.iyi 1784, 2271-2273, 3635, 2776.
* fileserver.iyi :51, 1-3, 13-14, 36-37, 49-50, 112.
* server_groups.ri:76, samples/ris/serve.ri:72,
  std_text_plain.ri:41, router.iyi:527,
  bench/std_fileserver_exercise.sh:199, bench/std_siblings.sh:46,
  src/socket.cr:372, tape_shrink_checker.cr:514-548 (515),
  check.sh:1187-1188.

Not checked: bench/std_fileserver_exercise.iyi:56-131; probes P1-P8
not rerun.
