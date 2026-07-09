# Atlas RFCs

Design decisions for Atlas are proposed and recorded here as numbered RFCs
("Request for Comments"). An RFC is written **before** the code it describes.

Atlas v1.0 froze the architecture (`docs/architecture.md`). From v1.1 onward,
every module — and any change that affects the module contract, the engine, or a
cross-cutting convention — starts as an RFC so the design is reviewed once, in
writing, before implementation.

## Process

1. **Draft.** Author writes `RFC-NNNN-<slug>.md` (copy the shape of RFC-0001).
   Status: `Proposed`.
2. **Review.** The maintainer reviews the design and the "Decisions requiring
   approval" section. Amendments happen in the RFC, not in code.
3. **Accept.** On approval the status becomes `Accepted` and the RFC is merged.
   Only then does implementation begin (its own branch / commit series / review).
4. **Supersede.** An RFC is never rewritten after acceptance; a later RFC
   supersedes it and links back.

## Status values

`Proposed` → under review · `Accepted` → approved, implement · `Implemented` →
shipped · `Superseded by RFC-NNNN` · `Rejected`.

## Index

| RFC | Title | Status |
|-----|-------|--------|
| [0001](RFC-0001-git-module.md) | Git module (reference implementation) | Accepted |
| [0002](RFC-0002-remove-verb.md) | Platform verb: `remove` | Proposed |
