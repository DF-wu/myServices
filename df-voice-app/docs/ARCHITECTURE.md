# Architecture

Last reviewed: 2026-06-08

DF Voice App is a single Expo Router application that targets web, Android, and optional iOS from one TypeScript codebase.

## Runtime Layers

- `app/`: Expo Router entry points and native stack shell.
- `src/components/app-shell.tsx`: product UI, workflow state, and user actions.
- `src/lib/openai-compatible.ts`: provider HTTP client for ASR, Chat Completions, Responses, model probes, and TTS.
- `src/lib/settings-portability.ts`: redacted settings export/import and credential preservation.
- `src/lib/workspace-storage.ts`: transcript, draft, custom prompt/provider templates, and conversation workspace persistence.
- `src/state/settings.tsx`: persisted settings and defaults merge.
- `src/data/templates.ts`: provider templates and default settings.
- `src/data/prompt-templates.ts`: reusable transcript workflow prompt templates.
- `src/config/provider-defaults.ts`: public build-time defaults from `EXPO_PUBLIC_*` variables.
- `plugins/with-local-http-android.js`: Android cleartext HTTP and Gradle wrapper pin.
- `scripts/`: verification, mock provider, Android SDK discovery, and server lifecycle helpers.

## Data Flow

1. User records audio with `expo-audio` or uploads audio/video through `expo-document-picker`.
2. The app posts multipart form data to `/v1/audio/transcriptions`.
3. Transcript text can be copied, exported, sent to conversation, or sent to TTS.
4. Conversation calls either `/v1/chat/completions` or `/v1/responses`; prompt workflow templates can wrap a transcript before sending.
5. Streaming responses are parsed from server-sent events and appended into the assistant message. Responses API streams consume delta events first and fall back to completed payload text when a provider sends the final response without deltas.
6. TTS calls `/v1/audio/speech`; web uses an object URL and native writes the returned bytes to cache. Web playback revokes the previous object URL when replacing audio or unmounting the app shell.

Each provider request receives an abort signal from the app shell in addition to its configured timeout. Cancelling an in-flight ASR, conversation, TTS, or provider diagnostic request aborts the HTTP call and ignores any stale response path that resolves after cancellation. Timeout aborts are converted into explicit timeout messages so slow providers are distinguishable from user-cancelled requests.
Before a provider request is sent, the provider client validates the request-critical settings it needs: HTTP(S) base URLs for ASR, conversation, TTS, and diagnostics; models for ASR and conversation; and model plus voice for TTS. This catches empty or malformed imported settings in the client and keeps provider errors actionable.

## Persistence

Native platforms use `expo-secure-store` when available for settings. Web uses `localStorage`. Stored settings are merged with the current defaults on load so new settings fields can be added without migration crashes.
The active transcript, raw ASR response, chat draft, custom prompt templates, custom provider templates, and recent conversation messages are saved as a workspace snapshot so mobile app restarts and browser refreshes do not discard current work. Web stores that snapshot in `localStorage`; native stores it as an app-private document JSON file. The Settings tab can write an empty workspace snapshot to clear sensitive working data without changing the active provider settings.

Settings export/import is intentionally redacted. API keys and extra headers are exported as `__DF_VOICE_REDACTED__`; importing that sentinel preserves the credential values already present on the target device.
Custom provider templates use the same credential sentinel before they are written to workspace storage. Applying a provider template merges it through the settings sanitizer so redacted credentials preserve the current device values.
The importer applies a field allowlist with enum, number, string, and boolean checks. Unsupported keys and invalid values are ignored rather than persisted.
Advanced JSON override fields are validated in the Settings UI before they are used by the provider client. The provider client still validates again at request time so direct state imports cannot bypass the JSON object and header-value constraints.
Numeric provider settings are validated in the Settings UI before they are persisted. Stored settings, provider templates, and settings imports also reject out-of-range numbers, non-finite values, and fractional values for integer-only fields so persisted data cannot silently push invalid provider parameters into runtime requests.

## Native Strategy

The app works in Expo Go for normal development. Android native builds are needed to verify generated manifest permissions and cleartext HTTP behavior. The generated `android/` and `ios/` directories are intentionally ignored and regenerated with Expo Prebuild.

## Verification

- `npm run verify:static`: TypeScript, settings portability and template contract logic checks, app/native/web config contracts, Expo doctor, Python script compile.
- `npm run verify:web:server`: desktop/mobile web smoke, JSON override and numeric setting validation, workspace clearing, custom prompt/provider templates, and layout checks.
- `npm run verify:web-build`: static web export build, manifest/head metadata checks, plus the same desktop/mobile smoke checks against `dist/`.
- `npm run verify:mock:server`: ASR upload and response formats, request cancellation, TTS, workspace restore, prompt templates, Chat Completions/Responses streaming and non-streaming, provider diagnostics, and export checks.
- `npm run verify:android-config`: Expo prebuild plus Android manifest/Gradle checks.
- `npm run verify:android-build`: debug APK build when Android SDK and JDK are available.
- `npm run verify:android-runtime`: adb install/launch check when a device or emulator is online.

Android verification scripts resolve SDK tools from `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `android/local.properties`, common local SDK directories, and `PATH` so local checks do not depend on shell-specific PATH setup.
