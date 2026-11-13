# Functional and nonfunctional requirements

Current implementation scope, reviewed November 12, 2026. DeclaraHorario supports the IF0009 institutional schedule declaration workflow in the local Web application and a limited Android laboratory module. This document describes the local delivery, not a certification against every external assignment document.

## Scope and actors

Flutter Web uses Spanish UI, light/dark themes, Firebase emulators and Socket.IO. Actors are declarant, supervisor, Human Resources and administrator. Administrators manage periods/roles/assignments and annulment lookup; there is no separate unit-management interface claimed here. Android reuses declarant authentication and data services for declaration lookup, draft creation/recovery, schedule capture, validation and summary. Android intentionally stops at `VALIDADA`; oath acceptance, signing, hierarchical approval and HR receipt are not represented as Android capabilities.

Remote Hosting, production availability, real email delivery, official oath approval, certified digital signatures and load capacity are not certified by this delivery. Existing remote configuration is not an instruction to deploy.

## Functional requirements

| ID | Requirement and implemented boundary |
| --- | --- |
| RF-01 | Authenticate with Email/Password and route by active profile/role; password recovery exists, public registration does not. |
| RF-02 | Load profile data and explicitly save reusable personal information. |
| RF-03 | Create declarations only within active valid academic periods; administer periods with active/inactive filters and live partial-ID search. |
| RF-04 | Assign canonical roles through authorized server operations; reject self role changes. |
| RF-05 | Capture name, identification, phone, email and unit in the declaration. |
| RF-06 | Register institutional appointments with category, workload, optional course code, dates and recurring classified blocks. |
| RF-07 | Register external institution, position, agreed workload, dates and blocks for conflict checking. |
| RF-08 | Store optional observations with the formal version. |
| RF-09 | Detect internal overlaps with day, affected jobs and conflicting interval/duration. |
| RF-10 | Compare institutional and external blocks, including external-to-external conflicts. |
| RF-11 | Calculate weekly totals/differences and enforce the selected teaching/consultation distribution. |
| RF-12 | Block validation/signatures on invalid content; repeat critical checks server-side. |
| RF-13 | Display approved oath text and require explicit acceptance with actor/time/version evidence. |
| RF-14 | Bind the declarant's internal signature and content hash to the signed formal version. |
| RF-15 | Show the supervisor only declarations authorized by current assignment or historical signer access. |
| RF-16 | Sign as superior with server authorization; retain historical signer identity after reassignment. |
| RF-17 | Return pending declarations with a mandatory observation. |
| RF-18 | Create a separate correction document from a returned version and preserve previous content/evidence. |
| RF-19 | Show state, responsible party, version, latest update and chronological history. |
| RF-20 | Receive declarations sent to HR with required superior signature/evidence. |
| RF-21 | Generate a final PDF containing form, oath and signature evidence; store it in local Storage Emulator and download through an authorized callable. |
| RF-22 | Finalize received declarations only after verifying final PDF evidence; keep them read-only. |
| RF-23 | Annul nonterminal declarations with reason, confirmation and concurrency guards; administrator lookup fills technical fields automatically. |
| RF-24 | Keep append-only audit events coordinated atomically with transitions and formal mirrors. |
| RF-25 | Preview weekly schedules and export the latest superior-approved institutional schedule per period to PDF/PNG. |
| RF-26 | Notify declarant, supervisor and HR of authorized state changes without sending form contents. |
| RF-27 | On Android, list declarations and show their persisted institutional states; create a declaration and reopen an existing draft. |
| RF-28 | On Android, capture person, appointment, institution, validity, weekly intervals and observations; calculate actual scheduled minutes and summarize validation results. |
| RF-29 | On Android, block validation when required fields, interval bounds, weekly hours or cross-institution overlaps are invalid, and show concrete errors that direct the user to review. |
| RF-30 | On Android, persist and recover drafts through the existing repository; do not expose oath, signature, approval or HR-receipt actions. |

RF-25/RF-26 document current extensions; they do not renumber the original HU-01–HU-25 stories.

## Schedule rules

| Rule | Contract |
| --- | --- |
| Days/times | Monday–Saturday, 24-hour times, end after start; automatic input separators |
| Lunch | No intersection with 12:00–13:00; never silently deducted |
| Daily limit | 600 aggregate minutes across jobs active on the same dates |
| Overlap | Same-day intervals overlap when maximum start is before minimum end; adjacent intervals are valid |
| Validity | Conflicts require overlapping dates containing the relevant weekday |
| Weekly workload | Each job must match its declared expected minutes |
| Teaching | 40/20/10-hour types; teaching is two thirds, consultation one third; exact integer-minute totals |
| Compatibility | Legacy custom workloads remain readable/valid without silently adding classifications |

One declaration chain is allowed per person/period, including returned/finalized chains. Current creation selects the first eligible period; no declarant period selector is implemented.

## Nonfunctional requirements and limits

| ID | Requirement / current evidence boundary |
| --- | --- |
| RNF-01 | Responsive Flutter forms, bounded lists, scrollable schedules and light/dark themes; visual refinement remains possible. |
| RNF-02 | Authentication required for protected application data/actions; login itself is public. |
| RNF-03 | Persisted active-role, ownership and assignment checks in callables and notification server. |
| RNF-04 | Versioned Firestore/Storage rules deny protected writes and direct final-PDF access. |
| RNF-05 | Signed content is immutable; controlled workflow metadata transitions remain possible through callables. |
| RNF-06 | Atomic declaration/mirror/audit writes and expected version/revision guards. |
| RNF-07 | User-facing error mapping, loading indicators and retry/refresh paths. |
| RNF-08 | Presentation/domain/data separation with shared application theme state. |
| RNF-09 | Version-controlled implementation and documentation; local credentials/exports excluded from delivery. |
| RNF-10 | Local availability through Flutter web-server and emulators; remote Hosting is outside the current delivery. |
| RNF-11 | Android narrow-screen schedule summaries use vertical day cards without horizontal scrolling; the wide-screen preview retains its independently scrollable grid. |
| RNF-12 | UCR reference colors and the permitted Arial substitute are centralized in the application theme; configured text/background pairings meet 4.5:1 contrast tests. Official institutional symbols are not reconstructed or altered. |

## Architecture and traceability

Flutter Web uses Firebase Auth, owner-scoped Firestore access and callable Functions. Functions use Admin SDK for trusted transitions, authorization and final PDF operations. Socket.IO provides only notices and triggers authorized re-reads. Storage denies direct client PDF access. Local backup scripts preserve Auth/Firestore/Storage snapshots.

See the [workflow diagram](MANUAL_USUARIO.md#state-and-signature-workflow), [data model](MODELO_FIRESTORE.md), [user stories](HISTORIAS_USUARIO.md) and [historical verification](CIERRE_TECNICO.md). Test existence does not imply a fresh test run or institutional acceptance.
