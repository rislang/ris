# Koja reference snapshot

Koja is a design source for ris's messages between tasks: a no-GC language
with Erlang-style processes, typed handles and copied messages. These are
reference copies, not ris requirements; [TAPE_SPEC.md](../../../TAPE_SPEC.md)
defines ris.

* Source: https://github.com/priit/koja (local ~/contribute/koja).
* Upstream: https://github.com/koja-lang/koja (site https://kojalang.org).
* Commit: `a8c3ce4b0c90ebcfb95ac348007b7e1611c40967` (2026-10-21).
* Copied on 2026-10-27 from a clean working tree: README, LANGUAGE.md and
  design/*.md; design/archive/ and the code are left out.
* Licence: MIT; the original [LICENSE](LICENSE) is included.

## Start here

* [Language reference](LANGUAGE.md): "Concurrency" covers `Ref<M, R>`,
  `cast`, `call`, `ReplyTo`, `receive` and unbounded mailboxes.
* [Memory model](design/MEMORY-MODEL.md): value semantics without a GC.
* [Supervision](design/SUPERVISION.md) and
  [scheduler protocol](design/SCHEDULER-PROTOCOL.md): process lifecycles.
* [Project README](KOJA_README.md): Koja's own overview.
