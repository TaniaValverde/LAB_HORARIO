# Declaration form and validation

This guide covers the authenticated declarant workflow (HU-01, HU-02 and HU-05–HU-14) through `validated`, plus its integration boundaries. Start `lib/main.dart` using the [four-terminal procedure](../README.md#local-startup-four-terminals).

## Data entry

Authentication uses provisioned Email/Password accounts. A missing own profile is created with the default declarant role; existing profiles are not silently elevated. Profile data includes name, identification, phone, email and unit. The form keeps its own snapshot and can explicitly save changes back to the profile.

A deterministic initial ID and transaction prevent duplicate chains for a person/period. The current creation use case selects the first active valid period. Signed/returned versions are read-only; corrections create new documents.

Institutional appointments collect workplace, category (Interino/En propiedad), optional course code, workload type, validity dates and recurring teaching/consultation blocks. External jobs collect institution, free-text position, custom weekly workload, dates and blocks. Observations are optional.

Time/date input inserts separators automatically. The weekly preview updates with form edits and provides both scrollbars. See the [manual](MANUAL_USUARIO.md#appointments-and-teaching-workloads) for exact workload distributions and input examples.

## Validation rules

- Monday through Saturday; 24-hour times with end after start. No overnight intervals.
- Exclude any intersection with `[12:00, 13:00)`; users split blocks themselves.
- Adjacent blocks such as 08:00–10:00 and 10:00–12:00 do not overlap.
- Compare institutional and external jobs, including two external jobs.
- Report a conflict only when validity dates intersect and include an occurrence of the block's weekday.
- Limit combined work to 600 minutes per day on concurrent dates.
- Compare weekly declared minutes to each appointment's expected workload.
- For typed institutional workloads, teaching and consultation must exactly complete the selected 40/20/10-hour total in a 2:1 ratio.
- Preserve legacy custom workload validation unless explicitly adapted; signed data is not migrated.
- Validate optional course codes (up to 40 characters) without requiring them on historical records.

Drafts may retain incomplete schedules. Final validation rejects blocking errors. Saving an editable validated declaration as a draft returns it to `draft`; stale revisions require refresh. Server validation in `functions/src/schedule_validation.ts` independently checks content before protected workflow actions.

## Integration contracts

`DeclarationForm` interprets payload schema version 1. Appointments and observations stay inside the formal version, so signatures/PDFs refer to the same content. Dates use `YYYY-MM-DD`; times and workloads use integer minutes. See the [data model](MODELO_FIRESTORE.md).

The real Firestore repository coordinates declaration, mirror and canonical audit event transactionally. `version` and `revision` are distinct. Client updates remain limited to permitted draft/validation changes; oath, signatures and privileged transitions use authorized callables.

`DeclarationPage`, `main_demo.dart`, in-memory repositories, prototype transition use cases and simulated PDF generation are retained references only. They are not evidence of authenticated persistence or server authorization and are not the normal startup path.

## Checks and limits

Relevant tests include declaration editor/flow, schedule validation, teaching workload/UI, input formatter, approved schedule and security tests. Follow the [isolated test guide](../security-tests/LOCAL_EMULATORS.md) before running emulator-backed suites.

Internal signatures are not certified external digital signatures. Official oath approval and remote deployment are outside the current local demonstration. No changes to validation behavior are implied by translating this documentation.
