# Target Architecture

See [SRS v4.0](SRS.md) for requirements and unresolved decisions.

- Lecturer application: Flutter Desktop / Dart on Windows.
- Student website and API: Next.js / TypeScript on Vercel.
- Data gateway: Google Apps Script with LockService.
- Persistent data: Google Sheets.

Communication: Desktop and student web -> Next.js API -> Apps Script -> Google Sheets.

The backend uses three logical layers:

- Controller: HTTP requests and responses.
- Service: attendance business rules.
- Repository: communication with the data gateway.

The old Flutter Web/Dart/Supabase scaffold has been removed. The new applications and their directory structure have not been initialized yet.
