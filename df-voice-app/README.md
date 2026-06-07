# DF Voice App

Standalone voice workbench for web, Android, and optional iOS. It records or uploads audio, sends it to OpenAI Whisper-compatible ASR endpoints, can continue the transcript through Chat Completions or Responses, and can play generated speech from OpenAI-compatible TTS providers.

## Features

- Record microphone audio and send it to `POST /v1/audio/transcriptions`
- Upload audio/video files for transcription
- Use local CapsWriter HTTP ASR or any OpenAI-compatible ASR provider
- Send transcript text to either `POST /v1/chat/completions` or `POST /v1/responses`
- Stream Chat Completions and Responses replies over server-sent events
- Generate speech with `POST /v1/audio/speech`
- Export transcripts, raw ASR payloads, and conversations as Markdown
- Check ASR, chat, and TTS providers with `GET /v1/models`
- Persist provider settings and API keys locally
- Apply templates for local CapsWriter, cloud-compatible, Android emulator, and LM Studio/Ollama-style setups
- Add provider-specific headers, ASR multipart fields, and JSON body overrides for OpenAI-compatible variants

## Run

From this project directory:

```bash
cd /home/df/workspace/myServices/df-voice-app
npm install
npm run web
```

Optional public build-time defaults can be copied from `.env.example`:

```bash
cp .env.example .env.local
```

Do not put API keys in `EXPO_PUBLIC_*` variables. Those values are bundled into web and native clients.

Android with Expo Go:

```bash
npm run android:go
```

Android native run with a local Android SDK/device:

```bash
npm run prebuild:android
npm run verify:android-build
npm run verify:android-runtime
npm run android
```

Android preview APK with EAS:

```bash
npx eas build --platform android --profile preview
```

iOS is optional and uses the same app:

```bash
npm run ios:go
npm run ios:native
```

The native app id is `app.dfvoice.app`.

## CapsWriter ASR

Start a CapsWriter HTTP API server separately:

```bash
CAPSWRITER_HTTP_API_ENABLE=true \
CAPSWRITER_HTTP_API_BIND=0.0.0.0 \
CAPSWRITER_HTTP_API_PORT=6017 \
python start_server_docker.py
```

Then use this ASR base URL in DF Voice App:

```text
http://YOUR_SERVER_IP:6017/v1
```

For Android emulators, `localhost` points at the emulator itself. Use your LAN IP or `10.0.2.2` when the server is on the host machine. The app includes an `Android Emulator Host` template that applies `10.0.2.2` to ASR, chat, and TTS providers.

## Provider Settings

The app exposes the parameters users normally need to tune:

- ASR: base URL, API key, model, `response_format`, language, prompt, temperature, timeout
- Conversation: base URL, API key, API mode, model, system prompt, temperature, top P, penalties, max output tokens, history, streaming, timeout
- TTS: base URL, API key, model, voice, output format, speed, instructions, timeout
- Advanced: per-provider extra headers, ASR extra form fields, and conversation/TTS extra JSON body fields

Streaming is enabled per conversation profile. Chat Completions reads `choices[].delta.content`; Responses reads `response.output_text.delta`.

Provider checks run independently for the ASR, conversation, and TTS base URLs. Each check reports HTTP status and model IDs returned by `/v1/models`; returned model IDs can be applied directly to that provider.

Advanced JSON fields are merged into the outgoing request after the built-in settings. They are intended for compatible providers that require custom headers, ASR fields such as timestamp options, or body fields such as `response_format`, `metadata`, `seed`, or vendor-specific flags.

Build-time provider defaults:

- `EXPO_PUBLIC_DF_VOICE_ASR_BASE_URL`
- `EXPO_PUBLIC_DF_VOICE_ASR_MODEL`
- `EXPO_PUBLIC_DF_VOICE_CONVERSATION_BASE_URL`
- `EXPO_PUBLIC_DF_VOICE_CONVERSATION_MODEL`
- `EXPO_PUBLIC_DF_VOICE_CONVERSATION_MODE`
- `EXPO_PUBLIC_DF_VOICE_TTS_BASE_URL`
- `EXPO_PUBLIC_DF_VOICE_TTS_MODEL`
- `EXPO_PUBLIC_DF_VOICE_TTS_VOICE`

Settings can be exported and imported from the Settings tab. Exports redact API keys and extra headers by default; importing a redacted file preserves the credentials already stored on the current device.

## Verification

Run static checks:

```bash
npm run verify:static
```

Run Android native checks:

```bash
npm run verify:android-config
npm run verify:android-build
npm run verify:android-runtime
```

`verify:android-config` regenerates the Android project, checks the cleartext HTTP manifest setting, and pins the Gradle wrapper to `gradle-8.14.3-bin.zip`. The Gradle pin avoids the React Native Gradle plugin's Foojay resolver incompatibility seen with Gradle 9.x.

`verify:android-build` also runs `:app:assembleDebug`. It requires JDK 17+ and an Android SDK with platform/build tools available through `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `android/local.properties` `sdk.dir`.

`verify:android-runtime` installs the debug APK on one online adb device/emulator, launches `app.dfvoice.app`, verifies the process stays alive, and writes `test-artifacts/android-runtime.png` plus recent logcat output. Set `ANDROID_SERIAL` when more than one device is attached. Headless or VM hosts without an online adb device or emulator acceleration cannot run this check.

Run the browser smoke test:

```bash
npm run verify:web:server
```

Run the ASR upload, TTS, model diagnostics, Chat Completions streaming, and Responses streaming integration checks:

```bash
npm run verify:mock:server
```

Run the CI-equivalent local gate:

```bash
npm run verify:ci
```

## Security

On Android and iOS, settings are stored with `expo-secure-store` when available. On web, settings are stored in browser `localStorage`; avoid saving production cloud API keys on shared machines.

The Android native config enables cleartext HTTP so local providers, `10.0.2.2`, and LAN IP endpoints work in release builds. It also pins the generated Gradle wrapper to 8.14.3 for React Native Gradle plugin compatibility. Background audio recording/playback services are disabled in the `expo-audio` config plugin.

Settings exports use the `__DF_VOICE_REDACTED__` sentinel for API keys and extra headers. Imports preserve existing local credentials whenever that sentinel is present.

## Project Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Provider compatibility](docs/PROVIDER_COMPATIBILITY.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
