# Software Requirements Specification

## 1. Document control

| Field | Value |
|---|---|
| Project | PRM393 Dynamic QR Attendance |
| Version | 4.0 |
| Updated | 2026-09-11 |
| Status | Consolidated project-owner requirements; pending team/lecturer review |
| Delivery context | Five students, three-week course project |

This version records the latest decisions discussed with the project owner. It supersedes the earlier Flutter Web/Supabase direction. It does not claim lecturer approval of every detail or completion of the implementation. Open decisions are listed in section 11.

## 2. Purpose and scope

The lecturer uses a Windows desktop application to import a markbook, generate teaching dates, open a QR attendance window, review results, and export them. Students scan the QR with their phones, open a hosted website, and authenticate with the Google account matching the imported email.

Each desktop installation serves one lecturer. Another lecturer installs their own copy and imports their own teaching data. Access to their cloud data still requires initial provisioning; a shared public administrator credential is not acceptable.

### Included in the MVP

- Flutter Windows desktop application without a routine lecturer sign-in screen.
- Import of both `.xlsx` and `.ods` markbooks containing multiple worksheets.
- Class rosters and weekly teaching patterns derived from the markbook.
- Lecturer-entered first teaching date and generation of 20 lessons per class offering.
- Lecturer-controlled opening, closing, reopening, and manual attendance correction.
- Signed QR tokens rotating every 15 seconds.
- Student Google sign-in, roster matching, and check-in through a mobile website.
- Google Sheets persistence and desktop polling while an attendance window is open.
- Local export to XLSX or CSV for selected lessons or all 20 lessons.

### Deferred or excluded

- Lecturer-entered secret/passcode.
- Offline attendance, connection-loss recovery policy, and automatic closure on disconnection.
- Automatic synchronization of exported files to Google Drive.
- FAP browser extension and direct FAP integration.
- Admin portal, shared-computer workflows, and student mobile installation.
- SQLite, Supabase, a separate Dart backend, and WebSockets in the selected MVP stack.
- Guaranteed physical-presence detection, device locking, GPS, or complete prevention of proxy attendance.

Google Sheets is a cloud Drive file, but storing attendance there is distinct from synchronizing exported XLSX/CSV files to Drive. The latter is deferred.

## 3. Actors and terminology

| Term | Meaning |
|---|---|
| Lecturer | Owner of one configured desktop installation and its teaching data |
| Student | Person whose verified email must match a roster entry for the selected class offering |
| Class offering | A class taught for a particular subject and semester; class code alone is insufficient |
| Daily slot | One of the four fixed time ranges within a day |
| Schedule code | Two-digit worksheet prefix encoding weekday pair and daily slot |
| Lesson | One of 20 dated teaching occurrences for a class offering |
| Attendance window | A period during which a lesson accepts check-ins; reopening creates a new window |
| Attendance result | One result per student and lesson: blank before first opening, then A or P |
| Manual override | A lecturer correction that subsequent student check-ins must not overwrite |

In exports, `Slot 01` through `Slot 20` denote lesson sequence numbers, not daily slot numbers. See [domain glossary](../ai/CONTEXT.md).

## 4. Input contract and scheduling

### 4.1 Observed source

The reference file is `FA26_Markbook.ods`, supplied by the lecturer. It contains eight worksheets and 282 roster rows across class offerings; these are not necessarily 282 unique students. The observed roster columns are `Class`, `RollNumber`, `Email`, `MemberCode`, and `FullName`.

| Source column | Interpretation |
|---|---|
| Class | Class code |
| RollNumber | Student identifier, preserved as text |
| Email | Email used for sign-in matching |
| FullName | Student display name |
| MemberCode | Additional source identifier; not a replacement for verified email |

Grade, comment, bonus, and examination columns are not attendance inputs. In particular, `ExamDate` and P/A-like values under unrelated columns must not be interpreted as teaching dates or existing attendance.

### 4.2 Schedule code

