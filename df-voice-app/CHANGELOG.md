# Changelog

## Unreleased

- Added the voice pipeline overview for desktop and mobile home screens.
- Added redacted settings export/import for moving provider configurations across devices.
- Hardened settings import validation against unknown fields and invalid enum/type values.
- Added a fast settings portability logic verifier to the static gate.
- Added provider and prompt template contract checks to the static gate.
- Added installable web app metadata and app config contract checks to the static gate.
- Added 192px and 512px web app icons to the exported manifest contract.
- Added static web export verification to catch production web build regressions.
- Added transcript workflow prompt templates and non-streaming conversation verification.
- Added local workspace restore for transcripts, drafts, and conversations.
- Added custom prompt template creation, restore, and deletion.
- Added a Settings action and smoke coverage for clearing local workspace data.
- Added inline validation for advanced JSON override fields.
- Added custom provider template creation, restore, application, and deletion.
- Redacted API keys and extra headers from custom provider templates stored in local workspace data.
- Added mock integration coverage for ASR text, SRT, and VTT response formats.
- Added numeric range validation for provider settings and stored/imported settings files.
- Added cancellation support for in-flight ASR, conversation, TTS, and provider diagnostic requests.
- Added confirmation dialogs for destructive local workspace, conversation, settings reset, and custom template actions.
- Added the high-severity dependency audit to the local CI-equivalent verification script.
- Added explicit timeout errors for provider requests and model diagnostics.
- Added Responses streaming fallback support for `response.output_text.done` and completed-response payloads.
- Released previous web TTS object URLs when replacing playback to avoid long-running session leaks.
- Improved Android verification scripts to find SDK tools from environment variables, `android/local.properties`, common local SDK paths, or `PATH`.

## 1.0.0

- Added standalone Expo voice workbench for web, Android, and optional iOS.
- Added microphone recording, file upload ASR, OpenAI-compatible chat, Responses, TTS, exports, templates, provider diagnostics, and native Android config checks.
- Added mock provider and Playwright verification scripts.
