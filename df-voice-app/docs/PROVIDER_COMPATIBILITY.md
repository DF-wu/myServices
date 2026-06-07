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
- API keys are optional so local providers can run without authentication.
- Extra headers are merged before each request and are useful for gateways or vendor routing.
- Extra JSON body fields are merged after built-in fields for conversation and TTS requests.
- Extra ASR form fields are appended after built-in ASR fields for provider-specific options.
- Android emulators should use `10.0.2.2` when the provider runs on the host machine.

## Known Audit Note

`npm audit --audit-level=moderate` currently reports a transitive `uuid` advisory through Expo CLI dependencies. The suggested forced fix downgrades Expo and is not safe for this app. CI gates on `npm audit --audit-level=high` until Expo publishes a compatible transitive fix.
