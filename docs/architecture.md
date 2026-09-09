# Three-Layer Architecture

- controllers: receive HTTP requests, call services, and return responses.
- services (BLL): validate and execute business logic.
- repositories (DAL): read and write database data and execute transactions.

Flutter in `frontend/lib` calls the backend API. Controllers do not access the database directly; services do not contain UI code; repositories do not return HTTP responses.

Database First: agree on business rules → design the database and SQL → implement the three layers. The SRS still requires team review.

Dart filenames use snake_case, for example `attendance_controller.dart`.

The runnable base contains a blank Flutter app and a Dart Shelf server. `backend/bin/server.dart` loads local configuration and starts the server; `GET /health` only reports process liveness. It does not need a service or repository because it performs no business logic or database access. The service and repository directories remain empty until features are implemented.

Run the backend from `backend/` so it can find `.env`. Hosting environment variables override local values. The frontend accepts public configuration through `--dart-define-from-file=.env`; it does not bundle the file as an asset. Frontend-to-backend calls, Supabase SDK initialization, authentication, and database operations are not implemented yet.
