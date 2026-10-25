# iyi reference snapshot

Use this documentation for inherited language, compiler and library
behaviour instead of rewriting it for ris. ris-specific rules take
precedence: [AGENTS.md](../../../AGENTS.md),
[TAPE_SPEC.md](../../../TAPE_SPEC.md) and [LEARN.md](../../../LEARN.md).

* Source: https://github.com/priit/iyi (local ~/contribute/iyi).
* Upstream: https://github.com/iyilang/iyi.
* Base commit: `c02af8facce2e40082e00611db1288cbae397622`.
* Base version: `v0.17.0-2-gc02af8fac`.
* SPEC.md updated from `1d1c96e495d9212c72007c5356d741190f2c95b1`.
* SPEC.md version: `v0.19.1`; copied on 2026-10-25 from a clean tree.
* Copied on 2026-10-25 from a clean working tree.
* Licence: Apache 2.0; [LICENSE](source/LICENSE), [NOTICE](source/NOTICE.md).

## Start here

* [iyi overview](source/README.md): imports, modules, tools and std APIs.
* [Language specification](source/SPEC.md): inherited language rules.
* [Changelog](source/CHANGELOG.md): changes up to this snapshot.
* [Agent tooling plan](source/AI_FIRST.md): historical design and evidence.
* [Manual pages](source/doc/man/): inherited Crystal commands.

SPEC.md is from iyi 0.19.1; other files remain at the base revision above.
Check the current implementation when behaviour differs. This snapshot
does not replace the inherited SPEC.md at ris's root. The GC design is
reference history, not ris's memory roadmap.

Root Markdown files, licence metadata and doc/ are copied under source/
without edits, preserving their relative layout. Links to source code,
samples or other repository files may require the full iyi checkout.
The 80-line limit for ris documents does not apply to these source copies.

## Updating

Copy explicitly from a clean iyi revision and record its commit here.
Preserve source documents unchanged; describe ris differences in ris docs.
doc/archive/iyi/ holds the separate history previously inherited by ris.
