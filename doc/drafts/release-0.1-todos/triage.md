# Todo clause triage for 0.1.0

Source: `./bin/ris spec todo` on dev4 (17e707bde), 2026-11-15. 27
clauses (24 root, 3 std); NoSpec lines and the xml `todo(...)` calls
in test/cli/std_xml_exercise.ri (TapeNode has no path) are left out.

Verdicts: DONE = built, only a `spec N.M` block is missing; PART =
partly built; NOT = not built, planned after 0.1.0. Evidence paths
are under test/ris/ unless named; "check.sh" is test/ris/check.sh.
Size: S = one block reusing existing programs (< 30 lines), M = a
few new programs, L = new compiler or runtime work first.

Most DONE rows already have a check.sh case; the proof is a spec
block that runs or names those programs, plus `ris spec ack`.

## Root clauses (SPEC.md)

| clause | verdict | evidence | proof plan / missing part |
|---|---|---|---|
| 1.2 | DONE | tape_primitives.ri, std_generic_tape.ri | S: assert each tape |
| | | | type lives on the tape; unboxed dispatch: heap_check.py |
| | | | shows 0 boxes for a union/dispatch program |
| 1.3 | DONE | check.sh:1098 class_finalize, heap_class.ri, | S: refused |
| | | class_share.ri, src/ris/region.ri:200 | finalize + Share; |
| | | | heap_class runs with 0 heap; class_escape refused |
| 1.4 | DONE | array_api.ri, owner_reference.ri | S: `b = a; b << 1` |
| | | | then `a.size` grew; `t = s` keeps text |
| 1.6 | DONE | check.sh:1090-1093 text_literal_heap, | S: literal has no |
| | | borrowed_text.ri, refused/text_lend_literal.ri | tape bytes; param |
| | | | borrow: heap_trap borrowed_text |
| 1.7 | DONE | copy_deep.ri, copy_rollback.ri (check.sh:1050), | M: split |
| | | refused/copy_pointer, copy_link, copy_*_cycle | sharing, no init |
| | | | run, rollback; "deep chains never overflow" needs one |
| | | | deep-chain program |
| 1.8 | DONE | once_in_program_init.ri (check.sh:1024), | S: init order |
| | | thread_program_initializers.ri, program_*.ri, | prints; |
| | | refused/program_copy_forged.ri | forged-owner refusal |
| 2.3 | DONE | refused/owner_byte_image, owner_raw_copy, | proved: |
| | | owner_raw_equality, owner_ffi_layout, | refusals name |
| | | class_copy.ri, board_owner.ri | copy_to(owner) or |
| | | | a lib struct; acked 2026-11-15 |
| 3.1 | DONE | refused/root_branch_escape, root_store_join, | S: name the |
| | | roots_holders.ri (check.sh:836) | refusals and run |
| 4.1 | DONE | cleanup_order.ri (check.sh:1174), | S: expected output |
| | | cleanup_*.ri, typed_group_results.ri | + panic result |
| | | | copied; unwind_failure fatal |
| 4.2 | DONE | size_failure.py, tape_limits.ri (check.sh), | proved: |
| | | doc/TAPE_API.md limits | RIS_TAPE_STATS and |
| | | | TAPE_API.md publish one set of limits; acked |
| | | | 2026-11-15 |
| 4.3 | DONE | signal_flags.ri (check.sh:2567), | S: signal flag |
| | | unwind_failure.ri (check.sh:2611) | test; fatal exit |
| | | | skips a defer (assert output lacks it) |
| 5.4 | DONE | ffi_marked.ri, ffi_callback.ri, refused/ffi_*.ri, | proved: |
| | | raw_pointer.ri, pointer_unsafe_*.ri | a proc literal |
| | | | passed to C attaches a C thread first; a panic in it |
| | | | stops at the C frame; a Proc value refused; 2026-11-15 |
| 5.6 | DONE | board_*.ri, board_checks.sh, refused/board_* | M: spec block |
| | | (board_recursive, board_class_post, not_flat) | calling existing |
| | | | board programs; large clause, many sub-proofs; |
| | | | macOS N=1 refusal not tested here |
| 6.1 | DONE | pool.ri, pool_errors.ri, pool_waste.ri, | proved: |
| | | refused/pool_*.ri (check.sh); src/ris/tape.ri | typed slot |
| | | | reuse, typed replacement, handle generations |
| | | | (odd live), double free and stale handles panic; |
| | | | 2026-11-15 (doc/drafts/pool-t) |
| 6.2 | DONE | pool_free_relocate.ri, slice_pool.ri, | proved: free |
| | | refused/shrink_pool_run*.ri, slice_pool_links.ri | keeps |
| | | | slots; realloc_slice is the explicit move, holders |
| | | | re-read, old views unchanged; 2026-11-15 |
| 6.3 | DONE | slice_pool_errors.ri (check.sh:701), | S: bounds / |
| | | le_offset_overflow.ri, side_overflow.ri | overflow panics |
| | | | before mutation; membership test may need M |
| 6.4 | DONE | load_check.ri, refused/load_foreign_link, | proved: |
| | | load_span_no_text, flat.ri (check.sh) | length, links |
| | | | and spans checked before publish; foreign links |
| | | | refused; no unions in flat types; 2026-11-15 |
| 6.5 | DONE | refused/pool_file.ri, slice_pool_file.ri, | proved: a |
| | | class_finalize.ri; src/compiler/.../call.cr | Pool or |
| | | | SlicePool element holding a class is refused at |
| | | | `new`; 2026-11-15 (doc/drafts/pool-t) |
| 6.6 | DONE | tape_stats.ri, pending_result.ri | proved: one |
| | | (check.sh), src/ris/region.ri | line per owner |
| | | | field by name (`Log.items`: objects, reserved, |
| | | | used bytes; names expanded by the compiler in |
| | | | Tape.note_owner), pool waste (freed slot bytes |
| | | | not yet reused), results moved down; stats on |
| | | | normal end, exit, panic, cancel, exhaustion; |
| | | | 2026-11-15 |
| 7.2 | DONE | stable_growth.ri, hash_api.ri, tree tests, | S: no-move |
| | | string_api.ri | assert after growth; Hash order |
| 7.3 | DONE | text_grow.ri, check.sh:2633 text_plain_builder | S: `t = s; |
| | | refused/text_*_field.ri | s << x` keeps t; refusal |
| | | | message `text = ""` |
| 7.4 | DONE | nested_containers.ri (check.sh:734), | S: change via |
| | | refused/nested_run_*view.ri | outer[i] shows; view |
| | | | after growth refused |
| 7.5 | DONE | long_lived_containers.ri (check.sh:734) | S: store copies, |
| | | | delete returns run (stats) |
| 7.6 | DONE | check.sh:266 tape_block_program_store, | S: refusals name |
| | | refused/yield_escape, return_escape | copy_to(owner) |

