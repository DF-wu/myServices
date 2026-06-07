# Changelog

## Unreleased

- Added the voice pipeline overview for desktop and mobile home screens.
- Added redacted settings export/import for moving provider configurations across devices.
- Hardened settings import validation against unknown fields and invalid enum/type values.
- Added a fast settings portability logic verifier to the static gate.
- Added static web export verification to catch production web build regressions.
- Added transcript workflow prompt templates and non-streaming conversation verification.
- Added local workspace restore for transcripts, drafts, and conversations.

## 1.0.0

- Added standalone Expo voice workbench for web, Android, and optional iOS.
- Added microphone recording, file upload ASR, OpenAI-compatible chat, Responses, TTS, exports, templates, provider diagnostics, and native Android config checks.
- Added mock provider and Playwright verification scripts.
