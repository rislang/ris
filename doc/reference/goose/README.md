# Goose reference snapshot

Goose is a design source for ris's tape memory. These are reference copies,
not ris requirements; [TAPE_SPEC.md](../../../TAPE_SPEC.md) defines ris.

* Source: https://github.com/domify/goose (local ~/contribute/goose).
* Upstream: https://github.com/aardappel/goose.
* Commit: `8511ae34bdc9aabf77baaab80b4d659ea87835e2` (tag `v2026.3`).
* Copied on 2026-10-25 from a clean working tree.
* Licence: Apache 2.0; the original [LICENSE](LICENSE) is included.

## Start here

* [Language specification](docs/goose_spec.md): v4 draft; section numbers
  in ris's tape spec refer to this snapshot.
* [Root structs](docs/design/root_structs.md): the planned owning state
  model, independent regions and borrowing.
* [Owned dynamic data](docs/design/owning_dynamic_data.md): pools, lifetimes
  and resources for independently closed objects.
* [Relative references](docs/design/relative_references.md): link encodings.

Linked Markdown documents are included transitively, with their original
paths. Source documents are byte-for-byte copies; their examples may refer
to code or assets in the full Goose repository that are not copied here.
The 80-line limit for ris documents does not apply to these source copies.

## Updating

Update explicitly from a clean Goose revision, record its commit here and
copy the source documents without edits. Review changed rules against
TAPE_SPEC.md; importing a snapshot does not adopt new Goose rules in ris.
