# Project Context

## Current direction

- PRM393 course project: five team members, an expected three-week schedule, and Flutter coursework.
- Dynamic QR attendance web application with Flutter Web and a Dart backend, deployed over HTTPS.
- Database First development. See `../docs/architecture.md` for backend responsibilities.
- The proposed MVP initially serves one teacher, with data designed for multiple teachers with separate classes and teaching schedules.
- Teachers import Excel files, open QR attendance, monitor or edit results, and export results. Students sign in with Google to check in.
- Proposed services: Supabase for the database, Auth, and Realtime; Render for the web application and backend.

## Requirements status

The SRS is the project initiator's proposal and has not been approved by the whole team. Decisions in the user's latest task provide updates; do not treat every SRS statement as finalized.

Verify these points before implementing the relevant functionality:
- The actual Excel format and column mapping.
- The distinction between a lesson and a slot number.
- Correcting incomplete student lists, reimporting schedules, and changing email addresses.
- Manual-edit precedence over check-in, requests near session closure, and export conditions.

Once the team approves the SRS, place the approved version in `docs/` and update its path here. Do not turn missing information into official requirements by assumption.