## Std module clauses

| clause | verdict | evidence | proof plan / missing part |
|---|---|---|---|
| base64.4 | DONE | src/std/base64.ri:317 | S: decode "QR==" (nonzero |
| | | | unused bits) gives "A"; drop the todo |
| box.3 | DONE | src/std/box.ri:18 | S: `Box.unbox(b.to_unsafe)` is the |
| | | | same object (`same?`); address equals across calls |
| capsule.8 | DONE | src/std/capsule.ri spec capsule.8 | proved: |
| | | | decode and decode? values and datagram payloads |
| | | | are subslices of the input (same?); 2026-11-15 |

## Totals

| verdict | count | clauses |
|---|---|---|
| DONE | 25 | 1.2 1.3 1.4 1.6 1.7 1.8 2.3 3.1 4.1 4.2 4.3 5.4 |
| | | 5.6 6.2 6.3 6.4 6.5 7.2 7.3 7.4 7.5 7.6, base64.4 |
| | | box.3 capsule.8 |
| PART | 1 | 6.6 |
| NOT | 1 | 6.1 |

Total 27 (24 root, 3 std).

Suggested 0.1.0 cut: write the 20 DONE proofs (mostly S); for PART,
narrow the clause to the kept part with a todo for the rest or move
the missing part to a later version; mark 6.1 planned (Pool(T)).

Verdicts were judged from file names, check.sh cases and a short read
of the code; no new programs were run. Verify each while writing its
proof.
