# Local technical verification record

This document preserves dated evidence. Historical counts are not current totals or a new execution on November 10, 2026. Scope is local Firebase Emulator Suite and Socket.IO, not remote deployment or an exhaustive security audit.

## October 22, 2026 baseline

| Check | Recorded result |
| --- | --- |
| Flutter analyze | No issues |
| Flutter test | 66 passed |
| Functions build and integration | Build succeeded; 56 passed |
| Socket.IO tests | 4 passed |
| Firestore/Storage rules | 34 passed |
| Flutter Web debug | JavaScript compiled |

Recorded total: 160 tests. Rules used isolated `FIRESTORE_TEST_PROJECT_ID=demo-cierre-reglas`. Expected permission errors occurred in negative tests. Security-test dependency audit reported zero vulnerabilities at that time, not an assurance about today's dependencies or other packages.

User-confirmed manual checks at that stage:

- Draft, validation, oath, declarant signature, supervisor submission/signature, HR receipt, PDF and finalization.
- Return, correction version 2 and finalization while retaining version 1.
- Role-visible restrictions, notification isolation, reconnection and supervisor/HR inbox refresh.
- Backup restoration with accounts, declarations and PDF downloads; automatic backup monitor.

Screenshots/videos were managed by the user, not added to the repository. A closing backup was recorded as `functions/firebase-export-backups/snapshot-1792699418180`; later snapshots may exist. This identifier is historical, not the current restore target.

## October 27–28, 2026 additions

Recorded at implementation time; do not add overlapping test counts together:

| Change | Recorded automated evidence |
| --- | --- |
| Automatic time separators | Analyze clean; 22 targeted Flutter tests passed |
| Teaching/consultation workloads and preview | Analyze clean; 81 Flutter tests; Functions build; 18 pure backend tests |
| Scrollbars, category selector and login theme | Analyze clean; 10 targeted Flutter tests |
| Automatic date separators | Analyze clean; 26 targeted Flutter tests |
| Course code | Analyze clean; 30 targeted Flutter tests; Functions build; 20 pure backend tests |
| Oath error explanation/local registry recovery | Analyze clean; 13 targeted Flutter tests; compiled handler returned test text version 1 |
| Approved schedule PDF/PNG | Analyze clean; 7 tests; local JavaScript build; PNG fixture visually inspected |
| Period filters | Analyze clean; 3 administrator dashboard tests |
| Annulment selector | Analyze clean; 4 Flutter tests; Functions build; 1 lookup unit test with intercepted reads |

The oath recovery restored only the missing configuration and text version from `snapshot-1792675961221`, preserving the original test wording and approval timestamp. Before/after backups were `snapshot-1793204480419` and `snapshot-1793204625454`, both recorded complete. The deletion cause was not proven. This did not establish real institutional approval or a new HTTP authentication test.

Later screenshots showed the period filtering/editing interface. Not every added feature has a recorded end-to-end acceptance check. In particular, do not claim a real annulment was executed merely because the selector was tested. Approved schedule browser downloads and final PDF traversal with all new fields still require explicit manual evidence.

## Known limits

- Windows export-on-exit EPERM failures: use explicit backup/restore. Preserve recoverable temporary exports.
- Port-recovery helper syntax was checked; manual validation during a real orphan-process incident remains pending.
- JavaScript Web builds succeeded. Optional WebAssembly checks encountered `socket_io_common` limitations; WebAssembly is not certified.
- No load test or production capacity claim; supervisors maintain per-declarant listeners.
- No administrator notifications, remote deployment certification, certified external digital signature or real email-delivery verification.
- Declaration creation selects the first eligible active period.

## Documentation maintenance — November 10, 2026

Documentation and source comments were reviewed against the current code and translated into English. Current guides replace obsolete deployment/startup/prototype instructions; this historical record remains explicitly dated. Runtime logic, dependency versions, stored data and Spanish UI strings are outside this documentation change.

Fresh checks: `flutter analyze --no-pub` passed with no issues; 12 modified source/rules files were verified to have comment-only differences; 49 local Markdown links/anchors resolved; `git diff --check` found no whitespace errors. No emulator integration/rules tests were needed or executed for this documentation-only pass. Follow the [README](../README.md) for operation and the [isolated test guide](../security-tests/LOCAL_EMULATORS.md) for destructive suites.
