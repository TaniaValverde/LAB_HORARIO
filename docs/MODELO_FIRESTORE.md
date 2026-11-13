# Firestore data model

Reviewed November 10, 2026. Privileged operations use callable Functions and Admin SDK; direct equivalent client writes are denied.

## Collections and write ownership

| Path | Purpose | Writer |
| --- | --- | --- |
| `users/{uid}` | Profile, role and active flag | Limited own-profile writes; role callable |
| `users/{uid}/role_events/{eventId}` | Role history | `assignUserRole` |
| `academic_periods/{periodId}` | Name, dates and active flag | `saveAcademicPeriod` |
| `supervisor_assignments/{declarantId}` | Current supervisor assignment | `assignDeclarantSupervisor` |
| `supervisor_assignments/{declarantId}/events/{eventId}` | Assignment history | Assignment callable |
| `declarations/{id}` | One formal declaration version and current workflow state | Guarded draft/validation client writes; privileged callables |
| `declarations/{id}/versions/{version}` | Coordinated mirror of that formal version | Same transaction as the declaration |
| `declarations/{id}/events/{eventId}` | Append-only audit | Restricted client creation/update events; protected server events |
| `system_config/declarant_oath` | Approved text pointer | Trusted provisioning |
| `institutional_texts/declarant_oath/versions/{N}` | Versioned oath wording | Trusted provisioning |

`academic_periods` is the actual collection name; there is no parallel `periods` collection in the integrated repositories.

## Identity, versions and revisions

There is one declaration chain per person and period. The first document ID is `${personId}_${periodId}`. A correction uses `${sourceId}_v${nextVersion}` and stores `parentVersionId`; the returned document and its signatures/history remain unchanged.

`version` identifies the formal workflow version. `revision` is a separate optimistic-concurrency counter. Draft edits and privileged transitions atomically maintain declaration, version mirror and audit event. The `versions` subcollection is not a substitute for the separate documents in the correction chain.

Fields include `personId`, `periodId`, `status`, `version`, `revision`, `parentVersionId`, `createdAt`, `updatedAt`, `payload`, oath/signature evidence, return observation, HR receipt, finalization and PDF metadata. Server-specific evidence fields are not all represented by the Dart entity; inspect Functions and serializers before changing the schema.

Persisted states:

```text
draft -> validated -> pendingDeclarantSignature -> signedByDeclarant
-> pendingSuperiorSignature -> signedBySuperior -> sentToHr
-> receivedByHr -> finalized
```

Additional states are `returned` and `annulled`. Spanish state labels are presentation values, not stored enum names.

## Payload v1

```text
schemaVersion: 1
profile: {name, identification, phone, email, unit}
appointments: [Appointment]
externalJobs: [Appointment]
observations: string

Appointment: {id, workplace, position, weeklyMinutes, startsOn, endsOn,
              institution, blocks, optional workloadType, optional courseCode}
Block: {day, start, end, optional activity}
```

Dates use `YYYY-MM-DD`; day is Monday (1) through Saturday (6). Start/end and weekly workloads use integer minutes. Institutional `position` is selected as Interino/En propiedad in the UI; external positions remain free text. Historical values remain readable.

Optional `courseCode` identifies an institutional course, with a nonempty value of at most 40 characters. The UI trims it and omits the key when empty. It is not added to external jobs. Dart and server validation check it, and reviews/PDFs display it.

New institutional appointments use `workloadType`: `fullTime` (2400 minutes), `halfTime` (1200), or `quarterTime` (600). Blocks use `activity`: `teaching` or `consultation`. Teaching is two thirds of the total; consultation is one third, i.e. 30 consultation minutes per teaching hour. Validation/signatures require exact totals and classified blocks when a workload type exists.

These are compatible optional extensions of payload v1. Legacy records omit these fields and keep custom workloads; untyped appointments cannot contain classified activities. Signed documents are not migrated. External jobs preserve the previous contract. Canonical hashing covers new fields without changing its algorithm.

## Signatures and audit

Signature identities and timestamps link to historical canonical audit events. SHA-256 hashes cover canonical `{payload, version, personId, periodId}`. Preserve sorted-key serialization, historical actor identity, oath evidence and mirror equality checks.

Historical signature revisions must be derived from the persisted signature identity, not the current declaration revision. No handwritten signature image is stored. Older audit records may lack newer hash fields and remain readable; do not infer that new privileged transitions may omit required evidence.

## PDFs, schedules and access

Final PDFs are generated server-side at `final-declarations/{declarationId}/v{version}.pdf` in Storage, with the path stored as `finalPdfPath`. Direct Storage client reads/writes are denied. Authorized callables generate/download the file and verify current access/evidence.

Weekly previews and approved schedule PDF/PNG exports are derived views; they add no collections or state transitions. Approved exports include institutional appointments only and are distinct from final declaration PDFs.

Administrator annulment lookup returns paginated metadata through `findDeclarationsForAnnulment`; it does not broaden direct Firestore access or expose payload/signatures. Socket.IO emits only `{id,status,version,revision}`.

See [user stories](HISTORIAS_USUARIO.md) for implementation traceability and [requirements](REQUERIMIENTOS.md) for validation rules.
