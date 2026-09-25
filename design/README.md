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
| Cover claim — one bit per chip, not a slot scan | active | 2026-09-25 | [`cover-claim.md`](cover-claim.md) |
| Door crossings — one list per doorway, one formation per order | landed | 2026-09-25 | [`door-crossings.md`](door-crossings.md) |
| Tick cost — spread steps, cheapen the weapon scans | landed | 2026-09-25 | [`tick-cost.md`](tick-cost.md) |
| Frame schedule — one world_tick on three video rasters | landed | 2026-09-24 | [`frame-schedule.md`](frame-schedule.md) |
| Development plan (phases 0–10, frozen names) | active | 2026-09-13 | [`development-plan.md`](development-plan.md) |
| Phase 0 — Pipeline honesty | landed | 2026-09-13 | [`phase-0-pipeline.md`](phase-0-pipeline.md) |
| Phase 1 — RAM world, 6502-shaped | landed | 2026-09-13 | [`phase-1-ram-world.md`](phase-1-ram-world.md) |
| Phase 2 — Units exist | landed | 2026-09-13 | [`phase-2-units-exist.md`](phase-2-units-exist.md) |
| Phase 3 — Command line | landed | 2026-09-13 | [`phase-3-command-line.md`](phase-3-command-line.md) |
| Phase 4 — Rooms, portals, stepper | landed | 2026-09-13 | [`phase-4-rooms-portals-stepper.md`](phase-4-rooms-portals-stepper.md) |
| Phase 5 — Cover and D | landed | 2026-09-13 | [`phase-5-cover-and-d.md`](phase-5-cover-and-d.md) |
| Cover advancing (directional live sets) | landed | 2026-09-14 | [`cover-advancing.md`](cover-advancing.md) |
| Phase 6 — Combat | landed | 2026-09-15 | [`phase-6-combat.md`](phase-6-combat.md) |
| Phase 7 — Mission script | landed | 2026-09-15 | [`phase-7-mission-script.md`](phase-7-mission-script.md) |
| Phase 7 follow-on — Retreat verb (`R`) | landed | 2026-09-16 | [`phase-7-retreat.md`](phase-7-retreat.md) |
| Phase 9 slice — `S` / `J`, `M` rewrite, `.` nudge (before Phase 8) | landed | 2026-09-17 | [`phase-9-s-j-nudge.md`](phase-9-s-j-nudge.md) |
| Phase 8 — Intel and camera | landed | 2026-09-21 | [`phase-8-intel-camera.md`](phase-8-intel-camera.md) (camera/`C`/`E` kept; scaled `Z` and fog hide cut) |
| Section roster on the strip | landed | 2026-09-12 | [`section-roster-strip.md`](section-roster-strip.md) |

## Conventions

- One topic per file; kebab-case names.
- Start with Title & Metadata (author, date, Draft/Accepted).
- Cite real source paths and APIs; prefer Mermaid for flows.
- When implementation merges, update this index (active → landed) and fold
  durable rules into the relevant `agents/` note in the same change set when
  practical.
