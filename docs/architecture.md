# Three-Layer Architecture

- controllers: receive HTTP requests, call services, and return responses.
- services (BLL): validate and execute business logic.
- repositories (DAL): read and write database data and execute transactions.

Flutter in `frontend/lib` calls the backend API. Controllers do not access the database directly; services do not contain UI code; repositories do not return HTTP responses.

Database First: agree on business rules → design the database and SQL → implement the three layers. The SRS still requires team review.

Dart filenames use snake_case, for example `attendance_controller.dart`. The repository currently contains only a directory scaffold, without application source code or runtime configuration.
