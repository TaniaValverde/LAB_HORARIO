# User stories and implementation traceability

Reviewed November 10, 2026. Each row identifies implemented local behavior and its main acceptance condition. This is not a production deployment or institutional acceptance claim. Test references identify available checks, not fresh results; dated evidence is in [technical verification](CIERRE_TECNICO.md).

## Identity, profile and periods

| Story | User goal and acceptance condition | Implementation / tests |
| --- | --- | --- |
| HU-01 | Sign in and reach the panel for the authenticated role. | `lib/features/auth/presentation/auth_gate.dart`, `declarant_dashboard.dart`; `test/declarant_dashboard_test.dart` |
| HU-02 | Reuse personal data: load the profile and explicitly save edits for later declarations. | `lib/features/profile/data/profile_repository.dart`, `declaration_editor.dart`; `test/declaration_editor_test.dart` |
| HU-03 | Organize declarations by periods: only active periods valid today allow creation. | `administrator_dashboard.dart`, `saveAcademicPeriod`, `AcademicPeriod.isOpenAt`; administrator dashboard and administration tests |
| HU-04 | Assign roles securely: server permissions apply and self-promotion is rejected. | `assignUserRole`, role service, Firestore rules; administration and rules tests |

## Declaration entry

| Story | User goal and acceptance condition | Implementation / tests |
| --- | --- | --- |
| HU-05 | Create a draft tied to the person/period without duplicate chains. | `create_declaration.dart`, Firestore repository; `test/declaration_flow_test.dart` |
| HU-06 | Store appointments with workplace, category, workload, dates and optional course code in the current version. | `appointment_dialog.dart`, `schedule.dart`; teaching workload/UI and editor tests |
| HU-07 | Add multiple daily blocks with valid start/end times and teaching/consultation classification when applicable. | Appointment dialog and schedule entities; input formatter and schedule validation tests |
| HU-08 | Register external institutions, positions, workload, dates and schedules. | Declaration editor/external appointments; schedule validation tests |
| HU-09 | Preserve optional observations in `payload.observations`. | Declaration editor/form entity; editor tests |

## Validation

| Story | User goal and acceptance condition | Implementation / tests |
| --- | --- | --- |
| HU-10 | Identify internal schedule conflicts with day, intervals and duration. | `lib/features/validation/domain/validate_schedule.dart`; `test/schedule_validation_test.dart` |
| HU-11 | Check institutional and external schedules together, including external-to-external conflicts. | Same validation engine and tests |
| HU-12 | Calculate declared time from valid block durations. | Schedule validation summaries and tests |
| HU-13 | Show expected/declared/difference totals and require the exact workload, including teaching/consultation split. | Dart validation and `functions/src/schedule_validation.ts`; teaching workload and server validation tests |
| HU-14 | Reject blocking errors before validation/signature. | Editor save flow, Dart validation and callable server validation; editor, schedule and oath integration tests |

## Oath, signatures and correction versions

| Story | User goal and acceptance condition | Implementation / tests |
| --- | --- | --- |
| HU-15 | Read approved wording and explicitly accept it with actor/time/formal-version evidence. | `oath_acceptance_section.dart`, `getApprovedDeclarantOath`, `acceptOath`; oath widget/integration tests |
| HU-16 | Sign the validated version internally and bind evidence/hash to its immutable content. | Declarant signature section, `signDeclaration`; oath integration and security rules tests |
| HU-17 | View only the supervisor's authorized pending declarations. | Supervisor inbox, `getSupervisorInbox`; supervisor inbox widget/server tests |
| HU-18 | Approve/sign as the authorized superior and retain the original signer after reassignment. | `signAsSuperior`, supervisor review; workflow tests |
| HU-19 | Return for correction only with a mandatory observation preserved in history. | `returnForCorrection`; workflow tests |
| HU-20 | Correct a returned declaration through a new document/version without changing the signed source. | `createDeclarationVersion`, parent link and formal mirrors; workflow tests |

## Tracking, HR and final document

| Story | User goal and acceptance condition | Implementation / tests |
| --- | --- | --- |
| HU-21 | See state, responsible party, version and latest update. | `getDeclarationStatus`, editor status card; workflow tests |
| HU-22 | Read chronological audit events with actor, date, version and transition. | `getDeclarationTimeline`; workflow and status label tests |
| HU-23 | Receive an authorized declaration already sent to HR with superior evidence. | `receiveDeclarationAtHr`, HR inbox; workflow tests |
| HU-24 | Generate/download the final declaration PDF with form, oath and internal signature evidence. | `functions/src/final_declaration_pdf.ts`, generation/download callables; PDF and workflow tests |
| HU-25 | Finalize a received declaration with verified final PDF evidence and retain historical access. | `finalizeDeclaration`; workflow tests |

## Supporting features

- Supervisor assignment: `assignDeclarantSupervisor`; signed outbox: `getSupervisorOutbox`.
- Administrator annulment lookup: `findDeclarationsForAnnulment`; actual transition: `annulDeclaration` with reason, confirmation and revision guards.
- Period live search and active/inactive filtering, with active periods shown initially.
- Approved institutional schedule view and PDF/PNG export, independently of the final declaration PDF.
- Socket.IO notices for declarant, supervisor and HR; no administrator notice channel.
- Local backup/restore and guarded orphan-port recovery scripts.

Formal version and concurrency revision are distinct. User story implementation does not remove the need for official oath provisioning, local integration checks or manual acceptance. Run destructive fixtures only in the [isolated environment](../security-tests/LOCAL_EMULATORS.md).
