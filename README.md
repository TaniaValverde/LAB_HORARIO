# DeclaraHorario

Flutter application for the IF0009 Integrative Project 2, Universidad de Costa Rica. Documentation reviewed November 12, 2026. The interface remains in Spanish; documentation and source comments are in English.

## Current scope

The Web application runs locally with Firebase emulators and Socket.IO, using `demo-declara-horario`. The integrated entry point is `lib/main.dart`: authentication, profiles, periods, roles, supervisor assignments, declarations, validation, oath acceptance, internal signatures, returns, correction versions, audit history, HR receipt, final PDF and finalization. The Android laboratory module reuses that application but is limited to listing, capturing, saving, validating and reviewing declarations; it does not offer signatures, hierarchical approvals or HR receipt.

Current additions include teaching/consultation workloads, automatic time/date separators, course codes, responsive mobile weekly previews, approved schedule PDF/PNG exports, period filters and declaration lookup for annulment. See the [user manual](docs/MANUAL_USUARIO.md).

`main_demo.dart` and in-memory repositories are retained prototypes, not the integrated workflow. Remote Firebase configuration exists but remote deployment is outside this delivery. Omitting `FIREBASE_EMULATORS=true` selects remote options.

## Prerequisites and first-time setup

- Flutter compatible with the Dart constraint in `pubspec.yaml` (currently `^3.13.2`).
- Node.js 22, npm, Firebase CLI and a compatible Java runtime for the emulators.
- Available local ports listed below.
- A complete backup for the normal restore procedure.

Use PowerShell from the repository root. Install dependencies once:

```powershell
flutter pub get
npm.cmd --prefix functions ci
npm.cmd --prefix realtime-server ci
```

Create `realtime-server/.env` from `.env.example` in that directory only if it does not already exist. Preserve existing configuration. Local values:

```dotenv
PORT=3001
HOST=127.0.0.1
ALLOWED_ORIGINS=http://localhost:5200
FIREBASE_PROJECT_ID=demo-declara-horario
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
FIRESTORE_EMULATOR_HOST=127.0.0.1:8180
```

Do not commit local environment files, credentials, emulator accounts or exports.

## Local startup: four terminals

Keep each service running in its own terminal. All commands below run from the repository root.

### Terminal 1 — Firebase emulators and restored data

```powershell
npm.cmd --prefix functions run emulators:restore
```

This builds Functions and imports the newest backup folder marked `COMPLETE` from `functions/firebase-export-backups/`. Selection uses folder names; the restore script does not recalculate checksums at startup. Wait until Auth, Firestore, Functions and Storage are ready.

