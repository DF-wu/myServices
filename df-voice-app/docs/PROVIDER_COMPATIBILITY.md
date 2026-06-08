# Provider Compatibility

Last reviewed: 2026-06-08

DF Voice App targets OpenAI-compatible HTTP APIs and local providers that implement the same endpoint shapes.

## Supported Endpoint Shapes

| Capability | Endpoint | Notes |
| --- | --- | --- |
| ASR | `POST /v1/audio/transcriptions` | Multipart upload with `file`, `model`, `response_format`, `language`, `prompt`, `temperature`, and custom extra form fields. |
| Models | `GET /v1/models` | Used independently for ASR, conversation, and TTS provider diagnostics. |
| Chat Completions | `POST /v1/chat/completions` | Supports normal JSON responses and SSE streaming with `choices[].delta.content`. |
| Responses | `POST /v1/responses` | Supports normal JSON responses and SSE streaming with `response.output_text.delta`, `response.output_text.done`, and completed-response payload fallbacks. |
| TTS | `POST /v1/audio/speech` | Sends `model`, `voice`, `input`, `response_format`, `speed`, optional `instructions`, and custom extra body fields. |

## Official Reference Points

- OpenAI Audio transcription API: `https://platform.openai.com/docs/api-reference/audio/createTranscription`
- OpenAI Audio speech API: `https://platform.openai.com/docs/api-reference/audio/createSpeech`
- OpenAI Chat Completions API: `https://platform.openai.com/docs/api-reference/chat/create`
- OpenAI Responses API: `https://platform.openai.com/docs/api-reference/responses/create`
- OpenAI streaming guide: `https://platform.openai.com/docs/guides/streaming-responses`
- Expo app config and prebuild concepts: `https://docs.expo.dev/workflow/configuration/` and `https://docs.expo.dev/guides/adopting-prebuild/`

## Provider Notes

- `baseUrl` may include `/v1` or omit it; the client normalizes endpoint paths.
- ASR, conversation, TTS, and model diagnostic requests require an HTTP(S) `baseUrl` before any network request is sent.
- ASR and conversation requests require `model`; TTS requests require both `model` and `voice`.
- API keys are optional so local providers can run without authentication.
- Extra headers are merged before each request and are useful for gateways or vendor routing.
- Extra JSON body fields are merged after built-in fields for conversation and TTS requests.
- Extra ASR form fields are appended after built-in ASR fields for provider-specific options.
- Local file uploads are checked against the ASR `maxUploadMb` setting before a multipart ASR request is sent.
- Android emulators should use `10.0.2.2` when the provider runs on the host machine.

## CapsWriter HTTP API

CapsWriter exposes its original WebSocket server on `6016`. DF Voice App does not use that WebSocket endpoint directly; it uses CapsWriter's optional OpenAI Whisper-compatible HTTP API on `6017`.

Enable the HTTP API with `CAPSWRITER_HTTP_API_ENABLE=true`, bind and expose `CAPSWRITER_HTTP_API_PORT=6017`, and use `http://HOST:6017/v1` as the ASR base URL. `GET /health` is available at the HTTP API root, while `GET /v1/models` and `POST /v1/audio/transcriptions` follow the OpenAI-compatible shape. `POST /v1/audio/translations` is not part of the supported app contract because CapsWriter returns `501` for that endpoint.

CapsWriter's default HTTP upload limit is `CAPSWRITER_HTTP_API_MAX_UPLOAD_MB=100`, so DF Voice App defaults ASR `maxUploadMb` to `100`. Raise both the server environment variable and the app setting for larger uploads. CapsWriter currently controls the actual recognizer model through `CAPSWRITER_MODEL_TYPE`; OpenAI-compatible fields such as `model`, `prompt`, `temperature`, and `language` may be accepted for compatibility but are provider-limited.

## Known Audit Note

`npm audit --audit-level=moderate` currently reports a transitive `uuid` advisory through Expo CLI dependencies. The suggested forced fix downgrades Expo and is not safe for this app. CI gates on `npm audit --audit-level=high` until Expo publishes a compatible transitive fix.