| Prefix | Weekdays | Daily slot |
|---|---|---|
| 1X | Monday and Thursday | X |
| 2X | Tuesday and Friday | X |
| 3X | Wednesday and Saturday | X |

For example, `12_PRM393_SE1917` means Monday/Thursday, daily slot 2, subject PRM393, class SE1917. The actual file also contains `23_PRM232`; its class is obtained from `Class` rather than requiring a class suffix. Unrecognized or conflicting metadata must be shown for lecturer correction before import is confirmed. Do not silently correct apparent subject-code typos.

### 4.3 Daily slot times

All teaching dates and times use Vietnam time, UTC+7 (`Asia/Ho_Chi_Minh`).

| Daily slot | Start | End |
|---|---|---|
| 1 | 07:00 | 09:15 |
| 2 | 09:30 | 11:45 |
| 3 | 12:30 | 14:45 |
| 4 | 15:00 | 17:15 |

### 4.4 Functional requirements: import and timetable

| ID | Requirement |
|---|---|
| FR-01 | Accept `.xlsx` and `.ods` and allow the lecturer to select worksheets to import. Equivalent source content must map to the same domain data in both formats. |
| FR-02 | Preview detected schedule code, subject, class, semester, roster, and validation errors before saving. Require confirmation of missing metadata, including semester. |
| FR-03 | Identify roster columns by their headers. Report missing required headers, missing student IDs/names/emails, and duplicate student IDs or matching emails within a class offering. Do not silently overwrite conflicting students. |
| FR-04 | Allow the lecturer to select the first actual teaching date for each class offering. Reject a first date outside the schedule's weekday pair instead of shifting it silently. |
| FR-05 | Generate 20 chronological lessons, including the selected first date, using the weekday pair and daily slot. Show the generated dates for confirmation. |
| FR-06 | Allow individual lesson dates to be adjusted for holidays or makeup classes. Do not automatically infer holidays. Do not regenerate and overwrite lessons with attendance history. |
| FR-07 | Suggest the lesson currently taking place using its actual date and time. If none matches, show no current lesson; permit explicit selection and confirmation of another lesson. |
| FR-08 | On reimport, preview changes and require confirmation. Preserve attendance and existing lesson identity. A roster removal must not erase historical results. Conflicts requiring an unresolved rule must be surfaced rather than guessed. |

## 5. Attendance requirements

### 5.1 Lecturer flow

| ID | Requirement |
|---|---|
| FR-09 | The lecturer explicitly opens attendance for a selected lesson. On first opening, initialize its roster results to A. A lesson never opened retains blank results. |
| FR-10 | Display a QR for the active window and replace its token every 15 seconds. The backend generates and validates the signed content; the desktop renders it. |
| FR-11 | Poll for results every five seconds while a window is open and refresh the displayed roster and count. This is near-real-time behavior, not a guaranteed five-second delivery SLA. |
| FR-12 | Allow explicit window closure. Display successful closure only after the backend confirms it. Once closure is confirmed, no new check-in may be accepted for that window. |
| FR-13 | Allow reopening the same lesson with a new attendance window. Preserve existing results and manual overrides; invalidate tokens from earlier windows. |
| FR-14 | Allow the lecturer to change A/P manually, including after closure. Preserve override provenance so a later student request cannot replace a lecturer correction. |

### 5.2 Student flow

| ID | Requirement |
|---|---|
| FR-15 | A student scans a QR with a phone and opens the HTTPS website without installing an app. |
| FR-16 | Authenticate through Google. The backend verifies the identity token and uses the verified identity's email; a client-supplied email string is not proof of identity. Imported addresses may be Gmail or institutional addresses. |
| FR-17 | Validate QR signature/expiry, current window identity and open status, and email membership in the associated class roster. A match in a different class is insufficient. |
| FR-18 | If QR expires during sign-in, ask the student to scan the current QR again. Retain the authenticated session when valid so another login is unnecessary. |
| FR-19 | Change A to P for a valid check-in unless a manual override applies. Save the result before returning success. |
| FR-20 | Repeated check-ins must not create duplicate results. Return an already-recorded message where applicable. |
| FR-21 | Return distinct feedback for successful check-in, already recorded, expired/invalid QR, closed window, email absent from the roster, manual override, authentication failure, and persistence failure. Do not report success when saving fails. |

