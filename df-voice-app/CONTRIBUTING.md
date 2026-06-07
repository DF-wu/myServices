# Contributing

DF Voice App is a standalone Expo app. Keep changes scoped to this project unless a repository-level workflow or shared service really needs to change.

## Development

```bash
npm ci
npm run web
```

Public build-time defaults can be copied from `.env.example`. Do not commit API keys or private provider credentials.

## Verification

Run the fast checks before opening a PR:

```bash
npm run verify:static
```

Run the browser and mock provider checks when changing UI, settings, provider calls, exports, or scripts:

```bash
npm run verify:web:server
npm run verify:mock:server
```

Run Android checks when touching `app.json`, native config plugins, audio permissions, or dependency versions:

```bash
npm run verify:android-config
npm run verify:android-build
```

`verify:android-runtime` needs one online adb device or emulator.

## Git

Prefer focused commits:

- Product/UI changes
- Provider/API behavior
- Native config and build changes
- Documentation and CI

Do not include generated `android/`, `.expo/`, `node_modules/`, `dist/`, or `test-artifacts/` output.
