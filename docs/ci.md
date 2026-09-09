# Continuous Integration

The `.github/workflows/ci.yml` workflow runs on pushes, pull request creation or updates, and manual dispatch through GitHub Actions. It has two independent jobs: `frontend checks` and `backend checks`.

## Checks

| Component | Checks |
|---|---|
| Flutter frontend | Install dependencies, check formatting, analyze, run tests when present, build web release |
| Dart backend | Install dependencies, check formatting, analyze, run tests when present |

Formatting, analysis, test, or build failures fail the job. The workflow does not deploy, access a live Supabase project, or require secrets at this stage.

## Scaffold behavior

If both `pubspec.yaml` and Dart source files are absent, the job reports that the component is not initialized in its Summary and does not install an SDK. A green result only confirms scaffold detection, not that the application works.

CI fails if Dart source exists without `pubspec.yaml`, or if a frontend/backend directory is missing. Checks start automatically once a package is initialized. After both packages are initialized, change the missing-pubspec branch to fail unconditionally so deleting a package cannot bypass checks.

Tests run only when files matching `test/**/*_test.dart` exist; missing tests are reported in the Summary. Backend tests require the `test` package in `dev_dependencies`. Integration checks requiring a separate environment can be added later when requested.

## Team workflow

1. Commit and push the workflow or submit it through a PR under the existing ruleset.
2. Open Actions to inspect results. Manual dispatch requires the workflow on the default branch.
3. After its first run, select `frontend checks` and `backend checks` as required checks in the main branch ruleset.
4. Commit frontend and backend `pubspec.lock` files when initializing packages. CI currently uses stable SDKs; select specific SDK versions matching local development when initializing the project.
5. Add public web build configuration such as a Supabase URL/publishable key when required. Never include a service-role key or QR signing secret in Flutter.

References: https://github.com/subosito/flutter-action, https://github.com/dart-lang/setup-dart, and https://github.com/actions/checkout.