### 5.3 State and precedence rules

| Lesson state | Result semantics |
|---|---|
| Never opened | Blank; no attendance has been taken |
| First window opened | All initial roster entries become A |
| Valid student check-in | P, unless manually overridden |
| Window closed | Preserve A/P; reject further check-ins |
| Window reopened | Preserve A/P and overrides; do not reset |

An attendance result is keyed by class offering, lesson, and student, not by QR token or attendance window. Manual correction has precedence over student check-in. A student marked A manually cannot change it by scanning again; the lecturer must correct it.

Closing a window and recording a check-in must share the same serialized persistence path. A check-in committed before closure is retained. After closure is confirmed, later check-ins fail. Server-side state is authoritative; a student's earlier sign-in or open browser tab does not reserve the right to check in.

## 6. Export

| ID | Requirement |
|---|---|
| FR-22 | Allow selection of one or more lessons, or all 20 lessons, for export. |
| FR-23 | Export `.xlsx` and `.csv` with student identifiers, names, and one result column per selected lesson. Preserve blank/A/P distinctions. |
| FR-24 | Include enough class/subject/semester and lesson-date context to identify results. Define the exact output column contract with the lecturer before extension integration. |
| FR-25 | Save exported files locally through the desktop. CSV represents a single table; it cannot preserve workbook tabs or formatting. |

The custom export must not be described as FAP-compatible until a target format has been verified. Automatic upload of exported files and the lecturer's FAP extension are outside the current MVP.

## 7. Selected technology and architecture

| Component | Selected technology |
|---|---|
| Lecturer application | Flutter Desktop / Dart, Windows |
| Student website | Next.js / TypeScript |
| Backend | Next.js Route Handlers |
| Web/API hosting | Vercel |
| Student identity | Google Identity Services |
| Persistent teaching data | Google Sheets |
| Serialized data gateway | Google Apps Script with LockService |
| QR signing | HMAC-SHA256; server-held key; 15-second tokens |
| Communication | HTTPS and JSON; five-second desktop polling during open windows |
| Collaboration and CI | GitHub and GitHub Actions |
| File parsing | Must support XLSX and ODS; library selection pending a compatibility spike |

```text
Flutter Desktop ----+
                    +--> Next.js API --> Apps Script --> Google Sheets
Student website ----+
```

The backend retains three logical layers: Controller (HTTP contract), Service (business rules), Repository (data gateway). Apps Script performs the serialized final state check and write. All attendance mutations must use this gateway; direct concurrent Sheet edits bypass its lock and are not a supported attendance workflow.

The lecturer application requests QR tokens from the backend; it does not expose the signing key to students. The deferred lecturer-entered secret is a different concept from the mandatory internal signing key.

Google Sheets is the source of truth. The desktop displays retrieved results; permanent offline local persistence is not part of the current scope. Persistent session state must not rely on one Vercel function instance's memory.

This SRS describes the target design. The repository still contains the earlier Flutter Web/Dart scaffold; migration has not been implemented or validated by this document update.

## 8. Logical data model

| Entity | Minimum information |
|---|---|
| Lecturer configuration | Installation/owner identity and binding to authorized teaching data; provisioning mechanism pending |
| Class offering | Stable ID, class code, subject code, semester, schedule code, owner |
| Enrollment | Class offering ID, student ID, full name, email, optional MemberCode, membership/history information |
| Lesson | Stable ID, offering ID, sequence 1–20, date, daily slot/time, lifecycle state |
| Attendance window | Window ID, lesson ID, open/closed state and timestamps |
| Attendance result | Lesson/enrollment reference, A/P, check-in time where applicable, manual-override provenance |

Blank before first opening may be represented by no result or an explicit empty value internally; exports and UI must preserve its meaning. Tab names and physical storage layout remain implementation details. The roster is scoped per class offering, so the same student may belong to several offerings.

