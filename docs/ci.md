# Continuous Integration

The `.github/workflows/ci.yml` workflow runs on pushes, pull request creation or updates, and manual dispatch through GitHub Actions. It has two independent jobs: `frontend checks` and `backend checks`.

## Checks

| Component | Checks |
|---|---|
| Flutter frontend | Install dependencies, check formatting, analyze, run tests when present, build web release |
| Dart backend | Install dependencies, check formatting, analyze, run tests when present |

Formatting, analysis, test, or build failures fail the job. The workflow does not deploy, access a live Supabase project, or require secrets at this stage.

## Package checks

Both packages are initialized. Missing pubspec.yaml files fail CI. Flutter is pinned to 3.44.4 and Dart to 3.12.2 to match the base setup.

Tests run only when test files exist; this base has no automated test suite yet. The web build does not require a local .env file.

## Team workflow

1. Commit and push the workflow or submit it through a PR under the existing ruleset.
2. Open Actions to inspect results. Manual dispatch requires the workflow on the default branch.
3. After its first run, select `frontend checks` and `backend checks` as required checks in the main branch ruleset.
4. Commit frontend and backend `pubspec.lock` files when initializing packages. CI uses the pinned SDK versions above; update local and CI SDKs together.
5. Add public web build configuration such as a Supabase URL/publishable key when required. Never include a service-role key or QR signing secret in Flutter.

References: https://github.com/subosito/flutter-action, https://github.com/dart-lang/setup-dart, and https://github.com/actions/checkout.
