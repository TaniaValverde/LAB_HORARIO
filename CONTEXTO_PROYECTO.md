# Project handoff — DeclaraHorario

Updated November 12, 2026. Read this file and relevant current source before changing behavior. This is maintenance context, not a substitute for inspecting code.

## Scope and repository state

The local delivery includes Flutter Web with Firebase emulators and Socket.IO, project `demo-declara-horario`, plus an Android laboratory module for declaration capture, drafts, validation and summary. Android intentionally stops before oath, signatures, hierarchical approval and HR receipt; the Web workflow retains its existing full lifecycle. Remote deployment/billing is not authorized. Documentation and comments are in English; the UI and collaboration with the user remain in Spanish.

At the start of this documentation pass, branch was `codex/integracion-juramento`, HEAD `92e4b70`. Tracked files were clean. Root export `firebase-export-1794326232909F2RZuz/` was untracked; it was not read, deleted, staged or changed. Always inspect current status rather than treating this snapshot as permanent. Do not commit/push/deploy without a request.

## Startup and shutdown

The [README](README.md#local-startup-four-terminals) is the canonical operational guide. All commands run from the repository root in separate terminals:

1. `npm.cmd --prefix functions run emulators:restore` — builds Functions and restores the newest COMPLETE snapshot; wait for all four emulators.
2. `npm.cmd --prefix functions run backup:watch` — automatic backups every 60 seconds.
3. `npm.cmd --prefix realtime-server start` — local notices with `.env` configured from `.env.example`.
4. `flutter run -d web-server --web-hostname=localhost --web-port=5200 --dart-define=FIREBASE_EMULATORS=true --dart-define=SOCKET_URL=http://localhost:3001`.

Application: http://localhost:5200. Emulator UI: http://127.0.0.1:4000. Auth 9099, Firestore 8180/websocket 9151, Functions 5001, Storage 9199, hub 4400, Socket.IO 3001.

Always include the emulator define; otherwise remote Firebase options are selected. Stop/relaunch Flutter to change defines. Do not restart emulators to troubleshoot a Flutter or notification-only problem.

Before shutdown: finish writes, stop the backup monitor, run `npm.cmd --prefix functions run backup` while emulators remain active, wait for `Backup complete`, then stop services. Do not rely on legacy export-on-exit after Windows EPERM failures. Preserve temporary exports and existing backups. Restore selection checks COMPLETE, not a new checksum audit. Cross-service backups require paused writes for a consistent closing snapshot.

## Current implementation

- Integrated entry point: `lib/main.dart`; `main_demo.dart`/in-memory repositories are retained prototypes.
- Auth/profile/role routing; profile reuse; periods and supervisor assignments.
- Declaration form, draft saving, validation, oath, internal declarant/supervisor signatures, submission, returns/correction versions, status/history, HR receipt, final PDF and finalization.
- Institutional 40/20/10-hour workloads with teaching:consultation ratio 2:1; consultation is included in the selected total. External/legacy appointments retain custom workloads.
- Institutional category selector Interino/En propiedad; optional course code up to 40 characters; automatic time/date separators.
- Weekly preview with horizontal/vertical scrollbars; login and authenticated theme consistency.
- Approved institutional schedule per period, latest version only, requiring superior signature evidence; local PDF/PNG copies distinct from final declaration PDFs.
- Administrative periods show active entries by default; immediate partial-ID search and active/inactive filtering with bounded scrolling.
- Administrator annulment lookup by period, 50-row pages, name/UID/ID search among loaded rows, read-only auto-filled ID/version/revision, explicit reason/confirmation. Terminal rows cannot be selected.
- Socket.IO notices for declarant/supervisor/HR, authorized re-reads and reconnection; no admin notice channel.
- Android uses the existing profile, declaration models, Firestore repositories and validator. Its four-step editor ends at `VALIDADA`; the weekly preview uses vertically stacked day cards on narrow screens. UCR reference colors are in `lib/core/theme/ucr_theme.dart`. The debug-only Android manifest permits local HTTP emulator traffic.

Current detail: [manual](docs/MANUAL_USUARIO.md), [requirements](docs/REQUERIMIENTOS.md), [user stories](docs/HISTORIAS_USUARIO.md), [model](docs/MODELO_FIRESTORE.md).

## Protected contracts

1. One declaration chain per person/period. Initial ID `${personId}_${periodId}`; correction ID `${sourceId}_v${nextVersion}`, linked by `parentVersionId`. Do not overwrite signed/returned source versions.
2. Formal `version` differs from optimistic-concurrency `revision`. Preserve atomic declaration + mirror + audit writes and expected-value guards.
3. Historical signature audit revisions derive from persisted signature identity, not current revision. Preserve canonical SHA-256 payload/version/person/period hashing, actor identity, timestamps, oath evidence and mirror checks.
4. Privileged transitions belong to callables. UI visibility is not authorization. Preserve active-profile, role, ownership and assignment checks in Functions, rules and Socket.IO; Admin SDK bypasses rules.
5. Approved oath registry requires positive integer versions and both configuration/text documents. Test wording is not official approval. Internal signatures are not certified external digital signatures.
6. Final PDF path is `final-declarations/{declarationId}/v{version}.pdf`; access remains through authorized callables. Storage client reads/writes stay denied.
7. Socket.IO carries only `{id,status,version,revision}` and is not state authority. Dispose listeners, reject stale identities and revalidate assignment/access.
8. Preserve payload v1 compatibility: optional `workloadType`, `activity`, `courseCode` are omitted for legacy data. No migration of signed records.
9. Keep asynchronous work outside synchronous Flutter `setState` callbacks.
10. Keep Android laboratory behavior limited to capture, draft persistence, validation and summary. Do not expose oath/signature/approval/HR actions on Android; keep the existing Web workflow and persisted state labels intact.

## Source map

| Area | Entry points |
| --- | --- |
| Startup/theme/auth | `lib/main.dart`, `lib/core`, `lib/features/auth` |
| Declaration storage/editor | `lib/features/declaration/data`, `domain`, `presentation` |
| Schedule validation | `lib/features/validation/domain/validate_schedule.dart`, `functions/src/schedule_validation.ts` |
| Schedule display/exports | Declaration presentation and `lib/features/schedule/presentation` |
| Administration | `lib/features/admin`, `period`, `roles` |
| Privileged workflows | `functions/src/index.ts` |
| Signature hash/final PDF | `functions/src/content_hash.ts`, `final_declaration_pdf.ts` |
| Notifications | `realtime-server/index.mjs`, `server.mjs`, `lib/features/realtime` |
| Local operations | `functions/scripts`, `firebase.json` |
| Security/tests | `firestore.rules`, `storage.rules`, `test`, package test directories |

Admin callables include `saveAcademicPeriod`, `assignUserRole`, `assignDeclarantSupervisor`, `findDeclarationsForAnnulment` and authorized annulment. Declaration/signature/HR callables retain server checks; group names are not permission grants.

## Verification and historical evidence

Dated results and incidents are consolidated in [technical verification](docs/CIERRE_TECNICO.md). Do not present the October 22 baseline of 160 tests or later overlapping targeted counts as a fresh run. Earlier user-confirmed checks cover the full local workflow, correction versions, notices and restored data. Later UI additions have automated evidence but not every path has recorded manual acceptance.

The October 28 missing-oath incident was repaired by restoring only the absent registry documents after backup. No declaration/signature data was replaced. The cause was not proven. Oath fixtures can delete configuration; avoid that suite on the live demo.

Rules tests clear Firestore: use `FIRESTORE_TEST_PROJECT_ID=demo-cierre-reglas`. Functions integration fixtures currently hardcode the demo project; use a disposable suite with no imported working data and no backup monitor. See [isolated testing](security-tests/LOCAL_EMULATORS.md). Do not mistake a test export for a working restore candidate.

## Remaining work and limits

- Await the teammate's Stitch design for possible visual changes; preserve working flows.
- Declaration creation still chooses the first eligible active period; a declarant period selector is not implemented.
- Manual acceptance of new download/annulment paths and complete final-PDF traversal with new fields needs explicit evidence.
- Port-recovery helper needs validation during a real orphan-process incident; do not provoke one.
- Backup retention is undefined; do not delete snapshots automatically.
- No WebAssembly certification, load testing, remote deployment certification, official oath approval or certified external digital-signature service.
- Root exports and credentials must remain out of commits.

## November 10 documentation maintenance

Current guides replace obsolete remote startup, deployment-as-pending-work, initial-only Socket.IO descriptions and custom-workload-only instructions. Documentation filenames are preserved; source comments are translated without changing runtime tokens. Spanish UI/persisted values remain unchanged.

Fresh checks: `flutter analyze --no-pub` completed with no issues. A comparison against HEAD confirmed that all 12 changed source/rules files differ only in full-line comments. All 49 local Markdown links/anchors resolved. `git diff --check` found no whitespace errors. No integration/rules suites were run for this documentation-only pass; no emulator data, runtime logic or dependencies were changed.
