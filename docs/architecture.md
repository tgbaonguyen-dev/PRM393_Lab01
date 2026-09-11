# Target Architecture

See [SRS v4.0](SRS.md) for requirements and unresolved decisions.

- Lecturer application: Flutter Desktop / Dart on Windows (`apps/desktop`).
- Student website: Next.js / TypeScript (`apps/web`).
- Backend API Server: Dart Shelf 3-layer architecture (`backend/`).
- Data gateway: Google Apps Script with LockService (`apps-script/`).
- Persistent data: Google Sheets.

Communication: Desktop and Student Web -> Dart Shelf Backend (Port 8080) -> Apps Script -> Google Sheets.

The backend uses three logical layers:
- Controller: HTTP requests and responses (`backend/lib/controllers/`).
- Service: attendance business rules & HMAC QR (`backend/lib/services/`).
- Repository: communication with the data gateway (`backend/lib/repositories/`).

The applications and their directory structure:
- `apps/desktop`: Flutter Desktop Windows application.
- `apps/web`: Next.js Student web check-in UI.
- `backend`: Dart Shelf 3-layer Backend API Server (Port 8080).
- `apps-script`: Google Apps Script Data Gateway with LockService.
