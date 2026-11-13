# Administration: periods, roles, assignments and annulment

Reviewed November 10, 2026. Use the [local startup procedure](../README.md#local-startup-four-terminals).

## Academic periods

The administrator panel reads `academic_periods` and creates/edits names, dates and active flags. Dates are inclusive: local start-of-day through the final day's 23:59:59.999, stored as timestamps.

Active periods appear by default. Active/inactive chips combine with immediate, case-insensitive partial ID search. The list has a 360-pixel maximum height and its own scrollbar. Filters survive create/edit operations within the screen. Activity and date validity are distinct.

Repository writes call `saveAcademicPeriod`, which requires an authenticated active administrator, validates ID/dates and records actor/timestamp metadata transactionally. Direct client writes are denied. Declaration creation also checks period activity and validity.

## Role assignment

`assignUserRole` requires an active administrator, an existing target profile and a target different from the caller. Role metadata and `users/{uid}/role_events/roleChanged_vN` are written together. Assigning the current role is idempotent.

Canonical roles: `declarant`, `supervisor`, `humanResources`, `administrator`. Server operations read the current persisted role/active flag. Clients cannot directly change `role` or `active`. The first administrator requires trusted provisioning; there is no public self-promotion endpoint.

## Supervisor assignments

Administration/HR request assignments through `assignDeclarantSupervisor`. It checks actor permissions, active profiles and supervisor role, and records an append-only event. Assignment and role are separate concepts. Direct client assignment/history writes are denied.

## Declaration lookup and annulment

`findDeclarationsForAnnulment` is an administrator-only read callable. Each page checks the persisted active administrator profile in a transaction, queries one period in document-ID order and returns up to 50 rows plus a cursor. Rows contain ID, person ID, period, name, state, version and revision, not payloads or signatures.

The dialog searches name/UID/ID within loaded results and loads further pages on request. It includes inactive periods and locks terminal declarations. Selection fills technical fields read-only; the administrator enters a reason and confirms.

`annulDeclaration` remains the authoritative write operation for permitted administration/HR callers. It requires explicit confirmation, a nonempty reason of at most 2000 characters, expected formal version and revision. It rejects finalized/already-annulled records, stale revisions and inconsistent mirrors. Declaration, mirror and audit event update atomically. The UI clears selection after an attempt and requires reselection before retry.

## Verification

Relevant tests: `test/administrator_dashboard_test.dart`, `test/annulment_picker_test.dart`, `functions/test/annulment_lookup.test.mjs`, `functions/test/administration.test.mjs`, `functions/test/workflow.test.mjs` and `security-tests/rules.test.mjs`.

The lookup unit test intercepts reads without changing emulator data. Integration/rules suites require the [isolated test procedure](../security-tests/LOCAL_EMULATORS.md).
