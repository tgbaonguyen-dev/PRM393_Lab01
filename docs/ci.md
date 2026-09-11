# Continuous Integration

The previous Flutter Web/Dart backend workflow was removed with the old scaffold.

After the new packages are initialized, configure GitHub Actions for Flutter Windows and Next.js checks. Select SDK versions and commands from the actual package configuration. Do not add production credentials to CI.

If GitHub rulesets still require the old frontend checks or backend checks, update those required checks when the new workflow is ready. Remote rulesets have not been changed by the local cleanup.
