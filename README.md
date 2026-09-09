# PRM393 Lab01

Runnable Flutter Web and Dart backend base. No attendance, login, import, or database features are implemented yet.

For team onboarding, follow the [local setup and run guide](docs/getting-started.md).

## Structure

```text
frontend/lib/                 # Flutter UI and public configuration
backend/bin/server.dart       # Server entry point
backend/lib/controllers/      # HTTP requests and responses
backend/lib/services/         # Business logic (empty until needed)
backend/lib/repositories/     # Database access (empty until needed)
database/                     # Future SQL schema and migrations
test/test-supabase.ps1        # Manual Supabase API connectivity check
```

Feature flow: Flutter -> Controller -> Service -> Repository -> Database.

## Requirements

Use Flutter 3.44.4 (includes Dart 3.12.2), Git, and Chrome. Run `flutter doctor` to check your machine. Commit both `pubspec.lock` files. Node.js/npm is not required; the existing backend npm files are not used by this Dart base.

## Run locally

Open two terminals from the repository root.

Backend:

```powershell
cd backend
dart pub get
dart run bin/server.dart
```

Open http://localhost:8080/health. Expected response: `{"status":"ok"}`. This endpoint checks the server process, not Supabase. The default bind address is `127.0.0.1`; configure `HOST=0.0.0.0` on hosting when required. `PORT` defaults to `8080`.

Frontend:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define-from-file=.env
```

The welcome screen also runs without Supabase configuration: omit `--dart-define-from-file=.env` if the file is not available yet. The frontend can call the sample backend API; it does not initialize Supabase yet.

## Local configuration

Create the ignored files locally; there are no `.env.example` files.

`frontend/.env` contains only public values:

```dotenv
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
API_BASE_URL=http://localhost:8080
```

Flutter reads these as build-time definitions through `lib/config.dart`. Restart/rebuild after changing them. Never pass `backend/.env` to a Flutter command.

`backend/.env` may contain:

```dotenv
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
SUPABASE_SECRET_KEY=
SUPABASE_JWKS_URL=
PORT=8080
```

The backend loads `.env` from its working directory. Process environment variables take precedence. Supabase values are reserved for future integration and are not used by `/health`.

To test actual Supabase API connectivity, run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\test-supabase.ps1
```

This test makes read-only API requests; it does not verify table permissions or Google sign-in.

## Checks

```powershell
cd backend
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

```powershell
cd frontend
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter build web --release
```

The release build produces `frontend/build/web/`. CI builds the placeholder without live Supabase configuration. Tests will run in CI once test files are added; this base has no automated test suite yet.

## Team documentation

Read `AGENTS.md`, `ai/CONTEXT.md`, `ai/DESIGN.md`, and `docs/architecture.md` before feature work. The SRS and visual design still require team agreement. Follow Database First: agree on business rules, design the schema, then implement features.

## Sample API

Start both applications using the commands above and click **Check connection** on the Flutter welcome page. A successful request displays **Connected** and the message returned by `GET /api/demo`. Stop the backend and click again to see the retryable error state (10-second timeout).

The example follows `frontend/lib/demo_api.dart` -> `backend/lib/controllers/demo_controller.dart` -> `backend/lib/services/demo_service.dart`. The service returns a sample message and UTC timestamp; it does not use Supabase or need a repository. Add repositories when real data access is implemented.

`API_BASE_URL` defaults to `http://localhost:8080` in Flutter. Backend `FRONTEND_ORIGIN` defaults to `http://localhost:3000` for CORS. If you change ports or deploy, configure these values accordingly and restart both applications. CORS is browser access configuration, not authentication.
