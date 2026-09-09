# PRM393 Lab01

Flutter Web and Dart backend scaffold using a three-layer architecture and Database First development. No application code or dependencies have been added yet.

```text
frontend/lib/                  # Flutter UI
backend/lib/controllers/       # Receive requests and return responses
backend/lib/services/          # BLL: business logic
backend/lib/repositories/      # DAL: database access
database/                      # SQL for database design
docs/architecture.md           # Architecture guide
```

Flow: Flutter → Controller → Service → Repository → Database.

The backend has only three layer directories. `.gitkeep` files preserve empty directories in Git. Add `pubspec.yaml` and the required files when implementation begins.

## CI

GitHub Actions is configured in `.github/workflows/ci.yml` for the frontend and backend. Before Dart/Flutter packages exist, it reports that they are not initialized. Once packages exist, it runs formatting checks, analysis, tests when present, and a Flutter Web build. See `docs/ci.md` for enabling required checks.

## AI documentation

```text
AGENTS.md          # AI instructions and documentation pointers
ai/
├── CONTEXT.md     # Project context and unresolved requirements
├── DESIGN.md      # UI design decisions
└── PROMPTS.md     # Task and review prompt templates
```

Provide a specific task and ask the AI to read `AGENTS.md`. Use this filename rather than `AGENT.md`; tools that do not load it automatically can read it when explicitly directed.