## 9. Non-functional requirements

- Keep signing keys, Google credentials, and lecturer access credentials out of QR URLs, student bundles, logs, exported markbooks, and version control.
- No routine lecturer login screen does not mean anonymous write access. Authenticate installation requests and authorize access to the correct teaching data.
- Student responses must not reveal unrelated student rosters or results.
- Treat imported data as data; never execute workbook macros or instructions embedded in cells. Validate inputs before committing them.
- Preserve student identifiers as text and use consistent email matching. Exact normalization rules require confirmation under section 11.
- All dates must use the stated teaching timezone. Server time controls QR expiry and acceptance.
- QR rotation reduces reuse duration but does not prove physical presence or prevent forwarding an unexpired token.
- Quota errors and failed writes must produce a failure/pending response, never a false success. Load-test with a representative class before acceptance; no unmeasured concurrency or latency guarantee is asserted.
- Mobile pages must provide readable feedback and a retry path. The lecturer QR view must be legible on a classroom projector.

## 10. Acceptance scenarios

| ID | Scenario and expected result |
|---|---|
| AC-01 | Import equivalent XLSX and ODS markbooks: same class metadata and roster data; source grades are not imported as attendance. |
| AC-02 | Import `12_PRM393_SE1917`: detect Monday/Thursday, daily slot 2, 09:30–11:45. Import `23_PRM232`: obtain its class from `Class` and request confirmation where needed. |
| AC-03 | Select a valid first date: preview 20 lessons on the correct weekday pair. Select an invalid weekday: show validation without silently changing the date. |
| AC-04 | Before first opening, export a lesson: results are blank. Open it: initial roster results are A. |
| AC-05 | Submit a valid QR and roster identity: store P and return success; desktop obtains P on a subsequent successful poll. |
| AC-06 | Submit an identity belonging only to another class: reject without changing results. |
| AC-07 | Complete sign-in after token expiry: request rescan. Repeated valid check-in: no duplicate result. |
| AC-08 | Close a window, then use its QR: reject even if the student signed in before closure. Concurrent close/check-in follows the serialized commit order. |
| AC-09 | Reopen a lesson: prior results remain; old-window QR is rejected; an unmodified A may become P. |
| AC-10 | Lecturer manually marks A; student scans: manual A remains and feedback explains the lecturer correction. |
| AC-11 | Reimport changed data: preview changes; confirmation does not erase attendance history. |
| AC-12 | Export selected lessons and all 20: correct students/columns and blank/A/P semantics in XLSX and CSV. |
| AC-13 | A save operation fails: no success message or fabricated P is returned. |

## 11. Open decisions and deferred behavior

These items must not be silently converted into approved rules:

| Item | Status |
|---|---|
| Initial lecturer provisioning and Sheets access authorization | Required before end-to-end implementation; no per-use login, exact setup still open |
| File parsing libraries | Test actual ODS and an XLSX equivalent before choosing |
| Subject-code anomalies and missing semester | Lecturer confirms during import; do not infer corrected codes from similarity |
| Email normalization, account changes, and roster conflicts | Exact rules and migration behavior still need definition |
| Students added after a lesson has opened/closed | Initial result and historical membership behavior not yet specified |
| Maximum simultaneous windows per lecturer | Earlier single-window proposal has not been explicitly reconfirmed for this desktop scope |
| Export while a window is open | Whether permitted is not yet confirmed |
| Connection loss, app termination, automatic window expiry | Explicitly deferred; do not claim the window closes when desktop disappears |
| Automatic Drive export synchronization and FAP extension | Deferred |
| Lecturer-entered secret key/passcode | Deferred |

## 12. Source and decision precedence

The project owner's latest explicit decisions take precedence over earlier drafts and generated templates. The supplied `FA26_Markbook.ods` grounds the observed input columns; the lecturer's explained schedule-code convention and supplied daily-slot times ground scheduling. The earlier synthetic Excel template is an example, not a mandatory source-file contract. This document contains no real student rows or credentials.
