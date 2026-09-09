# Running the Project Locally

This guide uses Windows PowerShell. The current sample connects Flutter Web to a Dart API. Attendance, Google sign-in, imports, and database operations are not implemented yet.

## 1. Prerequisites

Install Git, Flutter 3.44.4 (includes Dart 3.12.2), and Google Chrome. Use an editor such as VS Code with the Dart and Flutter extensions.

Check your environment:

```powershell
git --version
flutter --version
dart --version
flutter doctor
flutter devices
```

Chrome should appear as an available device. Android Studio and Android SDK setup are not required for this web-only sample. Node.js and npm are not used by the Dart backend, even if older npm files exist in the repository.

## 2. Get the repository

```powershell
git clone https://github.com/tgbaonguyen-dev/PRM393_Lab01.git
cd PRM393_Lab01
```

If you already have the repository, open your existing checkout. Make sure it includes the team's base/API changes; local changes are not available to teammates until committed and pushed.

The **repository root** means the directory containing `frontend`, `backend`, and `docs`.

## 3. Configure local environment files

Create the following files in your editor. They are ignored by Git and must be created on each developer's machine. Do not overwrite existing values when adding settings.

### Frontend: `frontend/.env`

```dotenv
API_BASE_URL=http://localhost:8080
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
```

### Backend: `backend/.env`

```dotenv
HOST=127.0.0.1
PORT=8080
FRONTEND_ORIGIN=http://localhost:3000
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
SUPABASE_SECRET_KEY=
SUPABASE_JWKS_URL=
```

Leave the Supabase values empty if you only want to run the sample API. For the separate Supabase connectivity test, obtain the shared project's values from the team: frontend needs the URL and publishable key; backend needs the URL and secret key. Each member does not need a separate Supabase project.

Only public configuration belongs in `frontend/.env`. Never put a secret key in it or pass `backend/.env` to Flutter. The backend loads its `.env` from the working directory, with process environment variables taking precedence. Flutter receives its values at build time through the command below; restart after changing them.

## 4. Start the backend

Open **Terminal 1 at the repository root**:

```powershell
cd backend
dart pub get
dart run bin/server.dart
```

Keep this terminal open. Expected startup message:

```text
Backend running at http://127.0.0.1:8080
```

Open [the health endpoint](http://localhost:8080/health). Expected response:

```json
{"status":"ok"}
```

Open [the sample API](http://localhost:8080/api/demo). It returns `message` and `serverTime`, with the message `Hello from the Dart backend!` and a UTC timestamp.

## 5. Start the frontend

Open **Terminal 2 at the repository root**:

```powershell
cd frontend
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define-from-file=.env
```

Chrome opens the app at [http://localhost:3000](http://localhost:3000). Keep both terminals running.

If you have not created `.env`, the sample also runs with the default local API address:

```powershell
flutter run -d chrome --web-port=3000
```

## 6. Check the complete sample flow

1. Click **Check connection** in the app.
2. The button shows **Connecting...** while the request runs.
3. A successful request displays **Connected** and **Hello from the Dart backend!**.
4. To check the error state, stop the backend with `Ctrl+C` and click again. The app displays **Connection failed**; requests time out after 10 seconds at most.
5. Restart the backend and click again to retry.

The example follows this path:

```text
Flutter page -> DemoApi -> GET /api/demo -> DemoController -> DemoService
```

The response uses sample data. A repository is unnecessary until database access is added. Success here confirms FE-to-BE communication, not Supabase access.

## 7. Check Supabase separately

After filling in the Supabase values, open a terminal **at the repository root**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\test-supabase.ps1
```

To check only one component, append `-Component frontend` or `-Component backend`.

`[PASS]` with HTTP 200 means the API accepted that component's configuration. The script does not print keys, change application records, verify RLS, or test Google sign-in.

## 8. Daily development

- Run the two startup commands in separate terminals. Run `pub get` again after dependency changes.
- In the Flutter terminal, use `r` for hot reload or `R` for hot restart. Restart the Flutter command after `.env` changes.
- Restart `dart run bin/server.dart` after backend code or configuration changes; it does not automatically reload.
- Use `Ctrl+C` to stop a process. Do not commit `.env`, generated build output, or dependency caches. Commit `pubspec.yaml` and `pubspec.lock` changes together.

## 9. Troubleshooting

| Problem | What to check |
|---|---|
| `flutter` or `dart` is not recognized | Add the Flutter SDK `bin` directory to PATH, then reopen the terminal. |
| No `pubspec.yaml` found | Run frontend commands inside `frontend/` and backend commands inside `backend/`. |
| `.env` cannot be found | Create it in the correct component directory; verify it is not named `.env.txt`. |
| `/health` shows the Flutter page | Use port **8080** for backend endpoints. Port **3000** serves Flutter. |
| API opens directly but the FE button fails | Check `API_BASE_URL` and `FRONTEND_ORIGIN`. The allowed origin must exactly match the browser's scheme, hostname, and port, without a trailing slash. `localhost` and `127.0.0.1` are different origins. |
| Address already in use | Stop your earlier server, or change the port and corresponding configuration. |
| Changes to `.env` have no effect | Restart the relevant process. Backend process environment variables override `.env`. |
| Supabase test returns 401 | Check the project's URL/key pairing and whether the key is still active. Use the provided script rather than sending a secret key from a browser. |

For example, to use backend port `8081`, change backend `PORT` to `8081` and frontend `API_BASE_URL` to `http://localhost:8081`, then restart both. To change the frontend port, update both `--web-port` and backend `FRONTEND_ORIGIN`.

## 10. Analyze and build

From `backend/`:

```powershell
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

From `frontend/`:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --fatal-warnings
flutter build web --release --dart-define-from-file=.env
```

Web output is written to `frontend/build/web/`. This build does not deploy the backend. A deployed frontend needs a reachable backend URL; `localhost` always refers to the browser user's machine. CI can build the sample without `--dart-define-from-file=.env`. See [CI](ci.md) and [Architecture](architecture.md) for more details.