If no backup exists, use the [new-environment procedure](#new-environment-without-a-backup) instead.

### Terminal 2 — Automatic backups

```powershell
npm.cmd --prefix functions run backup:watch
```

Keep the monitor running while you work. It backs up every 60 seconds. Successful attempts end with `Backup complete`.

### Terminal 3 — Notification server

```powershell
npm.cmd --prefix realtime-server start
```

This uses the local environment configured above. Socket.IO sends notifications; it does not perform declaration transitions.

### Terminal 4 — Flutter Web

```powershell
flutter run -d web-server --web-hostname=localhost --web-port=5200 --dart-define=FIREBASE_EMULATORS=true --dart-define=SOCKET_URL=http://localhost:3001
```

Open **[http://localhost:5200](http://localhost:5200)** in your browser.

The separate emulator management interface is **[http://127.0.0.1:4000](http://127.0.0.1:4000)**.

Do not omit `FIREBASE_EMULATORS=true`. Changing Dart defines requires stopping and relaunching Flutter; hot restart does not change them.

## Safe shutdown and backups

1. Finish application writes.
2. Stop the backup monitor in Terminal 2 with **Ctrl+C**.
3. While the emulators are still running, execute in Terminal 2:

```powershell
npm.cmd --prefix functions run backup
```

4. Wait for **`Backup complete`**. `BACKUP FAILED` does not indicate a completed backup.
5. Stop Flutter, Socket.IO and then the emulators with **Ctrl+C** in their respective terminals.

Backups include Auth, Firestore and Storage. They are not a transaction across services: avoid writes during the final backup. A monitor cannot preserve changes made after its last successful snapshot during a power failure.

Do not use the legacy `functions run emulators` export-on-exit procedure: Windows EPERM failures were observed. The backup script can recover rename failures through verified copying and preserves temporary exports. Backups are not automatically pruned. Root-level `firebase-export-*` folders may not be ignored by Git; preserve and review them before staging files.

## New environment without a backup

After dependency installation, start Terminal 1 with:

```powershell
npm.cmd --prefix functions run build
firebase.cmd emulators:start --project demo-declara-horario --only auth,firestore,functions,storage
```

Prepare fictitious data in Emulator UI:

1. Create Email/Password accounts in Authentication for the four roles.
2. Create matching `users/{uid}` profiles with `active: true`, `role`, `name`, `identification`, `phone`, `email` and `unit`. Canonical roles: `declarant`, `supervisor`, `humanResources`, `administrator`. The first administrator requires trusted provisioning; there is no self-promotion route.
3. Use Administration to create an active academic period whose dates include today.
4. Use the administrator or HR assignment panel to assign an active supervisor to the declarant.
5. Provision the emulator-only oath registry described in [oath integration](docs/INTEGRACION_JURAMENTO.md). Test wording is not official institutional approval.
6. Run `npm.cmd --prefix functions run backup` while emulators remain active; wait for `Backup complete`. Continue with Terminals 2–4.

There are no universal test passwords in the repository.

## Local ports

| Service | Port |
| --- | --- |
| Flutter Web | 5200 |
| Socket.IO | 3001 |
| Emulator UI / hub | 4000 / 4400 |
| Functions | 5001 |
| Firestore / websocket | 8180 / 9151 |
| Authentication | 9099 |
| Storage | 9199 |

## Android development

The Android target uses package ID `cr.ac.ucr.declarahorario`. For a physical phone, connect by USB, enable USB debugging, authorize this computer, and confirm `adb devices` lists it as `device`. Forward the local emulator and notice ports with `adb reverse tcp:8180 tcp:8180`, `adb reverse tcp:9099 tcp:9099`, `adb reverse tcp:5001 tcp:5001`, `adb reverse tcp:9199 tcp:9199` and `adb reverse tcp:3001 tcp:3001`. Start the local emulators and Socket.IO server using the existing localhost procedure, then run `flutter run -d <device-id> --dart-define=FIREBASE_EMULATORS=true --dart-define=SOCKET_URL=http://127.0.0.1:3001`. On the standard Android Emulator, the app detects the emulator and uses `10.0.2.2` for local services; use `--dart-define=SOCKET_URL=http://localhost:3001` so the notification client can map that host too. The debug-only Android manifest permits the HTTP connections required by local emulators; this permission is not enabled in the release manifest. No production Firebase configuration or signing credentials are included.

### Mobile laboratory scope and design rationale

- The Android dashboard reuses the authenticated declarant profile, Firestore declaration repository, declaration form model, schedule validator and existing status labels. It lists existing declarations, opens drafts and creates a declaration in an eligible period.
- The mobile editor uses four focused steps (personal data, appointments, weekly schedule and review). Schedule blocks appear as vertically stacked day cards on narrow screens; desktop retains the scrollable weekly grid. The summary totals actual block minutes, and validation displays actionable errors, including the exact conflicting intervals.
- Drafts and validated declarations use the existing Firestore persistence and audit write path. Reopening the declaration list retrieves saved work. A declaration cannot become `VALIDADA` while required fields, hours or schedule conflicts are invalid.
- Android stops at validation. It does not accept an oath, record a signature, send work for hierarchical approval, or claim HR receipt. The existing Web workflow remains unchanged.
- UCR reference colors are centralized in `UcrTheme`: blue `#005DA4`, sky `#00C0F3`, white `#FFFFFF`, yellow `#FFE06A` and green `#6DC067`. Yellow, green and sky surfaces use dark foregrounds; tests check at least 4.5:1 contrast for configured text pairs. Arial is selected as the assignment's permitted substitute when available. No UCR emblem, signature or logo is included or reconstructed; the Oficina de Comunicación Institucional's guidance restricts symbol use and alteration. The official 2019 manual URL cited by the assignment returned HTTP 403 in this environment, so exact manual page numbers still need confirmation from an accessible copy.
- Reused Web components are the declaration/profile and appointment models, Firestore repositories, validation use case, status definitions, schedule editor, profile repository and theme state. The principal small-screen adaptation is replacing the six-column preview with day cards while retaining the same validator and persistence contracts.
- The README answers the required reflection: the shared domain/data services avoided a second backend; the main small-screen challenges were dense schedule tables, long forms and precise time entry; the color tokens and contrast checks provide a consistent accessible palette; integrating signatures later would require an explicitly scoped mobile flow with the existing server-side identity, ownership, assignment, oath and audit checks rather than local UI-only signatures.

**Evidence still required for the academic hand-in:** capture the dashboard, weekly schedule and validation/summary on an Android emulator or device, and record a demonstration no longer than two minutes using fictitious data. These files are intentionally not fabricated. The exact pages of the official identity manual also remain to be added when its source is available.

If Firestore ports remain occupied after shutdown, identify their owner first. The recovery helper is:

```powershell
npm.cmd --prefix functions run emulators:free-ports
```

It requires a matching demo Firestore process with a closed parent and confirmation that a complete backup contains the intended data. It does not replace backup or authorize stopping unrelated Java/Node processes.

## Verification

Checks that do not modify the working emulator dataset:

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=FIREBASE_EMULATORS=true --dart-define=SOCKET_URL=http://localhost:3001
npm.cmd --prefix functions run build
node --test functions/test/content_hash.test.mjs functions/test/schedule_validation.test.mjs functions/test/final_declaration_pdf.test.mjs functions/test/annulment_lookup.test.mjs
npm.cmd --prefix realtime-server test
```

Optional local Web build:

```powershell
flutter build web --debug --no-wasm-dry-run --dart-define=FIREBASE_EMULATORS=true --dart-define=SOCKET_URL=http://localhost:3001
```

**Do not run full Functions integration or rules suites against the working demo dataset.** Rules tests clear Firestore; oath fixtures can delete shared configuration. Follow the [isolated test guide](security-tests/LOCAL_EMULATORS.md). Dated results are in [technical verification](docs/CIERRE_TECNICO.md); existing tests are not evidence of a fresh run.

## Troubleshooting

- Blank page or Chrome debugging connection: use Terminal 4's web-server command and open the URL manually.
- Missing periods: check `isActive` and date validity. Creation currently chooses the first active, valid period; keeping one eligible period avoids ambiguity.
- Oath unavailable: inspect both versioned registry documents; do not bypass approval checks.
- Callable `internal` error: inspect Functions logs and the network response. Localhost alone does not imply emulator mode.
- Declaration changed: refresh and review the new version/revision; do not edit signatures or states manually.
- Notifications disconnected: check Terminal 3 and the exact allowed origin `http://localhost:5200`.

## Repository and documentation

`lib/features` separates presentation, domain and data. `functions/src` implements privileged transitions; `realtime-server` provides notices; `functions/scripts` manages backups/restoration. Firestore and Storage rules protect direct access. Final PDFs are downloaded through authorized callables.

| Document | Purpose |
| --- | --- |
| [User manual](docs/MANUAL_USUARIO.md) | Role workflows, schedules, filters and annulment |
| [Requirements](docs/REQUERIMIENTOS.md) | Current scope and constraints |
| [User stories](docs/HISTORIAS_USUARIO.md) | HU-01–HU-25 acceptance and implementation references |
| [Firestore model](docs/MODELO_FIRESTORE.md) | Collections, versioning and evidence |
| [Declaration form](docs/PERSONA_1.md) | Profile, schedules and validation |
| [Oath integration](docs/INTEGRACION_JURAMENTO.md) | Approved text and internal signatures |
| [Administration](docs/ADMINISTRACION_HU03_HU04.md) | Periods, roles, assignments and annulment |
| [Socket.IO](docs/SOCKET_IO.md) | Notification contract and limits |
| [Delivery and shared work](docs/CIERRE_Y_TRABAJO_COMPARTIDO.md) | Delivery boundaries and pending work |
| [Technical verification](docs/CIERRE_TECNICO.md) | Dated historical evidence |
| [Project handoff](CONTEXTO_PROYECTO.md) | Maintenance context and protected contracts |

Documentation filenames remain unchanged to preserve existing links.
