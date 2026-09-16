# Design documents

This directory holds **design docs** for FORCE: proposed or in-flight
architecture writeups that are not yet (or no longer) part of the agent
handoff surface.

## Why not `agents/`?

[`agents/`](../agents/) is the implementation brief for the product **as it is**.
Design drafts, alternatives, and abandoned plans clutter that handoff and go
stale relative to source. Keep speculative and program-of-work docs here;
promote lasting invariants into `agents/*.md` when the work lands.

Game intent (what the player does, not how the C is structured) lives in
[`doc/`](../doc/); see [`doc/README.md`](../doc/README.md). Do not put
campaign or command-language drafts here.

The agents index points here: [`agents/README.md`](../agents/README.md) →
Design docs.

## Status legend

| Status | Meaning |
|--------|---------|
| **active** | Current design work; last touched for an in-progress feature |
| **landed** | Implemented; doc retained for history / follow-ons |
| **abandoned** | Not pursuing; kept only if useful as negative knowledge |

## Index

| Design | Status | Last worked on | Path |
|--------|--------|----------------|------|
| Development plan (phases 0–10, frozen names) | active | 2026-09-13 | [`development-plan.md`](development-plan.md) |
| Phase 0 — Pipeline honesty | landed | 2026-09-13 | [`phase-0-pipeline.md`](phase-0-pipeline.md) |
| Phase 1 — RAM world, 6502-shaped | landed | 2026-09-13 | [`phase-1-ram-world.md`](phase-1-ram-world.md) |
| Phase 2 — Units exist | landed | 2026-09-13 | [`phase-2-units-exist.md`](phase-2-units-exist.md) |
| Phase 3 — Command line | landed | 2026-09-13 | [`phase-3-command-line.md`](phase-3-command-line.md) |
| Phase 4 — Rooms, portals, stepper | landed | 2026-09-13 | [`phase-4-rooms-portals-stepper.md`](phase-4-rooms-portals-stepper.md) |
| Phase 5 — Cover and D | landed | 2026-09-13 | [`phase-5-cover-and-d.md`](phase-5-cover-and-d.md) |
| Cover advancing (directional live sets) | landed | 2026-09-14 | [`cover-advancing.md`](cover-advancing.md) |
| Phase 6 — Combat | landed | 2026-09-15 | [`phase-6-combat.md`](phase-6-combat.md) |
| Phase 7 — Mission script | active | 2026-09-15 | [`phase-7-mission-script.md`](phase-7-mission-script.md) |
| Section roster on the strip | landed | 2026-09-12 | [`section-roster-strip.md`](section-roster-strip.md) |

## Conventions

- One topic per file; kebab-case names.
- Start with Title & Metadata (author, date, Draft/Accepted).
- Cite real source paths and APIs; prefer Mermaid for flows.
- When implementation merges, update this index (active → landed) and fold
  durable rules into the relevant `agents/` note in the same change set when
  practical.
