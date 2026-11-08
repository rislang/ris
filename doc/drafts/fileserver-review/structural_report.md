# Structural review (egm-structural)

## Blocker
1. No Alternatives Considered: list (a) keep Response + copy out
   (SPEC 1.9 forbids), (b) streaming Outgoing body first (bigger
   std/http change), (c) keep old def beside (AGENTS.md rule),
   (d) leave serving to caller (no ranges/caching).

## Major
2. No Goals / Non-goals section (streaming, Router port, cap).
3. Risks incomplete: path traversal kept how, file size change between
   reserve and read, address space with many large requests.
4. Open questions hold decisions: Q1 -> Alternatives, Q3 -> Risks;
   give a proposed default for each remaining question.

## Nit
5. Problem should come before Change.
6. Indented code blocks; use fenced blocks.
7. Section names vs standard.
