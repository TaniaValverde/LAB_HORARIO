# Delivery scope and shared work

Reviewed November 10, 2026. The agreed delivery is a local Flutter Web application with Firebase emulators and Socket.IO. Remote Hosting is not an outstanding requirement of this local delivery; any future deployment needs separate authorization and configuration.

## Integrated responsibilities

The original form work covers HU-01, HU-02 and HU-05–HU-14 through validated state. The integrated application also implements period/role administration, oath acceptance, internal signatures, supervisor review/returns, correction versions, history, HR receipt, final PDF and finalization through trusted callables.

Workload classification, course codes, weekly previews, approved schedule downloads, period filtering and annulment lookup are part of the current interface. The in-memory demo remains a prototype and is not evidence of authenticated persistence.

## Current boundaries

| Area | Current state and remaining work |
| --- | --- |
| UI | Spanish light/dark interface; future visual refinement may follow the teammate's Stitch design without changing workflow contracts |
| Architecture | Presentation/domain/data separation; preserve shared contracts during changes |
| Firebase | Local Auth/Firestore/Functions/Storage integration; no remote rollout authorized |
| Versioning | Separate correction documents, immutable signed content, coordinated mirrors and revisions |
| Authorization | Server role/ownership/assignment checks plus restrictive direct-client rules |
| Oath | Test wording may support local demos; real institutional wording requires separate approval/publication |
| Signatures | Internal evidence with hashes and timestamps, not certified external digital signatures |
| Notifications | Declarant, supervisor and HR; no administrator notices |
| Data safety | Explicit backup before shutdown, restore latest COMPLETE snapshot; retention policy still undefined |
| Evidence | Dated automated/manual results in the technical record; new visual flows need their own acceptance evidence |

## Manual acceptance checklist

- Sign in by role and verify data isolation.
- Save/reopen drafts and verify persistence, including course codes and classified blocks.
- Check overlaps, lunch, daily limits and teaching/consultation totals; correct errors and validate.
- Accept test oath, sign, submit, review, receive, generate/download final PDF and finalize.
- Return a separate test declaration and correct it through a new version without altering historical evidence.
- Inspect the approved schedule and download PDF/PNG for an eligible period.
- Check active/inactive filters and partial ID search; inspect annulment candidates without confirming unintended actions.
- Verify narrow/wide layouts, theme changes, notification isolation and reconnection.
- Back up, wait for completion and restore in a later session; preserve screenshots without credentials/private data.

Test existence does not imply all items were manually accepted. See [technical verification](CIERRE_TECNICO.md) for historical evidence and [user stories](HISTORIAS_USUARIO.md) for traceability. Do not retrospectively rewrite accepted oath text or signed documents.
