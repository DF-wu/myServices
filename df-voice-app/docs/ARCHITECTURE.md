# Architecture

Last reviewed: 2026-06-08

DF Voice App is a single Expo Router application that targets web, Android, and optional iOS from one TypeScript codebase.

## Runtime Layers

- `app/`: Expo Router entry points and native stack shell.
- `src/components/app-shell.tsx`: product UI, workflow state, and user actions.
- `src/lib/openai-compatible.ts`: provider HTTP client for ASR, Chat Completions, Responses, model probes, and TTS.
- `src/lib/settings-portability.ts`: redacted settings export/import and credential preservation.
- `src/state/settings.tsx`: persisted settings and defaults merge.
- `src/data/templates.ts`: provider templates and default settings.
- `src/config/provider-defaults.ts`: public build-time defaults from `EXPO_PUBLIC_*` variables.
- `plugins/with-local-http-android.js`: Android cleartext HTTP and Gradle wrapper pin.
- `scripts/`: verification, mock provider, and server lifecycle helpers.

## Data Flow

1. User records audio with `expo-audio` or uploads audio/video through `expo-document-picker`.
2. The app posts multipart form data to `/v1/audio/transcriptions`.
3. Transcript text can be copied, exported, sent to conversation, or sent to TTS.
4. Conversation calls either `/v1/chat/completions` or `/v1/responses`.
5. Streaming responses are parsed from server-sent events and appended into the assistant message.
6. TTS calls `/v1/audio/speech`; web uses an object URL and native writes the returned bytes to cache.

## Persistence

Native platforms use `expo-secure-store` when available. Web uses `localStorage`. Stored settings are merged with the current defaults on load so new settings fields can be added without migration crashes.

Settings export/import is intentionally redacted. API keys and extra headers are exported as `__DF_VOICE_REDACTED__`; importing that sentinel preserves the credential values already present on the target device.

## Native Strategy

The app works in Expo Go for normal development. Android native builds are needed to verify generated manifest permissions and cleartext HTTP behavior. The generated `android/` and `ios/` directories are intentionally ignored and regenerated with Expo Prebuild.

## Verification

- `npm run verify:static`: TypeScript, Expo doctor, Python script compile.
- `npm run verify:web:server`: desktop/mobile web smoke and layout checks.
- `npm run verify:mock:server`: ASR upload, TTS, Chat Completions streaming, Responses streaming, provider diagnostics, and export checks.
- `npm run verify:android-config`: Expo prebuild plus Android manifest/Gradle checks.
- `npm run verify:android-build`: debug APK build when Android SDK and JDK are available.
- `npm run verify:android-runtime`: adb install/launch check when a device or emulator is online.
